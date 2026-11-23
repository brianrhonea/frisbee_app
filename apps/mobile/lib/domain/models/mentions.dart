// @mentions in team chat, like Discord: @everyone, @<role name> and
// @<member name> in a message's text. The composer suggests them; the
// message stores what it mentions (`mentions`), which the notifications
// trigger reads to reach those people even in a room they muted.
//
// Mirrors packages/shared/src/mentions.ts; both are checked against
// fixtures/mentions (test/shared_fixtures/mention_fixtures_test.dart).

/// Most people one message mentions by name, and most roles.
const maxMentionedUsers = 50;
const maxMentionedRoles = 20;

/// The word that mentions everyone who can read the room.
const everyoneMention = 'everyone';

/// An @mention of the user in a team room: their notification feed entry
/// (users/{uid}/notifications/mention_{teamId}_{roomId}, `mention: true`).
/// [text] is its body ("Cam mentioned you: ..."); [personal] when they were
/// named or reached by role, not @everyone. ChatMention in team_chats.ts.
class ChatMention {
  const ChatMention({
    required this.teamId,
    required this.roomId,
    required this.text,
    required this.at,
    this.personal = true,
  });

  final String teamId;
  final String roomId;
  final String text;
  final DateTime at;
  final bool personal;
}

enum MentionKind { everyone, role, user }

/// Someone or something a message can mention.
class MentionTarget {
  const MentionTarget(this.kind, this.id, this.label);

  final MentionKind kind;

  /// The uid or role id; 'everyone' for @everyone.
  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is MentionTarget &&
      other.kind == kind &&
      other.id == id &&
      other.label == label;

  @override
  int get hashCode => Object.hash(kind, id, label);
}

/// The team's members (uid → display name) and custom roles (id → name).
class MentionTargets {
  const MentionTargets({this.members = const {}, this.roles = const {}});

  final Map<String, String> members;
  final Map<String, String> roles;

  static const none = MentionTargets();
}

/// One @mention in a text: [start, end) covers the @ and the name.
class MentionSpan {
  const MentionSpan(this.start, this.end, this.kind, this.id);

  final int start;
  final int end;
  final MentionKind kind;
  final String id;
}

/// What a message mentions, as stored on it.
class Mentions {
  const Mentions({
    this.users = const [],
    this.roles = const [],
    this.everyone = false,
  });

  final List<String> users;
  final List<String> roles;
  final bool everyone;

  static const none = Mentions();

  bool get any => everyone || users.isNotEmpty || roles.isNotEmpty;

  Map<String, Object?> toMap() => {
    'users': users,
    'roles': roles,
    'everyone': everyone,
  };

  static Mentions fromMap(Object? raw) {
    if (raw is! Map) return none;
    List<String> ids(Object? l) => [
      if (l is List)
        for (final v in l)
          if (v is String) v,
    ];
    return Mentions(
      users: ids(raw['users']),
      roles: ids(raw['roles']),
      everyone: raw['everyone'] == true,
    );
  }

  /// Whether this mentions [uid] by name, by one of [roleIds], or everyone.
  bool reaches(String uid, Iterable<String> roleIds) =>
      everyone || users.contains(uid) || roleIds.any(roles.contains);
}

final _wordChar = RegExp(r'[\p{L}\p{N}_]', unicode: true);

bool _isWord(String text, int i) => _wordChar.hasMatch(text[i]);

const _kindOrder = {
  MentionKind.everyone: 0,
  MentionKind.role: 1,
  MentionKind.user: 2,
};

List<MentionTarget> _candidates(MentionTargets targets, bool groups) {
  final all = [
    if (groups)
      const MentionTarget(
        MentionKind.everyone,
        everyoneMention,
        everyoneMention,
      ),
    for (final r in targets.roles.entries)
      if (groups && r.value.trim().isNotEmpty)
        MentionTarget(MentionKind.role, r.key, r.value.trim()),
    for (final m in targets.members.entries)
      if (m.value.trim().isNotEmpty)
        MentionTarget(MentionKind.user, m.key, m.value.trim()),
  ];
  // The longest name wins: "@Sam Lee" over "@Sam". Then everyone, roles,
  // people. A stable sort, as JavaScript's.
  return _stableSort(
    all,
    (a, b) => b.label.length != a.label.length
        ? b.label.length - a.label.length
        : _kindOrder[a.kind]! - _kindOrder[b.kind]!,
  );
}

List<T> _stableSort<T>(List<T> list, int Function(T, T) compare) {
  final indexed = [for (final (i, v) in list.indexed) (i, v)];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1 - b.$1;
  });
  return [for (final (_, v) in indexed) v];
}

