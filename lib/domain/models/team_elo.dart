import 'model_utils.dart';

/// Our own team Elo ratings for one USA Ultimate ranking list, computed by
/// the `computeUsauTeamElo` Cloud Function from scraped game results.
/// [key] matches the [RankingDivision.key] of the same list.
class TeamEloDivision {
  const TeamEloDivision({
    required this.key,
    required this.label,
    required this.entries,
    this.updatedAt,
  });

  final String key;
  final String label;
  final List<TeamEloEntry> entries;
  final DateTime? updatedAt;

  factory TeamEloDivision.fromMap(String key, Map<String, dynamic> map) =>
      TeamEloDivision(
        key: key,
        label: map['label'] as String? ?? key,
        updatedAt: parseDate(map['updatedAt']),
        entries: [
          for (final e in (map['entries'] as List? ?? const []))
            TeamEloEntry.fromMap(Map<String, dynamic>.from(e)),
        ],
      );
}

class TeamEloEntry {
  const TeamEloEntry({
    required this.rank,
    required this.teamName,
    required this.elo,
    this.teamUrl = '',
    this.games = 0,
    this.wins = 0,
    this.losses = 0,
  });

  final int rank;
  final String teamName;
  final String teamUrl;
  final double elo;
  final int games;
  final int wins;
  final int losses;

  factory TeamEloEntry.fromMap(Map<String, dynamic> map) => TeamEloEntry(
    rank: (map['rank'] as num?)?.toInt() ?? 0,
    teamName: map['teamName'] as String? ?? '',
    teamUrl: map['teamUrl'] as String? ?? '',
    elo: (map['elo'] as num?)?.toDouble() ?? 0,
    games: (map['games'] as num?)?.toInt() ?? 0,
    wins: (map['wins'] as num?)?.toInt() ?? 0,
    losses: (map['losses'] as num?)?.toInt() ?? 0,
  );
}
