import 'dart:math';

/// What a custom role can let its members do. Coaches and captains (and
/// the owner) have them all; players and group members get only what their
/// roles grant. firestore.rules checks the same names; keep the two in
/// step.
enum TeamPermission {
  manageTeam('Manage team', 'Edit details, roster, playbook, posts and videos'),
  manageMembers('Manage members', 'Invite, approve and remove members'),
  manageChats('Manage chats', 'Create, edit and delete rooms and folders'),
  manageEvents('Manage events', 'Events, meetings and tournaments'),
  moderate('Moderate', "Delete other people's chat messages"),
  keepStats('Keep stats', 'Track games and edit stats');

  const TeamPermission(this.label, this.summary);
  final String label;
  final String summary;

  /// Groups don't keep stats.
  static List<TeamPermission> forGroup(bool isCommunity) =>
      isCommunity ? values.where((p) => p != keepStats).toList() : values;
}

/// A role the owner made up, like a Discord role: a name, a color and the
/// permissions it grants. Stored in the team doc's `roles` map.
class CustomRole {
  const CustomRole({
    required this.id,
    required this.name,
    this.color = 0,
    this.position = 0,
    this.permissions = const {},
  });

  /// Most roles a team can have; firestore.rules agrees.
  static const maxRoles = 50;
  static const maxNameLength = 40;

  /// Empty for a role that hasn't been saved yet.
  final String id;
  final String name;

  /// ARGB; 0 means no color.
  final int color;

  /// Lower sorts first, like Discord's role list read top down.
  final int position;
  final Set<TeamPermission> permissions;

  bool get isNew => id.isEmpty;

  factory CustomRole.fromMap(String id, Map<String, dynamic> map) => CustomRole(
    id: id,
    name: map['name'] as String? ?? '',
    color: (map['color'] as num?)?.toInt() ?? 0,
    position: (map['position'] as num?)?.toInt() ?? 0,
    permissions: {
      for (final p in (map['perms'] as List?) ?? const [])
        ?permissionByName('$p'),
    },
  );

  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    'color': color,
    'position': position,
    'perms': [
      for (final p in TeamPermission.values)
        if (permissions.contains(p)) p.name,
    ],
  };

  CustomRole copyWith({
    String? id,
    String? name,
    int? color,
    int? position,
    Set<TeamPermission>? permissions,
  }) => CustomRole(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
    position: position ?? this.position,
    permissions: permissions ?? this.permissions,
  );

  @override
  bool operator ==(Object other) =>
      other is CustomRole &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.position == position &&
      other.permissions.length == permissions.length &&
      other.permissions.containsAll(permissions);

  @override
  int get hashCode => Object.hash(id, name, color, position);
}

/// Parses the team doc's `roles` map.
Map<String, CustomRole> parseCustomRoles(Object? raw) => {
  if (raw is Map)
    for (final e in raw.entries)
      if (e.value is Map)
        '${e.key}': CustomRole.fromMap(
          '${e.key}',
          Map<String, dynamic>.from(e.value as Map),
        ),
};

/// Parses a `{uid: [values]}` map.
Map<String, Set<T>> parseMemberLists<T>(Object? raw, T? Function(String) f) => {
  if (raw is Map)
    for (final e in raw.entries)
      '${e.key}': {for (final v in (e.value as List?) ?? const []) ?f('$v')},
};

TeamPermission? permissionByName(String name) {
  for (final p in TeamPermission.values) {
    if (p.name == name) return p;
  }
  return null;
}

/// Most custom roles one member can have; firestore.rules checks only this
/// many for chat access.
const maxRolesPerMember = 10;

/// A fresh custom role id.
String newRoleId() {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 16; i++) chars.codeUnitAt(random.nextInt(chars.length)),
  ]);
}

/// [memberRoles] cleaned up for saving: only [members], only roles that
/// exist, no empty entries.
Map<String, Set<String>> cleanMemberRoles(
  Map<String, Set<String>> memberRoles,
  Map<String, CustomRole> roles,
  Iterable<String> members,
) {
  final keep = members.toSet();
  return {
    for (final e in memberRoles.entries)
      if (keep.contains(e.key))
        if (e.value.where(roles.containsKey).toSet() case final ids
            when ids.isNotEmpty)
          e.key: ids,
  };
}

/// Each member's permissions from their roles, as the team doc's
/// `memberPerms` stores them. Members whose roles grant nothing are left
/// out.
Map<String, Set<TeamPermission>> memberPermsFor(
  Map<String, Set<String>> memberRoles,
  Map<String, CustomRole> roles,
) => {
  for (final e in memberRoles.entries)
    if ({for (final id in e.value) ...?roles[id]?.permissions} case final perms
        when perms.isNotEmpty)
      e.key: perms,
};

/// The team doc fields for [roles] and [memberRoles] (already cleaned).
Map<String, dynamic> rolesData(
  Map<String, CustomRole> roles,
  Map<String, Set<String>> memberRoles,
) {
  List<String> sorted(Iterable<String> s) => s.toList()..sort();
  return {
    'roles': {for (final r in roles.values) r.id: r.toMap()},
    'memberRoles': {
      for (final e in memberRoles.entries) e.key: sorted(e.value),
    },
    'memberPerms': {
      for (final e in memberPermsFor(memberRoles, roles).entries)
        e.key: [
          for (final p in TeamPermission.values)
            if (e.value.contains(p)) p.name,
        ],
    },
  };
}
