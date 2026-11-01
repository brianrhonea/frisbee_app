import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/chat/chat_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/team.dart';

/// Which inbox entries to list.
enum InboxFilter { all, unread }

/// One entry in the inbox: a direct-message conversation or a team chat
/// room.
sealed class InboxItem {
  const InboxItem();

  /// Unique across conversations and rooms.
  String get key;
  String get title;

  /// The last message, prefixed with its author.
  String get preview;
  DateTime? get lastAt;
  bool get unread;
}

class DirectItem extends InboxItem {
  const DirectItem({
    required this.conversation,
    required this.uid,
    required this.unread,
  });

  final Conversation conversation;
  final String uid;
  @override
  final bool unread;

  @override
  String get key => 'dm:${conversation.id}';

  @override
  String get title => conversation.otherName(uid);

  @override
  String get preview =>
      '${conversation.lastSenderId == uid ? 'You: ' : ''}'
      '${conversation.lastMessage}';

  @override
  DateTime? get lastAt => conversation.lastMessageAt;
}

class RoomItem extends InboxItem {
  const RoomItem({
    required this.team,
    required this.room,
    required this.uid,
    this.last,
  });

  final Team team;
  final ChatRoom room;
  final String uid;

  /// The room's newest message; null if it has none (or hasn't loaded).
  final ChatMessage? last;

  @override
  String get key => 'room:${team.id}/${room.id}';

  /// "Cascades · Team chat" for General, else "Cascades · Handlers".
  @override
  String get title =>
      '${team.name} · ${room.isGeneral ? (team.isCommunity ? 'Group chat' : 'Team chat') : room.name}';

  @override
  String get preview {
    final m = last;
    if (m == null) return 'No messages yet';
    final who = m.authorId == uid
        ? 'You'
        : m.authorName.split(RegExp(r'\s+')).first;
    final text = messagePreview(
      m.text,
      m.attachments.length,
      image: m.attachments.isNotEmpty && m.attachments.every((a) => a.isImage),
    );
    return '$who: $text';
  }

  @override
  DateTime? get lastAt => last?.createdAt ?? room.createdAt;

  /// Team rooms don't track what each member has read.
  @override
  bool get unread => false;

  int get memberCount => team.members.length;
}

/// The user's inbox: direct messages and the chat rooms of every team they
/// are on, newest first.
class InboxViewModel extends ChangeNotifier {
  InboxViewModel({
    required DirectMessageRepository directMessageRepository,
    required TeamRepository teamRepository,
    required ChatRepository chatRepository,
    required AuthRepository authRepository,
  }) : uid = authRepository.currentUser?.uid ?? '',
       _chats = chatRepository {
    _subs.add(
      directMessageRepository
          .watchConversations(uid)
          .listen(
            (c) {
              _conversations = c;
              _error = null;
              notifyListeners();
            },
            onError: (Object e) {
              _error = e;
              _conversations ??= const [];
              notifyListeners();
            },
          ),
    );
    _subs.add(
      teamRepository.watchMyTeams(uid).listen(_onTeams, onError: (_) {}),
    );
  }

  final String uid;
  final ChatRepository _chats;
  final List<StreamSubscription<Object?>> _subs = [];
  List<Conversation>? _conversations;
  Object? _error;

  final Map<String, Team> _teams = {};
  final Map<String, StreamSubscription<List<ChatRoom>>> _roomSubs = {};
  final Map<String, List<ChatRoom>> _rooms = {};
  final Map<String, StreamSubscription<List<ChatMessage>>> _lastSubs = {};
  final Map<String, ChatMessage?> _last = {};

  bool get loaded => _conversations != null;
  List<Conversation> get conversations => _conversations ?? const [];
  Object? get error => _error;

  bool isUnread(Conversation c) => c.isUnread(uid);

  // Team rooms ---------------------------------------------------------------

