import 'model_utils.dart';

/// A user's public listing in the people directory: name and photo only,
/// never their email. Written from the signed-in user's auth profile.
class UserProfile {
  const UserProfile({required this.uid, required this.name, this.photoUrl});

  final String uid;
  final String name;
  final String? photoUrl;

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) =>
      UserProfile(
        uid: uid,
        name: map['name'] as String? ?? '',
        photoUrl: map['photoUrl'] as String?,
      );

  Map<String, dynamic> toMap() => {
    'name': name,
    'keywords': searchKeywords(name),
    'photoUrl': photoUrl,
  };

  /// Whether every word of [query] starts a word of this name.
  bool matches(String query) => matchesSearch(name, query);
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

  /// uid → when they last opened the conversation.
  final Map<String, DateTime> readAt;

  static String idFor(String a, String b) =>
      (a.compareTo(b) < 0 ? [a, b] : [b, a]).join('_');

  /// The other person, seen by [me].
  String otherId(String me) =>
      participants.firstWhere((p) => p != me, orElse: () => me);

  String otherName(String me) => names[otherId(me)] ?? 'UltiUP user';

  bool get hasMessages => lastMessageAt != null;

  /// A message from the other person that [me] hasn't opened yet.
  bool isUnread(String me) {
    final last = lastMessageAt;
    if (last == null || lastSenderId == me || lastSenderId.isEmpty) {
      return false;
    }
    final read = readAt[me];
    return read == null || read.isBefore(last);
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
