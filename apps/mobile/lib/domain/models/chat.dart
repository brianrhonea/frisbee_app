import 'dart:typed_data';

import 'model_utils.dart';
import 'team.dart';

/// What a member may do in a chat room.
enum ChatAccess {
  none('No access'),
  read('Read only'),
  write('Read & write');

  const ChatAccess(this.label);
  final String label;

  bool get canRead => this != none;
  bool get canWrite => this == write;
}

/// Attachments (photos and files) are capped at 10 MB, videos at
/// [maxVideoBytes]. storage.rules enforces the same limits; keep them in
/// step.
const maxAttachmentBytes = 10 * 1024 * 1024;

/// Videos in messages, which play in the conversation.
const maxVideoBytes = 100 * 1024 * 1024;

/// The most a file of [contentType] may be.
int maxBytesFor(String contentType) =>
    contentType.startsWith('video/') ? maxVideoBytes : maxAttachmentBytes;

class AttachmentTooLargeException implements Exception {
  const AttachmentTooLargeException(
    this.name, {
    this.limit = maxAttachmentBytes,
  });

  final String name;
  final int limit;

  @override
  String toString() => '$name is larger than ${formatFileSize(limit)}.';
}

//// Who a room or folder lets in: the ids that can go in its access lists.
/// [everyone] is every member; the team tiers (`coach`, `captain`,
/// `player`) are their own ids; anything else is a custom role id
/// ([Team.roles]). firestore.rules reads the same ids.
abstract final class ChatAudience {
  static const everyone = 'everyone';

  /// The ids [uid] counts as on [team]: everyone, their tier and their
  /// custom roles. Empty for non-members.
  static Set<String> idsFor(Team team, String uid) {
    final role = team.roleOf(uid);
    if (role == null) return const {};
    return {everyone, role.name, ...?team.memberRoles[uid]};
  }

  /// Ids an access editor offers on [team], in order: everyone, then
  /// custom roles. Rooms may still list legacy tiers (coach, captain,
  /// player); those keep working but aren't offered.
  static List<String> choicesFor(Team team) => [
    everyone,
    for (final r in team.sortedRoles) r.id,
  ];

  /// Display name of [id] on [team].
  static String labelOf(Team team, String id) {
    if (id == everyone) return 'Everyone';
    if (team.roles[id] case final r?) return r.name;
    for (final r in TeamRole.values) {
      if (r.name == id) return team.roleLabel(r);
    }
    return 'Deleted role';
  }

  /// Plural display name of [id], for room lists.
  static String pluralLabelOf(Team team, String id) {
    for (final r in TeamRole.values) {
      if (r.name == id) return r.pluralLabelFor(team.kind);
    }
    return labelOf(team, id);
  }
}

/// Access to a room, or the default for new rooms in a folder: per
/// audience id ([ChatAudience]) and per member. Write access always
/// includes read.
mixin ChatAccessLists {
  /// Ids that can read; includes [writeRoles].
  Set<String> get readRoles;
  Set<String> get writeRoles;

  /// Members (uids) who can read whatever their roles; includes
  /// [writeUsers].
  Set<String> get readUsers;
  Set<String> get writeUsers;

  /// Access for audience [id], ignoring per-member grants.
  ChatAccess roleAccess(String id) => writeRoles.contains(id)
      ? ChatAccess.write
      : readRoles.contains(id)
      ? ChatAccess.read
      : ChatAccess.none;

  /// Access granted to member [uid] directly, on top of their roles.
  ChatAccess userAccess(String uid) => writeUsers.contains(uid)
      ? ChatAccess.write
      : readUsers.contains(uid)
      ? ChatAccess.read
      : ChatAccess.none;

  /// What member [uid] of [team] can do here.
  ChatAccess accessFor(Team team, String uid) {
    final role = team.roleOf(uid);
    if (role == null) return ChatAccess.none;
    if (role == TeamRole.owner) return ChatAccess.write;
    var best = userAccess(uid);
    for (final id in ChatAudience.idsFor(team, uid)) {
      final a = roleAccess(id);
      if (a.index > best.index) best = a;
    }
    return best;
  }

  /// One-line description of who's in, for room lists.
  String audienceOn(Team team) {
    if (readRoles.contains(ChatAudience.everyone)) return 'Everyone';
    final tiers = [
      for (final r in TeamRole.rolesFor(team.kind))
        if (r != TeamRole.owner) r.name,
    ];
    // Rooms from before "everyone" list every tier instead.
    if (tiers.every(readRoles.contains)) return 'Everyone';
    final people = readUsers.length;
    final names = [
      for (final id in [
        // Legacy tiers first, as the access editor used to list them.
        for (final r in TeamRole.values)
          if (r != TeamRole.owner) r.name,
        ...ChatAudience.choicesFor(team),
      ])
        if (readRoles.contains(id)) ChatAudience.pluralLabelOf(team, id),
    ];
    return [
      if (names.isNotEmpty) names.join(', ') else 'Owner',
      if (people > 0) '$people ${people == 1 ? 'person' : 'people'}',
    ].join(' + ');
  }

  /// The access lists as stored. Write access is folded into read so the
  /// stored lists alone answer "who can read".
  Map<String, dynamic> accessMap() => {
    'readRoles': ({...readRoles, ...writeRoles}.toList()..sort()),
    'writeRoles': (writeRoles.toList()..sort()),
    'readUsers': ({...readUsers, ...writeUsers}.toList()..sort()),
    'writeUsers': (writeUsers.toList()..sort()),
  };
}

