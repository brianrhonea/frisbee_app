import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/meeting/meeting_repository.dart';
import '../../../data/repositories/meeting/meeting_settings_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/video/video_repository.dart';
import '../../../data/services/file_picker_service.dart';
import '../../../data/services/meeting_call.dart';
import '../../../data/services/meeting_presence.dart';
import '../../../domain/models/meeting.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import 'meeting_chat_viewmodel.dart';
import 'watch_together_viewmodel.dart';

enum RoomStage {
  /// Picking devices and waiting to get in.
  lobby,
  joining,
  inCall,

  /// Left, removed, or the meeting ended; see [MeetingRoomViewModel.endNotice].
  left,
}

/// What the lobby offers the user right now.
enum LobbyState {
  loading,

  /// Not invited, or the meeting is gone.
  unavailable,
  ended,

  /// Admins only: the meeting hasn't started.
  canStart,

  /// Waiting for an admin to start the meeting.
  waitingToStart,
  canJoin,

  /// Approval needed and not asked yet, or asked and turned away.
  canAsk,

  /// Asked; waiting for an admin.
  waitingForApproval,
}

/// The meeting room: the lobby (devices, preview, getting in), then the
/// call with its chat. Admins start and end the meeting and let people in.
///
/// Audio levels and device choices are the user's own
/// ([MeetingSettings]) and are remembered on this device.
class MeetingRoomViewModel extends ChangeNotifier {
  MeetingRoomViewModel({
    required this.teamId,
    required this.meetingId,
    required MeetingRepository meetingRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    required MeetingMediaService media,
    required MeetingSettingsRepository settingsRepository,
    required FilePickerService filePicker,
    required MeetingPresence presence,
    required VideoRepository videoRepository,
  }) : _meetings = meetingRepository,
       _videos = videoRepository,
       _auth = authRepository,
       _media = media,
       _settingsRepo = settingsRepository,
       _filePicker = filePicker,
       _presence = presence {
    presence.enter(teamId, meetingId);
    start = Command0<void>(_start);
    join = Command0<void>(_join);
    askToJoin = Command0<void>(_askToJoin);
    cancelAsk = Command0<void>(
      () => _meetings.cancelJoinRequest(teamId, meetingId, uid),
    );
    decide = Command1<void, ({String uid, bool admit})>(
      (d) => _meetings.decideJoinRequest(
        teamId,
        meetingId,
        d.uid,
        admit: d.admit,
        adminUid: uid,
      ),
    );
    endMeeting = Command0<void>(_endMeeting);
    toggleMic = Command0<void>(_toggleMic);
    toggleCamera = Command0<void>(_toggleCamera);
    setScreenSharing = Command1<void, ({bool on, String? sourceId})>(
      _setScreenSharing,
    );
    useDevice = Command1<void, MediaDeviceInfo>(_useDevice);

    _subs = [
      _meetings
          .watchMeeting(teamId, meetingId)
          .listen(_onMeeting, onError: _onError),
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        _teamLoaded = true;
        _watchRequests();
        notifyListeners();
      }, onError: _onError),
      _media.deviceChanges.listen((_) => _loadDevices()),
    ];
    unawaited(_init());
  }

  final String teamId;
  final String meetingId;
  final MeetingRepository _meetings;
  final VideoRepository _videos;
  final AuthRepository _auth;
  final MeetingMediaService _media;
  final MeetingSettingsRepository _settingsRepo;
  final FilePickerService _filePicker;
  final MeetingPresence _presence;
  late final List<StreamSubscription<Object?>> _subs;
  StreamSubscription<List<JoinRequest>>? _requestsSub;
  StreamSubscription<JoinRequest?>? _myRequestSub;
  bool _disposed = false;

  /// Admins: opens the meeting and joins it.
  late final Command0<void> start;
  late final Command0<void> join;
  late final Command0<void> askToJoin;
  late final Command0<void> cancelAsk;

  /// Admins: lets someone in, or turns them away.
  late final Command1<void, ({String uid, bool admit})> decide;

  /// Admins: ends the meeting for everyone.
  late final Command0<void> endMeeting;
  late final Command0<void> toggleMic;
  late final Command0<void> toggleCamera;
  late final Command1<void, ({bool on, String? sourceId})> setScreenSharing;

  /// Switches a device; in the lobby it's used once the call starts.
  late final Command1<void, MediaDeviceInfo> useDevice;

  String get uid => _auth.currentUser?.uid ?? '';
  String get myName => _auth.currentUser?.label ?? 'You';
  String? get myPhotoUrl => _auth.currentUser?.photoUrl;

  // Meeting and team ---------------------------------------------------------

  TeamMeeting? _meeting;
  TeamMeeting? get meeting => _meeting;
  bool _meetingLoaded = false;

  Team? _team;
  bool _teamLoaded = false;

  Object? _error;
  Object? get error => _error;

  bool get isAdmin => _team?.canEdit(uid) ?? false;

  /// Whether starting now would be ahead of the scheduled time.
  bool get isEarly => _meeting?.startsAt.isAfter(DateTime.now()) ?? false;

  bool get _needsApproval => switch ((_meeting, _team)) {
    (final m?, final t?) => m.needsApproval(t, uid),
    _ => false,
  };

  void _onMeeting(TeamMeeting? m) {
    final wasLive = _meeting?.isLive ?? false;
    _meeting = m;
    _meetingLoaded = true;
    _watchRequests();
    if (m == null || m.isEnded) {
      if (_stage == RoomStage.inCall || _stage == RoomStage.joining) {
        unawaited(_hangUp('The meeting has ended.'));
      }
    } else if (!wasLive && m.isLive) {
      _maybeAutoJoin();
    }
    notifyListeners();
  }

  /// Admins watch everyone's requests; invitees who need approval, their own.
  void _watchRequests() {
    final m = _meeting;
    if (m == null || !_teamLoaded) return;
    if (isAdmin) {
      _myRequestSub?.cancel();
      _myRequestSub = null;
      _requestsSub ??= _meetings.watchJoinRequests(teamId, meetingId).listen((
        r,
      ) {
        _requests = r;
        notifyListeners();
      }, onError: (Object e) => _requests = const []);
    } else if (_needsApproval) {
      _requestsSub?.cancel();
      _requestsSub = null;
      _myRequestSub ??= _meetings
          .watchMyJoinRequest(teamId, meetingId, uid)
          .listen((r) {
            final wasAdmitted = _myRequest?.isAdmitted ?? false;
            _myRequest = r;
            if (!wasAdmitted && (r?.isAdmitted ?? false)) _maybeAutoJoin();
            notifyListeners();
          }, onError: _onError);
    }
  }

  List<JoinRequest> _requests = const [];

  /// Admins: people waiting to be let in, oldest first.
  List<JoinRequest> get pendingRequests => [
    for (final r in _requests)
      if (r.isPending) r,
  ];

  JoinRequest? _myRequest;
  JoinRequest? get myRequest => _myRequest;

  LobbyState get lobbyState {
    final m = _meeting;
    final team = _team;
    if (!_meetingLoaded || !_teamLoaded) {
      return _error != null ? LobbyState.unavailable : LobbyState.loading;
    }
    if (m == null || team == null || !m.canSee(team, uid)) {
      return LobbyState.unavailable;
    }
    if (m.isEnded) return LobbyState.ended;
    if (!m.isLive) {
      return isAdmin ? LobbyState.canStart : LobbyState.waitingToStart;
    }
    if (!_needsApproval) return LobbyState.canJoin;
    return switch (_myRequest?.status) {
      JoinRequestStatus.admitted => LobbyState.canJoin,
      JoinRequestStatus.pending => LobbyState.waitingForApproval,
      _ => LobbyState.canAsk,
    };
  }

  /// Set when the user asked to join while the meeting wasn't open yet, or
  /// was waiting to be let in: they go straight in once they can.
  bool _wantsIn = false;

  /// Invitees can say they're ready; they join as soon as the meeting
  /// starts (or they're let in).
  bool get wantsIn => _wantsIn;

  void setWantsIn(bool value) {
    _wantsIn = value;
    notifyListeners();
    if (value) _maybeAutoJoin();
  }

  void _maybeAutoJoin() {
    if (_wantsIn &&
        _stage == RoomStage.lobby &&
        lobbyState == LobbyState.canJoin) {
      join.execute();
    }
  }

  // Lobby: settings, devices and preview -------------------------------------

  MeetingSettings _settings = const MeetingSettings();
  MeetingSettings get settings => _settings;

  List<MediaDeviceInfo> _devices = const [];

  List<MediaDeviceInfo> devicesOf(MediaDeviceKind kind) => [
    for (final d in _devices)
      if (d.kind == kind) d,
  ];

  bool get canPickSpeaker => _media.canPickSpeaker;
  bool get canShareScreen => _media.canShareScreen;
  bool get picksScreenSource => _media.picksScreenSource;

  /// Desktop: which screen or window to share; null if cancelled.
  Future<String?> pickScreenSource(BuildContext context) =>
      _media.pickScreenSource(context);

  /// The device in use for [kind]: the saved one if it's still plugged in,
  /// otherwise the system default (null).
  MediaDeviceInfo? selected(MediaDeviceKind kind) {
    final id = switch (kind) {
      MediaDeviceKind.audioInput => _settings.audioInputId,
      MediaDeviceKind.audioOutput => _settings.audioOutputId,
      MediaDeviceKind.videoInput => _settings.videoInputId,
    };
    return devicesOf(kind).where((d) => d.id == id).firstOrNull;
  }

  CameraPreview? _preview;

  /// The lobby's camera preview, while the camera is on.
  CallVideo? get preview => _preview?.video;

  /// A camera or mic problem to show in the lobby, e.g. permission refused.
  String? _mediaNotice;
  String? get mediaNotice => _mediaNotice;

  Future<void> _init() async {
    _settings = await _settingsRepo.load();
    if (_disposed) return;
    notifyListeners();
    if (_settings.micOn) await _checkMic();
    if (_settings.cameraOn) await _openPreview();
    await _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await _media.devices();
      if (_disposed) return;
      _devices = devices;
      notifyListeners();
    } on Exception {
      // Without the list the system defaults are still used.
    }
  }

  Future<bool> _checkMic() async {
    final ok = await _media.requestMicrophone();
    if (_disposed) return ok;
    if (!ok) {
      _mediaNotice =
          "Can't use the microphone. Allow microphone access in your "
          'device settings.';
      _settings = _settings.copyWith(micOn: false);
    }
    notifyListeners();
    return ok;
  }

  Future<void> _openPreview() async {
    await _closePreview();
    try {
      final preview = await _media.previewCamera(_settings.videoInputId);
      if (_disposed || !_settings.cameraOn || _stage != RoomStage.lobby) {
        await preview.dispose();
        return;
      }
      _preview = preview;
      _mediaNotice = null;
    } on Exception {
      _mediaNotice =
          "Can't use the camera. Allow camera access in your device "
          'settings, or pick another camera.';
      _settings = _settings.copyWith(cameraOn: false);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _closePreview() async {
    final preview = _preview;
    _preview = null;
    await preview?.dispose();
  }

  void _saveSettings(MeetingSettings next) {
    _settings = next;
    notifyListeners();
    unawaited(_settingsRepo.save(next));
  }

  Future<Result<void>> _toggleMic() async {
    final on = !micOn;
    final call = _call;
    if (call != null) {
      return guard(() => call.setMicOn(on));
    }
    _saveSettings(_settings.copyWith(micOn: on));
    if (on) {
      _mediaNotice = null;
      await _checkMic();
      unawaited(_loadDevices()); // Names show once access is granted.
    }
    return const Result.ok(null);
  }

  Future<Result<void>> _toggleCamera() async {
    final on = !cameraOn;
    final call = _call;
    if (call != null) return guard(() => call.setCameraOn(on));
    _saveSettings(_settings.copyWith(cameraOn: on));
    if (on) {
      await _openPreview();
      unawaited(_loadDevices());
    } else {
      await _closePreview();
      notifyListeners();
    }
    return const Result.ok(null);
  }

  Future<Result<void>> _useDevice(MediaDeviceInfo d) async {
    _saveSettings(switch (d.kind) {
      MediaDeviceKind.audioInput => _settings.copyWith(
        audioInputId: () => d.id,
      ),
      MediaDeviceKind.audioOutput => _settings.copyWith(
        audioOutputId: () => d.id,
      ),
      MediaDeviceKind.videoInput => _settings.copyWith(
        videoInputId: () => d.id,
      ),
    });
    final call = _call;
    if (call != null) return guard(() => call.useDevice(d));
    if (d.kind == MediaDeviceKind.videoInput && _settings.cameraOn) {
      await _openPreview();
    }
    return const Result.ok(null);
  }

  // Volume -------------------------------------------------------------------

  bool _audioMuted = false;

  /// Everyone else is silenced on this device (the mic is separate).
  bool get audioMuted => _audioMuted;

  void toggleAudioMuted() {
    _audioMuted = !_audioMuted;
    _applyVolumes();
    notifyListeners();
  }

  double get outputVolume => _settings.outputVolume;

  void setOutputVolume(double v) {
    _settings = _settings.copyWith(outputVolume: v.clamp(0, 1));
    _applyVolumes();
    notifyListeners();
  }

  double volumeOf(String participantUid) => _settings.volumeOf(participantUid);

  void setVolumeOf(String participantUid, double v) {
    _settings = _settings.copyWith(
      participantVolumes: {
        ..._settings.participantVolumes,
        participantUid: v.clamp(0, 2),
      },
    );
    _applyVolumes();
    notifyListeners();
  }

  /// Remembers volume changes once a slider is let go.
  void saveVolumes() => unawaited(_settingsRepo.save(_settings));

  void _applyVolumes() {
    _watch?.setVolume(_audioMuted ? 0 : _settings.outputVolume);
    final call = _call;
    if (call == null) return;
    for (final p in call.participants) {
      if (p.isLocal) continue;
      call.setVolume(
        p.uid,
        _audioMuted ? 0 : _settings.outputVolume * _settings.volumeOf(p.uid),
      );
    }
  }

  // Call ---------------------------------------------------------------------

  RoomStage _stage = RoomStage.lobby;
  RoomStage get stage => _stage;

  /// Why the user is out of the call, when they didn't leave themselves.
  String? _endNotice;
  String? get endNotice => _endNotice;

  MeetingCall? _call;
  MeetingChatViewModel? _chat;

  /// The meeting chat, while in the call.
  MeetingChatViewModel? get chat => _chat;

  WatchTogetherViewModel? _watch;

  /// Watch together, while in the call.
  WatchTogetherViewModel? get watch => _watch;

  List<CallParticipant> get participants => _call?.participants ?? const [];

  /// The first person sharing their screen, shown large.
  CallParticipant? get presenter =>
      participants.where((p) => p.screen != null).firstOrNull;

  bool get micOn => _call?.micOn ?? _settings.micOn;
  bool get cameraOn => _call?.cameraOn ?? _settings.cameraOn;
  bool get screenSharing => _call?.screenSharing ?? false;

  /// Asks to be let in, and joins as soon as an admin does.
  Future<Result<void>> _askToJoin() async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in.'));
    final result = await _meetings.requestToJoin(teamId, meetingId, user);
    if (result is Ok) _wantsIn = true;
    return result;
  }

  Future<Result<void>> _start() async {
    if (!isAdmin) {
      return Result.error(Exception('Only admins can start the meeting.'));
    }
    final started = await _meetings.startMeeting(teamId, meetingId, uid);
    if (started is Error) return started;
    return _join();
  }

  Future<Result<void>> _join() async {
    if (_stage != RoomStage.lobby) return const Result.ok(null);
    _stage = RoomStage.joining;
    _endNotice = null;
    notifyListeners();
    final access = await _meetings.joinToken(teamId, meetingId);
    switch (access) {
      case Error(:final error):
        _stage = RoomStage.lobby;
        notifyListeners();
        return Result.error(error);
      case Ok(:final value):
        // The call opens the camera itself; release the preview's first.
        await _closePreview();
        final call = _media.createCall()..addListener(_onCall);
        _call = call;
        try {
          await call.connect(
            value,
            CallSetup(
              micOn: _settings.micOn,
              cameraOn: _settings.cameraOn,
              audioInputId: selected(MediaDeviceKind.audioInput)?.id,
              audioOutputId: selected(MediaDeviceKind.audioOutput)?.id,
              videoInputId: selected(MediaDeviceKind.videoInput)?.id,
            ),
          );
        } on Exception catch (e) {
          _dropCall();
          _stage = RoomStage.lobby;
          if (_settings.cameraOn) unawaited(_openPreview());
          notifyListeners();
          return Result.error(e);
        }
        if (_disposed) return const Result.ok(null);
        _wantsIn = false;
        _chat = MeetingChatViewModel(
          teamId: teamId,
          meetingId: meetingId,
          meetingRepository: _meetings,
          canModerate: isAdmin,
          authRepository: _auth,
          filePicker: _filePicker,
        );
        if (_auth.currentUser case final user?) {
          _watch = WatchTogetherViewModel(
            teamId: teamId,
            meetingId: meetingId,
            meetingRepository: _meetings,
            videoRepository: _videos,
            user: user,
            canControl: isAdmin,
          );
        }
        _stage = RoomStage.inCall;
        _applyVolumes();
        notifyListeners();
        return const Result.ok(null);
    }
  }

  void _onCall() {
    final call = _call;
    if (call == null) return;
    if (call.endReason case final reason?) {
      unawaited(
        _hangUp(switch (reason) {
          CallEndReason.meetingEnded => 'The meeting has ended.',
          CallEndReason.removed => 'You were removed from the meeting.',
          CallEndReason.connectionLost => 'You lost your connection.',
        }),
      );
      return;
    }
    _applyVolumes();
    notifyListeners();
  }

  Future<Result<void>> _setScreenSharing(({bool on, String? sourceId}) r) {
    final call = _call;
    if (call == null) {
      return Future.value(Result.error(Exception('Join the meeting first.')));
    }
    return guard(() => call.setScreenSharing(r.on, sourceId: r.sourceId));
  }

  /// Leaves the call; the meeting goes on for everyone else.
  Future<void> leave() => _hangUp(null);

  Future<Result<void>> _endMeeting() async {
    final result = await _meetings.endMeeting(teamId, meetingId);
    if (result is Ok) await _hangUp('You ended the meeting.');
    return result;
  }

  Future<void> _hangUp(String? notice) async {
    final call = _call;
    if (call == null) return;
    _endNotice = notice;
    _dropCall();
    _stage = RoomStage.left;
    if (!_disposed) notifyListeners();
    await call.leave();
    call.dispose();
  }

  void _dropCall() {
    _call?.removeListener(_onCall);
    _call = null;
    _chat?.dispose();
    _chat = null;
    _watch?.dispose();
    _watch = null;
  }

  /// Back to the lobby after leaving, e.g. to rejoin.
  void backToLobby() {
    if (_stage != RoomStage.left) return;
    _stage = RoomStage.lobby;
    _endNotice = null;
    notifyListeners();
    if (_settings.cameraOn) unawaited(_openPreview());
  }

  void _onError(Object e) {
    _error = e;
    _meetingLoaded = true;
    _teamLoaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _presence.leave(teamId, meetingId);
    for (final s in _subs) {
      s.cancel();
    }
    _requestsSub?.cancel();
    _myRequestSub?.cancel();
    unawaited(_closePreview());
    final call = _call;
    _dropCall();
    if (call != null) {
      unawaited(call.leave().whenComplete(call.dispose));
    }
    unawaited(_settingsRepo.save(_settings));
    for (final c in [
      start,
      join,
      askToJoin,
      cancelAsk,
      decide,
      endMeeting,
      toggleMic,
      toggleCamera,
      setScreenSharing,
      useDevice,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}
