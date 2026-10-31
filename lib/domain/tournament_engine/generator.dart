import 'dart:math';

import '../models/group_tournament.dart';
import 'standings.dart';

/// A generated schedule: every game with a field and start time.
class SchedulePlan {
  const SchedulePlan({required this.games, required this.endsAt});

  final List<GroupGame> games;

  /// When the last game should finish (including an if-needed final).
  final DateTime endsAt;

  /// Minutes the plan runs past [idealEndsAt]; 0 if it fits or has none.
  int overrunMinutes(DateTime? idealEndsAt) => idealEndsAt == null
      ? 0
      : max(0, endsAt.difference(idealEndsAt).inMinutes);
}

class ScheduleException implements Exception {
  const ScheduleException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Generates and schedules every game of [tournament] for its teams, in
/// their current order (which seeds pools and brackets).
SchedulePlan generateSchedule(GroupTournament tournament) {
  final s = tournament.settings;
  final teams = [for (final t in tournament.teams) t.id];
  if (teams.length < 2) {
    throw const ScheduleException('A tournament needs at least two teams.');
  }
  final b = _Builder();
  switch (s.format) {
    case TournamentFormat.roundRobin:
      _pools(b, teams, 1);
    case TournamentFormat.poolsSingleElim:
      final pools = _pools(b, teams, s.poolCount.clamp(1, teams.length ~/ 2));
      _singleElim(b, _crossSeed(pools));
    case TournamentFormat.singleElim:
      _singleElim(b, [for (final t in teams) _Entrant.team(t)]);
    case TournamentFormat.doubleElim:
      _doubleElim(b, [for (final t in teams) _Entrant.team(t)]);
  }
  return _schedule(b.games, s);
}

/// Snake-seeds [teams] into [count] pools (A gets seeds 1, 2n, 2n+1...)
/// and adds each pool's round robin. Returns pool id → teams by seed.
Map<String, List<String>> _pools(_Builder b, List<String> teams, int count) {
  final pools = {for (var i = 0; i < count; i++) poolName(i): <String>[]};
  final ids = pools.keys.toList();
  for (var i = 0; i < teams.length; i++) {
    final lap = i ~/ count;
    final at = i % count;
    pools[ids[lap.isEven ? at : count - 1 - at]]!.add(teams[i]);
  }
  final rounds = {for (final p in ids) p: roundRobin(pools[p]!)};
  final most = rounds.values.map((r) => r.length).fold(0, max);
  // Round by round across pools, so pools finish together.
  for (var r = 0; r < most; r++) {
    for (final p in ids) {
      if (r >= rounds[p]!.length) continue;
      for (final (a, c) in rounds[p]!.elementAt(r)) {
        b.add(
          stage: GameStage.pool,
          round: r + 1,
          label: count == 1 ? 'Round ${r + 1}' : 'Pool $p · Round ${r + 1}',
          poolId: p,
          a: _Entrant.team(a),
          c: _Entrant.team(c),
        );
      }
    }
  }
  return pools;
}

/// Every pairing of [teams], by round (circle method). With an odd count
/// one team sits out each round.
List<List<(T, T)>> roundRobin<T>(List<T> teams) {
  final list = <T?>[...teams, if (teams.length.isOdd) null];
  final n = list.length;
  if (n < 2) return const [];
  final rounds = <List<(T, T)>>[];
  for (var r = 0; r < n - 1; r++) {
    final round = <(T, T)>[];
    for (var i = 0; i < n ~/ 2; i++) {
      final a = list[i];
      final c = list[n - 1 - i];
      if (a != null && c != null) round.add((a, c));
    }
    rounds.add(round);
    // Keep the first fixed, rotate the rest.
    list.insert(1, list.removeLast());
  }
  return rounds;
}

/// Bracket seeds from pool finish: every pool's 1st, then every 2nd in
/// reverse pool order, and so on, so pool-mates meet as late as possible.
List<_Entrant> _crossSeed(Map<String, List<String>> pools) {
  final ids = pools.keys.toList();
  final deepest = pools.values.map((p) => p.length).fold(0, max);
  return [
    for (var rank = 1; rank <= deepest; rank++)
      for (final p in rank.isOdd ? ids : ids.reversed)
        if (pools[p]!.length >= rank) _Entrant.source(PoolRank(p, rank)),
  ];
}

/// Bracket positions for [size] seeds (a power of two), in match order:
/// 1 v 8, 4 v 5, 2 v 7, 3 v 6 for 8.
List<int> seedOrder(int size) {
  var order = [1];
  while (order.length < size) {
    final n = order.length * 2;
    order = [
      for (final s in order) ...[s, n + 1 - s],
    ];
  }
  return order;
}

int _bracketSize(int n) {
  var p = 1;
  while (p < n) {
    p *= 2;
  }
  return p;
}

String _roundName(int matches, int round) => switch (matches) {
  1 => 'Final',
  2 => 'Semifinal',
  4 => 'Quarterfinal',
  _ => 'Round $round',
};

/// First-round entrants of a bracket of [entrants] in seed order; null is
/// a bye.
List<_Entrant?> _firstRound(List<_Entrant> entrants) {
  final size = _bracketSize(entrants.length);
  return [
    for (final seed in seedOrder(size))
      seed <= entrants.length ? entrants[seed - 1] : null,
  ];
}

/// Single elimination; byes go to the top seeds.
void _singleElim(_Builder b, List<_Entrant> entrants) {
  var current = _firstRound(entrants);
  var round = 1;
  while (current.length > 1) {
    final matches = current.length ~/ 2;
    current = [
      for (var i = 0; i < matches; i++)
        b
            .match(
              stage: GameStage.winners,
              round: round,
              label: _roundName(matches, round),
              a: current[2 * i],
              c: current[2 * i + 1],
            )
            .winner,
    ];
    round++;
  }
}

/// Double elimination: a winners' bracket, a losers' bracket fed by its
/// losers, then a final between the two champions. If the losers'
/// bracket team wins it, a second final decides it.
void _doubleElim(_Builder b, List<_Entrant> entrants) {
  var winners = _firstRound(entrants);
  final droppedByRound = <List<_Entrant?>>[];
  var round = 1;
  while (winners.length > 1) {
    final matches = winners.length ~/ 2;
    final results = [
      for (var i = 0; i < matches; i++)
        b.match(
          stage: GameStage.winners,
          round: round,
          label: "Winners' ${_roundName(matches, round).toLowerCase()}",
          a: winners[2 * i],
          c: winners[2 * i + 1],
        ),
    ];
    winners = [for (final r in results) r.winner];
    droppedByRound.add([for (final r in results) r.loser]);
    round++;
  }
  final wbChampion = winners.single;

  var lbRound = 0;
  List<_Entrant?> lbMatches(List<_Entrant?> sideA, List<_Entrant?> sideB) {
    lbRound++;
    return [
      for (var i = 0; i < sideA.length; i++)
        b
            .match(
              stage: GameStage.losers,
              round: lbRound,
              label: "Losers' round $lbRound",
              a: sideA[i],
              c: sideB[i],
            )
            .winner,
    ];
  }

  // Losers of the first round play each other, then each later round's
  // losers drop in to face the survivors (reversed every other round to
  // avoid rematches), with a round among the survivors in between.
  var losers = droppedByRound.first;
  if (losers.length > 1) {
    losers = lbMatches(
      [for (var i = 0; i < losers.length; i += 2) losers[i]],
      [for (var i = 1; i < losers.length; i += 2) losers[i]],
    );
  }
  for (var r = 1; r < droppedByRound.length; r++) {
    final drop = droppedByRound[r];
    losers = lbMatches(losers, r.isOdd ? drop.reversed.toList() : drop);
    if (losers.length > 1) {
      losers = lbMatches(
        [for (var i = 0; i < losers.length; i += 2) losers[i]],
        [for (var i = 1; i < losers.length; i += 2) losers[i]],
      );
    }
  }
  final lbChampion = losers.single;

  final finalRound = droppedByRound.length + 1;
  final grand = b.match(
    stage: GameStage.grandFinal,
    round: finalRound,
    label: 'Final',
    a: wbChampion,
    c: lbChampion,
  );
  final grandId = grand.gameId;
  if (grandId == null) return;
  // Played only if the losers' bracket champion (team B) wins the final:
  // then both teams have one loss.
  b.add(
    stage: GameStage.reset,
    round: finalRound + 1,
    label: 'Final (if needed)',
    a: _Entrant.source(LoserOf(grandId)),
    c: _Entrant.source(WinnerOf(grandId)),
    ifNeeded: true,
  );
}

/// A known team or a team decided by an earlier result.
class _Entrant {
  const _Entrant.team(String this.team) : source = null;
  const _Entrant.source(SlotSource this.source) : team = null;

