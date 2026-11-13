import '../models/group_tournament.dart';

/// A team's record in a pool.
class Standing {
  Standing(this.teamId);

  final String teamId;
  int wins = 0;
  int losses = 0;
  int pointsFor = 0;
  int pointsAgainst = 0;

  int get played => wins + losses;
  int get pointDiff => pointsFor - pointsAgainst;
}

/// Pool ids in order: "A", "B", ...
String poolName(int index) => String.fromCharCode(65 + index);

/// Teams of each pool, from its games.
Map<String, List<String>> poolTeams(List<GroupGame> games) {
  final pools = <String, Set<String>>{};
  for (final g in games) {
    final pool = g.poolId;
    if (g.stage != GameStage.pool || pool == null) continue;
    pools.putIfAbsent(pool, () => {}).addAll([?g.teamA, ?g.teamB]);
  }
  return {
    for (final key in pools.keys.toList()..sort()) key: pools[key]!.toList(),
  };
}

/// Whether every game in [poolId] is final.
bool poolComplete(String poolId, List<GroupGame> games) => games
    .where((g) => g.stage == GameStage.pool && g.poolId == poolId)
    .every((g) => g.isDone);

/// [teamIds] ranked by pool results: most wins, then head to head among
/// the tied teams, then point differential, then points scored. Ties
/// that remain keep [teamIds] order (the pool seed).
List<Standing> standings(List<String> teamIds, Iterable<GroupGame> games) {
  final done = [
    for (final g in games)
      if (g.isDone && teamIds.contains(g.teamA) && teamIds.contains(g.teamB)) g,
  ];
  final rows = {for (final id in teamIds) id: Standing(id)};
  for (final g in done) {
    final a = rows[g.teamA]!;
    final b = rows[g.teamB]!;
    a
      ..pointsFor += g.scoreA!
      ..pointsAgainst += g.scoreB!;
    b
      ..pointsFor += g.scoreB!
      ..pointsAgainst += g.scoreA!;
    if (g.winner == a.teamId) {
      a.wins++;
      b.losses++;
    } else {
      b.wins++;
      a.losses++;
    }
  }

  int headToHead(Standing s, Set<String> tied) => done
      .where(
        (g) =>
            g.winner == s.teamId &&
            tied.contains(g.teamA) &&
            tied.contains(g.teamB),
      )
      .length;

  final byWins = <int, List<Standing>>{};
  for (final r in rows.values) {
    byWins.putIfAbsent(r.wins, () => []).add(r);
  }
  return [
    for (final wins in byWins.keys.toList()..sort((a, b) => b - a))
      ...() {
        final group = byWins[wins]!;
        final tied = {for (final s in group) s.teamId};
        return group..sort((x, y) {
          final h2h = headToHead(y, tied) - headToHead(x, tied);
          if (h2h != 0) return h2h;
          final diff = y.pointDiff - x.pointDiff;
          if (diff != 0) return diff;
          final pf = y.pointsFor - x.pointsFor;
          if (pf != 0) return pf;
          return teamIds.indexOf(x.teamId) - teamIds.indexOf(y.teamId);
        });
      }(),
  ];
}
