import 'model_utils.dart';
import 'username.dart';

/// A user's public listing in the people directory: name and photo only,
/// never their email. Written from the signed-in user's auth profile.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.username,
  });

  final String uid;
  final String name;
  final String? photoUrl;

  /// Unique handle, without the "@"; null for people who haven't picked
  /// one yet.
  final String? username;

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) =>
      UserProfile(
        uid: uid,
        name: map['name'] as String? ?? '',
        photoUrl: map['photoUrl'] as String?,
        username: map['username'] as String?,
      );

  /// The fields anyone may rewrite. The username itself is written only
  /// when it's claimed (see AuthRepository.claimUsername); it's indexed
  /// here so people can search by it.
  Map<String, dynamic> toMap() => {
    'name': name,
    'keywords': profileKeywords(name, username),
    'photoUrl': photoUrl,
  };

  /// Whether every word of [query] starts a word of this name or
  /// username.
  bool matches(String query) =>
      matchesSearch('$name ${username ?? ''}', Username.normalize(query));
}

/// Who may start a conversation with someone (`messagePolicy` on their
/// private `users/{uid}` doc, which firestore.rules checks). People they
/// follow always reach their inbox, except with [nobody].
enum MessagePolicy {
  /// Anyone; people they don't follow land in Message requests.
  everyone('Everyone', 'People you don\'t follow go to Message requests.'),

  /// Their followers and people they follow; followers they don't follow
  /// back land in Message requests.
  followers(
    'Followers and people you follow',
    'Followers you don\'t follow back go to Message requests.',
  ),

  /// Only people they follow.
  following('Only people you follow', 'Nobody else can message you.'),

  /// Nobody new; existing conversations carry on.
  nobody('No one', 'Conversations you already have carry on.');

  const MessagePolicy(this.label, this.description);

  final String label;
  final String description;

  static MessagePolicy parse(Object? name) => MessagePolicy.values.firstWhere(
    (p) => p.name == name,
    orElse: () => MessagePolicy.everyone,
  );
}

/// Where a conversation stands with the person it was started with.
enum ConversationStatus {
  /// In both inboxes.
  accepted,

  /// Waiting in [Conversation.requestedOf]'s Message requests. They can
  /// read it without the sender knowing, then accept or delete it.
  request,

  /// Deleted from Message requests: the recipient never sees it again,
  /// and nothing tells the sender.
  declined;

  static ConversationStatus parse(Object? name) =>
      ConversationStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => ConversationStatus.accepted,
      );
}

/// The signed-in user's private record of a conversation, at
/// `users/{uid}/dmReads/{id}`: when they last read it, archived it, or
/// deleted it for themselves.
class ConversationPrivate {
  const ConversationPrivate({this.readAt, this.archivedAt, this.clearedAt});

  final DateTime? readAt;

  /// Archived: out of the inbox until a newer message arrives.
  final DateTime? archivedAt;

  /// Deleted for them: messages up to then are hidden, and the
  /// conversation stays out of the inbox until a newer one arrives.
  final DateTime? clearedAt;

  factory ConversationPrivate.fromMap(Map<String, dynamic> map) =>
      ConversationPrivate(
        readAt: parseDate(map['readAt']),
        archivedAt: parseDate(map['archivedAt']),
        clearedAt: parseDate(map['clearedAt']),
      );
}

/// A private conversation between two users. Its id is their uids, sorted
/// and joined with `_`, so each pair has exactly one.
class Conversation {
  const Conversation({
    required this.id,
    required this.participants,
    this.names = const {},
    this.lastMessage = '',
    this.lastMessageAt,
    this.lastSenderId = '',
    this.readAt = const {},
    this.status = ConversationStatus.accepted,
    this.requestedOf,
    this.mine = const ConversationPrivate(),
  });

  final String id;
  final List<String> participants;

  /// uid → display name, as each person last sent it.
  final Map<String, String> names;

  /// A short preview of the newest message.
  final String lastMessage;

  /// Null until the first message.
  final DateTime? lastMessageAt;
  final String lastSenderId;

  /// uid → when they last opened the conversation, shared with the other
  /// person as a read receipt. People who turn read receipts off stop
  /// updating theirs (see [myReadAt]).
  final Map<String, DateTime> readAt;

  /// Accepted, or a message request (to [requestedOf]).
  final ConversationStatus status;

  /// Who a message request is waiting on; null once accepted.
  final String? requestedOf;

  /// The signed-in user's private record of it; empty if not loaded.
  final ConversationPrivate mine;

  /// When the signed-in user last opened it, from their private record;
  /// kept even with read receipts off. Null if never, or not loaded.
  DateTime? get myReadAt => mine.readAt;

  Conversation copyWith({
    Map<String, String>? names,
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastSenderId,
    Map<String, DateTime>? readAt,
    ConversationStatus? status,
  }) => Conversation(
    id: id,
    participants: participants,
    names: names ?? this.names,
    lastMessage: lastMessage ?? this.lastMessage,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    lastSenderId: lastSenderId ?? this.lastSenderId,
    readAt: readAt ?? this.readAt,
    status: status ?? this.status,
    requestedOf: requestedOf,
    mine: mine,
  );

