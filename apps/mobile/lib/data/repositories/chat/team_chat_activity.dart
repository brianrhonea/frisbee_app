import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/models/chat.dart';
import '../../../domain/models/team.dart';
import '../team/team_repository.dart';
import 'chat_repository.dart';

/// One team's chat as the inbox lists it. The same rules as
/// teamChatSummary in packages/shared/src/team_chats.ts (vectors in
/// packages/shared/fixtures/team_chats).
class TeamChatSummary {
  const TeamChatSummary({
    required this.team,
    this.rooms = const [],
    this.unreadRooms = const [],
  });

  /// From the team's [rooms] the user can read ([readable]) and their
  /// read times ([reads], room id → time). Voice channels are left out.
  factory TeamChatSummary.fromReadable(
    Team team,
    Iterable<ChatRoom> readable,
    Map<String, DateTime> reads,
  ) {
    final rooms = [
      for (final r in readable)
        if (!r.isVoice) r,
    ];
    final unread = [
      for (final r in rooms)
        if (r.unreadSince(reads[r.id])) r,
    ]..sort((a, b) => b.lastAt!.compareTo(a.lastAt!));
    return TeamChatSummary(team: team, rooms: rooms, unreadRooms: unread);
  }

  final Team team;

  /// The text rooms the user can read, in the team's order.
  final List<ChatRoom> rooms;

  /// Those with a message the user hasn't read, newest first.
  final List<ChatRoom> unreadRooms;

  bool get unread => unreadRooms.isNotEmpty;

  /// When its newest room last had a message; null before any.
  DateTime? get lastAt {
    DateTime? last;
    for (final r in rooms) {
      final at = r.lastAt;
      if (at != null && (last == null || at.isAfter(last))) last = at;
    }
    return last;
  }

  /// The room a tap opens: the only unread one, else the newest, else the
  /// first (General).
  ChatRoom? get openRoom {
    if (unreadRooms.length == 1) return unreadRooms.single;
    final last = lastAt;
    return rooms.where((r) => r.lastAt == last && last != null).firstOrNull ??
        rooms.firstOrNull;
  }

  /// "New in #general and #carpool", "Team chat" or "No messages yet".
  String get subtitle {
    if (unread) {
      final names = [for (final r in unreadRooms) '#${r.handle}'];
      final shown = names.length <= 2
          ? names.join(' and ')
          : '${names.take(2).join(', ')} and ${names.length - 2} more';
      return 'New in $shown';
    }
    return lastAt == null ? 'No messages yet' : 'Team chat';
  }
}

/// Every team and community chat of the user's, live: which rooms they can
/// read and which have messages they haven't (ChatRoom.lastAt against
/// their private read times). The inbox lists them; the shell counts the
/// unread ones on the Messages tab.
class TeamChatActivity extends ChangeNotifier {
  TeamChatActivity({
    required TeamRepository teamRepository,
    required ChatRepository chatRepository,
    required this.uid,
  }) : _chats = chatRepository {
    if (uid.isEmpty) {
      _loaded = true;
      return;
    }
    _teamSub = teamRepository
        .watchMyTeams(uid)
        .listen(
          _onTeams,
          onError: (Object _) {
            _loaded = true;
            notifyListeners();
          },
        );
    _readSub = _chats.watchReads(uid).listen((r) {
      _reads = r;
      notifyListeners();
    }, onError: (Object _) {});
  }

  final String uid;
  final ChatRepository _chats;
  StreamSubscription<List<Team>>? _teamSub;
  StreamSubscription<Object?>? _readSub;
  final _roomSubs = <String, StreamSubscription<List<ChatRoom>>>{};

  /// The key each team's rooms are watched by: its roles change who reads
  /// what, so a change in them re-asks.
  final _roomKeys = <String, String>{};
  final _rooms = <String, List<ChatRoom>>{};
  Map<String, Map<String, DateTime>> _reads = const {};
  List<Team> _teams = const [];
  bool _loaded = false;
  bool _disposed = false;

  bool get loaded => _loaded;

  void _onTeams(List<Team> teams) {
    _teams = teams;
    _loaded = true;
    final ids = {for (final t in teams) t.id};
    for (final id in _roomSubs.keys.toList()) {
      if (ids.contains(id)) continue;
      _roomSubs.remove(id)?.cancel();
      _roomKeys.remove(id);
      _rooms.remove(id);
    }
    for (final t in teams) {
      final key = [
        t.roleOf(uid)?.name,
        ...?t.memberRoles[uid],
        t.has(uid, TeamPermission.manageChats),
      ].join(',');
      if (_roomKeys[t.id] == key) continue;
      _roomKeys[t.id] = key;
      _roomSubs.remove(t.id)?.cancel();
      _roomSubs[t.id] = _chats.watchRooms(t, uid).listen((r) {
        _rooms[t.id] = r;
        if (!_disposed) notifyListeners();
      }, onError: (Object _) {});
    }
    notifyListeners();
  }

  /// Each team's chat, unread ones first, then newest, then by name.
  List<TeamChatSummary> get summaries {
    final out = <TeamChatSummary>[];
    for (final t in _teams) {
      out.add(
        TeamChatSummary.fromReadable(t, [
          for (final r in _rooms[t.id] ?? const <ChatRoom>[])
            if (r.accessFor(t, uid).canRead) r,
        ], _reads[t.id] ?? const {}),
      );
    }
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    out.sort((a, b) {
      if (a.unread != b.unread) return a.unread ? -1 : 1;
      final byTime = (b.lastAt ?? epoch).compareTo(a.lastAt ?? epoch);
      if (byTime != 0) return byTime;
      return a.team.name.toLowerCase().compareTo(b.team.name.toLowerCase());
    });
    return out;
  }

  /// Teams with a room the user hasn't read.
  int get unreadCount => summaries.where((s) => s.unread).length;

  @override
  void dispose() {
    _disposed = true;
    _teamSub?.cancel();
    _readSub?.cancel();
    for (final s in _roomSubs.values) {
      s.cancel();
    }
    super.dispose();
  }
}