  final String? team;
  final SlotSource? source;
}

class _Match {
  const _Match({this.winner, this.loser, this.gameId});

  final _Entrant? winner;
  final _Entrant? loser;

  /// Null when a bye decided it without a game.
  final String? gameId;
}

class _Builder {
  final games = <GroupGame>[];

  String _nextId() => 'g${(games.length + 1).toString().padLeft(3, '0')}';

  /// A game between [a] and [c], or a bye if either is missing.
  _Match match({
    required GameStage stage,
    required int round,
    required String label,
    required _Entrant? a,
    required _Entrant? c,
  }) {
    if (a == null || c == null) return _Match(winner: a ?? c);
    final id = add(stage: stage, round: round, label: label, a: a, c: c);
    return _Match(
      winner: _Entrant.source(WinnerOf(id)),
      loser: _Entrant.source(LoserOf(id)),
      gameId: id,
    );
  }

  String add({
    required GameStage stage,
    required int round,
    required String label,
    required _Entrant a,
    required _Entrant c,
    String? poolId,
    bool ifNeeded = false,
  }) {
    final id = _nextId();
    games.add(
      GroupGame(
        id: id,
        order: games.length,
        stage: stage,
        round: round,
        label: label,
        poolId: poolId,
        teamA: a.team,
        teamB: c.team,
        sourceA: a.source,
        sourceB: c.source,
        ifNeeded: ifNeeded,
      ),
    );
    return id;
  }
}

/// Games each game must wait for: the games its teams come from, and for
/// pool-rank seeds every game of that pool.
Map<String, Set<String>> _dependencies(List<GroupGame> games) {
  final byPool = <String, Set<String>>{};
  for (final g in games) {
    if (g.stage == GameStage.pool) {
      byPool.putIfAbsent(g.poolId ?? '', () => {}).add(g.id);
    }
  }
  Set<String> from(SlotSource? s) => switch (s) {
    WinnerOf(:final gameId) || LoserOf(:final gameId) => {gameId},
    PoolRank(:final poolId) => byPool[poolId] ?? const {},
    null => const {},
  };
  return {
    for (final g in games) g.id: {...from(g.sourceA), ...from(g.sourceB)},
  };
}

/// Puts games into time slots, [TournamentSettings.fields] at a time, in
/// order, once the games they wait for are over and no team plays twice
/// in a slot.
SchedulePlan _schedule(List<GroupGame> games, TournamentSettings s) {
  final fields = max(1, s.fields);
  final slotLength = Duration(minutes: s.gameMinutes + s.breakMinutes);
  final deps = _dependencies(games);
  final slotOf = <String, int>{};
  final pending = [...games];
  final scheduled = <GroupGame>[];
  var slot = 0;
  while (pending.isNotEmpty) {
    final busy = <String>{};
    var used = 0;
    for (final g in [...pending]) {
      if (used == fields) break;
      final ready = deps[g.id]!.every((d) => (slotOf[d] ?? slot) < slot);
      final teams = [?g.teamA, ?g.teamB];
      if (!ready || teams.any(busy.contains)) continue;
      busy.addAll(teams);
      slotOf[g.id] = slot;
      pending.remove(g);
      used++;
      scheduled.add(
        g.copyWith(
          order: scheduled.length,
          field: used,
          startsAt: s.startsAt.add(slotLength * slot),
        ),
      );
    }
    slot++;
    if (slot > games.length * 2 + 2) {
      throw const ScheduleException("These games can't be scheduled.");
    }
  }
  final last = scheduled.map((g) => g.startsAt!).fold(s.startsAt, _later);
  return SchedulePlan(
    games: scheduled,
    endsAt: last.add(Duration(minutes: s.gameMinutes)),
  );
}

DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
