import 'package:flutter/widgets.dart';

import '../../domain/models/meeting.dart';

enum MediaDeviceKind { audioInput, audioOutput, videoInput }

/// A microphone, speaker or camera on this device.
class MediaDeviceInfo {
  const MediaDeviceInfo({
    required this.id,
    required this.label,
    required this.kind,
  });

  final String id;
  final String label;
  final MediaDeviceKind kind;

  @override
  bool operator ==(Object other) =>
      other is MediaDeviceInfo && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, kind);
}

/// A video stream to show: someone's camera or shared screen.
abstract class CallVideo {
  /// [mirror] flips it, as people expect of their own camera.
  Widget view({bool mirror = false, bool cover = true});
}

/// A camera preview shown before joining.
abstract class CameraPreview {
  CallVideo get video;
  Future<void> dispose();
}

/// One person in the call, as last seen.
class CallParticipant {
  const CallParticipant({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.isLocal = false,
    this.isSpeaking = false,
    this.micOn = false,
    this.camera,
    this.screen,
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final bool isLocal;
  final bool isSpeaking;
  final bool micOn;

  /// Null while their camera is off.
  final CallVideo? camera;

  /// Null unless they're sharing their screen.
  final CallVideo? screen;
}

/// What to start the call with: the devices picked in the lobby and
/// whether the mic and camera start on.
class CallSetup {
  const CallSetup({
    this.micOn = true,
    this.cameraOn = false,
    this.audioInputId,
    this.audioOutputId,
    this.videoInputId,
  });

  final bool micOn;
  final bool cameraOn;
  final String? audioInputId;
  final String? audioOutputId;
  final String? videoInputId;
}

/// Why the call ended without the user leaving.
enum CallEndReason {
  /// An admin ended the meeting, or the server closed the room.
  meetingEnded,

  /// An admin removed the user, or they joined from another device.
  removed,

  /// The connection was lost and couldn't be restored.
  connectionLost,
}

/// The live audio/video call behind a meeting. Notifies on any change to
/// [participants] or the local media state.
abstract class MeetingCall extends ChangeNotifier {
  Future<void> connect(MeetingAccess access, CallSetup setup);

  bool get connected;

  /// The user first, then everyone else in join order.
  List<CallParticipant> get participants;

  bool get micOn;
  bool get cameraOn;
  bool get screenSharing;

  /// Set when the call ended on its own; see [CallEndReason].
  CallEndReason? get endReason;

  Future<void> setMicOn(bool on);
  Future<void> setCameraOn(bool on);

  /// [sourceId] is the screen or window picked on desktop.
  Future<void> setScreenSharing(bool on, {String? sourceId});

  /// Switches the mic, speaker or camera in use.
  Future<void> useDevice(MediaDeviceInfo device);

  /// How loud [uid] plays on this device: 0 silent, 1 as sent, up to 2.
  void setVolume(String uid, double volume);

  Future<void> leave();
}

/// Devices, previews and calls. Each meeting room creates its own call.
abstract class MeetingMediaService {
  Future<List<MediaDeviceInfo>> devices();

  /// Fires when a device is plugged in or removed.
  Stream<void> get deviceChanges;

  /// Opens the camera for a preview; asks for permission the first time.
  Future<CameraPreview> previewCamera(String? deviceId);

  /// Asks for microphone permission ahead of joining. False if refused.
  Future<bool> requestMicrophone();

  /// Whether this platform can share its screen. iOS needs a broadcast
  /// extension the app doesn't have yet.
  bool get canShareScreen;

  /// Whether screen sharing starts with a picker of screens and windows.
  bool get picksScreenSource;

  /// Shows the screen and window picker; the chosen source's id, or null
  /// if cancelled. Only where [picksScreenSource].
  Future<String?> pickScreenSource(BuildContext context);

  /// Whether the speaker can be chosen; phones route audio themselves.
  bool get canPickSpeaker;

  MeetingCall createCall();
}