Set<T> _apply<T>(Set<T> set, T value, bool on) =>
    on ? {...set, value} : ({...set}..remove(value));

Set<String> _strings(Object? raw) => {
  for (final u in (raw as List?) ?? const []) '$u',
};

/// Access ids from a stored list. Rooms from before custom roles stored
/// `owner`, which the owner has anyway, so it's dropped.
Set<String> _roleIds(Object? raw) => _strings(raw)..remove('owner');

/// A team chat room, optionally in a folder ([ChatFolder]). Access is
/// granted per audience id and per member; see [ChatAccessLists]. The
/// owner can read and write every room. firestore.rules enforces the same;
/// keep the two in step.
/// Text rooms hold messages; voice rooms are drop-in calls, like Discord
/// voice channels. A room's kind is set when it's made.
enum ChatRoomKind {
  text,
  voice;

  static ChatRoomKind parse(Object? v) => v == 'voice' ? voice : text;
}

class ChatRoom with ChatAccessLists {
  const ChatRoom({
    required this.id,
    required this.name,
    this.kind = ChatRoomKind.text,
    this.readRoles = const {},
    this.writeRoles = const {},
    this.readUsers = const {},
    this.writeUsers = const {},
    this.folderId,
    this.position = 0,
    this.createdBy = '',
    this.createdAt,
  });

  /// A room every member can read and write; each team gets one.
  factory ChatRoom.general() => const ChatRoom(
    id: generalId,
    name: 'General',
    readRoles: {ChatAudience.everyone},
    writeRoles: {ChatAudience.everyone},
  );

  /// A new room in [folder] (or no folder), starting with its access.
  factory ChatRoom.newIn(ChatFolder? folder) => folder == null
      ? const ChatRoom(
          id: '',
          name: '',
          readRoles: {ChatAudience.everyone},
          writeRoles: {ChatAudience.everyone},
        )
      : ChatRoom(
          id: '',
          name: '',
          folderId: folder.id,
          readRoles: folder.readRoles,
          writeRoles: folder.writeRoles,
          readUsers: folder.readUsers,
          writeUsers: folder.writeUsers,
        );

  static const generalId = 'general';
  static const maxNameLength = 60;

  /// The folder new teams get their voice channels in.
  static const voiceFolderId = 'voice';

  /// The voice channels every team starts with, in [voiceFolderId]. Every
  /// member can join and talk.
  static List<ChatRoom> defaultVoiceRooms() => [
    for (final (i, (id, name)) in const [
      ('voice-lounge', 'Lounge'),
      ('voice-sideline', 'Sideline'),
      ('voice-film', 'Film Room'),
    ].indexed)
      ChatRoom(
        id: id,
        name: name,
        kind: ChatRoomKind.voice,
        folderId: voiceFolderId,
        position: i,
        readRoles: const {ChatAudience.everyone},
        writeRoles: const {ChatAudience.everyone},
      ),
  ];

  /// The folder [defaultVoiceRooms] go in.
  static ChatFolder defaultVoiceFolder() => const ChatFolder(
    id: voiceFolderId,
    name: 'Voice Channels',
    position: 1000,
    readRoles: {ChatAudience.everyone},
    writeRoles: {ChatAudience.everyone},
  );

  /// Empty for a room that hasn't been saved yet.
  final String id;
  final String name;
  final ChatRoomKind kind;

  bool get isVoice => kind == ChatRoomKind.voice;

