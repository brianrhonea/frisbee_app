import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';

import '../../../domain/models/chat.dart';
import '../../../domain/models/meeting.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';
import '../../services/callable_client.dart';
import '../../services/meeting_call.dart';
import '../auth/auth_repository.dart';
import '../chat/chat_repository.dart';
import '../meeting/meeting_settings_repository.dart';
import '../team/team_repository.dart';
import 'voice_repository.dart';

/// Said when the user loses access to the channel they're in.
const voiceLostAccessNotice = 'You no longer have access to this channel.';

/// Voice channels on LiveKit, through the same call service as meetings.
/// Tokens come from the `meetings-voiceToken` Cloud Function, which checks
/// the room's access lists like firestore.rules does.
///
/// While in a channel it watches the team and the room and re-checks, as
/// the token did: leaving the team, the team going or losing read access
/// drops the call; the room being deleted closes it; losing write access
/// turns the mic off and keeps the user listening. Signing out or another
/// account signing in disconnects.
class VoiceRepositoryLiveKit extends VoiceRepository {
  VoiceRepositoryLiveKit({
    required CallableClient functions,
    required MeetingMediaService media,
    required MeetingSettingsRepository settings,
    required TeamRepository teams,
    required ChatRepository chats,
    required AuthRepository auth,
  }) : _functions = functions,
       _media = media,
       _settings = settings,
       _teams = teams,
       _chats = chats,
       _auth = auth {
    _auth.addListener(_onAuth);
  }

  final CallableClient _functions;
  final MeetingMediaService _media;
  final MeetingSettingsRepository _settings;
  final TeamRepository _teams;
  final ChatRepository _chats;
  final AuthRepository _auth;

  MeetingCall? _call;
  VoiceChannel? _channel;
  bool _connecting = false;

  /// What the token allows; fixed for the call.
  bool _tokenCanSpeak = false;

  /// What the team and room allow now.
  bool _allowedToSpeak = true;
  String? _notice;

  /// Who joined; another account means hanging up.
  String? _uid;
  _Watch<Team?>? _teamWatch;
  _Watch<ChatRoom?>? _roomWatch;

  /// Bumped on every join and leave, so a slow join that's been replaced
  /// hangs up instead of taking over.
  int _attempt = 0;

  @override
  VoiceChannel? get channel => _channel;
  @override
  bool get connecting => _connecting;
  @override
  bool get connected => _call?.connected ?? false;
  @override
  bool get canSpeak => _call != null && _tokenCanSpeak && _allowedToSpeak;
  @override
  bool get micOn => _call?.micOn ?? false;
  @override
  List<CallParticipant> get participants => _call?.participants ?? const [];
  @override
  String? get notice => _notice;

  @override
  Future<Result<void>> join(VoiceChannel channel) async {
    if (isIn(channel.teamId, channel.roomId) && (connected || _connecting)) {
      return const Result.ok(null);
    }
    // Bumped before the hang-up so a later join, made while this one waits,
    // wins instead of being overwritten when this one resumes.
    final attempt = ++_attempt;
    await _hangUp();
    if (attempt != _attempt) return const Result.ok(null);
    _channel = channel;
    _connecting = true;
    _notice = null;
    _uid = _auth.currentUser?.uid;
    _allowedToSpeak = true;
    _watch(channel);
    notifyListeners();
    final result = await guard(() async {
      final access = await _functions.call('meetings-voiceToken', {
        'teamId': channel.teamId,
        'roomId': channel.roomId,
      });
      if (access is! Map) {
        throw const CallableException("Couldn't join the channel.");
      }
      final canSpeak = access['canSpeak'] == true;
      final settings = await _settings.load();
      final micOn =
          canSpeak && _allowedToSpeak && await _media.requestMicrophone();
      if (attempt != _attempt) return;
      final call = _media.createCall()..addListener(_onCall);
      _call = call;
      _tokenCanSpeak = canSpeak;
      await call.connect(
        MeetingAccess(url: '${access['url']}', token: '${access['token']}'),
        CallSetup(
          micOn: micOn,
          audioInputId: settings.audioInputId,
          audioOutputId: settings.audioOutputId,
        ),
      );
    });
    if (attempt != _attempt) return result;
    _connecting = false;
    if (result is Error) {
      await _hangUp();
      _channel = null;
    } else {
      // Rights may have gone while connecting.
      _check(force: true);
    }
    notifyListeners();
    return result;
  }

