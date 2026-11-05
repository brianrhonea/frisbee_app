import 'chat.dart';
import 'team.dart';

/// A role from a Discord server template, as the `discord-previewTemplate`
/// function maps it (functions/src/discord/template.ts).
class PlannedRole {
  const PlannedRole({
    required this.key,
    required this.name,
    this.color = 0,
    this.permissions = const {},
  });

  /// The template's role id; rooms' access lists refer to it.
  final String key;
  final String name;
  final int color;
  final Set<TeamPermission> permissions;

  factory PlannedRole.fromMap(Map<String, dynamic> map) => PlannedRole(
    key: '${map['key']}',
    name: '${map['name'] ?? ''}',
    color: (map['color'] as num?)?.toInt() ?? 0,
    permissions: {
      for (final p in (map['perms'] as List?) ?? const [])
        ?permissionByName('$p'),
    },
  );
}

/// Access lists that refer to template role keys or "everyone".
class PlannedAccess {
  const PlannedAccess({this.readRoles = const [], this.writeRoles = const []});

  final List<String> readRoles;
  final List<String> writeRoles;

  static List<String> _list(Object? raw) => [
    for (final v in (raw as List?) ?? const []) '$v',
  ];
}

class PlannedFolder extends PlannedAccess {
  const PlannedFolder({
    required this.key,
    required this.name,
    super.readRoles,
    super.writeRoles,
  });

  final String key;
  final String name;

  factory PlannedFolder.fromMap(Map<String, dynamic> map) => PlannedFolder(
    key: '${map['key']}',
    name: '${map['name'] ?? ''}',
    readRoles: PlannedAccess._list(map['readRoles']),
    writeRoles: PlannedAccess._list(map['writeRoles']),
  );
}

class PlannedRoom extends PlannedAccess {
  const PlannedRoom({
    required this.name,
    this.folderKey,
    super.readRoles,
    super.writeRoles,
  });

  final String name;
  final String? folderKey;

  factory PlannedRoom.fromMap(Map<String, dynamic> map) => PlannedRoom(
    name: '${map['name'] ?? ''}',
    folderKey: map['folderKey'] as String?,
    readRoles: PlannedAccess._list(map['readRoles']),
    writeRoles: PlannedAccess._list(map['writeRoles']),
  );
}

/// What a Discord server template holds, ready to import: roles,
/// categories (folders) and text channels (rooms) with who can read and
/// write them. Members and messages aren't in templates.
class DiscordImportPlan {
  const DiscordImportPlan({
    required this.serverName,
    this.roles = const [],
    this.folders = const [],
    this.rooms = const [],
    this.skippedChannels = const [],
    this.skippedRoles = const [],
  });

  final String serverName;

  /// Highest role first.
  final List<PlannedRole> roles;

  /// In Discord's order.
  final List<PlannedFolder> folders;

  /// In Discord's order.
  final List<PlannedRoom> rooms;

  /// "name: reason", for channels that don't become rooms (voice ones).
  final List<String> skippedChannels;
  final List<String> skippedRoles;

  factory DiscordImportPlan.fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>> maps(Object? raw) => [
      for (final m in (raw as List?) ?? const [])
        if (m is Map) Map<String, dynamic>.from(m),
    ];
    return DiscordImportPlan(
      serverName: '${map['serverName'] ?? 'Discord server'}',
      roles: [for (final m in maps(map['roles'])) PlannedRole.fromMap(m)],
      folders: [for (final m in maps(map['folders'])) PlannedFolder.fromMap(m)],
      rooms: [for (final m in maps(map['rooms'])) PlannedRoom.fromMap(m)],
      skippedChannels: [
        for (final m in maps(map['skipped'])) '${m['name']}: ${m['reason']}',
      ],
      skippedRoles: [
        for (final r in (map['skippedRoles'] as List?) ?? const []) '$r',
      ],
    );
  }
}

/// The plan turned into this team's roles, folders and rooms, with new
/// ids. Roles and folders whose names the team already has are reused, and
/// rooms already in their folder by name are left alone, so importing the
/// same template twice adds nothing.
class DiscordImport {
  const DiscordImport({
    required this.roles,
    required this.newRoles,
    required this.folders,
    required this.rooms,
    required this.alreadyHere,
    required this.tooManyRoles,
  });

