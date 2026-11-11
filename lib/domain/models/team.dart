import 'model_utils.dart';
import 'team_role.dart';

export 'team_role.dart';

/// Member tiers, most access first. Teams and groups have only an owner
/// and players (members, in a group); anything more comes from the owner's
/// custom roles ([Team.roles]). Coach and captain are tiers from before
/// custom roles: the owner's app moves them into roles of the same name
/// ([Team.needsRoleMigration]). A player can also be given stats access
/// ([Team.statKeepers]). firestore.rules enforces the same permissions;
/// keep the two in step.
enum TeamRole {
  /// Everything, including roles and ownership.
  owner,

  /// Team admin and stats, including invite codes and links.
  coach,

  /// Same as coach.
  captain,

  /// Read only, unless given stats access.
  player;

  /// Team details, roster, schedule and playbook.
  bool get canEdit => this == owner || this == coach || this == captain;

  /// Stats come with every role but player.
  bool get canKeepStats => canEdit;

  bool get canSetRoles => this == owner;

  bool get canShareCode => canEdit;

  /// Whether this role may remove a member with role [target]. Anyone may
  /// leave on their own; the owner can't be removed.
  bool canRemove(TeamRole target) => switch (this) {
    owner => target != owner,
    coach || captain => target == player,
    player => false,
  };

  String get label => switch (this) {
    owner => 'Owner',
    coach => 'Coach',
    captain => 'Captain',
    player => 'Player',
  };

  String get pluralLabel => switch (this) {
    owner => 'Owners',
    coach => 'Coaches',
    captain => 'Captains',
    player => 'Players',
  };

  /// Community groups call players members. Captains in a group are
  /// organizers from before custom roles, until the owner's app moves them
  /// into an "Organizer" role ([Team.needsOrganizerMigration]).
  String labelFor(TeamKind kind) => switch ((kind.isGroupLike, this)) {
    (true, captain) => 'Organizer',
    (true, player) => 'Member',
    _ => label,
  };

  String pluralLabelFor(TeamKind kind) => switch ((kind.isGroupLike, this)) {
    (true, captain) => 'Organizers',
    (true, player) => 'Members',
    _ => pluralLabel,
  };

  String summaryFor(TeamKind kind) => switch ((kind, this)) {
    (TeamKind.organization, owner) => 'Everything, including roles and teams',
    (TeamKind.organization, player) =>
      'Roles decide which teams, chats and events they get',
    (TeamKind.community || TeamKind.organization, owner) =>
      'Everything, including roles',
    (TeamKind.community || TeamKind.organization, captain) =>
      'Manage events, tournaments and join requests',
    (TeamKind.community, player) => 'Join events; roles can grant more',
    (TeamKind.team, player) => 'View the team; roles can grant more',
    _ => summary,
  };

  /// Tiers a member can be given: the owner and everyone else. Custom
  /// roles do the rest.
  static List<TeamRole> rolesFor(TeamKind kind) => const [owner, player];

  /// What the role can do, for the role picker.
  String get summary => switch (this) {
    owner => 'Everything, including roles and ownership',
    coach => 'Manage the team and keep stats',
    captain => 'Manage the team and keep stats',
    player => 'View only, unless given stats access',
  };
}

/// A closed team (invite code, roster, stats), an open community group
/// anyone can join, with pickup events and tournaments instead, or a
/// school or club community: members, roles, chats and events like a
/// group, plus the teams it links (each still a full team), which members
/// join by holding the roles each team asks for.
enum TeamKind {
  team('Team', 'team'),
  community('Community group', 'group'),
  organization('School or club', 'community');

  const TeamKind(this.label, this.noun);
  final String label;

  /// What the app calls one in a sentence: "team", "group", "community".
  final String noun;

  /// Joined like a group (openly or with approval) and has a description
  /// and location, no roster or stats of its own.
  bool get isGroupLike => this != team;
}

/// Where a community group plays, shown on a map on its home page.
class GroupLocation {
  const GroupLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String address;
  final double latitude;
  final double longitude;

  static GroupLocation? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    if (lat is! num || lng is! num) return null;
    return GroupLocation(
      address: '${raw['address'] ?? ''}',
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'address': address,
    'lat': latitude,
    'lng': longitude,
  };

  @override
  bool operator ==(Object other) =>
      other is GroupLocation &&
      other.address == address &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(address, latitude, longitude);
}

