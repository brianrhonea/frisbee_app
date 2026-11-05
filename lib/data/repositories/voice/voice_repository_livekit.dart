import 'dart:async';

import '../../../domain/models/meeting.dart';
import '../../../utils/result.dart';
import '../../services/callable_client.dart';
import '../../services/meeting_call.dart';
import '../meeting/meeting_settings_repository.dart';
import 'voice_repository.dart';

/// Voice channels on LiveKit, through the same call service as meetings.
/// Tokens come from the `meetings-voiceToken` Cloud Function, which checks
/// the room's access lists like firestore.rules does.
class VoiceRepositoryLiveKit extends VoiceRepository {
  VoiceRepositoryLiveKit({
    required CallableClient functions,
    required MeetingMediaService media,
    required MeetingSettingsRepository settings,
  }) : _functions = functions,
       _media = media,
       _settings = settings;

  final CallableClient _functions;
  final MeetingMediaService _media;
  final MeetingSettingsRepository _settings;

  MeetingCall? _call;
  VoiceChannel? _channel;
  bool _connecting = false;
  bool _canSpeak = false;
  String? _notice;

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
  bool get canSpeak => _canSpeak;
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
    await _hangUp();
    final attempt = ++_attempt;
    _channel = channel;
    _connecting = true;
    _notice = null;
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
      final micOn = canSpeak && await _media.requestMicrophone();
      if (attempt != _attempt) return;
      final call = _media.createCall()..addListener(_onCall);
      _call = call;
      _canSpeak = canSpeak;
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
    }
    notifyListeners();
    return result;
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
    _canSpeak = false;
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
    if (call == null || (on && !_canSpeak)) return;
    if (on && !await _media.requestMicrophone()) {
      throw const CallableException(
        'Allow microphone access to talk in voice channels.',
      );
    }
    await call.setMicOn(on);
  });

  @override
  void dispose() {
    unawaited(_hangUp());
    super.dispose();
  }
}
