// Shared vectors for the tournament engine (lib/domain/tournament_engine),
// checked by packages/shared/test/tournament_engine_fixtures.test.ts
// against both TypeScript ports (tournament_engine.ts and
// group_tournaments.ts's groupEngine). See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/tournament_engine/generator.dart';
import 'package:frisbee_app/domain/tournament_engine/progress.dart';
import 'package:frisbee_app/domain/tournament_engine/standings.dart';

import 'fixture_file.dart';

List<String> _teams(int n) => [for (var i = 1; i <= n; i++) 't$i'];

Map<String, Object?> _game(GroupGame g) => {'id': g.id, ...g.toMap()};

Map<String, Object?> _plan(SchedulePlan p) => {
  'games': [for (final g in p.games) _game(g)],
  'days': [
    for (final d in p.days)
      {'startsAt': d.startsAt, 'endsAt': d.endsAt, 'games': d.games},
  ],
};

Map<String, Object?> _fill(SlotFill f) => {
  'gameId': f.gameId,
  'teamA': f.teamA,
  'teamB': f.teamB,
};

/// Plays [plan] out the same way the TypeScript test does: the earliest
/// game with both teams, the better seed winning except in every third
/// game, then the fills that result. Records each step and the outcome.
Map<String, Object?> _playThrough(
  TournamentFormat format,
  List<String> seeds,
  SchedulePlan plan,
) {
  var games = [...plan.games];
  final steps = <Map<String, Object?>>[];
  final awaiting = awaitingSeeds(games);
  for (var guard = 0; guard < 500; guard++) {
    final playable = [
      for (final g in gamesToPlay(games))
        if (g.hasTeams) g,
    ]..sort((a, b) => a.order - b.order);
    if (playable.isEmpty) break;
    final g = playable.first;
    final upset = g.order % 3 == 2;
    final aWins = (seeds.indexOf(g.teamA!) < seeds.indexOf(g.teamB!)) != upset;
    final low = (g.order * 5) % 12;
    final done = g.copyWith(
      status: GameStatus.done,
      scoreA: () => aWins ? 13 : low,
      scoreB: () => aWins ? low : 13,
    );
    games = [for (final x in games) x.id == g.id ? done : x];
    final fills = [...fillsAfter(done, games), ...bracketSeeds(games)];
    steps.add({
      'game': g.id,
      'scoreA': done.scoreA,
      'scoreB': done.scoreB,
      'fills': [for (final f in fills) _fill(f)],
    });
    for (final f in fills) {
      games = [
        for (final x in games)
          x.id == f.gameId
              ? x.copyWith(
                  teamA: () => f.teamA ?? x.teamA,
                  teamB: () => f.teamB ?? x.teamB,
                )
              : x,
      ];
    }
  }
  final pools = poolTeams(games);
  return {
    'awaitingSeedsAtStart': awaiting,
    'steps': steps,
    'poolTeams': pools,
    'poolStandings': {
      for (final p in pools.entries)
        p.key: [
          for (final s in standings(
            p.value,
            games.where((g) => g.poolId == p.key),
          ))
            s.teamId,
        ],
    },
    'gamesToPlay': [for (final g in gamesToPlay(games)) g.id],
    'skipped': [
      for (final g in games)
        if (skippedGame(g, games)) g.id,
    ],
    'laterGamesPlayed': [
      for (final g in games)
        if (laterGamesPlayed(g, games)) g.id,
    ],
    'pendingFills': [for (final f in pendingFills(games)) _fill(f)],
    'champion': championOf(format, games),
    'placements': placementsOf(format, seeds, games),
  };
}

const _start = '2026-06-06T09:00:00.000';

final _tournaments = <Map<String, Object?>>[
  for (final format in TournamentFormat.values)
    for (final n in [2, 3, 4, 5, 6, 7, 8, 12, 16])
      {
        'name': '${format.name}, $n teams',
        'teams': _teams(n),
        'settings': {
          'format': format.name,
          'poolCount': n >= 8 ? (n >= 12 ? 3 : 2) : (n >= 6 ? 2 : 1),
          'gameMinutes': 50,
          'breakMinutes': 10,
          'fields': n <= 4 ? 1 : (n <= 8 ? 2 : 4),
          'startsAt': _start,
          'laterDays': n >= 12 ? ['2026-06-07T08:30:00.000'] : <String>[],
        },
      },
  {
    'name': 'pools and placement, 10 teams in 3 pools over 3 days',
    'teams': _teams(10),
    'settings': {
      'format': 'poolsPlacement',
      'poolCount': 3,
      'gameMinutes': 40,
      'breakMinutes': 5,
      'fields': 3,
      'startsAt': '2026-07-10T17:00:00.000',
      'laterDays': ['2026-07-11T08:00:00.000', '2026-07-12T09:00:00.000'],
    },
  },
  {
    'name': 'pool count clamped to half the teams',
    'teams': _teams(5),
    'settings': {
      'format': 'poolsSingleElim',
      'poolCount': 6,
      'fields': 1,
      'startsAt': _start,
    },
  },
];