  /// The name as Discord writes channels: lowercase, dashes for spaces.
  String get handle =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

  @override
  final Set<String> readRoles;
  @override
  final Set<String> writeRoles;
  @override
  final Set<String> readUsers;
  @override
  final Set<String> writeUsers;

  /// The folder it's in; null for rooms outside any folder.
  final String? folderId;

  /// Order within its folder (or among unfiled rooms), lowest first.
  final int position;
  final String createdBy;
  final DateTime? createdAt;

  bool get isNew => id.isEmpty;
  bool get isGeneral => id == generalId;

  ChatRoom withRoleAccess(String roleId, ChatAccess access) => _copy(
    readRoles: _apply(readRoles, roleId, access.canRead),
    writeRoles: _apply(writeRoles, roleId, access.canWrite),
  );

  ChatRoom withUserAccess(String uid, ChatAccess access) => _copy(
    readUsers: _apply(readUsers, uid, access.canRead),
    writeUsers: _apply(writeUsers, uid, access.canWrite),
  );

  ChatRoom withName(String name) => _copy(name: name);

  /// Only while the room is new; a saved room keeps its kind.
  ChatRoom withKind(ChatRoomKind kind) => isNew
      ? ChatRoom(
          id: id,
          name: name,
          kind: kind,
          readRoles: readRoles,
          writeRoles: writeRoles,
          readUsers: readUsers,
          writeUsers: writeUsers,
          folderId: folderId,
          position: position,
        )
      : this;

  ChatRoom withFolder(String? folderId) => _copy(folderId: () => folderId);

  ChatRoom withPosition(int position) => _copy(position: position);

  /// Drops per-member grants for people no longer on [team], and grants
  /// for custom roles it no longer has.
  ChatRoom forMembersOf(Team team) {
    bool live(String id) =>
        team.roles.containsKey(id) ||
        id == ChatAudience.everyone ||
        TeamRole.values.any((r) => r.name == id);
    return _copy(
      readRoles: readRoles.where(live).toSet(),
      writeRoles: writeRoles.where(live).toSet(),
      readUsers: readUsers.where(team.members.containsKey).toSet(),
      writeUsers: writeUsers.where(team.members.containsKey).toSet(),
    );
  }

  ChatRoom _copy({
    String? name,
    Set<String>? readRoles,
    Set<String>? writeRoles,
    Set<String>? readUsers,
    Set<String>? writeUsers,
    String? Function()? folderId,
    int? position,
  }) => ChatRoom(
    id: id,
    name: name ?? this.name,
    kind: kind,
    readRoles: readRoles ?? this.readRoles,
    writeRoles: writeRoles ?? this.writeRoles,
    readUsers: readUsers ?? this.readUsers,
    writeUsers: writeUsers ?? this.writeUsers,
    folderId: folderId != null ? folderId() : this.folderId,
    position: position ?? this.position,
    createdBy: createdBy,
    createdAt: createdAt,
  );

  factory ChatRoom.fromMap(String id, Map<String, dynamic> map) => ChatRoom(
    id: id,
    name: map['name'] as String? ?? '',
    kind: ChatRoomKind.parse(map['kind']),
    readRoles: _roleIds(map['readRoles']),
    writeRoles: _roleIds(map['writeRoles']),
    readUsers: _strings(map['readUsers']),
    writeUsers: _strings(map['writeUsers']),
    folderId: map['folderId'] as String?,
    position: (map['position'] as num?)?.toInt() ?? 0,
    createdBy: map['createdBy'] as String? ?? '',
    createdAt: parseDate(map['createdAt']),
  );

  /// Name, place and access lists.
  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    ...accessMap(),
    'folderId': folderId,
    'position': position,
  };
}

/// A folder of chat rooms, like a Discord category. One level only. Its
/// access lists are what new rooms in it start with; each room keeps its
/// own. Every member can see folder names, but the app hides a folder with
/// no room they can read.
class ChatFolder with ChatAccessLists {
  const ChatFolder({
    required this.id,
    required this.name,
    this.position = 0,
    this.readRoles = const {ChatAudience.everyone},
    this.writeRoles = const {ChatAudience.everyone},
    this.readUsers = const {},
    this.writeUsers = const {},
  });

  static const maxNameLength = 60;

  /// Empty for a folder that hasn't been saved yet.
  final String id;
  final String name;
  final int position;
  @override
  final Set<String> readRoles;
  @override
  final Set<String> writeRoles;
  @override
  final Set<String> readUsers;
  @override
  final Set<String> writeUsers;