  Conversation withMine(ConversationPrivate? mine) => Conversation(
    id: id,
    participants: participants,
    names: names,
    lastMessage: lastMessage,
    lastMessageAt: lastMessageAt,
    lastSenderId: lastSenderId,
    readAt: readAt,
    status: status,
    requestedOf: requestedOf,
    mine: mine ?? const ConversationPrivate(),
  );

  Conversation withMyReadAt(DateTime? at) => withMine(
    ConversationPrivate(
      readAt: at,
      archivedAt: mine.archivedAt,
      clearedAt: mine.clearedAt,
    ),
  );

  static String idFor(String a, String b) =>
      (a.compareTo(b) < 0 ? [a, b] : [b, a]).join('_');

  /// The other person, seen by [me].
  String otherId(String me) =>
      participants.firstWhere((p) => p != me, orElse: () => me);

  String otherName(String me) => names[otherId(me)] ?? 'Stall 10 user';

  bool get hasMessages => lastMessageAt != null;

  /// A message request waiting on [me] to accept or delete it.
  bool isRequestFor(String me) =>
      status == ConversationStatus.request && requestedOf == me;

  /// A request [me] sent that hasn't been accepted (or was quietly
  /// declined: the sender can't tell).
  bool isPendingFrom(String me) =>
      status != ConversationStatus.accepted &&
      requestedOf != null &&
      requestedOf != me;

  /// Whether [me] declined it from their requests.
  bool isDeclinedBy(String me) =>
      status == ConversationStatus.declined && requestedOf == me;

  /// Nothing has happened since [at].
  bool _quietSince(DateTime? at) {
    final last = lastMessageAt;
    return at != null && (last == null || !last.isAfter(at));
  }

  /// Archived by the signed-in user, with nothing newer since.
  bool get isArchived => _quietSince(mine.archivedAt);

  /// Deleted by the signed-in user, with nothing newer since.
  bool get isCleared => _quietSince(mine.clearedAt);

  /// Messages from before this are hidden from the signed-in user.
  DateTime? get hiddenBefore => mine.clearedAt;

  /// In [me]'s inbox: has messages, isn't a request to them (or one they
  /// declined), and they haven't archived or deleted it since.
  bool inInbox(String me) =>
      hasMessages &&
      !isRequestFor(me) &&
      !isDeclinedBy(me) &&
      !isArchived &&
      !isCleared;

  /// A message from the other person that [me] hasn't opened yet. Requests
  /// and archived or deleted conversations count separately.
  bool isUnread(String me) {
    final last = lastMessageAt;
    if (last == null || lastSenderId == me || lastSenderId.isEmpty) {
      return false;
    }
    if (isRequestFor(me) || isDeclinedBy(me) || isArchived || isCleared) {
      return false;
    }
    return _unreadBy(me, last);
  }

  /// A message request [me] hasn't opened since its newest message.
  bool isUnreadRequest(String me) {
    final last = lastMessageAt;
    return isRequestFor(me) && last != null && _unreadBy(me, last);
  }

  bool _unreadBy(String me, DateTime last) {
    final shared = readAt[me];
    final mine = myReadAt;
    final read = shared == null || (mine != null && mine.isAfter(shared))
        ? mine
        : shared;
    return read == null || read.isBefore(last);
  }

  /// Whether the other person has read [me]'s latest message, by their
  /// read receipt.
  bool isSeen(String me) {
    final last = lastMessageAt;
    if (last == null || lastSenderId != me) return false;
    final theirs = readAt[otherId(me)];
    return theirs != null && !theirs.isBefore(last);
  }

  factory Conversation.fromMap(String id, Map<String, dynamic> map) =>
      Conversation(
        id: id,
        participants: [
          for (final p in (map['participants'] as List?) ?? const []) '$p',
        ],
        names: {
          for (final e in ((map['names'] as Map?) ?? const {}).entries)
            '${e.key}': '${e.value}',
        },
        lastMessage: map['lastMessage'] as String? ?? '',
        lastMessageAt: parseDate(map['lastMessageAt']),
        lastSenderId: map['lastSenderId'] as String? ?? '',
        readAt: {
          for (final e in ((map['readAt'] as Map?) ?? const {}).entries)
            '${e.key}': ?parseDate(e.value),
        },
        status: ConversationStatus.parse(map['status']),
        requestedOf: map['requestedOf'] as String?,
      );
}

/// Preview text for a message: its text, else what's attached.
String messagePreview(String text, int attachments, {bool image = false}) {
  final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isNotEmpty) return t.length > 120 ? '${t.substring(0, 117)}…' : t;
  if (attachments == 0) return '';
  if (image) return attachments == 1 ? '📷 Photo' : '📷 $attachments photos';
  return attachments == 1 ? '📎 File' : '📎 $attachments files';
}
