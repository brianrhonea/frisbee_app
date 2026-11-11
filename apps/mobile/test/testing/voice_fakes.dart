import 'package:frisbee_app/data/repositories/voice/voice_repository.dart';
import 'package:frisbee_app/data/services/meeting_call.dart';
import 'package:frisbee_app/utils/result.dart';

/// Joins at once; [failWith] makes the next join fail.
class FakeVoiceRepository extends VoiceRepository {
  FakeVoiceRepository({this.me = 'u1', this.speaks = true});

  final String me;
  bool speaks;
  Exception? failWith;
  final joins = <VoiceChannel>[];

  VoiceChannel? _channel;
  bool _micOn = false;
  List<CallParticipant> others = const [];

  @override
  VoiceChannel? get channel => _channel;
  @override
  bool get connecting => false;
  @override
  bool get connected => _channel != null;
  @override
  bool get canSpeak => _channel != null && speaks;
  @override
  bool get micOn => _micOn;
  @override
  String? notice;

  @override
  List<CallParticipant> get participants => _channel == null
      ? const []
      : [
          CallParticipant(uid: me, name: 'Me', isLocal: true, micOn: _micOn),
          ...others,
        ];

  @override
  Future<Result<void>> join(VoiceChannel channel) async {
    joins.add(channel);
    if (failWith case final e?) {
      failWith = null;
      return Result.error(e);
    }
    _channel = channel;
    _micOn = speaks;
    notifyListeners();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> leave() async {
    _channel = null;
    _micOn = false;
    notifyListeners();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setMicOn(bool on) async {
    _micOn = on && speaks;
    notifyListeners();
    return const Result.ok(null);
  }
}
