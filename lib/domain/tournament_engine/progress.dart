import '../models/group_tournament.dart';
import 'standings.dart';

/// A team to write into a waiting game once it's known.
typedef SlotFill = ({String gameId, String? teamA, String? teamB});

/// Teams that move on once [finished] is final: winners and losers into
/// the games waiting on them. The if-needed final only gets its teams
/// when the losers' bracket team (team B) won the first final.
///
/// With [overwrite] (an organizer correcting a score), slots already
/// filled are replaced too; callers should first check [laterGamesPlayed].
List<SlotFill> fillsAfter(
  GroupGame finished,
  List<GroupGame> games, {
  bool overwrite = false,
}) {
  final winner = finished.winner;
  final loser = finished.loser;
  if (winner == null || loser == null) return const [];
  String? resolve(SlotSource? s) => switch (s) {
    WinnerOf(:final gameId) when gameId == finished.id => winner,
    LoserOf(:final gameId) when gameId == finished.id => loser,
    _ => null,
  };
  String? fill(String? current, SlotSource? source) {
    final team = resolve(source);
    if (team == null || team == current) return null;
    return current == null || overwrite ? team : null;
  }

  return [
    for (final g in games)
      if (g.id != finished.id && !g.isDone)
        if ((fill(g.teamA, g.sourceA), fill(g.teamB, g.sourceB)) case (
          final a,
          final b,
        ) when a != null || b != null)
          if (!(g.stage == GameStage.reset &&
              finished.stage == GameStage.grandFinal &&
              winner != finished.teamB))
            (gameId: g.id, teamA: a, teamB: b),
  ];
}

/// Whether a game fed by [game]'s result has already been played (or
/// reported), so its result can't change without undoing them.
bool laterGamesPlayed(GroupGame game, List<GroupGame> games) => games.any(
  (g) =>
      g.status != GameStatus.scheduled &&
      [g.sourceA, g.sourceB].any(
        (s) => switch (s) {
          WinnerOf(:final gameId) ||
          LoserOf(:final gameId) => gameId == game.id,
          _ => false,
        },
      ),
);

/// Fills that should already have been written for finished games (e.g.
/// a confirm whose bracket update failed); safe to apply again.
List<SlotFill> pendingFills(List<GroupGame> games) => [
  for (final g in games)
    if (g.isDone) ...fillsAfter(g, games),
];

/// Seeds bracket games from pool standings once every pool is complete.
/// Empty until then, or if there's nothing left to seed.
List<SlotFill> bracketSeeds(List<GroupGame> games) {
  final pools = poolTeams(games);
  if (pools.isEmpty || !pools.keys.every((p) => poolComplete(p, games))) {
    return const [];
  }
  final ranked = {
    for (final p in pools.entries)
      p.key: [
        for (final s in standings(
          p.value,
          games.where((g) => g.poolId == p.key),
        ))
          s.teamId,
      ],
  };
  String? resolve(SlotSource? s) => switch (s) {
    PoolRank(:final poolId, :final rank) => ranked[poolId]?.elementAtOrNull(
      rank - 1,
    ),
    _ => null,
  };
  return [
    for (final g in games)
      if ((
            g.teamA == null ? resolve(g.sourceA) : null,
            g.teamB == null ? resolve(g.sourceB) : null,
          )
          case (final a, final b) when a != null || b != null)
        (gameId: g.id, teamA: a, teamB: b),
  ];
}

/// Whether bracket games are waiting on pool standings.
bool awaitingSeeds(List<GroupGame> games) => games.any(
  (g) =>
      (g.teamA == null && g.sourceA is PoolRank) ||
      (g.teamB == null && g.sourceB is PoolRank),
);

/// Games still to be played; the if-needed final drops out once the
/// first final shows it isn't needed.
List<GroupGame> gamesToPlay(List<GroupGame> games) {
  final grand = games.where((g) => g.stage == GameStage.grandFinal).firstOrNull;
  final resetNeeded = grand == null || !grand.isDone
      ? true
      : grand.winner == grand.teamB;
  return [
    for (final g in games)
      if (!g.isDone && !(g.ifNeeded && !resetNeeded)) g,
  ];
}

/// Whether the if-needed final turned out not to be needed.
bool skippedGame(GroupGame game, List<GroupGame> games) =>
    game.ifNeeded && !game.isDone && !gamesToPlay(games).contains(game);

/// The winner's team id once every game that needs playing is done.
String? champion(GroupTournament t, List<GroupGame> games) {
  if (games.isEmpty || gamesToPlay(games).isNotEmpty) return null;
  if (t.settings.format == TournamentFormat.roundRobin) {
    final pool = poolTeams(games).values.firstOrNull ?? const [];
    return standings(pool, games).firstOrNull?.teamId;
  }
  final reset = games.where((g) => g.stage == GameStage.reset).firstOrNull;
  if (reset != null && reset.isDone) return reset.winner;
  final grand = games.where((g) => g.stage == GameStage.grandFinal).firstOrNull;
  if (grand != null) return grand.winner;
  // Single elimination: the game no other game waits on.
  final fed = {
    for (final g in games)
      for (final s in [g.sourceA, g.sourceB])
        if (s case WinnerOf(:final gameId)) gameId,
  };
  return games
      .where((g) => g.stage.isBracket && !fed.contains(g.id))
      .lastOrNull
      ?.winner;
}

/// Valid scores: whole numbers, no ties (someone has to win).
String? scoreError(int? a, int? b, {int max = 99}) {
  if (a == null || b == null) return 'Enter both scores.';
  if (a < 0 || b < 0 || a > max || b > max) return 'Scores go from 0 to $max.';
  if (a == b) return "Games can't end in a tie.";
  return null;
}
