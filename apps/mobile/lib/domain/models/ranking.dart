import 'model_utils.dart';
import 'team.dart';

/// One ranked team in a [DivisionRanking].
class RankedTeam {
  const RankedTeam({
    required this.rank,
    required this.teamId,
    required this.name,
    required this.rating,
    this.wins = 0,
    this.losses = 0,
  });

  final int rank;
  final String teamId;
  final String name;
  final int rating;
  final int wins;
  final int losses;

  /// "12–3".
  String get record => '$wins–$losses';

  factory RankedTeam.fromMap(Map<String, dynamic> map) => RankedTeam(
    rank: (map['rank'] as num?)?.toInt() ?? 0,
    teamId: '${map['teamId'] ?? ''}',
    name: map['name'] as String? ?? 'Team',
    rating: (map['rating'] as num?)?.round() ?? 0,
    wins: (map['wins'] as num?)?.toInt() ?? 0,
    losses: (map['losses'] as num?)?.toInt() ?? 0,
  );
}

/// Stall 10's own ranking of one level and division, at
/// `rankings/{level-division}`. The `rankings` Cloud Functions build it
/// from finished games in public tournaments hosted on the app: a
/// score-differential rating over the last 12 months, newer games and
/// bigger margins counting more.
class DivisionRanking {
  const DivisionRanking({
    required this.level,
    required this.division,
    this.teams = const [],
    this.minGames = 5,
    this.updatedAt,
  });

  final CompetitionLevel level;
  final Division division;

  /// Best first.
  final List<RankedTeam> teams;

  /// Games a team needs to be ranked.
  final int minGames;
  final DateTime? updatedAt;

  /// "club-mixed", the doc id.
  String get key => keyFor(level, division);

  /// Whether this is a ranking anyone may see: never youth (see
  /// [rankedLevels]).
  bool get isRanked => rankedLevels.contains(level);

  /// "Club Mixed".
  String get label => '${level.label} ${division.label}';

  static String keyFor(CompetitionLevel level, Division division) =>
      '${level.name}-${division.name}';

  factory DivisionRanking.fromMap(Map<String, dynamic> map) => DivisionRanking(
    level: enumByName(
      CompetitionLevel.values,
      map['level'],
      CompetitionLevel.club,
    ),
    division: enumByName(Division.values, map['division'], Division.mixed),
    teams: [
      for (final t in (map['teams'] as List?) ?? const [])
        if (t is Map) RankedTeam.fromMap(Map<String, dynamic>.from(t)),
    ],
    minGames: (map['minGames'] as num?)?.toInt() ?? 5,
    updatedAt: parseDate(map['updatedAt']),
  );
}

/// The levels that are ranked, in the Level filter's order. Listed on
/// purpose rather than "every level but youth", so a level added later
/// isn't ranked (or shown) until it's added here. Youth is never ranked:
/// the `rankings` Cloud Functions skip youth divisions and youth teams,
/// and readers leave out a youth ranking too. Mirrors `rankedLevels` in
/// packages/shared/src/rankings.ts.
const rankedLevels = [
  CompetitionLevel.club,
  CompetitionLevel.college,
  CompetitionLevel.league,
  CompetitionLevel.pickup,
];

/// The Rankings page's two filters, Level and Division, and what they're
/// set to. Mirrors `chooseRanking` in packages/shared/src/rankings.ts,
/// checked against the shared vectors in
/// packages/shared/fixtures/rankings.
class RankingChoice {
  const RankingChoice({
    required this.level,
    required this.division,
    required this.levels,
    required this.divisions,
  });

  final CompetitionLevel level;
  final Division division;

  /// Levels with any ranking, in order: the Level filter's options.
  final List<CompetitionLevel> levels;

  /// Divisions ranked at [level], in order: the Division filter's options.
  final List<Division> divisions;

  String get key => DivisionRanking.keyFor(level, division);

  /// The ranking shown when nothing (or nothing with data) is asked for,
  /// if it has data.
  static const defaultKey = 'club-mixed';

  /// A ranking key's level and division, or null for anything not ranked
  /// (youth, unknown, malformed).
  static ({CompetitionLevel level, Division division})? parseKey(
    String? key,
  ) {
    final parts = key?.split('-') ?? const [];
    if (parts.length != 2) return null;
    final level = rankedLevels.where((l) => l.name == parts[0]).firstOrNull;
    final division = Division.values
        .where((d) => d.name == parts[1])
        .firstOrNull;
    return level == null || division == null
        ? null
        : (level: level, division: division);
  }

  /// The ranked keys among [keys], each once, by level then division.
  static List<String> orderedKeys(Iterable<String> keys) {
    int order(String k) {
      final p = parseKey(k)!;
      return rankedLevels.indexOf(p.level) * 10 + p.division.index;
    }

    return {
      for (final k in keys)
        if (parseKey(k) != null) k,
    }.toList()..sort((a, b) => order(a).compareTo(order(b)));
  }

  /// Reads the page's link: `?level=club&division=mixed`, or the old
  /// `?d=club-mixed` / `?division=club-mixed` (a key, used when no level
  /// is given). A youth or unknown key reads as nothing asked for.
  static ({String? level, String? division}) wantFromQuery({
    String? level,
    String? division,
    String? d,
  }) {
    final legacy = d ?? (division != null && division.contains('-') ? division : null);
    if (legacy != null && level == null) {
      final p = parseKey(legacy);
      return (level: p?.level.name, division: p?.division.name);
    }
    return (
      level: level,
      division: division != null && division.contains('-') ? null : division,
    );
  }

