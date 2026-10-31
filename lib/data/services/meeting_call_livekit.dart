import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:logging/logging.dart';

import '../../domain/models/meeting.dart';
import 'meeting_call.dart';

/// Meetings over LiveKit. Join tokens come from the `meetings-joinToken`
/// Cloud Function, which names each participant by uid and puts their
/// profile photo in the participant metadata.
class LiveKitMediaService implements MeetingMediaService {
  @override
  Future<List<MediaDeviceInfo>> devices() async => [
    for (final d in await lk.Hardware.instance.enumerateDevices())
      if (_kind(d.kind) case final kind?)
        MediaDeviceInfo(
          id: d.deviceId,
          label: d.label.isEmpty ? _fallbackLabel(kind) : d.label,
          kind: kind,
        ),
  ];

  static MediaDeviceKind? _kind(String kind) => switch (kind) {
    'audioinput' => MediaDeviceKind.audioInput,
    'audiooutput' => MediaDeviceKind.audioOutput,
    'videoinput' => MediaDeviceKind.videoInput,
    _ => null,
  };

  static String _fallbackLabel(MediaDeviceKind kind) => switch (kind) {
    MediaDeviceKind.audioInput => 'Microphone',
    MediaDeviceKind.audioOutput => 'Speaker',
    MediaDeviceKind.videoInput => 'Camera',
  };

  @override
  Stream<void> get deviceChanges => lk.Hardware.instance.onDeviceChange.stream;

  @override
  Future<CameraPreview> previewCamera(String? deviceId) async {
    final track = await lk.LocalVideoTrack.createCameraTrack(
      lk.CameraCaptureOptions(deviceId: deviceId),
    );
    return _LiveKitPreview(track);
  }

  @override
  Future<bool> requestMicrophone() async {
    try {
      final track = await lk.LocalAudioTrack.create();
      await track.stop();
      await track.dispose();
      return true;
    } on Exception {
      return false;
    }
  }

  static bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  bool get canShareScreen =>
      _isDesktop || defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get picksScreenSource => _isDesktop;

  @override
  Future<String?> pickScreenSource(BuildContext context) async {
    final source = await showDialog<rtc.DesktopCapturerSource>(
      context: context,
      builder: (_) => lk.ScreenSelectDialog(),
    );
    return source?.id;
  }

  @override
  bool get canPickSpeaker => _isDesktop;

  @override
  MeetingCall createCall() => LiveKitMeetingCall();
}

class _LiveKitVideo implements CallVideo {
  _LiveKitVideo(this.track);

  final lk.VideoTrack track;

  @override
  Widget view({bool mirror = false, bool cover = true}) =>
      lk.VideoTrackRenderer(
        track,
        key: ValueKey(track.sid ?? track.mediaStreamTrack.id),
        fit: cover ? lk.VideoViewFit.cover : lk.VideoViewFit.contain,
        mirrorMode: mirror
            ? lk.VideoViewMirrorMode.mirror
            : lk.VideoViewMirrorMode.off,
      );
}

class _LiveKitPreview implements CameraPreview {
  _LiveKitPreview(this._track) : video = _LiveKitVideo(_track);

  final lk.LocalVideoTrack _track;

  @override
  final CallVideo video;

  @override
  Future<void> dispose() async {
    await _track.stop();
    await _track.dispose();
  }
}

class LiveKitMeetingCall extends MeetingCall {
  static final _log = Logger('LiveKitMeetingCall');

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  final Map<String, double> _volumes = {};

  /// Videos are wrapped once per track so renderers aren't rebuilt.
  final Map<lk.VideoTrack, CallVideo> _videos = {};
  List<CallParticipant> _participants = const [];
  CallEndReason? _endReason;
  bool _leaving = false;
  bool _disposed = false;
  Future<void>? _hangUp;
  bool _backgroundOn = false;

  @override
  List<CallParticipant> get participants => _participants;

  @override
  bool get connected =>
      _room?.connectionState == lk.ConnectionState.connected ||
      _room?.connectionState == lk.ConnectionState.reconnecting;

  lk.LocalParticipant? get _me => _room?.localParticipant;

  @override
  bool get micOn => _me?.isMicrophoneEnabled() ?? false;

  @override
  bool get cameraOn => _me?.isCameraEnabled() ?? false;

  @override
  bool get screenSharing => _me?.isScreenShareEnabled() ?? false;

  @override
  CallEndReason? get endReason => _endReason;

