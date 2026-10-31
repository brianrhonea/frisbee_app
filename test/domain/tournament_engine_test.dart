import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/tournament_engine/generator.dart';
import 'package:frisbee_app/domain/tournament_engine/progress.dart';
import 'package:frisbee_app/domain/tournament_engine/standings.dart';
import 'package:frisbee_app/domain/tournament_engine/team_builder.dart';

final start = DateTime(2026, 11, 7, 9);

GroupTournament tournamentOf(
  int teamCount,
  TournamentFormat format, {
  int pools = 2,
  int fields = 2,
  DateTime? idealEndsAt,
}) => GroupTournament(
  id: 't',
  name: 'Fall Hat',
  settings: TournamentSettings(
    startsAt: start,
    format: format,
    poolCount: pools,
    fields: fields,
    gameMinutes: 30,
    breakMinutes: 10,
    idealEndsAt: idealEndsAt,
  ),
  teams: [
    for (var i = 1; i <= teamCount; i++)
      TournamentTeam(id: 'T$i', name: 'Team $i', captainId: 'c$i'),
  ],
);

/// Plays every game as soon as both teams are known, applying bracket
/// fills and seeds like the app does. [winner] picks who wins.
List<GroupGame> playOut(
  List<GroupGame> games, {
  String Function(GroupGame g)? winner,
}) {
  final byId = {for (final g in games) g.id: g};
  winner ??= (g) =>
      int.parse(g.teamA!.substring(1)) < int.parse(g.teamB!.substring(1))
      ? g.teamA!
      : g.teamB!;
  void apply(List<SlotFill> fills) {
    for (final f in fills) {
      final g = byId[f.gameId]!;
      byId[f.gameId] = g.copyWith(
        teamA: f.teamA == null ? null : () => f.teamA,
        teamB: f.teamB == null ? null : () => f.teamB,
      );
    }
  }

  for (var guard = 0; guard < 500; guard++) {
    final list = byId.values.toList()..sort((a, b) => a.order - b.order);
    final next = gamesToPlay(list).where((g) => g.hasTeams).firstOrNull;
    if (next == null) {
      final seeds = bracketSeeds(list);
      if (seeds.isEmpty) return list;
      apply(seeds);
      continue;
    }
    final aWins = winner(next) == next.teamA;
    final done = next.copyWith(
      status: GameStatus.done,
      scoreA: () => aWins ? 11 : 7,
      scoreB: () => aWins ? 7 : 11,
    );
    byId[next.id] = done;
    apply(fillsAfter(done, byId.values.toList()));
  }
  fail('Tournament never finished');
}

Map<String, int> losses(List<GroupGame> games) {
  final l = <String, int>{};
  for (final g in games.where((g) => g.isDone)) {
    l[g.loser!] = (l[g.loser!] ?? 0) + 1;
  }
  return l;
}