  bool get isNew => id.isEmpty;

  ChatFolder copyWith({
    String? id,
    String? name,
    int? position,
    Set<String>? readRoles,
    Set<String>? writeRoles,
  }) => ChatFolder(
    id: id ?? this.id,
    name: name ?? this.name,
    position: position ?? this.position,
    readRoles: readRoles ?? this.readRoles,
    writeRoles: writeRoles ?? this.writeRoles,
    readUsers: readUsers,
    writeUsers: writeUsers,
  );

  ChatFolder withRoleAccess(String roleId, ChatAccess access) => copyWith(
    readRoles: _apply(readRoles, roleId, access.canRead),
    writeRoles: _apply(writeRoles, roleId, access.canWrite),
  );

  factory ChatFolder.fromMap(String id, Map<String, dynamic> map) => ChatFolder(
    id: id,
    name: map['name'] as String? ?? '',
    position: (map['position'] as num?)?.toInt() ?? 0,
    readRoles: _roleIds(map['readRoles']),
    writeRoles: _roleIds(map['writeRoles']),
    readUsers: _strings(map['readUsers']),
    writeUsers: _strings(map['writeUsers']),
  );

  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    'position': position,
    ...accessMap(),
  };
}

int _byPosition(int ap, String an, int bp, String bn) =>
    ap != bp ? ap.compareTo(bp) : an.toLowerCase().compareTo(bn.toLowerCase());

/// Folders ordered by position, then name.
List<ChatFolder> sortFolders(Iterable<ChatFolder> folders) =>
    folders.toList()
      ..sort((a, b) => _byPosition(a.position, a.name, b.position, b.name));

/// Rooms ordered General first, then by position, then name.
List<ChatRoom> sortRooms(Iterable<ChatRoom> rooms) =>
    rooms.toList()..sort((a, b) {
      if (a.isGeneral != b.isGeneral) return a.isGeneral ? -1 : 1;
      return _byPosition(a.position, a.name, b.position, b.name);
    });

/// A folder (null for rooms outside any folder) and its rooms, in order.
typedef RoomGroup = ({ChatFolder? folder, List<ChatRoom> rooms});

/// Rooms grouped for a sidebar: rooms outside any folder first, then each
/// folder with its rooms. Folders without a room in [rooms] are left out
/// unless [keepEmpty] (for people who manage chats).
List<RoomGroup> groupRooms(
  Iterable<ChatRoom> rooms,
  Iterable<ChatFolder> folders, {
  bool keepEmpty = false,
}) {
  final known = {for (final f in folders) f.id};
  final unfiled = sortRooms(
    rooms.where((r) => r.folderId == null || !known.contains(r.folderId)),
  );
  return [
    if (unfiled.isNotEmpty) (folder: null, rooms: unfiled),
    for (final f in sortFolders(folders))
      if (sortRooms(rooms.where((r) => r.folderId == f.id)) case final inFolder
          when inFolder.isNotEmpty || keepEmpty)
        (folder: f, rooms: inFolder),
  ];
}

// A file or photo on a message. [path] is its Cloud Storage path.
class ChatAttachment {
  const ChatAttachment({
    required this.path,
    required this.name,
    required this.contentType,
    required this.size,
  });

  final String path;
  final String name;
  final String contentType;
  final int size;

  bool get isImage => contentType.startsWith('image/');

  /// Plays in the conversation (streamed, not downloaded first).
  bool get isVideo => contentType.startsWith('video/');

