import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/chat/chat_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/voice/voice_repository.dart';
import '../../../data/services/meeting_call.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Backs a voice channel's page: who's in it and joining, muting and
/// leaving. The call itself lives in [VoiceRepository], so it carries on
/// when the user opens other rooms.
class VoiceChannelViewModel extends ChangeNotifier {
  VoiceChannelViewModel({
    required this.teamId,
    required this.roomId,
    required TeamRepository teamRepository,
    required ChatRepository chatRepository,
    required VoiceRepository voiceRepository,
    required AuthRepository authRepository,
  }) : _voice = voiceRepository,
       _auth = authRepository {
    join = Command0<void>(_join);
    leave = Command0<void>(_voice.leave);
    toggleMic = Command0<void>(() => _voice.setMicOn(!_voice.micOn));
    _voice.addListener(notifyListeners);
    _subs = [
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        _teamLoaded = true;
        notifyListeners();
      }, onError: _onError),
      chatRepository.watchRoom(teamId, roomId).listen((r) {
        _room = r;
        _roomLoaded = true;
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final String roomId;
  final VoiceRepository _voice;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  late final Command0<void> join;
  late final Command0<void> leave;
  late final Command0<void> toggleMic;

  Team? _team;
  ChatRoom? _room;
  bool _teamLoaded = false;
  bool _roomLoaded = false;
  Object? _error;

  String get uid => _auth.currentUser?.uid ?? '';
  Team? get team => _team;
  ChatRoom? get room => _room;
  bool get loaded => _teamLoaded && _roomLoaded;
  Object? get error => _error;

  ChatAccess get access => switch ((_team, _room)) {
    (final t?, final r?) => r.accessFor(t, uid),
    _ => ChatAccess.none,
  };

  bool get canManage => _team?.has(uid, TeamPermission.manageChats) ?? false;

  /// Whether the user is in (or joining) this channel.
  bool get isHere => _voice.isIn(teamId, roomId);
  bool get connecting => isHere && _voice.connecting;
  bool get connected => isHere && _voice.connected;

  /// The channel the user is in elsewhere, which joining here leaves.
  VoiceChannel? get elsewhere => isHere ? null : _voice.channel;

  bool get micOn => isHere && _voice.micOn;

  /// Whether the user may talk here; listeners join muted.
  bool get canSpeak => isHere ? _voice.canSpeak : access.canWrite;

  List<CallParticipant> get participants =>
      connected ? _voice.participants : const [];

  /// Why the call dropped, shown until the next join.
  String? get notice => isHere ? null : _voice.notice;

  Future<Result<void>> _join() {
    final room = _room;
    if (room == null || !access.canRead) {
      return Future.value(
        Result.error(Exception("You don't have access to this channel.")),
      );
    }
    return _voice.join(
      VoiceChannel(
        teamId: teamId,
        roomId: roomId,
        name: room.name,
        teamName: _team?.name ?? '',
      ),
    );
  }

  void _onError(Object e) {
    _error = e;
    _teamLoaded = true;
    _roomLoaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _voice.removeListener(notifyListeners);
    for (final s in _subs) {
      s.cancel();
    }
    join.dispose();
    leave.dispose();
    toggleMic.dispose();
    super.dispose();
  }
}
