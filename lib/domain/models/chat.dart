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

/// Attachments (photos and files) are capped at 10 MB. storage.rules
/// enforces the same limit; keep the two in step.
const maxAttachmentBytes = 10 * 1024 * 1024;

class AttachmentTooLargeException implements Exception {
  const AttachmentTooLargeException(this.name);

  final String name;

  @override
  String toString() =>
      '$name is larger than ${formatFileSize(maxAttachmentBytes)}.';
}

/// A team chat room. Access is granted per role and per member; write
/// access always includes read. The team owner can read and write every
/// room. firestore.rules enforces the same; keep the two in step.
class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.name,
    this.readRoles = const {},
    this.writeRoles = const {},
    this.readUsers = const {},
    this.writeUsers = const {},
    this.createdBy = '',
    this.createdAt,
  });

  /// A room every member can read and write; each team gets one.
  factory ChatRoom.general() => const ChatRoom(
    id: generalId,
    name: 'General',
    readRoles: {...TeamRole.values},
    writeRoles: {...TeamRole.values},
  );

  static const generalId = 'general';

  /// Empty for a room that hasn't been saved yet.
  final String id;
  final String name;

  /// Roles that can read; includes [writeRoles].
  final Set<TeamRole> readRoles;
  final Set<TeamRole> writeRoles;

  /// Members (uids) who can read whatever their role; includes [writeUsers].
  final Set<String> readUsers;
  final Set<String> writeUsers;
  final String createdBy;
  final DateTime? createdAt;

  bool get isNew => id.isEmpty;
  bool get isGeneral => id == generalId;

  /// Access for role [role], ignoring per-member grants.
  ChatAccess roleAccess(TeamRole role) => writeRoles.contains(role)
      ? ChatAccess.write
      : readRoles.contains(role)
      ? ChatAccess.read
      : ChatAccess.none;

  /// Access granted to member [uid] directly, on top of their role.
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
    final byRole = roleAccess(role);
    final byUser = userAccess(uid);
    return byRole.index >= byUser.index ? byRole : byUser;
  }

  /// One-line description of who's in the room, for room lists.
  String get audience {
    final roles = readRoles.where((r) => r != TeamRole.owner).toList();
    if (roles.length == TeamRole.values.length - 1) return 'Everyone';
    final people = readUsers.length;
    final parts = [
      if (roles.isNotEmpty)
        roles.map((r) => r.pluralLabel).join(', ')
      else
        'Owner',
      if (people > 0) '$people ${people == 1 ? 'person' : 'people'}',
    ];
    return parts.join(' + ');
  }

  ChatRoom withRoleAccess(TeamRole role, ChatAccess access) => _copy(
    readRoles: _apply(readRoles, role, access.canRead),
    writeRoles: _apply(writeRoles, role, access.canWrite),
  );

  ChatRoom withUserAccess(String uid, ChatAccess access) => _copy(
    readUsers: _apply(readUsers, uid, access.canRead),
    writeUsers: _apply(writeUsers, uid, access.canWrite),
  );

  ChatRoom withName(String name) => _copy(name: name);

  /// Drops per-member grants for people no longer on [team].
  ChatRoom forMembersOf(Team team) => _copy(
    readUsers: readUsers.where(team.members.containsKey).toSet(),
    writeUsers: writeUsers.where(team.members.containsKey).toSet(),
  );

  static Set<T> _apply<T>(Set<T> set, T value, bool on) =>
      on ? {...set, value} : ({...set}..remove(value));

  ChatRoom _copy({
    String? name,
    Set<TeamRole>? readRoles,
    Set<TeamRole>? writeRoles,
    Set<String>? readUsers,
    Set<String>? writeUsers,
  }) => ChatRoom(
    id: id,
    name: name ?? this.name,
    readRoles: readRoles ?? this.readRoles,
    writeRoles: writeRoles ?? this.writeRoles,
    readUsers: readUsers ?? this.readUsers,
    writeUsers: writeUsers ?? this.writeUsers,
    createdBy: createdBy,
    createdAt: createdAt,
  );

  factory ChatRoom.fromMap(String id, Map<String, dynamic> map) {
    Set<TeamRole> roles(Object? raw) => {
      for (final r in (raw as List?) ?? const [])
        enumByName(TeamRole.values, r, TeamRole.player),
    };
    Set<String> users(Object? raw) => {
      for (final u in (raw as List?) ?? const []) '$u',
    };
    return ChatRoom(
      id: id,
      name: map['name'] as String? ?? '',
      readRoles: roles(map['readRoles']),
      writeRoles: roles(map['writeRoles']),
      readUsers: users(map['readUsers']),
      writeUsers: users(map['writeUsers']),
      createdBy: map['createdBy'] as String? ?? '',
      createdAt: parseDate(map['createdAt']),
    );
  }

  /// Name and access lists. Write access is folded into read so the
  /// stored lists alone answer "who can read".
  Map<String, dynamic> toMap() {
    List<String> names(Iterable<TeamRole> r) =>
        TeamRole.values.where(r.contains).map((r) => r.name).toList();
    return {
      'name': name.trim(),
      'readRoles': names({...readRoles, ...writeRoles}),
      'writeRoles': names(writeRoles),
      'readUsers': ({...readUsers, ...writeUsers}.toList()..sort()),
      'writeUsers': (writeUsers.toList()..sort()),
    };
  }
}

/// A file or photo on a message. [path] is its Cloud Storage path.
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
  bool get tooLarge => size > maxAttachmentBytes;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.text = '',
    this.attachments = const [],
    this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final List<ChatAttachment> attachments;

  /// Null only for a message still being written to the server.
  final DateTime? createdAt;

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
