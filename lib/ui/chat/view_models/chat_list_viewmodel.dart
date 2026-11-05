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

typedef RoomMove = ({ChatRoom room, String? folderId});
typedef Shift = ({String id, int by});

/// A room dropped into [folderId] (null for none) at [index] among that
/// folder's rooms as listed before the move.
typedef RoomDrop = ({String roomId, String? folderId, int index});

/// A folder dropped at [index] among the folders as listed before the move.
typedef FolderDrop = ({String folderId, int index});

/// Backs the team Chat tab: the rooms the member can see, in folders.
class ChatListViewModel extends ChangeNotifier {
  ChatListViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required ChatRepository chatRepository,
    required AuthRepository authRepository,
    required VoiceRepository voiceRepository,
  }) : _chats = chatRepository,
       _auth = authRepository,
       _voice = voiceRepository {
    _voice.addListener(notifyListeners);
    placeRoom = Command1<void, RoomDrop>(_placeRoom);
    placeFolder = Command1<void, FolderDrop>(_placeFolder);
    leaveVoice = Command0<void>(_voice.leave);
    toggleMic = Command0<void>(() => _voice.setMicOn(!_voice.micOn));
    saveFolder = Command1<String, ChatFolder>(_saveFolder);
    deleteFolder = Command1<void, String>(
      (id) => _chats.deleteFolder(teamId, id, rooms),
    );
    moveRoom = Command1<void, RoomMove>(_moveRoom);
    shiftRoom = Command1<void, Shift>(_shiftRoom);
    shiftFolder = Command1<void, Shift>(_shiftFolder);
    _teamSub = teamRepository.watchTeam(teamId).listen((t) {
      _team = t;
      _teamLoaded = true;
      _watchRooms();
      notifyListeners();
    }, onError: _onError);
    _folderSub = _chats.watchFolders(teamId).listen((f) {
      _folders = f;
      notifyListeners();
    }, onError: (Object _) {});
  }

  /// Creates or renames a folder (and sets its default access).
  late final Command1<String, ChatFolder> saveFolder;

  /// Deletes a folder; its rooms move out of it.
  late final Command1<void, String> deleteFolder;

  /// Moves a room into a folder (null for none), at the end.
  late final Command1<void, RoomMove> moveRoom;

  /// Moves a room up (-1) or down (+1) within its folder.
  late final Command1<void, Shift> shiftRoom;

  /// Moves a folder up (-1) or down (+1).
  late final Command1<void, Shift> shiftFolder;

  /// Drag and drop: puts a room in a folder at a place.
  late final Command1<void, RoomDrop> placeRoom;

  /// Drag and drop: puts a folder at a place.
  late final Command1<void, FolderDrop> placeFolder;

  /// Disconnects from voice, from the bar under the room list.
  late final Command0<void> leaveVoice;
  late final Command0<void> toggleMic;

  final String teamId;
  final ChatRepository _chats;
  final AuthRepository _auth;
  final VoiceRepository _voice;
  late final StreamSubscription<Team?> _teamSub;
  late final StreamSubscription<List<ChatFolder>> _folderSub;
  StreamSubscription<List<ChatRoom>>? _roomSub;
  String? _watchedKey;
  bool _ensuredGeneral = false;
  bool _ensuredVoice = false;

  Team? _team;
  bool _teamLoaded = false;
  List<ChatRoom>? _rooms;
  List<ChatFolder> _folders = const [];
  final _collapsed = <String>{};
  Object? _error;

  String get uid => _auth.currentUser?.uid ?? '';
  Team? get team => _team;
  bool get loaded => _teamLoaded && (_team == null || _rooms != null);
  List<ChatRoom> get rooms => _rooms ?? const [];
  List<ChatFolder> get folders => _folders;
  Object? get error => _error;

  /// Rooms by folder, in order. People who manage chats also see empty
  /// folders, so they can fill them.
  List<RoomGroup> get groups =>
      groupRooms(rooms, _folders, keepEmpty: canManage);

  /// Members who can manage chats create rooms and folders and set access.
  bool get canManage => _team?.has(uid, TeamPermission.manageChats) ?? false;

  bool isCollapsed(String folderId) => _collapsed.contains(folderId);

  // Voice --------------------------------------------------------------------

  /// The voice channel the user is in, on any team; null when they're not.
  VoiceChannel? get voiceChannel => _voice.channel;
  bool get voiceConnecting => _voice.connecting;
  bool get voiceConnected => _voice.connected;
  bool get micOn => _voice.micOn;
  bool get canSpeak => _voice.canSpeak;

  /// Who's in [room] with the user; empty unless they're in it too.
  List<CallParticipant> voiceParticipants(ChatRoom room) =>
      _voice.isIn(teamId, room.id) && _voice.connected
      ? _voice.participants
      : const [];

  void toggleFolder(String folderId) {
    if (!_collapsed.remove(folderId)) _collapsed.add(folderId);
    notifyListeners();
  }

  /// One-line description of who's in [room], for room lists.
  String audienceOf(ChatRoom room) =>
      _team == null ? '' : room.audienceOn(_team!);

  String audienceLabel(String id) =>
      _team == null ? '' : ChatAudience.labelOf(_team!, id);

  /// Audience ids a folder's default access can be set for.
  List<String> get audiences =>
      _team == null ? const [] : ChatAudience.choicesFor(_team!);

  String? _selectedId;

  /// The room open beside the list on wide screens: the one picked, else
  /// the first room the member can read.
  String? get selectedId {
    final picked = _selectedId;
    if (picked != null && rooms.any((r) => r.id == picked)) return picked;
    final readable = rooms.where((r) => accessTo(r).canRead);
    return (readable.where((r) => !r.isVoice).firstOrNull ??
            readable.firstOrNull)
        ?.id;
  }

  void select(String roomId) {
    if (_selectedId == roomId) return;
    _selectedId = roomId;
    notifyListeners();
  }

  ChatAccess accessTo(ChatRoom room) =>
      _team == null ? ChatAccess.none : room.accessFor(_team!, uid);

  /// Which rooms are visible depends on the tier, custom roles and Manage
  /// chats, so resubscribe when they change.
  void _watchRooms() {
    final team = _team;
    final role = team?.roleOf(uid);
    final key = team == null || role == null
        ? null
        : [
            role.name,
            team.has(uid, TeamPermission.manageChats),
            ...(team.memberRoles[uid]?.toList() ?? <String>[])..sort(),
          ].join('/');
    if (key == _watchedKey && _roomSub != null) return;
    _watchedKey = key;
    _roomSub?.cancel();
    _roomSub = null;
    _rooms = null;
    if (team == null || role == null) return;
    _roomSub = _chats.watchRooms(team, uid).listen((r) {
      _rooms = r;
      _error = null;
      _ensureGeneral();
      _ensureVoice();
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

  /// Teams made before voice channels get the defaults on an admin's
  /// visit, unless they already have voice channels or the folder.
  void _ensureVoice() {
    if (_ensuredVoice || !canManage) return;
    _ensuredVoice = true;
    if (rooms.any((r) => r.isVoice) ||
        _folders.any((f) => f.id == ChatRoom.voiceFolderId)) {
      return;
    }
    _chats.ensureVoiceRooms(teamId, uid);
  }

  Future<Result<void>> _placeRoom(RoomDrop d) {
    final room = rooms.where((r) => r.id == d.roomId).firstOrNull;
    if (room == null) return Future.value(const Result.ok(null));
    final folderId = _folders.any((f) => f.id == d.folderId)
        ? d.folderId
        : null;
    final before = _roomsIn(folderId);
    final from = before.indexWhere((r) => r.id == room.id);
    final siblings = [...before]..removeWhere((r) => r.id == room.id);
    // Dropping on a room further down puts it after that room.
    final at = d.index.clamp(0, siblings.length);
    siblings.insert(at, room.withFolder(folderId));
    if (from == at && room.folderId == folderId) {
      return Future.value(const Result.ok(null));
    }
    return _chats.arrange(
      teamId,
      rooms: [
        for (final (i, r) in siblings.indexed)
          if (r.position != i || r.id == room.id) r.withPosition(i),
      ],
    );
  }

  Future<Result<void>> _placeFolder(FolderDrop d) {
    final list = [..._folders];
    final from = list.indexWhere((f) => f.id == d.folderId);
    if (from < 0) return Future.value(const Result.ok(null));
    final folder = list.removeAt(from);
    final at = d.index.clamp(0, list.length);
    if (at == from) return Future.value(const Result.ok(null));
    list.insert(at, folder);
    return _chats.arrange(
      teamId,
      folders: _renumber(
        list,
        (f) => f.position,
        (f, i) => f.copyWith(position: i),
      ),
    );
  }

  Future<Result<String>> _saveFolder(ChatFolder folder) {
    if (folder.name.trim().isEmpty) {
      return Future.value(Result.error(Exception('Give the folder a name.')));
    }
    final placed = folder.isNew
        ? folder.copyWith(
            position: _folders.isEmpty
                ? 0
                : _folders.map((f) => f.position).reduce(_max) + 1,
          )
        : folder;
    return _chats.saveFolder(teamId, placed, uid);
  }

  static int _max(int a, int b) => a > b ? a : b;

  List<ChatRoom> _roomsIn(String? folderId) => groups
      .where((g) => g.folder?.id == folderId)
      .expand((g) => g.rooms)
      .toList();

  Future<Result<void>> _moveRoom(RoomMove m) {
    final siblings = _roomsIn(m.folderId);
    final position = siblings.isEmpty
        ? 0
        : siblings.map((r) => r.position).reduce(_max) + 1;
    return _chats.arrange(
      teamId,
      rooms: [m.room.withFolder(m.folderId).withPosition(position)],
    );
  }

  /// Renumbers [items] in their new order, keeping only those whose
  /// position changed.
  static List<T> _renumber<T>(
    List<T> items,
    int Function(T) position,
    T Function(T, int) withPosition,
  ) => [
    for (final (i, item) in items.indexed)
      if (position(item) != i) withPosition(item, i),
  ];

  Future<Result<void>> _shiftRoom(Shift s) {
    final room = rooms.where((r) => r.id == s.id).firstOrNull;
    if (room == null) return Future.value(const Result.ok(null));
    final known = _folders.any((f) => f.id == room.folderId);
    final siblings = _roomsIn(known ? room.folderId : null);
    final from = siblings.indexWhere((r) => r.id == s.id);
    final to = from + s.by;
    if (from < 0 || to < 0 || to >= siblings.length) {
      return Future.value(const Result.ok(null));
    }
    siblings.insert(to, siblings.removeAt(from));
    return _chats.arrange(
      teamId,
      rooms: _renumber(
        siblings,
        (r) => r.position,
        (r, i) => r.withPosition(i),
      ),
    );
  }

  Future<Result<void>> _shiftFolder(Shift s) {
    final list = [..._folders];
    final from = list.indexWhere((f) => f.id == s.id);
    final to = from + s.by;
    if (from < 0 || to < 0 || to >= list.length) {
      return Future.value(const Result.ok(null));
    }
    list.insert(to, list.removeAt(from));
    return _chats.arrange(
      teamId,
      folders: _renumber(
        list,
        (f) => f.position,
        (f, i) => f.copyWith(position: i),
      ),
    );
  }

  void _onError(Object e) {
    _error = e;
    _rooms ??= const [];
    notifyListeners();
  }

  @override
  void dispose() {
    _voice.removeListener(notifyListeners);
    _teamSub.cancel();
    _folderSub.cancel();
    _roomSub?.cancel();
    super.dispose();
  }
}
