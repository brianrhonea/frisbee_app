// A league's schedule by week (F30), mirroring packages/shared's
// test/league_weeks.test.ts case for case.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/tournament_engine/league_weeks.dart';

void main() {
  GroupGame game(
    String id,
    DateTime? startsAt, [
    GameStage stage = GameStage.pool,
  ]) => GroupGame(
    id: id,
    order: 0,
    stage: stage,
    round: 1,
    label: stage.label,
    startsAt: startsAt,
  );

  // Tuesdays in May 2027; two games a night on the 4th (two rounds).
  final games = [
    game('a', DateTime(2027, 5, 4, 18)),
    game('b', DateTime(2027, 5, 4, 19)),
    game('c', DateTime(2027, 5, 11, 18)),
    // The 18th is skipped.
    game('d', DateTime(2027, 5, 25, 18)),
    game('e', DateTime(2027, 6, 1, 18), GameStage.winners),
    game('f', DateTime(2027, 6, 1, 19), GameStage.winners),
  ];

  group('leagueWeeks', () {
    test('groups games by night, numbering the nights', () {
      final weeks = leagueWeeks(games);
      expect(
        [
          for (final w in weeks)
            [w.day, w.number, w.games.map((g) => g.id).toList()],
        ],
        [
          [
            DateTime(2027, 5, 4),
            1,
            ['a', 'b'],
          ],
          [
            DateTime(2027, 5, 11),
            2,
            ['c'],
          ],
          [
            DateTime(2027, 5, 25),
            3,
            ['d'],
          ],
          [
            DateTime(2027, 6, 1),
            4,
            ['e', 'f'],
          ],
        ],
      );
    });

    test('a night of bracket games is the playoffs', () {
      expect(leagueWeeks(games).map((w) => w.label), [
        'Week 1',
        'Week 2',
        'Week 3',
        'Week 4 · Playoffs',
      ]);
      final weeks = leagueWeeks(games);
      expect(weeks[2].labelOf(leagueNights(weeks)), 'Week 3 of 4');
      expect(weeks[3].labelOf(4), 'Week 4 of 4 · Playoffs');
    });

    test('games with no start come last', () {
      final weeks = leagueWeeks([game('x', null), games.first]);
      expect(weeks.map((w) => w.day), [DateTime(2027, 5, 4), null]);
      expect(weeks[1].label, 'Not scheduled yet');
      expect(leagueNights(weeks), 1);
    });

    test('no games, no weeks', () {
      expect(leagueWeeks(const []), isEmpty);
    });
  });

  group('currentWeekIndex', () {
    final weeks = leagueWeeks(games);
    test('before the season, the first night', () {
      expect(currentWeekIndex(weeks, DateTime(2027, 4, 1)), 0);
    });
    test('on game night, tonight', () {
      expect(currentWeekIndex(weeks, DateTime(2027, 5, 11, 21)), 1);
    });
    test('between nights, the next one', () {
      expect(currentWeekIndex(weeks, DateTime(2027, 5, 12)), 2);
    });
    test('after the season, the last night', () {
      expect(currentWeekIndex(weeks, DateTime(2027, 7, 1)), 3);
    });
    test('with no weeks, 0', () {
      expect(currentWeekIndex(const [], DateTime(2027, 5, 11)), 0);
    });
  });
}
