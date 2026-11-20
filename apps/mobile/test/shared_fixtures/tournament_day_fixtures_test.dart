// Shared vectors for a team's tournament-day card (TournamentDay in
// lib/domain/tournament_engine/tournament_day.dart), checked by
// packages/shared/test/tournament_day_fixtures.test.ts against
// tournamentDay in tournament_day.ts. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/tournament_engine/tournament_day.dart';

import 'fixture_file.dart';

DateTime _at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 11, day, hour, minute);

GroupGame _g(
  String id,
  int order,
  String? a,
  String? b, {
  DateTime? at,
  int? sa,
  int? sb,
  String? reportedBy,
  int field = 1,
  GameStage stage = GameStage.pool,
  String? pool = 'A',
}) => GroupGame(
  id: id,
  order: order,
  stage: stage,
  round: 1,
  label: 'Game $id',
  poolId: stage == GameStage.pool ? pool : null,
  field: field,
  startsAt: at,
  teamA: a,
  teamB: b,
  status: sa != null
      ? GameStatus.done
      : reportedBy != null
      ? GameStatus.reported
      : GameStatus.scheduled,
  scoreA: sa,
  scoreB: sb,
  report: reportedBy == null
      ? null
      : ScoreReport(scoreA: 13, scoreB: 9, byTeamId: reportedBy),
);

/// A pool of four on Nov 21: us, b, c, d; then a final.
List<GroupGame> _pool({
  bool firstDone = false,
  bool secondDone = false,
  String? reportedBy,
}) => [
  _g(
    '1',
    0,
    'us',
    'b',
    at: _at(21, 9),
    sa: firstDone ? 13 : null,
    sb: firstDone ? 8 : null,
  ),
  _g('2', 1, 'c', 'd', at: _at(21, 9), field: 2, sa: 13, sb: 11),
  _g(
    '3',
    2,
    'c',
    'us',
    at: _at(21, 10, 30),
    field: 3,
    sa: secondDone ? 13 : null,
    sb: secondDone ? 10 : null,
    reportedBy: secondDone ? null : reportedBy,
  ),
  _g('4', 3, 'b', 'd', at: _at(21, 10, 30), field: 4),
  _g('5', 4, 'us', 'd', at: _at(21, 12)),
  _g('6', 5, null, null, at: _at(22, 9), stage: GameStage.winners),
];

final _cases = <Map<String, Object?>>[
  {
    'name': 'the morning of: first game next, nothing due yet',
    'games': _pool(),
    'now': _at(21, 7),
    'live': false,
  },
  {
    'name': 'after the first win: record, pool place, the second game next',
    'games': _pool(firstDone: true),
    'now': _at(21, 10),
    'live': true,
  },
  {
    'name': 'a started game with no score is due for a report',
    'games': _pool(firstDone: true),
    'now': _at(21, 10, 45),
    'live': true,
  },
  {
    'name': 'the other team reported: confirm',
    'games': _pool(firstDone: true, reportedBy: 'c'),
    'now': _at(21, 11),
    'live': true,
  },
  {
    'name': 'we reported: awaiting the other captain',
    'games': _pool(firstDone: true, reportedBy: 'us'),
    'now': _at(21, 11),
    'live': true,
  },
  {
    'name': 'after a loss: last result is the loss',
    'games': _pool(firstDone: true, secondDone: true),
    'now': _at(21, 11, 30),
    'live': true,
  },
  {
    'name': 'the evening before: tomorrow',
    'games': _pool(),
    'now': _at(20, 18),
    'live': false,
  },
  {
    'name': 'the afternoon before: nothing yet',
    'games': _pool(),
    'now': _at(20, 15),
    'live': false,
  },
  {
    'name': 'two days before: nothing',
    'games': _pool(),
    'now': _at(19, 20),
    'live': false,
  },
  {
    'name': 'a live event with no times still shows',
    'games': [_g('1', 0, 'us', 'b'), _g('2', 1, 'b', 'c')],
    'now': _at(21, 9),
    'live': true,
  },
  {
    'name': 'a team not in the games has no card',
    'games': _pool(),
    'now': _at(21, 9),
    'live': true,
  },
];

String? _id(TeamGame? g) => g?.game.id;

void main() {
  test('tournament day (tournament_day/day.json)', () {
    checkFixture(
      'tournament_day/day.json',
      "TournamentDay.of(games, team, now, live): a team's tournament-day "
          'card. Null (no card) unless the team plays today, the event is '
          'live with a game left, or it is 17:00 or later the day before its '
          'next game. `next` is its earliest game still to play (by start, '
          'then order), `last` its latest final; `pool` and `place` come '
          "from the pool's standings (`place` only once it has a pool "
          'result); `due` is the earliest of its games '
          'with both teams that is reported (confirm, or awaiting when it '
          'reported) or has started unreported (report).',
      [
        for (final c in _cases)
          () {
            final team = c['name'] == 'a team not in the games has no card'
                ? 'zz'
                : 'us';
            final d = TournamentDay.of(
              c['games']! as List<GroupGame>,
              team,
              now: c['now']! as DateTime,
              live: c['live']! as bool,
            );
            return {
              'name': c['name'],
              'team': team,
              'games': [
                for (final g in c['games']! as List<GroupGame>)
                  {'id': g.id, ...g.toMap()},
              ],
              'now': c['now'],
              'live': c['live'],
              'day': d == null
                  ? null
                  : {
                      'phase': d.phase,
                      'next': _id(d.next),
                      'opponent': d.next?.opponent,
                      'last': _id(d.last),
                      'lastWon': d.last?.won,
                      'lastScore': d.last == null
                          ? null
                          : [d.last!.scoreFor, d.last!.scoreAgainst],
                      'wins': d.wins,
                      'losses': d.losses,
                      'pool': d.pool,
                      'place': d.poolPlace,
                      'poolSize': d.poolSize,
                      'due': d.scoreDue?.id,
                      'dueKind': d.scoreDueKind,
                    },
            };
          }(),
      ],
    );
  });
}