/// The extra details a community group stores on its team doc and
/// directory listing. Teams store none of them, so their docs don't change.
Map<String, dynamic> communityFields({
  required TeamKind kind,
  required String description,
  required bool requiresApproval,
  required GroupLocation? location,
}) => kind.isGroupLike
    ? {
        'kind': kind.name,
        'description': description,
        'requiresApproval': requiresApproval,
        'location': location?.toMap(),
      }
    : {};

enum Division {
  mixed('Mixed'),
  open('Open'),
  women('Women'),
  masters('Masters');

  const Division(this.label);
  final String label;
}

enum CompetitionLevel {
  club('Club'),
  college('College'),
  youth('Youth'),
  league('League'),
  pickup('Pickup');

  const CompetitionLevel(this.label);
  final String label;
}

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.division,
    required this.level,
    required this.ownerId,
    required this.members,
    this.memberNames = const {},
    this.statKeepers = const {},
    this.city = '',
    this.createdAt,
    this.kind = TeamKind.team,
    this.description = '',
    this.requiresApproval = false,
    this.location,
    this.roles = const {},
    this.memberRoles = const {},
    this.memberPerms = const {},
    this.linkedTeams = const {},
    this.orgId,
    this.orgName = '',
    this.orgLinked = false,
    this.orgMembers = const {},
    this.orgRoles = const {},
    this.official = false,
  });

  /// An official organizer, e.g. Stall 10: its events carry a verified
  /// badge. Set only from the Firebase console or admin tools; the rules
  /// never let the app write it.
  final bool official;

  /// Team roles that copy a community role (team role id → community role
  /// id), e.g. Woof Captain. Who has them follows the community: the
  /// communities Cloud Functions give and take them away.
  final Map<String, String> orgRoles;

  final String id;
  final String name;
  final Division division;
  final CompetitionLevel level;
  final String city;
  final String ownerId;
  final TeamKind kind;

  /// A community's teams, by team id (organizations only). Its admins
  /// write them; a team is only really in the community once its own
  /// admins asked to be ([orgId]).
  final Map<String, LinkedTeam> linkedTeams;

  /// The community this team asked to join or is part of, if any. Team
  /// admins set it; the community accepts by listing the team.
  final String? orgId;
  final String orgName;

  /// Whether the community accepted the team. Cloud Functions set it,
  /// along with [orgMembers].
  final bool orgLinked;

  /// Members the community added because they hold one of the team's
  /// roles there. They leave again when they lose it; members added on the
  /// team itself never do. Cloud Functions keep it.
  final Set<String> orgMembers;

  bool get isOrganization => kind == TeamKind.organization;

  /// Part of a community that accepted it.
  bool get inCommunity => orgLinked && orgId != null;

  /// Asked to join a community that hasn't answered yet.
  bool get communityPending => orgId != null && !orgLinked;

  /// Linked teams, by name.
  List<LinkedTeam> get sortedLinkedTeams =>
      linkedTeams.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// The linked teams [uid]'s roles let into.
  Set<String> teamsFor(String uid) {
    final mine = memberRoles[uid] ?? const <String>{};
    return {
      for (final t in linkedTeams.values)
        if (t.roles.any(mine.contains)) t.id,
    };
  }

  /// Custom roles by id. Only the owner edits them.
  final Map<String, CustomRole> roles;

  /// uid → ids of the custom roles they have.
  final Map<String, Set<String>> memberRoles;

  /// uid → the permissions their custom roles grant, denormalized by the
  /// owner whenever roles change, so firestore.rules can check them
  /// without reading every role.
  final Map<String, Set<TeamPermission>> memberPerms;

  /// What the group is about, on its home page. Groups only.
  final String description;

  /// Whether organizers approve each join request. Groups only; teams are
  /// joined by invite code.
  final bool requiresApproval;

  /// Where the group plays. Groups only.
  final GroupLocation? location;

  /// A community group or a school or club community: joined openly or
  /// with approval, no roster or stats of its own.
  bool get isCommunity => kind.isGroupLike;

  /// A group that needs approval to join. Its location, posts and events are
  /// for members only; search shows just its name, city and description.
  bool get isPrivateGroup => isCommunity && requiresApproval;

  /// Who [uid] counts as when an event or room lists who sees it, or null
  /// if they see everything: on a team or group, and for a community's
  /// owner and event managers.
  Set<String>? eventAudienceOf(String uid) {
    if (!isOrganization || has(uid, TeamPermission.manageEvents)) return null;
    final role = roleOf(uid);
    if (role == null) return const {};
    return {'everyone', role.name, ...?memberRoles[uid]};
  }

  /// uid → role.
  final Map<String, TeamRole> members;

  /// uid → display name, denormalized at join time for member lists.
  final Map<String, String> memberNames;

  /// Players the owner gave stats access to.
  final Set<String> statKeepers;

  final DateTime? createdAt;

  TeamRole? roleOf(String uid) => members[uid];

  /// Whether member [uid] may do [permission]: the owner, coaches and
  /// captains always; others when a custom role (or, for stats, stats
  /// access) grants it.
  bool has(String uid, TeamPermission permission) => switch (roleOf(uid)) {
    null => false,
    final role when role.canEdit => true,
    _ =>
      (permission == TeamPermission.keepStats && statKeepers.contains(uid)) ||
          (memberPerms[uid]?.contains(permission) ?? false),
  };

  /// Team details, roster, playbook, posts and videos.
  bool canEdit(String uid) => has(uid, TeamPermission.manageTeam);

  bool canKeepStats(String uid) => has(uid, TeamPermission.keepStats);

  /// Whether [by] may remove [target]. Anyone may leave; nobody removes
  /// the owner. The owner removes anyone; coaches, captains and members
  /// with Manage members remove plain members, but not other admins.
  bool canRemove(String by, String target) {
    final me = roleOf(by);
    final them = roleOf(target);
    if (me == null || them == null || them == TeamRole.owner) return false;
    if (by == target || me == TeamRole.owner) return true;
    return has(by, TeamPermission.manageMembers) &&
        them == TeamRole.player &&
        (memberPerms[target]?.isEmpty ?? true);
  }

  /// Custom roles, top of the list first.
  List<CustomRole> get sortedRoles => roles.values.toList()
    ..sort(
      (a, b) => a.position != b.position
          ? a.position.compareTo(b.position)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

  /// [uid]'s custom roles, top first.
  List<CustomRole> rolesOf(String uid) {
    final ids = memberRoles[uid] ?? const {};
    return [
      for (final r in sortedRoles)
        if (ids.contains(r.id)) r,
    ];
  }

  /// What roles [roleIds] grant together, from [roles] (or this team's).
  Set<TeamPermission> permissionsOf(
    Iterable<String> roleIds, [
    Map<String, CustomRole>? roles,
  ]) => {for (final id in roleIds) ...?(roles ?? this.roles)[id]?.permissions};

  /// Members still on the coach or captain tier, from before custom roles.
  /// The owner's app moves them into roles with the same powers
  /// ([legacyTierRoles]).
  bool get needsRoleMigration =>
      members.values.any((r) => r == TeamRole.coach || r == TeamRole.captain);

  /// The custom role each legacy tier in use becomes: "Coach" and
  /// "Captain" with every permission on a team, "Organizer" in a group.
  /// Reuses a role of the same name if the team already has one.
  Map<TeamRole, CustomRole> legacyTierRoles() {
    final inUse = {
      for (final r in members.values)
        if (r == TeamRole.coach || r == TeamRole.captain) r,
    };
    var position = roles.length;
    final made = <String, CustomRole>{};
    CustomRole named(String name, int color, Set<TeamPermission> perms) =>
        made[name] ??=
            roles.values.where((r) => r.name == name).firstOrNull ??
            CustomRole(
              id: newRoleId(),
              name: name,
              color: color,
              position: position++,
              permissions: perms,
            );
    return {
      for (final tier in TeamRole.values)
        if (inUse.contains(tier))
          tier: isCommunity
              ? named('Organizer', 0xFF1E88E5, const {
                  TeamPermission.manageTeam,
                  TeamPermission.manageMembers,
                  TeamPermission.manageChats,
                  TeamPermission.manageEvents,
                })
              : tier == TeamRole.coach
              ? named('Coach', 0xFF2E7D32, TeamPermission.values.toSet())
              : named('Captain', 0xFF1E88E5, TeamPermission.values.toSet()),
    };
  }

  /// A player with stats access.
  bool isStatKeeper(String uid) =>
      roleOf(uid) == TeamRole.player && statKeepers.contains(uid);

  String nameOf(String uid) => memberNames[uid] ?? 'Member';

  /// [role]'s label here, e.g. "Organizer" in a group.
  String roleLabel(TeamRole role) => role.labelFor(kind);

  factory Team.fromMap(String id, Map<String, dynamic> map) {
    final rawMembers = (map['members'] as Map?) ?? const {};
    final rawNames = (map['memberNames'] as Map?) ?? const {};
    // "stats" was briefly a role; it now means a player with stats access.
    final legacyStats = [
      for (final e in rawMembers.entries)
        if (e.value == 'stats') '${e.key}',
    ];
    return Team(
      id: id,
      name: map['name'] as String? ?? '',
      division: enumByName(Division.values, map['division'], Division.mixed),
      level: enumByName(
        CompetitionLevel.values,
        map['level'],
        CompetitionLevel.club,
      ),
      city: map['city'] as String? ?? '',
      ownerId: map['ownerId'] as String? ?? '',
      members: {
        for (final e in rawMembers.entries)
          e.key as String: enumByName(
            TeamRole.values,
            e.value,
            TeamRole.player,
          ),
      },
      memberNames: {
        for (final e in rawNames.entries) e.key as String: '${e.value}',
      },
      statKeepers: {
        for (final id in (map['statKeepers'] as List?) ?? const []) '$id',
        ...legacyStats,
      },
      createdAt: parseDate(map['createdAt']),
      kind: enumByName(TeamKind.values, map['kind'], TeamKind.team),
      description: map['description'] as String? ?? '',
      requiresApproval: map['requiresApproval'] as bool? ?? false,
      location: GroupLocation.fromMap(map['location']),
      roles: parseCustomRoles(map['roles']),
      memberRoles: parseMemberLists(map['memberRoles'], (s) => s),
      memberPerms: parseMemberLists(map['memberPerms'], permissionByName),
      linkedTeams: LinkedTeam.parse(map['linkedTeams']),
      orgId: map['orgId'] as String?,
      orgName: map['orgName'] as String? ?? '',
      orgLinked: map['orgLinked'] == true,
      orgMembers: {
        for (final u in (map['orgMembers'] as List?) ?? const []) '$u',
      },
      orgRoles: {
        if (map['orgRoles'] case final Map m)
          for (final e in m.entries) '${e.key}': '${e.value}',
      },
      official: map['official'] == true,
    );
  }

  /// Editable fields only; membership changes go through dedicated
  /// repository methods so security rules can validate them. The kind is
  /// set at creation and never changes.
  Map<String, dynamic> toEditableMap() => {
    'name': name,
    'division': division.name,
    'level': level.name,
    'city': city,
    ...communityFields(
      kind: kind,
      description: description,
      requiresApproval: requiresApproval,
      location: location,
    )..remove('kind'),
  };

  Team copyWith({
    String? name,
    Division? division,
    CompetitionLevel? level,
    String? city,
    Map<String, TeamRole>? members,
    Map<String, String>? memberNames,
    Set<String>? statKeepers,
    String? description,
    bool? requiresApproval,
    GroupLocation? Function()? location,
    Map<String, CustomRole>? roles,
    Map<String, Set<String>>? memberRoles,
    Map<String, Set<TeamPermission>>? memberPerms,
    Map<String, LinkedTeam>? linkedTeams,
    String? Function()? orgId,
    String? orgName,
    bool? orgLinked,
    Set<String>? orgMembers,
    Map<String, String>? orgRoles,
  }) => Team(
    id: id,
    name: name ?? this.name,
    division: division ?? this.division,
    level: level ?? this.level,
    city: city ?? this.city,
    ownerId: ownerId,
    members: members ?? this.members,
    memberNames: memberNames ?? this.memberNames,
    statKeepers: statKeepers ?? this.statKeepers,
    createdAt: createdAt,
    kind: kind,
    description: description ?? this.description,
    requiresApproval: requiresApproval ?? this.requiresApproval,
    location: location != null ? location() : this.location,
    roles: roles ?? this.roles,
    memberRoles: memberRoles ?? this.memberRoles,
    memberPerms: memberPerms ?? this.memberPerms,
    linkedTeams: linkedTeams ?? this.linkedTeams,
    orgId: orgId != null ? orgId() : this.orgId,
    orgName: orgName ?? this.orgName,
    orgLinked: orgLinked ?? this.orgLinked,
    orgMembers: orgMembers ?? this.orgMembers,
    orgRoles: orgRoles ?? this.orgRoles,
    official: official,
  );
}

