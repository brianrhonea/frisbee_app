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

/// Creates a chat room or edits its name, folder and who can read and
/// write.
class ChatRoomSettingsViewModel extends ChangeNotifier {
  ChatRoomSettingsViewModel({
    required this.teamId,
    this.roomId,
    this.folderId,
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
      _chats.watchFolders(teamId).listen((f) {
        _folders = f;
        _foldersLoaded = true;
        _startNewRoom();
        notifyListeners();
      }, onError: (Object _) => _foldersLoaded = true),
      if (roomId != null)
        _chats.watchRoom(teamId, roomId!).listen((r) {
          // Load once; later changes would overwrite the user's edits.
          if (_draft != null || _roomMissing) return;
          _draft = r;
          _roomMissing = r == null;
          notifyListeners();
        }, onError: _onError),
    ];
  }

  /// A new room starts with its folder's access, once folders are known;
  /// open to everyone outside a folder.
  void _startNewRoom() {
    if (roomId != null || _draft != null) return;
    _draft = ChatRoom.newIn(
      _folders.where((f) => f.id == folderId).firstOrNull,
    );
  }

  /// Null when creating a room.
  final String? roomId;

  /// The folder a new room goes in, if any.
  final String? folderId;
  final String teamId;
  final ChatRepository _chats;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  /// Saves and returns the room id.
  late final Command0<String> save;

  /// Deletes the room with its messages and files.
  late final Command0<void> delete;

  Team? _team;
  List<ChatFolder> _folders = const [];
  bool _foldersLoaded = false;
  ChatRoom? _draft;
  bool _roomMissing = false;
  Object? _error;

  String get uid => _auth.currentUser?.uid ?? '';
  Team? get team => _team;
  ChatRoom? get room => _draft;
  bool get isNew => roomId == null;
  bool get loaded =>
      _team != null && _foldersLoaded && (_draft != null || _roomMissing);
  Object? get error => _error;

  bool get canManage => _team?.has(uid, TeamPermission.manageChats) ?? false;

  /// Deleting a room deletes its messages, so chat managers delete only
  /// rooms they can read. General stays.
  bool get canDelete {
    final room = _draft;
    final team = _team;
    return !isNew &&
        canManage &&
        room != null &&
        team != null &&
        !room.isGeneral &&
        room.accessFor(team, uid).canRead;
  }

  bool get canSave => canManage && (_draft?.name.trim().isNotEmpty ?? false);

  /// Audience ids whose access can be set ([ChatAudience]): everyone, the
  /// team's tiers and its custom roles. The owner always has full access.
  List<String> get audiences =>
      _team == null ? const [] : ChatAudience.choicesFor(_team!);

  String audienceLabel(String id) =>
      _team == null ? '' : ChatAudience.labelOf(_team!, id);

  /// Folders the room can go in.
  List<ChatFolder> get folders => _folders;

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

  /// What member [uid] gets from their tier and custom roles alone.
  ChatAccess accessByRole(String uid) {
    final room = _draft;
    final team = _team;
    if (room == null || team == null) return ChatAccess.none;
    var best = ChatAccess.none;
    for (final id in ChatAudience.idsFor(team, uid)) {
      final a = room.roleAccess(id);
      if (a.index > best.index) best = a;
    }
    return best;
  }

  /// [uid]'s tier and custom roles, for the people list.
  String rolesLabel(String uid) {
    final team = _team;
    final role = team?.roleOf(uid);
    if (team == null || role == null) return '';
    return [
      team.roleLabel(role),
      for (final r in team.rolesOf(uid)) r.name,
    ].join(', ');
  }

  void setName(String name) => _update(_draft?.withName(name));

  /// Text or voice; only while creating the room.
  void setKind(ChatRoomKind kind) => _update(_draft?.withKind(kind));

  void setRoleAccess(String audienceId, ChatAccess access) =>
      _update(_draft?.withRoleAccess(audienceId, access));

  void setFolder(String? folderId) => _update(_draft?.withFolder(folderId));

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
