import 'model_utils.dart';
import 'stats.dart';
import 'team.dart';

/// Which hand a player throws with.
enum ThrowingHand {
  right('Right'),
  left('Left'),
  both('Both');

  const ThrowingHand(this.label);
  final String label;
}

/// Stat totals over some games, as shown on a profile.
class StatTotals {
  const StatTotals({
    this.games = 0,
    this.points = 0,
    this.goals = 0,
    this.assists = 0,
    this.blocks = 0,
    this.completions = 0,
    this.throwaways = 0,
    this.catches = 0,
    this.drops = 0,
  });

  final int games;
  final int points;
  final int goals;
  final int assists;

  /// Hand blocks and breakups.
  final int blocks;
  final int completions;
  final int throwaways;

  /// Catches, goals included.
  final int catches;
  final int drops;

  int get throws => completions + throwaways;

  /// Null with no throws.
  double? get completionPct => throws == 0 ? null : completions / throws;

  /// Per-game average of [count]; null with no games.
  double? perGame(int count) => games == 0 ? null : count / games;

  bool get isEmpty => games == 0 && points == 0;

  /// One game's line for [player].
  factory StatTotals.fromPlayer(PlayerStats p) => StatTotals(
    games: 1,
    points: p.pointsPlayed,
    goals: p.goals,
    assists: p.assists,
    blocks: p.handBlocks + p.breakups,
    completions: p.completions,
    throwaways: p.throwaways,
    catches: p.catches + p.goals,
    drops: p.drops,
  );

  StatTotals operator +(StatTotals o) => StatTotals(
    games: games + o.games,
    points: points + o.points,
    goals: goals + o.goals,
    assists: assists + o.assists,
    blocks: blocks + o.blocks,
    completions: completions + o.completions,
    throwaways: throwaways + o.throwaways,
    catches: catches + o.catches,
    drops: drops + o.drops,
  );

  factory StatTotals.fromMap(Map<String, dynamic> m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return StatTotals(
      games: n('games'),
      points: n('points'),
      goals: n('goals'),
      assists: n('assists'),
      blocks: n('blocks'),
      completions: n('completions'),
      throwaways: n('throwaways'),
      catches: n('catches'),
      drops: n('drops'),
    );
  }

  Map<String, int> toMap() => {
    'games': games,
    'points': points,
    'goals': goals,
    'assists': assists,
    'blocks': blocks,
    'completions': completions,
    'throwaways': throwaways,
    'catches': catches,
    'drops': drops,
  };

  @override
  bool operator ==(Object other) =>
      other is StatTotals && _mapEquals(toMap(), other.toMap());

  @override
  int get hashCode => Object.hashAll(toMap().values);
}

/// A team on a player's profile, with their number and role there.
class ProfileTeam {
  const ProfileTeam({
    required this.id,
    required this.name,
    this.kind = TeamKind.team,
    this.subtitle = '',
    this.role,
    this.number,
    this.position,
  });

  final String id;
  final String name;
  final TeamKind kind;

  /// "Mixed · Club · Denver".
  final String subtitle;
  final String? role;
  final int? number;
  final String? position;

  factory ProfileTeam.fromMap(Map<String, dynamic> m) => ProfileTeam(
    id: m['id'] as String? ?? '',
    name: m['name'] as String? ?? '',
    kind: enumByName(TeamKind.values, m['kind'], TeamKind.team),
    subtitle: m['subtitle'] as String? ?? '',
    role: m['role'] as String?,
    number: (m['number'] as num?)?.toInt(),
    position: m['position'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'subtitle': subtitle,
    'role': role,
    'number': number,
    'position': position,
  };

  @override
  bool operator ==(Object other) =>
      other is ProfileTeam && _mapEquals(toMap(), other.toMap());

  @override
  int get hashCode => Object.hashAll(toMap().values);
}

/// One game on a player's profile: the result and their line.
class ProfileGame {
  const ProfileGame({
    required this.teamName,
    required this.opponent,
    required this.date,
    required this.ourScore,
    required this.theirScore,
    required this.line,
  });

  final String teamName;
  final String opponent;
  final DateTime date;
  final int ourScore;
  final int theirScore;
  final StatTotals line;

  bool get won => ourScore > theirScore;
  bool get tied => ourScore == theirScore;

  factory ProfileGame.fromMap(Map<String, dynamic> m) => ProfileGame(
    teamName: m['teamName'] as String? ?? '',
    opponent: m['opponent'] as String? ?? '',
    date: parseDate(m['date']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    ourScore: (m['ourScore'] as num?)?.toInt() ?? 0,
    theirScore: (m['theirScore'] as num?)?.toInt() ?? 0,
    line: StatTotals.fromMap(
      Map<String, dynamic>.from((m['line'] as Map?) ?? const {}),
    ),
  );

  Map<String, dynamic> toMap() => {
    'teamName': teamName,
    'opponent': opponent,
    'date': date.toIso8601String(),
    'ourScore': ourScore,
    'theirScore': theirScore,
    'line': line.toMap(),
  };

  // Field by field: comparing toMap()s would compare the nested line maps
  // by identity, so a game read back would never equal the one published
  // and the profile would republish on every snapshot.
  @override
  bool operator ==(Object other) =>
      other is ProfileGame &&
      teamName == other.teamName &&
      opponent == other.opponent &&
      date == other.date &&
      ourScore == other.ourScore &&
      theirScore == other.theirScore &&
      line == other.line;

  @override
  int get hashCode => Object.hashAll([teamName, opponent, date, line]);
}

/// What a player chooses to show others on their profile.
class ProfileVisibility {
  const ProfileVisibility({
    this.stats = true,
    this.teams = true,
    this.games = true,
  });

  final bool stats;
  final bool teams;

  /// Recent games and their results.
  final bool games;