/// A team in a school or club community (`linkedTeams.{teamId}` on the
/// community's doc): its name for the community's Teams list, and the
/// community roles that make someone a member of it.
class LinkedTeam {
  const LinkedTeam({
    required this.id,
    required this.name,
    this.division = Division.mixed,
    this.roles = const {},
  });

  /// Most teams a community links; firestore.rules agrees.
  static const max = 20;

  final String id;
  final String name;
  final Division division;

  /// Community role ids; holding any of them puts you on the team.
  final Set<String> roles;

  static Map<String, LinkedTeam> parse(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.value is Map)
          '${e.key}': LinkedTeam.fromMap(
            '${e.key}',
            Map<String, dynamic>.from(e.value as Map),
          ),
  };

  factory LinkedTeam.fromMap(String id, Map<String, dynamic> map) => LinkedTeam(
    id: id,
    name: map['name'] as String? ?? '',
    division: enumByName(Division.values, map['division'], Division.mixed),
    roles: {for (final r in (map['roles'] as List?) ?? const []) '$r'},
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'division': division.name,
    'roles': roles.toList()..sort(),
  };

  LinkedTeam copyWith({String? name, Set<String>? roles}) => LinkedTeam(
    id: id,
    name: name ?? this.name,
    division: division,
    roles: roles ?? this.roles,
  );
}

