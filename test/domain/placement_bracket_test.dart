import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/tournament_engine/generator.dart';
import 'package:frisbee_app/domain/tournament_engine/progress.dart';

/// Plays every game in order: the better (lower) seed always wins.
List<GroupGame> playOut(List<String> seeds, List<GroupGame> games) {
  var current = [...games];
  int rank(String t) => seeds.indexOf(t);
  for (var guard = 0; guard < 500; guard++) {
    final fills = bracketSeeds(current);
    current = _apply(current, fills);
    final next = current.where((g) => !g.isDone && g.hasTeams).firstOrNull;
    if (next == null) break;
    final aWins = rank(next.teamA!) < rank(next.teamB!);
    final done = next.copyWith(
      status: GameStatus.done,
      scoreA: () => aWins ? 13 : 9,
      scoreB: () => aWins ? 9 : 13,
    );
    current = [for (final g in current) g.id == done.id ? done : g];
    current = _apply(current, fillsAfter(done, current));
  }
  return current;
}

List<GroupGame> _apply(List<GroupGame> games, List<SlotFill> fills) => [
  for (final g in games)
    if (fills.where((f) => f.gameId == g.id).firstOrNull case final f?)
      g.copyWith(
        teamA: f.teamA == null ? null : () => f.teamA,
        teamB: f.teamB == null ? null : () => f.teamB,
      )
    else
      g,
];

void main() {
  final start = DateTime(2027, 5, 1, 9);

  test('ordinal', () {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 103].map(ordinal), [
      '1st',
      '2nd',
      '3rd',
      '4th',
      '11th',
      '12th',
      '13th',
      '21st',
      '22nd',
      '103rd',
    ]);
  });

  test('suggested pools follow the usual club formats', () {
    expect([4, 6, 8, 10, 12, 16, 20].map(suggestedPools), [
      1,
      1,
      2,
      2,
      3,
      4,
      4,
    ]);
    expect(suggestedFormat(4), TournamentFormat.roundRobin);
    expect(suggestedFormat(12), TournamentFormat.poolsPlacement);
  });

  for (final n in [2, 3, 5, 6, 8, 12, 16]) {
    test('placement bracket for $n teams gives every place once', () {
      final seeds = [for (var i = 1; i <= n; i++) 't$i'];
      final plan = scheduleFor(
        seeds,
        TournamentSettings(
          startsAt: start,
          format: TournamentFormat.poolsPlacement,
          poolCount: n >= 8 ? 2 : 1,
          fields: 4,
        ),
      );
      final played = playOut(seeds, plan.games);
      expect(gamesToPlay(played), isEmpty);
      final places = placementsOf(
        TournamentFormat.poolsPlacement,
        seeds,
        played,
      );
      expect(places.toSet(), seeds.toSet());
      expect(places.length, n);
      // Better seeds always win, so they finish in seed order.
      expect(places, seeds);
      expect(championOf(TournamentFormat.poolsPlacement, played), 't1');
    });
  }

  test('a 6-team bracket starts with crossovers and labels places', () {
    final seeds = [for (var i = 1; i <= 6; i++) 't$i'];
    final games = scheduleFor(
      seeds,
      TournamentSettings(
        startsAt: start,
        format: TournamentFormat.poolsPlacement,
        poolCount: 1,
      ),
    ).games.where((g) => g.stage != GameStage.pool).toList();
    // A single pool feeds the bracket directly by pool finish.
    expect(games.where((g) => g.stage == GameStage.crossover), hasLength(2));
    final labels = games.map((g) => g.label).toSet();
    expect(
      labels,
      containsAll([
        'Crossover',
        'Semifinal',
        'Final',
        '3rd place',
        '5th place',
      ]),
    );
    expect(games.firstWhere((g) => g.label == 'Final').place, 1);
    expect(games.firstWhere((g) => g.label == '5th place').place, 5);
  });

  test('place round-trips and is left out when null', () {
    const g = GroupGame(
      id: 'g1',
      order: 0,
      stage: GameStage.placement,
      round: 3,
      label: '5th place',
      place: 5,
    );
    expect(GroupGame.fromMap('g1', g.toMap()).place, 5);
    const plain = GroupGame(
      id: 'g2',
      order: 0,
      stage: GameStage.pool,
      round: 1,
      label: 'Round 1',
    );
    expect(plain.toMap().containsKey('place'), isFalse);
  });
}
