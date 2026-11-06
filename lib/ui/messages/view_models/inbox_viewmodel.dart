import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../domain/models/direct_message.dart';
import '../../../utils/command.dart';

/// Which inbox entries to list.
enum InboxFilter {
  all,
  unread,

  /// Message requests waiting on the user.
  requests,

  /// Conversations the user archived.
  archived,
}

/// One entry in the inbox: a direct-message conversation.
class InboxItem {
  const InboxItem({required this.conversation, required this.uid});

  final Conversation conversation;
  final String uid;

  String get key => 'dm:${conversation.id}';

  String get title => conversation.titleFor(uid);

  bool get isGroup => conversation.isGroup;

  /// The last message, prefixed with "You: " when the user sent it.
  String get preview {
    final c = conversation;
    if (!c.hasMessages) return c.isGroup ? 'New group' : '';
    final from = c.lastSenderId == uid
        ? 'You: '
        : c.isGroup
        ? '${(c.names[c.lastSenderId] ?? 'Someone').split(' ').first}: '
        : '';
    return '$from${c.lastMessage}';
  }

  DateTime? get lastAt => conversation.lastMessageAt;

  bool get unread =>
      conversation.isUnread(uid) || conversation.isUnreadRequest(uid);

  bool get isRequest => conversation.isRequestFor(uid);

  bool get isArchived => conversation.isArchived;
}

/// The user's private messages, newest first. Team chats live on team
/// pages, not here.
class InboxViewModel extends ChangeNotifier {
  InboxViewModel({
    required DirectMessageRepository directMessageRepository,
    required AuthRepository authRepository,
  }) : uid = authRepository.currentUser?.uid ?? '',
       _dms = directMessageRepository {
    archive = Command1<void, InboxItem>(
      (i) => _dms.setArchived(
        i.conversation.id,
        uid,
        archived: !i.conversation.isArchived,
      ),
    );
    delete = Command1<void, InboxItem>(
      (i) => _dms.clearConversation(i.conversation.id, uid),
    );
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
  final DirectMessageRepository _dms;
  late final StreamSubscription<List<Conversation>> _sub;

  /// Archives a conversation, or brings an archived one back.
  late final Command1<void, InboxItem> archive;

  /// Deletes a conversation for the user only.
  late final Command1<void, InboxItem> delete;
  List<Conversation>? _conversations;
  Object? _error;

  bool get loaded => _conversations != null;
  List<Conversation> get conversations => _conversations ?? const [];
  Object? get error => _error;

  bool isUnread(Conversation c) => c.isUnread(uid);

  List<InboxItem> _sorted(bool Function(Conversation) keep) {
    final items = [
      for (final c in conversations)
        if (keep(c)) InboxItem(conversation: c, uid: uid),
    ];
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    items.sort((a, b) => (b.lastAt ?? epoch).compareTo(a.lastAt ?? epoch));
    return items;
  }

  /// Every conversation in the inbox, newest first: not requests waiting
  /// on the user, and not archived or deleted.
  List<InboxItem> get allItems => _sorted((c) => c.inInbox(uid));

  /// Message requests waiting on the user, newest first.
  List<InboxItem> get requestItems => _sorted((c) => c.isRequestFor(uid));

  /// Archived conversations, newest first.
  List<InboxItem> get archivedItems => _sorted(
    (c) =>
        c.hasMessages &&
        c.isArchived &&
        !c.isCleared &&
        !c.isRequestFor(uid) &&
        !c.isDeclinedBy(uid),
  );

  int get requestCount => requestItems.length;

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
    final source = switch (_filter) {
      InboxFilter.all => allItems,
      InboxFilter.unread => allItems.where((i) => i.unread),
      InboxFilter.requests => requestItems,
      InboxFilter.archived => archivedItems,
    };
    return [
      for (final i in source)
        if (q.isEmpty || i.title.toLowerCase().contains(q)) i,
    ];
  }

  int get unreadCount => allItems.where((i) => i.unread).length;

  String? _selectedKey;

  /// The conversation open beside the list on wide screens: the one picked,
  /// else the newest in the list.
  InboxItem? get selected {
    final all = items;
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
    final item = conversations
        .where((c) => c.id == id)
        .map((c) => InboxItem(conversation: c, uid: uid))
        .firstOrNull;
    if (item != null) select(item);
  }

  @override
  void dispose() {
    archive.dispose();
    delete.dispose();
    _sub.cancel();
    super.dispose();
  }
}