/// A team asking to join a school or club community
/// (`teams/{orgId}/linkRequests/{teamId}`). The community's admins accept
/// it (choosing which roles get on the team) or decline it.
class TeamLinkRequest {
  const TeamLinkRequest({
    required this.teamId,
    required this.teamName,
    this.division = Division.mixed,
    this.requestedBy = '',
    this.requestedByName = '',
    this.createdAt,
  });

  final String teamId;
  final String teamName;
  final Division division;
  final String requestedBy;
  final String requestedByName;
  final DateTime? createdAt;

  factory TeamLinkRequest.fromMap(String teamId, Map<String, dynamic> map) =>
      TeamLinkRequest(
        teamId: teamId,
        teamName: map['teamName'] as String? ?? '',
        division: enumByName(Division.values, map['division'], Division.mixed),
        requestedBy: map['requestedBy'] as String? ?? '',
        requestedByName: map['requestedByName'] as String? ?? '',
        createdAt: parseDate(map['createdAt']),
      );
}

/// Input for creating a team or community group.
class NewTeam {
  const NewTeam({
    required this.name,
    required this.division,
    required this.level,
    this.city = '',
    this.kind = TeamKind.team,
    this.description = '',
    this.requiresApproval = false,
    this.location,
    this.orgId,
    this.orgName = '',
  });

