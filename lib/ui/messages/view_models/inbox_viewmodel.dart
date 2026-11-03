import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../domain/models/direct_message.dart';

/// Which inbox entries to list.
enum InboxFilter { all, unread }

/// One entry in the inbox: a direct-message conversation.
class InboxItem {
  const InboxItem({required this.conversation, required this.uid});

  final Conversation conversation;
  final String uid;

  String get key => 'dm:${conversation.id}';

  String get title => conversation.otherName(uid);

  /// The last message, prefixed with "You: " when the user sent it.
  String get preview =>
      '${conversation.lastSenderId == uid ? 'You: ' : ''}'
      '${conversation.lastMessage}';

  DateTime? get lastAt => conversation.lastMessageAt;

  bool get unread => conversation.isUnread(uid);
}

/// The user's private messages, newest first. Team chats live on team
/// pages, not here.
class InboxViewModel extends ChangeNotifier {
  InboxViewModel({
    required DirectMessageRepository directMessageRepository,
    required AuthRepository authRepository,
  }) : uid = authRepository.currentUser?.uid ?? '' {
    _sub = directMessageRepository
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
        );
  }

  final String uid;
  late final StreamSubscription<List<Conversation>> _sub;
  List<Conversation>? _conversations;
  Object? _error;

  bool get loaded => _conversations != null;
  List<Conversation> get conversations => _conversations ?? const [];
  Object? get error => _error;

  bool isUnread(Conversation c) => c.isUnread(uid);

  /// Every conversation, newest first.
  List<InboxItem> get allItems {
    final items = [
      for (final c in conversations) InboxItem(conversation: c, uid: uid),
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

  /// The conversation open beside the list on wide screens: the one picked,
  /// else the newest.
  InboxItem? get selected {
    final all = allItems;
    return all.where((i) => i.key == _selectedKey).firstOrNull ??
        all.firstOrNull;
  }

  /// Id of the selected conversation.
  String? get selectedId => selected?.conversation.id;

  void select(InboxItem item) {
    if (_selectedKey == item.key) return;
    _selectedKey = item.key;
    notifyListeners();
  }

  /// Selects the conversation with [id].
  void selectConversation(String id) {
    final item = allItems.where((i) => i.conversation.id == id).firstOrNull;
    if (item != null) select(item);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
