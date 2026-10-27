import 'model_utils.dart';

enum TeamRole {
  owner,
  coach,
  player;

  bool get canEdit => this == owner || this == coach;

  String get label => switch (this) {
    owner => 'Owner',
    coach => 'Coach',
    player => 'Player',
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
    this.city = '',
    this.inviteCode,
    this.createdAt,
  });

  final String id;
  final String name;
  final Division division;
  final CompetitionLevel level;
  final String city;
  final String ownerId;

  /// Code other users enter to join as a player.
  final String? inviteCode;

  /// uid → role.
  final Map<String, TeamRole> members;

  /// uid → display name, denormalized at join time for member lists.
  final Map<String, String> memberNames;
  final DateTime? createdAt;

  TeamRole? roleOf(String uid) => members[uid];

  bool canEdit(String uid) => roleOf(uid)?.canEdit ?? false;

  String nameOf(String uid) => memberNames[uid] ?? 'Member';

  factory Team.fromMap(String id, Map<String, dynamic> map) {
    final rawMembers = (map['members'] as Map?) ?? const {};
    final rawNames = (map['memberNames'] as Map?) ?? const {};
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
      inviteCode: map['inviteCode'] as String?,
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
  }) => Team(
    id: id,
    name: name ?? this.name,
    division: division ?? this.division,
    level: level ?? this.level,
    city: city ?? this.city,
    ownerId: ownerId,
    inviteCode: inviteCode,
    members: members,
    memberNames: memberNames,
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
