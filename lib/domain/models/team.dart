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

  /// What the role can do, for the role picker.
  String get summary => switch (this) {
    owner => 'Everything, including roles and new invite codes',
    coach => 'Manage the team and keep stats',
    captain => 'Manage the team and keep stats',
    player => 'View only, unless given stats access',
  };
}

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
  });

  final String id;
  final String name;
  final Division division;
  final CompetitionLevel level;
  final String city;
  final String ownerId;

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
    );
  }

  /// Editable fields only; membership changes go through dedicated
  /// repository methods so security rules can validate them.
  Map<String, dynamic> toEditableMap() => {
    'name': name,
    'division': division.name,
    'level': level.name,
    'city': city,
  };

  Team copyWith({
    String? name,
    Division? division,
    CompetitionLevel? level,
    String? city,
    Map<String, TeamRole>? members,
    Set<String>? statKeepers,
  }) => Team(
    id: id,
    name: name ?? this.name,
    division: division ?? this.division,
    level: level ?? this.level,
    city: city ?? this.city,
    ownerId: ownerId,
    members: members ?? this.members,
    memberNames: memberNames,
    statKeepers: statKeepers ?? this.statKeepers,
    usauUrl: usauUrl,
    usauName: usauName,
    usauSyncedAt: usauSyncedAt,
    createdAt: createdAt,
  );
}

/// Input for creating a team.
class NewTeam {
  const NewTeam({
    required this.name,
    required this.division,
    required this.level,
    this.city = '',
  });

  final String name;
  final Division division;
  final CompetitionLevel level;
  final String city;

  Map<String, dynamic> toMap() => {
    'name': name,
    'division': division.name,
    'level': level.name,
    'city': city,
  };
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
  });

  factory TeamListing.of(Team team) => TeamListing(
    id: team.id,
    name: team.name,
    division: team.division,
    level: team.level,
    city: team.city,
  );

  final String id;
  final String name;
  final Division division;
  final CompetitionLevel level;
  final String city;

  /// "Mixed · Club · Denver".
  String get subtitle =>
      [division.label, level.label, if (city.isNotEmpty) city].join(' · ');

  /// Whether every word of [query] starts a word of the name or city.
  bool matches(String query) => matchesSearch('$name $city', query);

  /// Whether this still matches [team], or needs republishing.
  bool sameAs(Team team) =>
      id == team.id &&
      name == team.name &&
      division == team.division &&
      level == team.level &&
      city == team.city;

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
      );

  Map<String, dynamic> toMap() => {
    'name': name,
    'division': division.name,
    'level': level.name,
    'city': city,
    'keywords': searchKeywords('$name $city'),
  };
}