  ProfileVisibility copyWith({bool? stats, bool? teams, bool? games}) =>
      ProfileVisibility(
        stats: stats ?? this.stats,
        teams: teams ?? this.teams,
        games: games ?? this.games,
      );

  factory ProfileVisibility.fromMap(Map<String, dynamic> m) =>
      ProfileVisibility(
        stats: m['stats'] as bool? ?? true,
        teams: m['teams'] as bool? ?? true,
        games: m['games'] as bool? ?? true,
      );

  Map<String, bool> toMap() => {'stats': stats, 'teams': teams, 'games': games};

  @override
  bool operator ==(Object other) =>
      other is ProfileVisibility &&
      other.stats == stats &&
      other.teams == teams &&
      other.games == games;

  @override
  int get hashCode => Object.hash(stats, teams, games);
}

/// The parts of a profile the player writes themselves.
class ProfileDetails {
  const ProfileDetails({
    this.bio = '',
    this.pronouns = '',
    this.hometown = '',
    this.school = '',
    this.throwingHand,
    this.playingSince,
    this.visibility = const ProfileVisibility(),
  });

  static const maxBio = 280;

  final String bio;
  final String pronouns;
  final String hometown;
  final String school;
  final ThrowingHand? throwingHand;

  /// Year they started playing.
  final int? playingSince;
  final ProfileVisibility visibility;

  ProfileDetails copyWith({
    String? bio,
    String? pronouns,
    String? hometown,
    String? school,
    ThrowingHand? Function()? throwingHand,
    int? Function()? playingSince,
    ProfileVisibility? visibility,
  }) => ProfileDetails(
    bio: bio ?? this.bio,
    pronouns: pronouns ?? this.pronouns,
    hometown: hometown ?? this.hometown,
    school: school ?? this.school,
    throwingHand: throwingHand == null ? this.throwingHand : throwingHand(),
    playingSince: playingSince == null ? this.playingSince : playingSince(),
    visibility: visibility ?? this.visibility,
  );

  factory ProfileDetails.fromMap(Map<String, dynamic> m) => ProfileDetails(
    bio: m['bio'] as String? ?? '',
    pronouns: m['pronouns'] as String? ?? '',
    hometown: m['hometown'] as String? ?? '',
    school: m['school'] as String? ?? '',
    throwingHand: m['throwingHand'] == null
        ? null
        : enumByName(
            ThrowingHand.values,
            m['throwingHand'],
            ThrowingHand.right,
          ),
    playingSince: (m['playingSince'] as num?)?.toInt(),
    visibility: ProfileVisibility.fromMap(
      Map<String, dynamic>.from((m['visibility'] as Map?) ?? const {}),
    ),
  );

  Map<String, dynamic> toMap() => {
    'bio': bio.trim(),
    'pronouns': pronouns.trim(),
    'hometown': hometown.trim(),
    'school': school.trim(),
    'throwingHand': throwingHand?.name,
    'playingSince': playingSince,
    'visibility': visibility.toMap(),
  };
}

/// What a player's app publishes from their teams for others to see; each
/// part only if [ProfileVisibility] allows it.
class ProfileSummary {
  const ProfileSummary({
    this.teams = const [],
    this.seasons = const {},
    this.games = const [],
    this.updatedAt,
  });

  /// Most recent games kept on a profile.
  static const maxGames = 5;

  final List<ProfileTeam> teams;

  /// Season (the year, e.g. "2026") → totals.
  final Map<String, StatTotals> seasons;

  /// Newest first, at most [maxGames].
  final List<ProfileGame> games;
  final DateTime? updatedAt;

  /// Every season added up.
  StatTotals get career =>
      seasons.values.fold(const StatTotals(), (a, b) => a + b);

  bool get hasStats => seasons.values.any((s) => !s.isEmpty);

  /// The same content, ignoring when it was published.
  bool sameAs(ProfileSummary o) =>
      _listEquals(teams, o.teams) &&
      _mapEquals(seasons, o.seasons) &&
      _listEquals(games, o.games);
}

/// A player's public profile, from `profiles/{uid}`.
class PlayerProfile {
  const PlayerProfile({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.details = const ProfileDetails(),
    this.summary = const ProfileSummary(),
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final ProfileDetails details;
  final ProfileSummary summary;

  factory PlayerProfile.fromMap(String uid, Map<String, dynamic> m) {
    List<Map<String, dynamic>> maps(Object? raw) => [
      for (final e in (raw as List?) ?? const [])
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    final stats = Map<String, dynamic>.from((m['stats'] as Map?) ?? const {});
    return PlayerProfile(
      uid: uid,
      name: m['name'] as String? ?? '',
      photoUrl: m['photoUrl'] as String?,
      details: ProfileDetails.fromMap(m),
      summary: ProfileSummary(
        teams: [for (final t in maps(m['teams'])) ProfileTeam.fromMap(t)],
        seasons: {
          for (final e in stats.entries)
            if (e.value is Map)
              e.key: StatTotals.fromMap(Map<String, dynamic>.from(e.value)),
        },
        games: [for (final g in maps(m['games'])) ProfileGame.fromMap(g)],
        updatedAt: parseDate(m['summaryUpdatedAt']),
      ),
    );
  }

  /// Every word someone might search for this player by: their school,
  /// hometown and teams (their name is indexed separately).
  List<String> get searchTags => searchKeywords(
    [
      details.school,
      details.hometown,
      for (final t in summary.teams) t.name,
    ].join(' '),
  );

  /// Whether every word of [query] starts a word of the name, school,
  /// hometown or a team name.
  bool matches(String query) => matchesSearch(
    [
      name,
      details.school,
      details.hometown,
      for (final t in summary.teams) t.name,
    ].join(' '),
    query,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}
