import 'model_utils.dart';

/// Member roles, most access first. A player can also be given stats
/// access ([Team.statKeepers]). firestore.rules enforces the same
/// permissions; keep the two in step.
enum TeamRole {
  /// Everything, including roles, ownership and new invite codes.
  owner,

  /// Team admin and stats. Can share, not regenerate, the invite code.
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

  bool get canRegenerateCode => this == owner;

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

  /// Community groups call captains organizers and players members.
  String labelFor(TeamKind kind) => switch ((kind, this)) {
    (TeamKind.community, captain) => 'Organizer',
    (TeamKind.community, player) => 'Member',
    _ => label,
  };

  String pluralLabelFor(TeamKind kind) => switch ((kind, this)) {
    (TeamKind.community, captain) => 'Organizers',
    (TeamKind.community, player) => 'Members',
    _ => pluralLabel,
  };

  String summaryFor(TeamKind kind) => switch ((kind, this)) {
    (TeamKind.community, owner) => 'Everything, including roles',
    (TeamKind.community, captain) =>
      'Manage events, tournaments and join requests',
    (TeamKind.community, player) => 'Join events and tournaments',
    _ => summary,
  };

  /// Roles a member can be given; groups have no coaches.
  static List<TeamRole> rolesFor(TeamKind kind) => switch (kind) {
    TeamKind.team => values,
    TeamKind.community => const [owner, captain, player],
  };

  /// What the role can do, for the role picker.
  String get summary => switch (this) {
    owner => 'Everything, including roles and new invite codes',
    coach => 'Manage the team and keep stats',
    captain => 'Manage the team and keep stats',
    player => 'View only, unless given stats access',
  };
}

/// A closed team (invite code, roster, stats) or an open community group
/// anyone can join, with pickup events and tournaments instead.
enum TeamKind {
  team('Team'),
  community('Community group');

  const TeamKind(this.label);
  final String label;
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
}) => kind == TeamKind.community
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
    this.usauUrl,
    this.usauName,
    this.usauSyncedAt,
    this.createdAt,
    this.kind = TeamKind.team,
    this.description = '',
    this.requiresApproval = false,
    this.location,
  });

  final String id;
  final String name;
  final Division division;
  final CompetitionLevel level;
  final String city;
  final String ownerId;
  final TeamKind kind;

  /// What the group is about, on its home page. Groups only.
  final String description;

  /// Whether organizers approve each join request. Groups only; teams are
  /// joined by invite code.
  final bool requiresApproval;

  /// Where the group plays. Groups only.
  final GroupLocation? location;

  bool get isCommunity => kind == TeamKind.community;

  /// A group that needs approval to join. Its location, posts and events are
  /// for members only; search shows just its name, city and description.
  bool get isPrivateGroup => isCommunity && requiresApproval;

  /// uid → role.
  final Map<String, TeamRole> members;

  /// uid → display name, denormalized at join time for member lists.
  final Map<String, String> memberNames;

  /// Players the owner gave stats access to.
  final Set<String> statKeepers;

  /// Linked USA Ultimate team page, for roster imports.
  final String? usauUrl;

  /// Team name as USA Ultimate shows it.
  final String? usauName;

  /// When the roster was last synced with USA Ultimate.
  final DateTime? usauSyncedAt;
  final DateTime? createdAt;

  TeamRole? roleOf(String uid) => members[uid];

  bool canEdit(String uid) => roleOf(uid)?.canEdit ?? false;

  bool canKeepStats(String uid) => switch (roleOf(uid)) {
    null => false,
    final role => role.canKeepStats || statKeepers.contains(uid),
  };

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
      usauUrl: map['usauUrl'] as String?,
      usauName: map['usauName'] as String?,
      usauSyncedAt: parseDate(map['usauSyncedAt']),
      createdAt: parseDate(map['createdAt']),
      kind: enumByName(TeamKind.values, map['kind'], TeamKind.team),
      description: map['description'] as String? ?? '',
      requiresApproval: map['requiresApproval'] as bool? ?? false,
      location: GroupLocation.fromMap(map['location']),
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
    usauUrl: usauUrl,
    usauName: usauName,
    usauSyncedAt: usauSyncedAt,
    createdAt: createdAt,
    kind: kind,
    description: description ?? this.description,
    requiresApproval: requiresApproval ?? this.requiresApproval,
    location: location != null ? location() : this.location,
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
  });

  final String name;
  final Division division;
  final CompetitionLevel level;
  final String city;
  final TeamKind kind;
  final String description;
  final bool requiresApproval;
  final GroupLocation? location;

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
  };

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

  bool get isCommunity => kind == TeamKind.community;

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

  bool get isCommunity => kind == TeamKind.community;

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
