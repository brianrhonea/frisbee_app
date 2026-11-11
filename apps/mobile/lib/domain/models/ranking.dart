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
