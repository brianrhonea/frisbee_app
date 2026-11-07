import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/notification.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

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
  const InboxItem({
    required this.conversation,
    required this.uid,
    this.muted = false,
    this.typing,
  });

  final Conversation conversation;
  final String uid;

  /// The user silenced its notifications.
  final bool muted;

  /// "typing…" (or "Sam is typing…" in a group) while someone is; null
  /// otherwise.
  final String? typing;

  String get key => 'dm:${conversation.id}';

  String get title => conversation.titleFor(uid);

  bool get isGroup => conversation.isGroup;

  /// The other person in a direct conversation, for their photo.
  String get otherId => conversation.otherId(uid);

  /// Up to two other members of a group, for its stacked photos.
  List<({String uid, String name})> get faces => [
    for (final p in conversation.othersThan(uid).take(2))
      (uid: p, name: conversation.names[p] ?? 'Someone'),
  ];

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
    NotificationRepository? notificationRepository,
  }) : uid = authRepository.currentUser?.uid ?? '',
       _dms = directMessageRepository,
       _notices = notificationRepository {
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
    toggleMute = Command1<void, InboxItem>((i) async {
      final repo = _notices;
      if (repo == null) {
        return Result.error(Exception("Notifications aren't available."));
      }
      return repo.setConversationMuted(uid, i.conversation.id, muted: !i.muted);
    });
    _sub = directMessageRepository
        .watchConversations(uid)
        .listen(
          (c) {
            _conversations = c;
            _error = null;
            _watchTyping();
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _conversations ??= const [];
            notifyListeners();
          },
        );
    if (notificationRepository != null && uid.isNotEmpty) {
      _prefsSub = notificationRepository.watchPreferences(uid).listen((p) {
        _prefs = p;
        notifyListeners();
      }, onError: (Object _) {});
    }
  }

  final String uid;
  final DirectMessageRepository _dms;
  final NotificationRepository? _notices;
  late final StreamSubscription<List<Conversation>> _sub;
  StreamSubscription<NotificationPreferences>? _prefsSub;
  NotificationPreferences? _prefs;

  /// Archives a conversation, or brings an archived one back.
  late final Command1<void, InboxItem> archive;

  /// Deletes a conversation for the user only.
  late final Command1<void, InboxItem> delete;

  /// Silences a conversation's notifications, or turns them back on.
  late final Command1<void, InboxItem> toggleMute;

  /// Whether conversations can be muted here.
  bool get canMute => _notices != null;

  List<Conversation>? _conversations;
  Object? _error;

  bool get loaded => _conversations != null;
  List<Conversation> get conversations => _conversations ?? const [];
  Object? get error => _error;

  bool isUnread(Conversation c) => c.isUnread(uid);

  bool isMuted(String conversationId) =>
      _prefs?.isConversationMuted(conversationId) ?? false;

  InboxItem _item(Conversation c) => InboxItem(
    conversation: c,
    uid: uid,
    muted: isMuted(c.id),
    typing: typingIn(c),
  );

  List<InboxItem> _sorted(bool Function(Conversation) keep) {
    final items = [
      for (final c in conversations)
        if (keep(c)) _item(c),
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
    final item = conversations.where((c) => c.id == id).map(_item).firstOrNull;
    if (item != null) select(item);
  }

  // Typing ------------------------------------------------------------------

  /// How many of the newest conversations show who's typing; each is one
  /// small listener.
  static const typingWatched = 20;

  /// How long someone counts as typing after their last keystroke shows
  /// (as MessageThreadViewModel.typingFor).
  static const typingFor = Duration(seconds: 6);

  final _typingSubs = <String, StreamSubscription<Map<String, DateTime?>>>{};

  /// Conversation id → uid → the stamp last seen for them.
  final _typingSeen = <String, Map<String, DateTime?>>{};

  /// Conversation id → uid → when (on this device's clock) they stop
  /// counting as typing.
  final _typingUntil = <String, Map<String, DateTime>>{};
  Timer? _typingExpiry;

  /// Clock, replaceable in tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  void _watchTyping() {
    final wanted = {
      for (final i in allItems.take(typingWatched)) i.conversation.id,
    };
    for (final id in _typingSubs.keys.toList()) {
      if (wanted.contains(id)) continue;
      _typingSubs.remove(id)?.cancel();
      _typingSeen.remove(id);
      _typingUntil.remove(id);
    }
    for (final id in wanted) {
      _typingSubs[id] ??= _dms
          .watchTyping(id)
          .listen((t) => _onTyping(id, t), onError: (Object _) {});
    }
  }

  void _onTyping(String id, Map<String, DateTime?> typing) {
    final at = now();
    final seen = _typingSeen[id] ?? const {};
    final until = _typingUntil[id] ??= {};
    for (final MapEntry(key: who, value: stamp) in typing.entries) {
      if (who == uid) continue;
      // New or rewritten: they've just typed (see MessageThreadViewModel).
      if (!seen.containsKey(who) || seen[who] != stamp) {
        until[who] = at.add(typingFor);
      }
    }
    until.removeWhere((who, _) => !typing.containsKey(who));
    _typingSeen[id] = Map.of(typing);
    _scheduleTypingExpiry();
    notifyListeners();
  }

  void _scheduleTypingExpiry() {
    _typingExpiry?.cancel();
    final all = [for (final m in _typingUntil.values) ...m.values];
    if (all.isEmpty) return;
    final next = all.reduce((a, b) => a.isBefore(b) ? a : b);
    var wait = next.difference(now());
    if (wait.isNegative) wait = Duration.zero;
    _typingExpiry = Timer(wait + const Duration(milliseconds: 50), () {
      final at = now();
      for (final m in _typingUntil.values) {
        m.removeWhere((_, until) => !until.isAfter(at));
      }
      _scheduleTypingExpiry();
      notifyListeners();
    });
  }

  /// "typing…", or in a group "Sam is typing…"; null when nobody is.
  String? typingIn(Conversation c) {
    final at = now();
    final who = [
      for (final MapEntry(key: id, value: until)
          in (_typingUntil[c.id] ?? const <String, DateTime>{}).entries)
        if (until.isAfter(at)) id,
    ];
    if (who.isEmpty) return null;
    if (!c.isGroup) return 'typing…';
    final first = (c.names[who.first] ?? 'Someone').split(' ').first;
    return who.length == 1
        ? '$first is typing…'
        : '$first and ${who.length - 1} more are typing…';
  }

  @override
  void dispose() {
    archive.dispose();
    delete.dispose();
    toggleMute.dispose();
    _sub.cancel();
    _prefsSub?.cancel();
    for (final s in _typingSubs.values) {
      s.cancel();
    }
    _typingExpiry?.cancel();
    super.dispose();
  }
}