  void _onTeams(List<Team> teams) {
    final ids = {for (final t in teams) t.id};
    for (final id in _roomSubs.keys.toList()) {
      if (ids.contains(id)) continue;
      _roomSubs.remove(id)?.cancel();
      _rooms.remove(id);
      _teams.remove(id);
    }
    for (final t in teams) {
      _teams[t.id] = t;
      _roomSubs[t.id] ??= _chats.watchRooms(t, uid).listen((rooms) {
        _rooms[t.id] = rooms;
        _watchLastMessages();
        notifyListeners();
      }, onError: (Object _) {});
    }
    _watchLastMessages();
    notifyListeners();
  }

  /// Follows the newest message of each room the user can read.
  void _watchLastMessages() {
    final wanted = <String, (String, String)>{};
    for (final e in _rooms.entries) {
      final team = _teams[e.key];
      if (team == null) continue;
      for (final r in e.value) {
        if (r.accessFor(team, uid).canRead) {
          wanted['${team.id}/${r.id}'] = (team.id, r.id);
        }
      }
    }
    for (final key in _lastSubs.keys.toList()) {
      if (wanted.containsKey(key)) continue;
      _lastSubs.remove(key)?.cancel();
      _last.remove(key);
    }
    for (final MapEntry(:key, value: (teamId, roomId)) in wanted.entries) {
      _lastSubs[key] ??= _chats.watchMessages(teamId, roomId, limit: 1).listen((
        m,
      ) {
        _last[key] = m.lastOrNull;
        notifyListeners();
      }, onError: (Object _) {});
    }
  }

  // The list -----------------------------------------------------------------

  /// Every conversation with a message, and every readable team room,
  /// newest first.
  List<InboxItem> get allItems {
    final items = <InboxItem>[
      for (final c in conversations)
        DirectItem(conversation: c, uid: uid, unread: c.isUnread(uid)),
      for (final e in _rooms.entries)
        if (_teams[e.key] case final team?)
          for (final r in e.value)
            if (r.accessFor(team, uid).canRead)
              RoomItem(
                team: team,
                room: r,
                uid: uid,
                last: _last['${team.id}/${r.id}'],
              ),
    ];
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    items.sort((a, b) => (b.lastAt ?? epoch).compareTo(a.lastAt ?? epoch));
    return items;
  }

  InboxFilter _filter = InboxFilter.all;
  InboxFilter get filter => _filter;

  void setFilter(InboxFilter f) {
    if (_filter == f) return;
    _filter = f;
    notifyListeners();
  }

  String _query = '';
  String get query => _query;

  void setQuery(String q) {
    if (_query == q) return;
    _query = q;
    notifyListeners();
  }

  /// [allItems] narrowed by [filter] and [query].
  List<InboxItem> get items {
    final q = _query.trim().toLowerCase();
    return [
      for (final i in allItems)
        if ((_filter == InboxFilter.all || i.unread) &&
            (q.isEmpty || i.title.toLowerCase().contains(q)))
          i,
    ];
  }

  int get unreadCount => allItems.where((i) => i.unread).length;

  String? _selectedKey;

  /// The entry open beside the list on wide screens: the one picked, else
  /// the newest.
  InboxItem? get selected {
    final all = allItems;
    return all.where((i) => i.key == _selectedKey).firstOrNull ??
        all.firstOrNull;
  }

  /// Id of the selected direct-message conversation, if one is selected.
  String? get selectedId => switch (selected) {
    DirectItem(:final conversation) => conversation.id,
    _ => null,
  };

  void select(InboxItem item) {
    if (_selectedKey == item.key) return;
    _selectedKey = item.key;
    notifyListeners();
  }

  /// Selects the conversation with [id].
  void selectConversation(String id) {
    final item = allItems.whereType<DirectItem>().where(
      (i) => i.conversation.id == id,
    );
    if (item.isNotEmpty) select(item.first);
  }

  @override
  void dispose() {
    for (final s in [..._subs, ..._roomSubs.values, ..._lastSubs.values]) {
      s.cancel();
    }
    super.dispose();
  }
}