  final String name;
  final Division division;
  final CompetitionLevel level;
  final String city;
  final TeamKind kind;
  final String description;
  final bool requiresApproval;
  final GroupLocation? location;

  /// The community it's made in, if any (a team only).
  final String? orgId;
  final String orgName;

  Map<String, dynamic> toMap() => {
    'name': name,
    'division': division.name,
    'level': level.name,
    'city': city,
    ...communityFields(
      kind: kind,
      description: description,
      requiresApproval: requiresApproval,
      location: location,
    ),
    if (orgId case final id?) ...{'orgId': id, 'orgName': orgName},
  };

  NewTeam inCommunity(Team org) => NewTeam(
    name: name,
    division: division,
    level: level,
    city: city,
    orgId: org.id,
    orgName: org.name,
  );

  /// The directory listing for the new team, once it has [id].
  TeamListing listing(String id) => TeamListing(
    id: id,
    name: name,
    division: division,
    level: level,
    city: city,
    kind: kind,
    description: description,
    requiresApproval: requiresApproval,
    location: location,
  );
}

/// A team's entry in the public team directory (`teamDirectory/{teamId}`):
/// what anyone signed in sees when searching, without members or invite
/// code. Mirrors the team's editable fields.
class TeamListing {
  const TeamListing({
    required this.id,
    required this.name,
    required this.division,
    required this.level,
    this.city = '',
    this.kind = TeamKind.team,
    this.description = '',
    this.requiresApproval = false,
    this.location,
    this.official = false,
  });