final _seasons = <Map<String, Object?>>[
  {
    'name': 'six teams, eight weeks, four in the playoffs',
    'teams': _teams(6),
    'settings': {'startsAt': '2027-06-02T18:30:00.000', 'fields': 2},
    'season': {'weeks': 8, 'playoffWeeks': 2, 'playoffTeams': 4},
  },
  {
    'name': 'odd count has byes; no playoffs',
    'teams': _teams(5),
    'settings': {'startsAt': '2027-06-02T18:30:00.000', 'fields': 2},
    'season': {'weeks': 6, 'playoffWeeks': 0, 'playoffTeams': 0},
  },
  {
    'name': 'skip dates and two games a night',
    'teams': _teams(4),
    'settings': {
      'startsAt': '2027-06-02T18:30:00.000',
      'fields': 1,
      'gameMinutes': 30,
      'breakMinutes': 5,
    },
    'season': {
      'weeks': 5,
      'playoffWeeks': 1,
      'playoffTeams': 2,
      'gamesPerNight': 2,
      'skipDates': ['2027-06-16T00:00:00.000', '2027-06-30T00:00:00.000'],
    },
  },
  {
    'name': 'eight-team playoffs in fewer weeks than rounds',
    'teams': _teams(9),
    'settings': {'startsAt': '2027-03-03T19:00:00.000', 'fields': 4},
    'season': {'weeks': 10, 'playoffWeeks': 2, 'playoffTeams': 8},
  },
  {
    'name': 'a longer season than the round robin, across a clock change',
    'teams': _teams(4),
    'settings': {'startsAt': '2027-10-06T18:00:00.000', 'fields': 2},
    'season': {'weeks': 9, 'playoffWeeks': 1, 'playoffTeams': 2},
  },
];