  /// Which ranking the filters show, given the [keys] that have data, or
  /// null when none does: the [level] and [division] asked for if that
  /// ranking has data; else [level] at its first division with data; else
  /// [division] at the first level that has it; else Club Mixed, else the
  /// first ranking.
  static RankingChoice? choose(
    Iterable<String> keys, {
    String? level,
    String? division,
  }) {
    final ordered = orderedKeys(keys);
    if (ordered.isEmpty) return null;
    final prefer = ordered.contains(defaultKey)
        ? [defaultKey, ...ordered.where((k) => k != defaultKey)]
        : ordered;
    final parsed = [for (final k in prefer) parseKey(k)!];
    final l = rankedLevels.where((x) => x.name == level).firstOrNull;
    final d = Division.values.where((x) => x.name == division).firstOrNull;
    final pick =
        parsed
            .where(
              (p) => (l == null || p.level == l) && (d == null || p.division == d),
            )
            .firstOrNull ??
        (l == null ? null : parsed.where((p) => p.level == l).firstOrNull) ??
        parsed.first;
    final all = [for (final k in ordered) parseKey(k)!];
    return RankingChoice(
      level: pick.level,
      division: pick.division,
      levels: [
        for (final x in rankedLevels)
          if (all.any((p) => p.level == x)) x,
      ],
      divisions: [
        for (final x in Division.values)
          if (all.any((p) => p.level == pick.level && p.division == x)) x,
      ],
    );
  }
}

/// A team that placed in a [TournamentResult] division.
typedef PlacedTeam = ({String teamId, String name});

/// One division's top two at a finished tournament.
class DivisionResult {
  const DivisionResult({required this.label, this.champion, this.runnerUp});

  /// "Club Mixed".
  final String label;
  final PlacedTeam? champion;
  final PlacedTeam? runnerUp;

  static PlacedTeam? _team(Object? raw) => raw is Map
      ? (teamId: '${raw['teamId'] ?? ''}', name: '${raw['name'] ?? 'Team'}')
      : null;

  factory DivisionResult.fromMap(Map<String, dynamic> map) => DivisionResult(
    label: map['label'] as String? ?? '',
    champion: _team(map['champion']),
    runnerUp: _team(map['runnerUp']),
  );
}

/// A recently finished public tournament, from
/// `tournamentResults/recent`.
class TournamentResult {
  const TournamentResult({
    required this.tournamentId,
    required this.name,
    this.hostName = '',
    this.location = '',
    this.startsOn,
    this.endsOn,
    this.divisions = const [],
  });

  final String tournamentId;
  final String name;
  final String hostName;
  final String location;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final List<DivisionResult> divisions;

  factory TournamentResult.fromMap(Map<String, dynamic> map) =>
      TournamentResult(
        tournamentId: '${map['tournamentId'] ?? ''}',
        name: map['name'] as String? ?? '',
        hostName: map['hostName'] as String? ?? '',
        location: map['location'] as String? ?? '',
        startsOn: parseDate(map['startsOn']),
        endsOn: parseDate(map['endsOn']),
        divisions: [
          for (final d in (map['divisions'] as List?) ?? const [])
            if (d is Map) DivisionResult.fromMap(Map<String, dynamic>.from(d)),
        ],
      );
}

/// A rated player in Stall 10's player ranking.
class RankedPlayer {
  const RankedPlayer({
    required this.rank,
    required this.uid,
    required this.name,
    required this.rating,
    this.username,
    this.photoUrl,
    this.games = 0,
    this.points = 0,
    this.goals = 0,
    this.assists = 0,
    this.blocks = 0,
    this.turnovers = 0,
  });

  final int rank;
  final String uid;
  final String name;
  final String? username;
  final String? photoUrl;

  /// 1–99; the average rated player is 50.
  final int rating;

  /// This season plus half of last season, rounded.
  final int games;
  final int points;
  final int goals;
  final int assists;
  final int blocks;
  final int turnovers;

  factory RankedPlayer.fromMap(Map<String, dynamic> map) {
    int n(String k) => (map[k] as num?)?.round() ?? 0;
    return RankedPlayer(
      rank: n('rank'),
      uid: '${map['uid'] ?? ''}',
      name: map['name'] as String? ?? '',
      username: map['username'] as String?,
      photoUrl: map['photoUrl'] as String?,
      rating: n('rating'),
      games: n('games'),
      points: n('points'),
      goals: n('goals'),
      assists: n('assists'),
      blocks: n('blocks'),
      turnovers: n('turnovers'),
    );
  }
}

/// Stall 10's player ranking, at `playerRankings/all`. The `rankings`
/// Cloud Functions rate players nightly from the season stats on public
/// profiles, once they have [minGames] games logged: production per point
/// played (goals, assists, blocks and touches, less turnovers), weighed
/// against how many points they've played.
class PlayerRanking {
  const PlayerRanking({
    this.players = const [],
    this.minGames = 10,
    this.updatedAt,
  });

  /// Best first.
  final List<RankedPlayer> players;
  final int minGames;
  final DateTime? updatedAt;

  factory PlayerRanking.fromMap(Map<String, dynamic> map) => PlayerRanking(
    players: [
      for (final p in (map['players'] as List?) ?? const [])
        if (p is Map) RankedPlayer.fromMap(Map<String, dynamic>.from(p)),
    ],
    minGames: (map['minGames'] as num?)?.toInt() ?? 10,
    updatedAt: parseDate(map['updatedAt']),
  );
}
