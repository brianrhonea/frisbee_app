import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/chat/chat_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/team.dart';

/// Backs the team Chat tab: the rooms the member can see.
class ChatListViewModel extends ChangeNotifier {
  ChatListViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required ChatRepository chatRepository,
    required AuthRepository authRepository,
  }) : _chats = chatRepository,
       _auth = authRepository {
    _teamSub = teamRepository.watchTeam(teamId).listen((t) {
      _team = t;
      _teamLoaded = true;
      _watchRooms();
      notifyListeners();
    }, onError: _onError);
  }

  final String teamId;
  final ChatRepository _chats;
  final AuthRepository _auth;
  late final StreamSubscription<Team?> _teamSub;
  StreamSubscription<List<ChatRoom>>? _roomSub;
  TeamRole? _watchedRole;
  bool _ensuredGeneral = false;

  Team? _team;
  bool _teamLoaded = false;
  List<ChatRoom>? _rooms;
  Object? _error;

  String get uid => _auth.currentUser?.uid ?? '';
  Team? get team => _team;
  bool get loaded => _teamLoaded && (_team == null || _rooms != null);
  List<ChatRoom> get rooms => _rooms ?? const [];
  Object? get error => _error;

  /// Owners, coaches and captains create rooms and set their access.
  bool get canManage => _team?.canEdit(uid) ?? false;

  String? _selectedId;

  /// The room open beside the list on wide screens: the one picked, else
  /// the first room the member can read.
  String? get selectedId {
    final picked = _selectedId;
    if (picked != null && rooms.any((r) => r.id == picked)) return picked;
    return rooms.where((r) => accessTo(r).canRead).firstOrNull?.id;
  }

  void select(String roomId) {
    if (_selectedId == roomId) return;
    _selectedId = roomId;
    notifyListeners();
  }

  ChatAccess accessTo(ChatRoom room) =>
      _team == null ? ChatAccess.none : room.accessFor(_team!, uid);

  /// Which rooms are visible depends on the role, so resubscribe when it
  /// changes.
  void _watchRooms() {
    final team = _team;
    final role = team?.roleOf(uid);
    if (role == _watchedRole && _roomSub != null) return;
    _watchedRole = role;
    _roomSub?.cancel();
    _roomSub = null;
    _rooms = null;
    if (team == null || role == null) return;
    _roomSub = _chats.watchRooms(team, uid).listen((r) {
      _rooms = r;
      _error = null;
      _ensureGeneral();
      notifyListeners();
    }, onError: _onError);
  }

  /// Teams made before chat have no General room; an admin's visit adds it.
  void _ensureGeneral() {
    if (_ensuredGeneral || !canManage) return;
    if (rooms.any((r) => r.isGeneral)) return;
    _ensuredGeneral = true;
    _chats.ensureGeneralRoom(teamId, uid);
  }

  void _onError(Object e) {
    _error = e;
    _rooms ??= const [];
    notifyListeners();
  }

  @override
  void dispose() {
    _teamSub.cancel();
    _roomSub?.cancel();
    super.dispose();
  }
}