void main() {
  group('team builder', () {
    test('deals everyone into teams that differ by at most one', () {
      final players = [for (var i = 0; i < 23; i++) (uid: 'u$i', name: 'P$i')];
      final teams = buildTeams(players, teamSize: 7, random: Random(1));
      expect(teams.length, 4);
      final sizes = teams.map((t) => t.playerIds.length).toList();
      expect(sizes.reduce(max) - sizes.reduce(min), lessThanOrEqualTo(1));
      expect(teams.expand((t) => t.playerIds).toSet().length, 23);
      for (final t in teams) {
        expect(t.playerIds, contains(t.captainId));
      }
      expect(teams.map((t) => t.name), [
        'Team 1',
        'Team 2',
        'Team 3',
        'Team 4',
      ]);
    });

    test('makes at least two teams and ignores duplicates', () {
      final teams = buildTeams([
        (uid: 'a', name: 'A'),
        (uid: 'a', name: 'A'),
        (uid: 'b', name: 'B'),
      ], teamSize: 9);
      expect(teams.length, 2);
      expect(teams.expand((t) => t.playerIds).toList()..sort(), ['a', 'b']);
    });

    test('moving players keeps one team each and a captain', () {
      var teams = blankTeams(2);
      expect(teams.map((t) => t.id), ['team1', 'team2']);
      teams = movePlayer(teams, (uid: 'a', name: 'A'), teamId: 'team1');
      teams = movePlayer(teams, (uid: 'b', name: 'B'), teamId: 'team1');
      expect(teams.first.captainId, 'a');
      teams = movePlayer(teams, (uid: 'a', name: 'A'), teamId: 'team2');
      expect(teams.first.playerIds, ['b']);
      expect(teams.first.captainId, 'b');
      expect(teams.last.captainId, 'a');
      teams = movePlayer(teams, (uid: 'a', name: 'A'), teamId: null);
      expect(teams.last.playerIds, isEmpty);
      expect(teams.last.captainId, isNull);
      expect(blankTeams(1, existing: teams).single.id, 'team3');
    });
  });

  group('round robin', () {
    for (final n in [2, 3, 4, 5, 8]) {
      test('$n teams: every pair plays once, nobody twice a round', () {
        final teams = [for (var i = 0; i < n; i++) i];
        final rounds = roundRobin(teams);
        final pairs = <String>{};
        for (final round in rounds) {
          final seen = <int>{};
          for (final (a, b) in round) {
            expect(seen.add(a) && seen.add(b), isTrue);
            expect(pairs.add('${min(a, b)}-${max(a, b)}'), isTrue);
          }
        }
        expect(pairs.length, n * (n - 1) ~/ 2);
      });
    }

    test('the best record wins', () {
      final t = tournamentOf(5, TournamentFormat.roundRobin);
      final games = playOut(generateSchedule(t).games);
      expect(games.length, 10);
      expect(games.every((g) => g.label.startsWith('Round')), isTrue);
      expect(champion(t, games), 'T1');
    });
  });

  test('seed order spreads the top seeds', () {
    expect(seedOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
    expect(seedOrder(4), [1, 4, 2, 3]);
  });

  group('single elimination', () {
    for (final n in [2, 3, 5, 6, 7, 8, 12]) {
      test('$n teams: n-1 games, one champion, byes for top seeds', () {
        final t = tournamentOf(n, TournamentFormat.singleElim);
        final plan = generateSchedule(t);
        expect(plan.games.length, n - 1);
        final games = playOut(plan.games);
        final l = losses(games);
        expect(l.length, n - 1);
        expect(l.values.every((v) => v == 1), isTrue);
        expect(champion(t, games), 'T1');
      });
    }

    test('labels the last rounds', () {
      final games = generateSchedule(
        tournamentOf(8, TournamentFormat.singleElim),
      ).games;
      expect(games.where((g) => g.label == 'Quarterfinal').length, 4);
      expect(games.where((g) => g.label == 'Semifinal').length, 2);
      expect(games.where((g) => g.label == 'Final').length, 1);
    });

    test('an upset still finishes', () {
      final t = tournamentOf(6, TournamentFormat.singleElim);
      final games = playOut(
        generateSchedule(t).games,
        winner: (g) => g.teamA == 'T1' || g.teamB == 'T1'
            ? (g.teamA == 'T1' ? g.teamB! : g.teamA!)
            : g.teamA!,
      );
      expect(champion(t, games), isNot('T1'));
      expect(champion(t, games), isNotNull);
    });
  });

  group('double elimination', () {
    for (final n in [2, 3, 4, 5, 6, 7, 8, 11, 16]) {
      test('$n teams: out after two losses, reset only if needed', () {
        final t = tournamentOf(n, TournamentFormat.doubleElim);
        final plan = generateSchedule(t);
        expect(plan.games.where((g) => g.ifNeeded).length, 1);
        final games = playOut(plan.games);
        final l = losses(games);
        final champ = champion(t, games)!;
        expect(champ, 'T1');
        for (var i = 1; i <= n; i++) {
          final id = 'T$i';
          expect(l[id] ?? 0, id == champ ? 0 : 2, reason: id);
        }
        // The winners' bracket champion won the final: no reset.
        final reset = games.singleWhere((g) => g.ifNeeded);
        expect(skippedGame(reset, games), isTrue);
        expect(games.where((g) => g.isDone).length, 2 * n - 2);
      });
    }

    test('the reset is played when the losers bracket team wins', () {
      final t = tournamentOf(4, TournamentFormat.doubleElim);
      final games = playOut(
        generateSchedule(t).games,
        winner: (g) {
          // T1 wins everything except the first final.
          if (g.stage == GameStage.grandFinal) {
            return g.teamA == 'T1' ? g.teamB! : g.teamA!;
          }
          final a = int.parse(g.teamA!.substring(1));
          final b = int.parse(g.teamB!.substring(1));
          return a < b ? g.teamA! : g.teamB!;
        },
      );
      final reset = games.singleWhere((g) => g.ifNeeded);
      expect(reset.isDone, isTrue);
      expect(champion(t, games), 'T1');
      expect(losses(games)['T1'], 1);
    });
  });

  group('pool play + single elimination', () {
    test('snake-seeds pools, then seeds the bracket from standings', () {
      final t = tournamentOf(8, TournamentFormat.poolsSingleElim);
      final plan = generateSchedule(t);
      final pools = poolTeams(plan.games);
      expect(pools['A']!.toSet(), {'T1', 'T4', 'T5', 'T8'});
      expect(pools['B']!.toSet(), {'T2', 'T3', 'T6', 'T7'});
      expect(plan.games.where((g) => g.stage == GameStage.pool).length, 12);
      // Everyone plays on in a bracket of 8.
      expect(plan.games.where((g) => g.stage.isBracket).length, 7);
      expect(awaitingSeeds(plan.games), isTrue);
      expect(bracketSeeds(plan.games), isEmpty);

      final games = playOut(plan.games);
      expect(awaitingSeeds(games), isFalse);
      expect(champion(t, games), 'T1');
      // Pool winners (T1, T2) are on opposite halves: they meet in the final.
      final fin = games.singleWhere((g) => g.label == 'Final');
      expect({fin.teamA, fin.teamB}, {'T1', 'T2'});
    });

    test('odd pools and three teams still work', () {
      for (final n in [3, 5, 7, 9]) {
        final t = tournamentOf(n, TournamentFormat.poolsSingleElim, pools: 2);
        final games = playOut(generateSchedule(t).games);
        expect(champion(t, games), 'T1', reason: '$n teams');
      }
    });
  });

  group('scheduler', () {
    for (final format in TournamentFormat.values) {
      test('${format.name}: no team twice a slot, waits for earlier games', () {
        final t = tournamentOf(9, format, fields: 3);
        final games = playOut(generateSchedule(t).games);
        final bySlot = <DateTime, List<GroupGame>>{};
        for (final g in games) {
          bySlot.putIfAbsent(g.startsAt!, () => []).add(g);
        }
        for (final slot in bySlot.values) {
          expect(slot.length, lessThanOrEqualTo(3));
          expect({for (final g in slot) g.field}.length, slot.length);
          final teams = [
            for (final g in slot) ...[?g.teamA, ?g.teamB],
          ];
          expect(teams.toSet().length, teams.length);
        }
        final byId = {for (final g in games) g.id: g};
        for (final g in games) {
          for (final s in [g.sourceA, g.sourceB]) {
            final dep = switch (s) {
              WinnerOf(:final gameId) ||
              LoserOf(:final gameId) => [byId[gameId]!],
              PoolRank(:final poolId) => games.where((p) => p.poolId == poolId),
              null => const <GroupGame>[],
            };
            for (final d in dep) {
              expect(d.startsAt!.isBefore(g.startsAt!), isTrue);
            }
          }
        }
      });
    }

    test('slots are game plus break long; warns past the ideal end', () {
      final t = tournamentOf(
        4,
        TournamentFormat.roundRobin,
        fields: 2,
        idealEndsAt: start.add(const Duration(hours: 1)),
      );
      final plan = generateSchedule(t);
      // 6 games, 2 at a time: 3 slots of 40 minutes, the last 30 long.
      expect(plan.games.map((g) => g.startsAt).toSet(), {
        start,
        start.add(const Duration(minutes: 40)),
        start.add(const Duration(minutes: 80)),
      });
      expect(plan.endsAt, start.add(const Duration(minutes: 110)));
      expect(plan.overrunMinutes(t.settings.idealEndsAt), 50);
      expect(plan.overrunMinutes(null), 0);
    });

    test('needs two teams', () {
      expect(
        () => generateSchedule(tournamentOf(1, TournamentFormat.singleElim)),
        throwsA(isA<ScheduleException>()),
      );
    });
  });

  group('standings', () {
    GroupGame game(String a, String b, int sa, int sb) => GroupGame(
      id: '$a$b',
      order: 0,
      stage: GameStage.pool,
      round: 1,
      label: '',
      poolId: 'A',
      teamA: a,
      teamB: b,
      status: GameStatus.done,
      scoreA: sa,
      scoreB: sb,
    );

    test('wins, then head to head, then point differential', () {
      final games = [
        game('a', 'b', 11, 9), // a beats b
        game('b', 'c', 11, 1),
        game('c', 'a', 11, 2),
        game('d', 'a', 0, 11),
        game('d', 'b', 0, 11),
        game('d', 'c', 0, 11),
      ];
      // a, b, c all 2-1: three-way head to head is 1-1 each, so point
      // differential decides: b +19, c +10, a +4.
      final order = standings(['a', 'b', 'c', 'd'], games);
      expect(order.map((s) => s.teamId), ['b', 'c', 'a', 'd']);
      expect(order.first.wins, 2);
      expect(order.last.losses, 3);

      // Two tied: the head-to-head winner is ahead even with a worse diff.
      final two = standings(['a', 'b'], [game('a', 'b', 11, 10)]);
      expect(two.first.teamId, 'a');
    });
  });

  group('scores', () {
    test('rejects ties and out-of-range scores', () {
      expect(scoreError(11, 9), isNull);
      expect(scoreError(11, 11), isNotNull);
      expect(scoreError(-1, 3), isNotNull);
      expect(scoreError(100, 3), isNotNull);
      expect(scoreError(null, 3), isNotNull);
    });

    test('model round-trips through maps', () {
      final t = tournamentOf(3, TournamentFormat.doubleElim);
      final back = GroupTournament.fromMap('t', t.toMap());
      expect(back.settings.format, TournamentFormat.doubleElim);
      expect(back.teams.map((x) => x.captainId), ['c1', 'c2', 'c3']);
      expect(t.toMap()['captains'], {'T1': 'c1', 'T2': 'c2', 'T3': 'c3'});
      for (final g in generateSchedule(t).games) {
        final copy = GroupGame.fromMap(g.id, g.toMap());
        expect(copy.sourceA, g.sourceA);
        expect(copy.sourceB, g.sourceB);
        expect(copy.stage, g.stage);
        expect(copy.ifNeeded, g.ifNeeded);
        expect(copy.startsAt, g.startsAt);
      }
    });
  });
}