/// The @mentions in [text], in order. An @ starts one only at the start or
/// after a character that isn't a letter, digit or _ (so emails don't), and
/// the name must end at the end or before one. Names match ignoring case.
/// Without [groups], only people (for someone who can't mention roles).
List<MentionSpan> mentionSpans(
  String text,
  MentionTargets targets, {
  bool groups = true,
}) {
  if (!text.contains('@')) return const [];
  final list = _candidates(targets, groups);
  final lower = text.toLowerCase();
  final spans = <MentionSpan>[];
  var i = 0;
  while (i < text.length) {
    final at = text.indexOf('@', i);
    if (at < 0) break;
    if (at > 0 && _isWord(text, at - 1)) {
      i = at + 1;
      continue;
    }
    MentionTarget? hit;
    for (final c in list) {
      final end = at + 1 + c.label.length;
      if (lower.startsWith(c.label.toLowerCase(), at + 1) &&
          (end >= text.length || !_isWord(text, end))) {
        hit = c;
        break;
      }
    }
    if (hit == null) {
      i = at + 1;
      continue;
    }
    final end = at + 1 + hit.label.length;
    spans.add(MentionSpan(at, end, hit.kind, hit.id));
    i = end;
  }
  return spans;
}

/// What [text] mentions, to store on the message. @everyone and roles count
/// only when [canMentionGroups] (the owner and chat managers; the rules
/// agree), and each list is capped at its limit.
Mentions mentionsIn(
  String text,
  MentionTargets targets, {
  required bool canMentionGroups,
}) {
  final users = <String>[];
  final roles = <String>[];
  var everyone = false;
  for (final s in mentionSpans(text, targets, groups: canMentionGroups)) {
    switch (s.kind) {
      case MentionKind.user:
        if (!users.contains(s.id) && users.length < maxMentionedUsers) {
          users.add(s.id);
        }
      case MentionKind.role when canMentionGroups:
        if (!roles.contains(s.id) && roles.length < maxMentionedRoles) {
          roles.add(s.id);
        }
      case MentionKind.everyone when canMentionGroups:
        everyone = true;
      default:
        break;
    }
  }
  return Mentions(users: users, roles: roles, everyone: everyone);
}

/// The @word being typed just before [cursor], for suggestions: its start
/// (the @) and what's typed after it. Null when the cursor isn't in one.
/// Up to 30 characters, which may include spaces ("@Sam Le").
({int start, String query})? mentionQuery(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final before = text.substring(0, cursor);
  final at = before.lastIndexOf('@');
  if (at < 0 || (at > 0 && _isWord(before, at - 1))) return null;
  final query = before.substring(at + 1);
  if (query.length > 30 ||
      query.contains('\n') ||
      query.contains('@') ||
      query.startsWith(RegExp(r'\s'))) {
    return null;
  }
  return (start: at, query: query);
}

int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Suggestions for [query]: everyone and roles (when [canMentionGroups]),
/// then members, whose name or any word of it starts with the query. At
/// most [limit].
List<MentionTarget> mentionSuggestions(
  String query,
  MentionTargets targets, {
  required bool canMentionGroups,
  int limit = 8,
}) {
  final q = query.trim().toLowerCase();
  bool matches(String label) {
    final l = label.toLowerCase();
    return q.isEmpty ||
        l.startsWith(q) ||
        l.split(RegExp(r'\s+')).any((w) => w.startsWith(q));
  }

  final out = <MentionTarget>[];
  if (canMentionGroups) {
    if (matches(everyoneMention)) {
      out.add(
        const MentionTarget(
          MentionKind.everyone,
          everyoneMention,
          everyoneMention,
        ),
      );
    }
    final roles = targets.roles.entries.toList();
    roles.sort((a, b) => _byName(a.value, b.value));
    for (final r in roles) {
      if (r.value.trim().isNotEmpty && matches(r.value)) {
        out.add(MentionTarget(MentionKind.role, r.key, r.value.trim()));
      }
    }
  }
  final members = targets.members.entries.toList();
  members.sort((a, b) => _byName(a.value, b.value));
  for (final m in members) {
    if (m.value.trim().isNotEmpty && matches(m.value)) {
      out.add(MentionTarget(MentionKind.user, m.key, m.value.trim()));
    }
  }
  return out.take(limit).toList();
}

/// [text] with the @query at [start]..[cursor] replaced by the mention and
/// a space; and the new cursor.
({String text, int cursor}) insertMention(
  String text,
  int start,
  int cursor,
  String label,
) {
  final inserted = '@$label ';
  return (
    text: text.substring(0, start) + inserted + text.substring(cursor),
    cursor: start + inserted.length,
  );
}
