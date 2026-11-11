import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/tournament_engine/generator.dart';
import 'package:frisbee_app/domain/tournament_engine/progress.dart';

void main() {
  // Wednesday 2 June 2027, 6:30pm.
  final firstNight = DateTime(2027, 6, 2, 18, 30);
  TournamentSettings settings({int fields = 2}) => TournamentSettings(
    startsAt: firstNight,
    playersOnField: 4,
    fields: fields,
    gameMinutes: 40,
    breakMinutes: 10,
  );
  List<String> teams(int n) => [for (var i = 1; i <= n; i++) 't$i'];
  const noPlayoffs = LeagueSeason(weeks: 5, playoffWeeks: 0, playoffTeams: 0);

  Set<String> pair(GroupGame g) => {g.teamA!, g.teamB!};
  List<GroupGame> pool(SchedulePlan p) => [
    for (final g in p.games)
      if (g.stage == GameStage.pool) g,
  ];

  group('seasonNights', () {
    test('are a week apart at the same time', () {
      final nights = seasonNights(settings(), noPlayoffs);
      expect(nights, hasLength(5));
      expect(nights.first, firstNight);
      expect(nights[1], DateTime(2027, 6, 9, 18, 30));
      expect(nights.last, DateTime(2027, 6, 30, 18, 30));
    });

    test('skip dates push the season out a week', () {
      final nights = seasonNights(
        settings(),
        noPlayoffs.copyWith(skipDates: [DateTime(2027, 6, 16)]),
      );
      expect(nights, hasLength(5));
      expect(nights.contains(DateTime(2027, 6, 16, 18, 30)), isFalse);
      expect(nights[2], DateTime(2027, 6, 23, 18, 30));
      expect(nights.last, DateTime(2027, 7, 7, 18, 30));
    });

    test('keep the hour across a clock change', () {
      final s = TournamentSettings(startsAt: DateTime(2027, 3, 10, 19));
      final nights = seasonNights(s, noPlayoffs);
      expect(nights.map((n) => n.hour), everyElement(19));
    });
  });

  group('regular season', () {
    test('every team meets every other once in a full round robin', () {
      final plan = seasonFor(teams(6), settings(), noPlayoffs);
      final pairs = pool(plan).map(pair).toList();
      expect(pairs, hasLength(15));
      expect({
        for (final p in pairs) ([...p]..sort()).join('-'),
      }, hasLength(15));
      expect(plan.days, hasLength(5));
      expect(plan.days.map((d) => d.games), everyElement(3));
    });

    test('games are pool A, round = week, and labelled by week', () {
      final plan = seasonFor(teams(4), settings(), noPlayoffs);
      for (final g in plan.games) {
        expect(g.stage, GameStage.pool);
        expect(g.poolId, 'A');
        expect(g.label, 'Week ${g.round}');
      }
      expect(plan.games.map((g) => g.round).toSet(), {1, 2, 3, 4, 5});
    });

    test('an odd number of teams gives each team one bye per cycle', () {
      final all = teams(5);
      final plan = seasonFor(all, settings(), noPlayoffs);
      final byes = [
        for (var week = 1; week <= 5; week++) byesIn(all, plan.games, week),
      ];
      expect(byes.map((b) => b.length), everyElement(1));
      expect({for (final b in byes) b.single}, hasLength(5));
    });

    test('no team plays twice in a slot and fields cap each slot', () {
      for (final n in [4, 5, 6, 8, 9]) {
        final plan = seasonFor(
          teams(n),
          settings(),
          const LeagueSeason(weeks: 6, playoffWeeks: 0, playoffTeams: 0),
        );
        final bySlot = <DateTime, List<GroupGame>>{};
        for (final g in plan.games) {
          bySlot.putIfAbsent(g.startsAt!, () => []).add(g);
        }
        for (final slot in bySlot.values) {
          expect(slot.length, lessThanOrEqualTo(2), reason: '$n teams');
          final playing = [
            for (final g in slot) ...[g.teamA, g.teamB],
          ];
          expect(playing.toSet().length, playing.length, reason: '$n teams');
          expect(slot.map((g) => g.field).toSet(), hasLength(slot.length));
        }
      }
    });

    test('games start at the night time and step by game plus break', () {
      final plan = seasonFor(teams(8), settings(), noPlayoffs);
      final firstWeek = plan.games.where((g) => g.round == 1).toList();
      // Four games on two fields: two slots, 50 minutes apart.
      expect(firstWeek.map((g) => g.startsAt).toSet(), {
        firstNight,
        firstNight.add(const Duration(minutes: 50)),
      });
      expect(
        plan.days.first.endsAt,
        firstNight.add(const Duration(minutes: 90)),
      );
    });

    test('the round robin repeats when there are more weeks than rounds', () {
      final plan = seasonFor(
        teams(4),
        settings(),
        const LeagueSeason(weeks: 8, playoffWeeks: 0, playoffTeams: 0),
      );
      expect(plan.games, hasLength(16));
      final byRound = {
        for (var w = 1; w <= 8; w++)
          w: {
            for (final g in plan.games.where((g) => g.round == w)) ...pair(g),
          },
      };
      expect(byRound[1], byRound[4]);
    });

    test('a short season ends before everyone has met', () {
      final plan = seasonFor(
        teams(6),
        settings(),
        const LeagueSeason(weeks: 3, playoffWeeks: 0, playoffTeams: 0),
      );
      expect(plan.games, hasLength(9));
    });

    test('two games a night plays two rounds each night', () {
      final plan = seasonFor(
        teams(4),
        settings(),
        const LeagueSeason(
          weeks: 2,
          playoffWeeks: 0,
          playoffTeams: 0,
          gamesPerNight: 2,
        ),
      );
      expect(plan.games, hasLength(8));
      expect(plan.days.map((d) => d.games), [4, 4]);
      // Over the two nights each pair met once, then again.
      final week1 = [
        for (final g in plan.games.where((g) => g.round == 1)) pair(g),
      ];
      expect(week1.toSet(), hasLength(4));
    });

    test('skipped weeks have no games', () {
      final plan = seasonFor(
        teams(4),
        settings(),
        noPlayoffs.copyWith(skipDates: [DateTime(2027, 6, 16)]),
      );
      final days = plan.games.map((g) => g.startsAt!.day).toSet();
      expect(days.contains(16), isFalse);
      expect(plan.days.map((d) => d.startsAt.day), [2, 9, 23, 30, 7]);
    });
  });

  group('playoffs', () {
    const season = LeagueSeason(weeks: 5, playoffWeeks: 1, playoffTeams: 4);

    List<GroupGame> bracket(SchedulePlan p) => [
      for (final g in p.games)
        if (g.stage != GameStage.pool) g,
    ];

    test(
      'the top four play a semifinal round and a final on the last night',
      () {
        final plan = seasonFor(teams(6), settings(), season);
        expect(plan.days, hasLength(5));
        final games = bracket(plan);
        expect(games.map((g) => g.label), ['Semifinal', 'Semifinal', 'Final']);
        final lastNight = DateTime(2027, 6, 30, 18, 30);
        expect(
          games.map(
            (g) =>
                DateTime(g.startsAt!.year, g.startsAt!.month, g.startsAt!.day),
          ),
          everyElement(DateTime(2027, 6, 30)),
        );
        expect(games.first.startsAt, lastNight);
        // The final waits for the semifinals.
        expect(games.last.startsAt, lastNight.add(const Duration(minutes: 50)));
        // Regular season is the first four weeks.
        expect(pool(plan).map((g) => g.round).toSet(), {1, 2, 3, 4});
      },
    );

    test('playoff slots fill from the final standings', () {
      // Four teams over four weeks: everyone has met, so the table is strict.
      final all = teams(4);
      final plan = seasonFor(all, settings(), season);
      var games = plan.games;
      expect(bracketSeeds(games), isEmpty);
      // Lower-numbered teams always win, so the table is t1..t4.
      games = [
        for (final g in games)
          if (g.stage == GameStage.pool)
            g.copyWith(
              status: GameStatus.done,
              scoreA: () =>
                  int.parse(g.teamA!.substring(1)) <
                      int.parse(g.teamB!.substring(1))
                  ? 15
                  : 10,
              scoreB: () =>
                  int.parse(g.teamA!.substring(1)) <
                      int.parse(g.teamB!.substring(1))
                  ? 10
                  : 15,
            )
          else
            g,
      ];
      final fills = bracketSeeds(games);
      expect(fills, hasLength(2));
      expect(
        {
          for (final f in fills) {f.teamA, f.teamB},
        },
        {
          {'t1', 't4'},
          {'t2', 't3'},
        },
      );
    });

    test('two playoff weeks spread the rounds over two nights', () {
      final plan = seasonFor(
        teams(6),
        settings(),
        season.copyWith(playoffWeeks: 2),
      );
      final games = bracket(plan);
      final semis = games.where((g) => g.label == 'Semifinal');
      final grand = games.singleWhere((g) => g.label == 'Final');
      expect(semis.map((g) => g.startsAt!.day).toSet(), {23});
      expect(grand.startsAt!.day, 30);
      expect(pool(plan).map((g) => g.round).toSet(), {1, 2, 3});
    });

    test('eight teams in one playoff week still order their rounds', () {
      final plan = seasonFor(
        teams(10),
        settings(),
        season.copyWith(playoffTeams: 8),
      );
      final games = bracket(plan);
      expect(games, hasLength(7));
      expect(games.map((g) => g.startsAt!.day).toSet(), {30});
      GroupGame byLabel(String l) => games.firstWhere((g) => g.label == l);
      final quarters = games.where((g) => g.label == 'Quarterfinal');
      final semis = games.where((g) => g.label == 'Semifinal');
      for (final s in semis) {
        for (final q in quarters) {
          expect(s.startsAt!.isAfter(q.startsAt!), isTrue);
        }
        expect(byLabel('Final').startsAt!.isAfter(s.startsAt!), isTrue);
      }
    });

    test('a bracket bigger than the league shrinks to the league', () {
      final plan = seasonFor(
        teams(3),
        settings(),
        season.copyWith(playoffTeams: 8),
      );
      // Three teams: seed 1 has a bye, 2 v 3 then the final.
      expect(bracket(plan).map((g) => g.label), ['Semifinal', 'Final']);
    });

    test('no playoffs means a season of pool games only', () {
      final plan = seasonFor(teams(4), settings(), noPlayoffs);
      expect(bracket(plan), isEmpty);
    });
  });

  group('errors', () {
    test('a league needs two teams', () {
      expect(
        () => seasonFor(teams(1), settings(), noPlayoffs),
        throwsA(isA<ScheduleException>()),
      );
    });

    test('the playoffs cannot take every week', () {
      expect(
        () => seasonFor(
          teams(4),
          settings(),
          const LeagueSeason(weeks: 2, playoffWeeks: 2, playoffTeams: 4),
        ),
        throwsA(isA<ScheduleException>()),
      );
    });
  });

  group('planFor', () {
    HostedTournament hosted({required HostedKind kind, LeagueSeason? season}) =>
        HostedTournament(
          id: 'x1',
          hostId: 'h1',
          hostName: 'Host',
          name: 'Thursday Night',
          startsOn: firstNight,
          kind: kind,
          season: season,
        );
    TournamentDivision division() => TournamentDivision(
      id: 'd1',
      division: Division.mixed,
      level: CompetitionLevel.league,
      settings: settings().copyWith(format: TournamentFormat.roundRobin),
    );

    test('a league gets its weekly season', () {
      final plan = planFor(
        hosted(kind: HostedKind.league, season: noPlayoffs),
        division(),
        teams(4),
      );
      expect(plan.games.first.label, 'Week 1');
      expect(plan.days, hasLength(5));
    });

    test('a tournament gets the usual schedule', () {
      final plan = planFor(
        hosted(kind: HostedKind.tournament),
        division(),
        teams(4),
      );
      expect(plan.games.first.label, 'Round 1');
      expect(plan.days, hasLength(1));
    });
  });
}