  @override
  Future<void> connect(MeetingAccess access, CallSetup setup) async {
    final room = lk.Room(
      roomOptions: lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioCaptureOptions: lk.AudioCaptureOptions(
          deviceId: setup.audioInputId,
        ),
        defaultCameraCaptureOptions: lk.CameraCaptureOptions(
          deviceId: setup.videoInputId,
        ),
        defaultAudioOutputOptions: lk.AudioOutputOptions(
          deviceId: setup.audioOutputId,
        ),
      ),
    );
    _room = room;
    _listener = room.createListener()
      ..on<lk.TrackSubscribedEvent>((e) {
        if (e.track is lk.RemoteAudioTrack) {
          _applyVolume(e.participant.identity, e.track);
        }
      })
      ..on<lk.RoomDisconnectedEvent>((e) {
        if (_leaving) return;
        _endReason = switch (e.reason) {
          lk.DisconnectReason.roomDeleted ||
          lk.DisconnectReason.serverShutdown => CallEndReason.meetingEnded,
          lk.DisconnectReason.participantRemoved ||
          lk.DisconnectReason.duplicateIdentity => CallEndReason.removed,
          _ => CallEndReason.connectionLost,
        };
      })
      ..listen((_) => _refresh());
    room.addListener(_refresh);
    await room.connect(access.url, access.token);
    final me = room.localParticipant;
    if (me != null) {
      // Media failures (no device, permission refused) shouldn't keep the
      // user out of the meeting; they join with it off.
      if (setup.micOn) await _try(() => me.setMicrophoneEnabled(true));
      if (setup.cameraOn) await _try(() => me.setCameraEnabled(true));
    }
    _refresh();
  }

  Future<void> _try(Future<void> Function() action) async {
    try {
      await action();
    } on Exception catch (e) {
      _log.warning('Media failed', e);
    }
  }

  void _refresh() {
    final room = _room;
    if (room == null) return;
    final seen = <lk.VideoTrack>{};
    CallVideo? video(lk.Participant p, lk.TrackSource source) {
      final pub = p.getTrackPublicationBySource(source);
      final track = pub?.track;
      if (pub == null || pub.muted || track is! lk.VideoTrack) return null;
      seen.add(track);
      return _videos[track] ??= _LiveKitVideo(track);
    }

    CallParticipant from(lk.Participant p, {required bool local}) =>
        CallParticipant(
          uid: p.identity,
          name: p.name.isEmpty ? 'Member' : p.name,
          photoUrl: _photo(p.metadata),
          isLocal: local,
          isSpeaking: p.isSpeaking,
          micOn: p.isMicrophoneEnabled(),
          camera: video(p, lk.TrackSource.camera),
          screen: video(p, lk.TrackSource.screenShareVideo),
        );

    final remotes = room.remoteParticipants.values.toList()
      ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    _participants = [
      if (room.localParticipant case final me?) from(me, local: true),
      for (final p in remotes) from(p, local: false),
    ];
    _videos.removeWhere((track, _) => !seen.contains(track));
    if (!_disposed) notifyListeners();
  }

  static String? _photo(String? metadata) {
    if (metadata == null || metadata.isEmpty) return null;
    try {
      final data = jsonDecode(metadata);
      return data is Map && data['photoUrl'] is String
          ? data['photoUrl'] as String
          : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> setMicOn(bool on) async {
    await _me?.setMicrophoneEnabled(on);
    _refresh();
  }

  @override
  Future<void> setCameraOn(bool on) async {
    await _me?.setCameraEnabled(on);
    _refresh();
  }

  @override
  Future<void> setScreenSharing(bool on, {String? sourceId}) async {
    final me = _me;
    if (me == null) return;
    if (!on) {
      await me.setScreenShareEnabled(false);
      await _stopBackground();
      _refresh();
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android only lets a foreground service capture the screen.
      if (!await rtc.Helper.requestCapturePermission()) return;
      await _startBackground();
    }
    try {
      await me.setScreenShareEnabled(
        true,
        screenShareCaptureOptions: lk.ScreenShareCaptureOptions(
          sourceId: sourceId,
          maxFrameRate: 15,
        ),
      );
    } catch (_) {
      await _stopBackground();
      rethrow;
    }
    _refresh();
  }

  Future<void> _startBackground() async {
    final ready = await FlutterBackground.initialize(
      androidConfig: const FlutterBackgroundAndroidConfig(
        notificationTitle: 'Sharing your screen',
        notificationText: 'UltiUP is sharing your screen with the meeting.',
        notificationImportance: AndroidNotificationImportance.normal,
        shouldRequestBatteryOptimizationsOff: false,
      ),
    );
    if (ready) {
      _backgroundOn = await FlutterBackground.enableBackgroundExecution();
    }
  }

  Future<void> _stopBackground() async {
    if (!_backgroundOn) return;
    _backgroundOn = false;
    await FlutterBackground.disableBackgroundExecution();
  }

  @override
  Future<void> useDevice(MediaDeviceInfo device) async {
    final room = _room;
    if (room == null) return;
    final d = lk.MediaDevice(device.id, device.label, switch (device.kind) {
      MediaDeviceKind.audioInput => 'audioinput',
      MediaDeviceKind.audioOutput => 'audiooutput',
      MediaDeviceKind.videoInput => 'videoinput',
    }, null);
    switch (device.kind) {
      case MediaDeviceKind.audioInput:
        await room.setAudioInputDevice(d);
      case MediaDeviceKind.audioOutput:
        await room.setAudioOutputDevice(d);
      case MediaDeviceKind.videoInput:
        await room.setVideoInputDevice(d);
    }
    _refresh();
  }

  @override
  void setVolume(String uid, double volume) {
    if (_volumes[uid] == volume) return;
    _volumes[uid] = volume;
    final p = _room?.remoteParticipants.values
        .where((p) => p.identity == uid)
        .firstOrNull;
    for (final pub in p?.audioTrackPublications ?? const []) {
      if (pub.track case final track?) _applyVolume(uid, track);
    }
  }

  void _applyVolume(String uid, lk.Track track) {
    final volume = _volumes[uid];
    if (volume == null) return;
    unawaited(
      rtc.Helper.setVolume(
        volume,
        track.mediaStreamTrack,
      ).catchError((Object e) => _log.warning('Volume failed for $uid', e)),
    );
  }

  @override
  Future<void> leave() {
    _leaving = true;
    return _hangUp ??= _disconnect(_room);
  }

  Future<void> _disconnect(lk.Room? room) async {
    await _stopBackground();
    if (room != null &&
        room.connectionState != lk.ConnectionState.disconnected) {
      await room.disconnect();
    }
  }

  @override
  void dispose() {
    final room = _room;
    _room = null;
    _disposed = true;
    room?.removeListener(_refresh);
    // Hang up once: after leave() if it's under way, otherwise here. The
    // room is disposed only after it has disconnected.
    unawaited(() async {
      await (_hangUp ??= _disconnect(room));
      await _listener?.dispose();
      await room?.dispose();
    }());
    super.dispose();
  }
}
