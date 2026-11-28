import 'player_profile.dart';
import 'team.dart';

/// The roster spot a player was linked to on a team.
class HistorySpot {
  const HistorySpot({required this.id, required this.name, this.number});

  final String id;
  final String name;
  final int? number;
}

/// One team a player's roster spot is (or was) linked to, with their season
/// totals from it. From `GET /v1/players/:uid/team-history`
/// (packages/shared/src/team_history.ts); the server decides who may see it.
class TeamHistoryEntry {
  const TeamHistoryEntry({
    required this.teamId,
    required this.teamName,
    required this.kind,
    required this.current,
    required this.spot,
    this.seasons = const {},
    this.partial = false,
  });

  final String teamId;
  final String teamName;
  final TeamKind kind;

  /// Still a member; false once they have left the team.
  final bool current;
  final HistorySpot spot;

  /// Season (the UTC year of a game's date) to totals.
  final Map<String, StatTotals> seasons;

  /// The team has more games than the server reads: totals cover only the
  /// first 1000.
  final bool partial;

  /// Seasons, newest first.
  List<String> get seasonsNewestFirst =>
      seasons.keys.toList()..sort((a, b) => b.compareTo(a));

  /// The newest season with totals; null without games.
  String? get latestSeason => seasonsNewestFirst.firstOrNull;

  /// Null for a malformed entry (skipped by the list parser).
  static TeamHistoryEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['teamId'];
    final spot = json['spot'];
    if (id is! String || id.isEmpty || spot is! Map) return null;
    final spotId = spot['id'];
    if (spotId is! String || spotId.isEmpty) return null;
    final seasons = <String, StatTotals>{};
    if (json['seasons'] case final Map s) {
      for (final MapEntry(:key, :value) in s.entries) {
        if (value is Map) seasons['$key'] = _totals(value);
      }
    }
    return TeamHistoryEntry(
      teamId: id,
      teamName: json['teamName'] as String? ?? '',
      kind: switch (json['teamKind']) {
        'community' => TeamKind.community,
        'organization' => TeamKind.organization,
        _ => TeamKind.team,
      },
      current: json['current'] == true,
      spot: HistorySpot(
        id: spotId,
        name: spot['name'] as String? ?? '',
        number: (spot['number'] as num?)?.toInt(),
      ),
      seasons: seasons,
      partial: json['partial'] == true,
    );
  }

  static StatTotals _totals(Map m) {
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
}