  void _watch(VoiceChannel channel) {
    _teamWatch?.cancel();
    _roomWatch?.cancel();
    _teamWatch = _Watch(
      () => _teams.watchTeam(channel.teamId),
      onData: (_) => _check(),
      onDenied: _lostAccess,
    );
    _roomWatch = _Watch(
      () => _chats.watchRoom(channel.teamId, channel.roomId),
      onData: (_) => _check(),
      onDenied: _lostAccess,
    );
  }

  /// Re-checks access once both the team and the room have loaded. With
  /// [force], applies the mic rule even if nothing changed.
  void _check({bool force = false}) {
    final teamWatch = _teamWatch;
    final roomWatch = _roomWatch;
    final uid = _uid;
    if (teamWatch == null || roomWatch == null || uid == null) return;
    if (!teamWatch.loaded || !roomWatch.loaded) return;
    // A cached miss isn't a deletion or a removal; only once it's been seen.
    final team = teamWatch.value;
    if (team == null) {
      if (teamWatch.everSeen) _lostAccess();
      return;
    }
    final room = roomWatch.value;
    if (room == null) {
      if (roomWatch.everSeen) _drop('The voice channel closed.');
      return;
    }
    final access = room.accessFor(team, uid);
    if (!access.canRead) return _lostAccess();
    if (!force && _allowedToSpeak == access.canWrite) return;
    _allowedToSpeak = access.canWrite;
    final call = _call;
    if (!_allowedToSpeak && call != null && call.micOn) {
      unawaited(call.setMicOn(false).catchError((Object _) {}));
    }
    notifyListeners();
  }

  void _lostAccess() => _drop(voiceLostAccessNotice);

  void _drop(String notice) {
    if (_channel == null) return;
    _notice = notice;
    unawaited(leave());
  }

  void _onAuth() {
    if (_channel != null && _auth.currentUser?.uid != _uid) {
      unawaited(leave());
    }
  }

  void _onCall() {
    final call = _call;
    if (call != null && call.endReason != null) {
      _notice = switch (call.endReason!) {
        CallEndReason.removed => 'You joined this channel somewhere else.',
        CallEndReason.connectionLost => 'Lost the connection to voice.',
        CallEndReason.meetingEnded => 'The voice channel closed.',
      };
      unawaited(leave());
      return;
    }
    notifyListeners();
  }

  @override
  Future<Result<void>> leave() async {
    _attempt++;
    _connecting = false;
    _channel = null;
    await _hangUp();
    notifyListeners();
    return const Result.ok(null);
  }

  Future<void> _hangUp() async {
    final call = _call;
    _call = null;
    _tokenCanSpeak = false;
    _teamWatch?.cancel();
    _roomWatch?.cancel();
    _teamWatch = null;
    _roomWatch = null;
    if (call == null) return;
    call.removeListener(_onCall);
    try {
      await call.leave();
    } catch (_) {
      // Already gone.
    }
    call.dispose();
  }

  @override
  Future<Result<void>> setMicOn(bool on) => guard(() async {
    final call = _call;
    if (call == null || (on && !canSpeak)) return;
    if (on && !await _media.requestMicrophone()) {
      throw const CallableException(
        'Allow microphone access to talk in voice channels.',
      );
    }
    await call.setMicOn(on);
  });

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    unawaited(_hangUp());
    super.dispose();
  }
}

/// A stream that keeps watching: permission-denied goes to [onDenied]; any
/// other error, or the stream ending, resubscribes after a backoff of 1 s
/// doubling to 30 s.
class _Watch<T> {
  _Watch(this._open, {required this.onData, required this.onDenied}) {
    _start();
  }

  final Stream<T> Function() _open;
  final void Function(T value) onData;
  final void Function() onDenied;
  StreamSubscription<T>? _sub;
  Timer? _retry;
  var _failures = 0;
  var _closed = false;

  bool loaded = false;
  bool everSeen = false;
  T? value;

  void _start() {
    if (_closed) return;
    _sub = _open().listen(
      (v) {
        _failures = 0;
        loaded = true;
        value = v;
        if (v != null) everSeen = true;
        onData(v);
      },
      onError: (Object e) {
        if (_closed) return;
        if (e is FirebaseException && e.code == 'permission-denied') {
          onDenied();
          return;
        }
        unawaited(_sub?.cancel());
        _resubscribe();
      },
      onDone: _resubscribe,
    );
  }

  void _resubscribe() {
    if (_closed || (_retry?.isActive ?? false)) return;
    _sub = null;
    _retry = Timer(
      Duration(milliseconds: math.min(30000, 1000 << math.min(5, _failures++))),
      _start,
    );
  }

  void cancel() {
    _closed = true;
    _retry?.cancel();
    unawaited(_sub?.cancel());
  }
}