  factory TeamListing.of(Team team) => TeamListing(
    id: team.id,
    name: team.name,
    division: team.division,
    level: team.level,
    city: team.city,
    kind: team.kind,
    description: team.description,
    requiresApproval: team.requiresApproval,
    location: team.location,
    official: team.official,
  );

  final String id;
  final String name;
  final Division division;
  final CompetitionLevel level;
  final String city;
  final TeamKind kind;
  final String description;
  final bool requiresApproval;
  final GroupLocation? location;

  /// Copied from [Team.official].
  final bool official;

  bool get isCommunity => kind.isGroupLike;

  bool get isOrganization => kind == TeamKind.organization;

  /// A group that needs approval to join. Its location, posts and events are
  /// for members only; search shows just its name, city and description.
  bool get isPrivateGroup => isCommunity && requiresApproval;

  /// "Mixed · Club · Denver", or "Community group · Denver".
  String get subtitle => [
    if (isCommunity) kind.label else ...[division.label, level.label],
    if (city.isNotEmpty) city,
  ].join(' · ');

  /// Whether every word of [query] starts a word of the name or city.
  bool matches(String query) => matchesSearch('$name $city', query);

  /// Whether this still matches [team], or needs republishing.
  bool sameAs(Team team) =>
      id == team.id &&
      name == team.name &&
      division == team.division &&
      level == team.level &&
      city == team.city &&
      kind == team.kind &&
      description == team.description &&
      requiresApproval == team.requiresApproval &&
      official == team.official &&
      location == (team.isPrivateGroup ? null : team.location);

  factory TeamListing.fromMap(String id, Map<String, dynamic> map) =>
      TeamListing(
        id: id,
        name: map['name'] as String? ?? '',
        division: enumByName(Division.values, map['division'], Division.mixed),
        level: enumByName(
          CompetitionLevel.values,
          map['level'],
          CompetitionLevel.club,
        ),
        city: map['city'] as String? ?? '',
        kind: enumByName(TeamKind.values, map['kind'], TeamKind.team),
        description: map['description'] as String? ?? '',
        requiresApproval: map['requiresApproval'] as bool? ?? false,
        location: GroupLocation.fromMap(map['location']),
        official: map['official'] == true,
      );

  Map<String, dynamic> toMap() => {
    'name': name,
    'division': division.name,
    'level': level.name,
    'city': city,
    ...communityFields(
      kind: kind,
      description: description,
      requiresApproval: requiresApproval,
      // A private group's location is for members only.
      location: isPrivateGroup ? null : location,
    ),
    if (official) 'official': true,
    'keywords': searchKeywords('$name $city'),
  };
}

/// Someone asking to join a group that requires approval
/// (`teams/{id}/joinRequests/{uid}`). Organizers approve or decline it.
class GroupJoinRequest {
  const GroupJoinRequest({
    required this.uid,
    required this.name,
    this.createdAt,
  });

  final String uid;
  final String name;
  final DateTime? createdAt;

  factory GroupJoinRequest.fromMap(String uid, Map<String, dynamic> map) =>
      GroupJoinRequest(
        uid: uid,
        name: map['name'] as String? ?? '',
        createdAt: parseDate(map['createdAt']),
      );
}

/// An invitation to join a team or group
/// (`users/{uid}/teamInvites/{teamId}`), sent by an owner or organizer who
/// found the user in the people directory. Accepting joins without a code.
class TeamInvite {
  const TeamInvite({
    required this.teamId,
    required this.teamName,
    this.kind = TeamKind.team,
    this.invitedBy = '',
    this.invitedByName = '',
    this.createdAt,
  });

  final String teamId;
  final String teamName;
  final TeamKind kind;
  final String invitedBy;
  final String invitedByName;
  final DateTime? createdAt;

  bool get isCommunity => kind.isGroupLike;

  factory TeamInvite.fromMap(String teamId, Map<String, dynamic> map) =>
      TeamInvite(
        teamId: teamId,
        teamName: map['teamName'] as String? ?? '',
        kind: enumByName(TeamKind.values, map['kind'], TeamKind.team),
        invitedBy: map['invitedBy'] as String? ?? '',
        invitedByName: map['invitedByName'] as String? ?? '',
        createdAt: parseDate(map['createdAt']),
      );
}
