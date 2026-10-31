import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/chat/chat_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

typedef ChatMember = ({String uid, String name, TeamRole role});

/// Creates a chat room or edits its name and who can read and write.
class ChatRoomSettingsViewModel extends ChangeNotifier {
  ChatRoomSettingsViewModel({
    required this.teamId,
    this.roomId,
    required TeamRepository teamRepository,
    required ChatRepository chatRepository,
    required AuthRepository authRepository,
  }) : _chats = chatRepository,
       _auth = authRepository {
    save = Command0<String>(_save);
    delete = Command0<void>(() => _chats.deleteRoom(teamId, roomId!));
    _subs = [
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        notifyListeners();
      }, onError: _onError),
      if (roomId != null)
        _chats.watchRoom(teamId, roomId!).listen((r) {
          // Load once; later changes would overwrite the user's edits.
          if (_draft != null || _roomMissing) return;
          _draft = r;
          _roomMissing = r == null;
          notifyListeners();
        }, onError: _onError),
    ];
    if (roomId == null) {
      // New rooms start open to everyone, admins writing.
      _draft = const ChatRoom(
        id: '',
        name: '',
        readRoles: {...TeamRole.values},
        writeRoles: {TeamRole.owner, TeamRole.coach, TeamRole.captain},
      );
    }
  }

  /// Null when creating a room.
  final String? roomId;
  final String teamId;
  final ChatRepository _chats;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  /// Saves and returns the room id.
  late final Command0<String> save;

  /// Deletes the room with its messages and files.
  late final Command0<void> delete;

  Team? _team;
  ChatRoom? _draft;
  bool _roomMissing = false;
  Object? _error;

  String get uid => _auth.currentUser?.uid ?? '';
  Team? get team => _team;
  ChatRoom? get room => _draft;
  bool get isNew => roomId == null;
  bool get loaded => _team != null && (_draft != null || _roomMissing);
  Object? get error => _error;

  bool get canManage => _team?.canEdit(uid) ?? false;

  /// Only the owner deletes rooms, since only they can read every one.
  /// General stays.
  bool get canDelete =>
      !isNew &&
      !(_draft?.isGeneral ?? true) &&
      _team?.roleOf(uid) == TeamRole.owner;

  bool get canSave => canManage && (_draft?.name.trim().isNotEmpty ?? false);

  /// Roles whose access can be set; the owner always has full access.
  List<TeamRole> get roles =>
      TeamRole.values.where((r) => r != TeamRole.owner).toList();

  /// Members who can be given access beyond their role, by name.
  List<ChatMember> get members {
    final team = _team;
    if (team == null) return const [];
    return [
      for (final e in team.members.entries)
        if (e.value != TeamRole.owner)
          (uid: e.key, name: team.nameOf(e.key), role: e.value),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void setName(String name) => _update(_draft?.withName(name));

  void setRoleAccess(TeamRole role, ChatAccess access) =>
      _update(_draft?.withRoleAccess(role, access));

  void setUserAccess(String uid, ChatAccess access) =>
      _update(_draft?.withUserAccess(uid, access));

  void _update(ChatRoom? room) {
    if (room == null) return;
    _draft = room;
    notifyListeners();
  }

  Future<Result<String>> _save() async {
    final room = _draft;
    final team = _team;
    if (room == null || team == null) {
      return Result.error(Exception('Room not loaded'));
    }
    if (room.name.trim().isEmpty) {
      return Result.error(Exception('Give the room a name.'));
    }
    return _chats.saveRoom(teamId, room.forMembersOf(team), uid);
  }

  void _onError(Object e) {
    _error = e;
    _roomMissing = true;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