  /// Every custom role the team will have: its own plus the new ones.
  final Map<String, CustomRole> roles;

  /// Names of the roles being added.
  final List<String> newRoles;

  /// New folders, with ids already chosen so rooms can refer to them.
  final List<ChatFolder> folders;

  /// New rooms.
  final List<ChatRoom> rooms;

  /// Rooms skipped because the team already has one by that name there.
  final List<String> alreadyHere;

  /// Roles left out to stay within [CustomRole.maxRoles].
  final List<String> tooManyRoles;

  bool get isEmpty => newRoles.isEmpty && folders.isEmpty && rooms.isEmpty;

  /// Maps [plan] onto [team], which has [folders] and [rooms] already.
  /// [newId] makes ids for new roles and folders.
  factory DiscordImport.of(
    DiscordImportPlan plan, {
    required Team team,
    required List<ChatFolder> folders,
    required List<ChatRoom> rooms,
    String Function() newId = newRoleId,
  }) {
    String norm(String s) => s.trim().toLowerCase();

    // Roles: reuse by name, else add while there's room.
    final roles = {...team.roles};
    final roleIds = <String, String>{};
    final newRoles = <String>[];
    final tooMany = [...plan.skippedRoles];
    var position = roles.isEmpty
        ? 0
        : roles.values.map((r) => r.position).reduce((a, b) => a > b ? a : b) +
              1;
    for (final r in plan.roles) {
      final existing = roles.values
          .where((e) => norm(e.name) == norm(r.name))
          .firstOrNull;
      if (existing != null) {
        roleIds[r.key] = existing.id;
        continue;
      }
      if (roles.length >= CustomRole.maxRoles) {
        tooMany.add(r.name);
        continue;
      }
      final role = CustomRole(
        id: newId(),
        name: r.name,
        color: r.color,
        position: position++,
        permissions: r.permissions,
      );
      roles[role.id] = role;
      roleIds[r.key] = role.id;
      newRoles.add(role.name);
    }

    // Access lists in this team's ids. Roles that didn't make it are
    // dropped, which only ever narrows access.
    Set<String> ids(List<String> keys) => {
      for (final k in keys)
        if (k == ChatAudience.everyone) k else ?roleIds[k],
    };

    // Folders: reuse by name, else add after the team's own.
    final folderIds = <String, String>{};
    final newFolders = <ChatFolder>[];
    var folderPosition = folders.isEmpty
        ? 0
        : folders.map((f) => f.position).reduce((a, b) => a > b ? a : b) + 1;
    for (final f in plan.folders) {
      final existing = folders
          .where((e) => norm(e.name) == norm(f.name))
          .firstOrNull;
      if (existing != null) {
        folderIds[f.key] = existing.id;
        continue;
      }
      final folder = ChatFolder(
        id: newId(),
        name: f.name,
        position: folderPosition++,
        readRoles: ids(f.readRoles),
        writeRoles: ids(f.writeRoles),
      );
      newFolders.add(folder);
      folderIds[f.key] = folder.id;
    }

    // Rooms: skip ones already in their folder by name; add the rest after
    // the rooms already there.
    final taken = <String>{
      for (final r in rooms) '${r.folderId}/${norm(r.name)}',
    };
    final next = <String?, int>{};
    int nextPosition(String? folderId) => next[folderId] ??= rooms
        .where((r) => r.folderId == folderId)
        .fold(0, (n, r) => r.position >= n ? r.position + 1 : n);
    final newRooms = <ChatRoom>[];
    final alreadyHere = <String>[];
    for (final r in plan.rooms) {
      final folderId = r.folderKey == null ? null : folderIds[r.folderKey];
      final key = '$folderId/${norm(r.name)}';
      if (!taken.add(key)) {
        alreadyHere.add(r.name);
        continue;
      }
      final position = nextPosition(folderId);
      next[folderId] = position + 1;
      newRooms.add(
        ChatRoom(
          id: '',
          name: r.name,
          folderId: folderId,
          position: position,
          readRoles: ids(r.readRoles),
          writeRoles: ids(r.writeRoles),
        ),
      );
    }

    return DiscordImport(
      roles: roles,
      newRoles: newRoles,
      folders: newFolders,
      rooms: newRooms,
      alreadyHere: alreadyHere,
      tooManyRoles: tooMany,
    );
  }
}