  factory ChatAttachment.fromMap(Map<String, dynamic> map) => ChatAttachment(
    path: map['path'] as String? ?? '',
    name: map['name'] as String? ?? '',
    contentType: map['contentType'] as String? ?? 'application/octet-stream',
    size: (map['size'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'path': path,
    'name': name,
    'contentType': contentType,
    'size': size,
  };
}

/// A file picked to send, not uploaded yet.
class NewAttachment {
  NewAttachment({required this.name, required this.bytes})
    : contentType = contentTypeFor(name);

  final String name;
  final Uint8List bytes;
  final String contentType;

  int get size => bytes.length;
  bool get isImage => contentType.startsWith('image/');
  bool get isVideo => contentType.startsWith('video/');
  bool get tooLarge => size > maxBytesFor(contentType);
}

/// The message a reply answers, copied onto the reply when it's sent so it
/// still shows if the original is deleted or not loaded.
class MessageReply {
  const MessageReply({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.text = '',
  });

  /// [message]'s quote: its text (or what's attached), clipped.
  factory MessageReply.of(ChatMessage message) => MessageReply(
    id: message.id,
    authorId: message.authorId,
    authorName: message.authorName,
    text: message.preview,
  );

  /// Longest quote kept; firestore.rules allows the same.
  static const maxText = 200;

  final String id;
  final String authorId;
  final String authorName;
  final String text;

  static MessageReply? fromMap(Object? map) {
    if (map is! Map) return null;
    final id = map['id'];
    if (id is! String || id.isEmpty) return null;
    return MessageReply(
      id: id,
      authorId: map['authorId'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      text: map['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'authorId': authorId,
    'authorName': authorName,
    'text': text.length > maxText ? '${text.substring(0, maxText - 1)}…' : text,
  };
}

/// The quick reactions offered on a message, as iMessage's tapbacks.
const quickReactions = ['❤️', '👍', '👎', '😂', '‼️', '❓'];

/// How many people reacted to a message with [emoji], and whether the
/// user is one of them.
typedef ReactionCount = ({String emoji, int count, bool mine});

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.text = '',
    this.attachments = const [],
    this.createdAt,
    this.replyTo,
    this.reactions = const {},
  });

  /// Longest reaction stored: one emoji, possibly several code units.
  static const maxReaction = 16;

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final List<ChatAttachment> attachments;

  /// Null only for a message still being written to the server.
  final DateTime? createdAt;

  /// The message this one answers; null for none.
  final MessageReply? replyTo;

  /// uid → their reaction. One each, like iMessage's tapbacks; reacting
  /// again replaces it.
  final Map<String, String> reactions;

  /// Its text, else what's attached: for quotes and previews.
  String get preview {
    final images =
        attachments.isNotEmpty && attachments.every((a) => a.isImage);
    final videos =
        attachments.isNotEmpty && attachments.every((a) => a.isVideo);
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isNotEmpty) return t.length > 120 ? '${t.substring(0, 117)}…' : t;
    if (attachments.isEmpty) return '';
    if (images) return attachments.length == 1 ? '📷 Photo' : '📷 Photos';
    if (videos) return attachments.length == 1 ? '🎬 Video' : '🎬 Videos';
    return attachments.length == 1 ? '📎 File' : '📎 Files';
  }

  /// [uid]'s reaction, or null.
  String? reactionOf(String uid) => reactions[uid];

  /// Each reaction with how many gave it, most first (ties in the order
  /// of [quickReactions], then first seen).
  List<ReactionCount> reactionCounts(String uid) {
    final counts = <String, int>{};
    for (final r in reactions.values) {
      counts[r] = (counts[r] ?? 0) + 1;
    }
    final mine = reactions[uid];
    int rank(String e) {
      final i = quickReactions.indexOf(e);
      return i < 0 ? quickReactions.length : i;
    }

    final order = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : rank(a).compareTo(rank(b));
      });
    return [
      for (final e in order) (emoji: e, count: counts[e]!, mine: e == mine),
    ];
  }

  ChatMessage withReaction(String uid, String? emoji) => ChatMessage(
    id: id,
    authorId: authorId,
    authorName: authorName,
    text: text,
    attachments: attachments,
    createdAt: createdAt,
    replyTo: replyTo,
    reactions: {
      for (final e in reactions.entries)
        if (e.key != uid) e.key: e.value,
      uid: ?emoji,
    },
  );

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) =>
      ChatMessage(
        id: id,
        authorId: map['authorId'] as String? ?? '',
        authorName: map['authorName'] as String? ?? '',
        text: map['text'] as String? ?? '',
        attachments: [
          for (final a in (map['attachments'] as List?) ?? const [])
            ChatAttachment.fromMap(Map<String, dynamic>.from(a as Map)),
        ],
        createdAt: parseDate(map['createdAt']),
        replyTo: MessageReply.fromMap(map['replyTo']),
        reactions: {
          for (final e in ((map['reactions'] as Map?) ?? const {}).entries)
            if (e.value is String && (e.value as String).isNotEmpty)
              '${e.key}': e.value as String,
        },
      );
}

const _contentTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'm4v': 'video/mp4',
  'webm': 'video/webm',
  '3gp': 'video/3gpp',
  'zip': 'application/zip',
};

/// MIME type from a file name's extension.
String contentTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return _contentTypes[ext] ?? 'application/octet-stream';
}

/// "2.4 MB", "830 KB".
String formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}