GroupGame _poolGame(String id, String a, String b, int sa, int sb) => GroupGame(
  id: id,
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

final _standings = <(String, List<String>, List<GroupGame>)>[
  (
    'wins first',
    ['a', 'b', 'c'],
    [
      _poolGame('1', 'a', 'b', 13, 10),
      _poolGame('2', 'b', 'c', 13, 4),
      _poolGame('3', 'a', 'c', 13, 9),
    ],
  ),
  (
    'head to head breaks a two-way tie over point differential',
    ['a', 'b', 'c', 'd'],
    [
      _poolGame('1', 'a', 'b', 10, 13),
      _poolGame('2', 'a', 'c', 13, 1),
      _poolGame('3', 'a', 'd', 13, 2),
      _poolGame('4', 'b', 'c', 9, 13),
      _poolGame('5', 'b', 'd', 13, 12),
      _poolGame('6', 'c', 'd', 5, 13),
    ],
  ),
  (
    'three-way tie: head to head even, then point differential',
    ['a', 'b', 'c'],
    [
      _poolGame('1', 'a', 'b', 13, 11),
      _poolGame('2', 'b', 'c', 13, 5),
      _poolGame('3', 'c', 'a', 13, 12),
    ],
  ),
  (
    'then points scored, then seed order',
    ['a', 'b', 'c', 'd'],
    [
      _poolGame('1', 'a', 'b', 11, 13),
      _poolGame('2', 'b', 'c', 9, 11),
      _poolGame('3', 'c', 'a', 13, 15),
      _poolGame('4', 'd', 'a', 5, 13),
    ],
  ),
  (
    'unplayed and outside games are ignored',
    ['a', 'b', 'c'],
    [
      _poolGame('1', 'a', 'b', 4, 13),
      _poolGame('2', 'a', 'x', 13, 0),
      _poolGame('3', 'b', 'c', 13, 0).copyWith(status: GameStatus.reported),
    ],
  ),
];

void main() {
  test('schedules and play-throughs (tournament_engine/schedules.json)', () {
    checkFixture(
      'tournament_engine/schedules.json',
      'scheduleFor for each case, then the game played out: the earliest '
          'game with both teams, the better seed (lower index in teams) '
          'winning 13 to (order * 5) % 12 except when order % 3 == 2; after '
          'each game the fills are fillsAfter(game) then bracketSeeds, '
          'applied in order (a null side keeps its team).',
      [
        for (final c in _tournaments)
          () {
            final settings = TournamentSettings.fromMap(
              c['settings']! as Map<String, dynamic>,
            );
            final teams = (c['teams']! as List).cast<String>();
            final plan = scheduleFor(teams, settings);
            return {
              ...c,
              'plan': _plan(plan),
              'playThrough': _playThrough(settings.format, teams, plan),
            };
          }(),
      ],
    );
  });

  test('league seasons (tournament_engine/seasons.json)', () {
    checkFixture(
      'tournament_engine/seasons.json',
      'seasonNights and seasonFor, then byesIn for each week and the season '
          'played out as in schedules.json (format singleElim for the '
          'champion).',
      [
        for (final c in _seasons)
          () {
            final settings = TournamentSettings.fromMap(
              c['settings']! as Map<String, dynamic>,
            );
            final season = LeagueSeason.fromMap(c['season'])!;
            final teams = (c['teams']! as List).cast<String>();
            final plan = seasonFor(teams, settings, season);
            return {
              ...c,
              'nights': seasonNights(settings, season),
              'plan': _plan(plan),
              'byes': [
                for (var w = 1; w <= season.weeks; w++)
                  byesIn(teams, plan.games, w),
              ],
              'playThrough': _playThrough(
                TournamentFormat.singleElim,
                teams,
                plan,
              ),
            };
          }(),
      ],
    );
  });

  test('schedule errors (tournament_engine/schedule_errors.json)', () {
    String? error(void Function() f) {
      try {
        f();
        return null;
      } on ScheduleException catch (e) {
        return e.message;
      }
    }

    final s = TournamentSettings(startsAt: date(_start));
    checkFixture(
      'tournament_engine/schedule_errors.json',
      'The ScheduleException message for each case.',
      [
        {
          'name': 'one team',
          'kind': 'tournament',
          'teams': ['t1'],
          'error': error(() => scheduleFor(['t1'], s)),
        },
        {
          'name': 'league with one team',
          'kind': 'season',
          'teams': ['t1'],
          'season': {'weeks': 4, 'playoffWeeks': 1, 'playoffTeams': 2},
          'error': error(
            () => seasonFor(['t1'], s, const LeagueSeason(weeks: 4)),
          ),
        },
        {
          'name': 'league with only playoff weeks',
          'kind': 'season',
          'teams': _teams(4),
          'season': {'weeks': 2, 'playoffWeeks': 2, 'playoffTeams': 2},
          'error': error(
            () => seasonFor(
              _teams(4),
              s,
              const LeagueSeason(weeks: 2, playoffWeeks: 2, playoffTeams: 2),
            ),
          ),
        },
      ],
    );
  });

  test('standings (tournament_engine/standings.json)', () {
    checkFixture(
      'tournament_engine/standings.json',
      'standings(teamIds, games): each row in rank order.',
      [
        for (final (name, teams, games) in _standings)
          {
            'name': name,
            'teamIds': teams,
            'games': [for (final g in games) _game(g)],
            'expected': [
              for (final s in standings(teams, games))
                {
                  'teamId': s.teamId,
                  'wins': s.wins,
                  'losses': s.losses,
                  'pointsFor': s.pointsFor,
                  'pointsAgainst': s.pointsAgainst,
                },
            ],
          },
      ],
    );
  });

  test('helpers (tournament_engine/helpers.json)', () {
    checkFixture(
      'tournament_engine/helpers.json',
      'roundRobin, seedOrder, suggestedPools, suggestedFormat, ordinal, '
          'gamesPerDay, poolName and scoreError.',
      [
        {
          'name': 'roundRobin',
          'cases': [
            for (var n = 0; n <= 9; n++)
              {
                'teams': _teams(n),
                'rounds': [
                  for (final r in roundRobin(_teams(n)))
                    [
                      for (final (a, b) in r) [a, b],
                    ],
                ],
              },
          ],
        },
        {
          'name': 'seedOrder',
          'cases': [
            for (final size in [1, 2, 4, 8, 16, 32])
              {'size': size, 'order': seedOrder(size)},
          ],
        },
        {
          'name': 'suggestedPools and suggestedFormat',
          'cases': [
            for (var n = 2; n <= 64; n++)
              {
                'teams': n,
                'pools': suggestedPools(n),
                'format': suggestedFormat(n).name,
              },
          ],
        },
        {
          'name': 'ordinal',
          'cases': [
            for (final n in [
              for (var i = 1; i <= 25; i++) i,
              100,
              101,
              102,
              103,
              104,
              111,
              112,
              113,
              121,
              1011,
            ])
              {'n': n, 'text': ordinal(n)},
          ],
        },
        {
          'name': 'gamesPerDay',
          'cases': [
            for (final (total, days) in [
              (0, 1),
              (7, 1),
              (7, 2),
              (7, 3),
              (12, 3),
              (2, 3),
            ])
              {
                'total': total,
                'days': days,
                'perDay': gamesPerDay(total, days),
              },
          ],
        },
        {
          'name': 'poolName',
          'cases': [
            for (var i = 0; i < 6; i++) {'index': i, 'name': poolName(i)},
          ],
        },
        {
          'name': 'scoreError',
          'cases': [
            for (final (a, b, max) in [
              (null, 3, null),
              (3, null, null),
              (13, 11, null),
              (0, 1, null),
              (-1, 4, null),
              (100, 4, null),
              (99, 98, null),
              (7, 7, null),
              (16, 14, 15),
              (15, 14, 15),
            ])
              {
                'a': a,
                'b': b,
                'max': max,
                'error': max == null
                    ? scoreError(a, b)
                    : scoreError(a, b, max: max),
              },
          ],
        },
      ],
    );
  });
}
