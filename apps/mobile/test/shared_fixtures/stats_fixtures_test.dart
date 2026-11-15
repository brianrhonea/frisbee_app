// Shared vectors for game stats (lib/domain/models/stats.dart), checked by
// packages/shared/test/stats_fixtures.test.ts against stats.ts. See
// fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/stats.dart';
import 'package:frisbee_app/domain/tournament_engine/seeded_random.dart';

import 'fixture_file.dart';

final _roster = [
  for (var i = 1; i <= 12; i++) 'p${i.toString().padLeft(2, '0')}',
];

/// A game played out from [seed]: lines rotate through the roster, and
/// each point is a few passes, turnovers and blocks until someone scores
/// (or, for the last point when [unfinished], until it stops).
StatsGame _simulated(
  String id,
  int seed, {
  int gameTo = 11,
  bool unfinished = false,
}) {
  final r = SeededRandom(seed);
  String any(List<String> from) => from[r.nextInt(from.length)];
  final points = <StatPoint>[];
  var startOn = Side.values[r.nextInt(2)];
  var us = 0, them = 0;
  for (var n = 0; us < gameTo && them < gameTo; n++) {
    final line = [for (var k = 0; k < 7; k++) _roster[(n * 3 + k) % 12]];
    final field = [...line];
    final actions = <StatAction>[];
    var side = startOn;
    String? holder;
    PointResult? result;
    if (side == Side.defense) {
      actions.add(
        StatAction(
          StatKind.pull,
          playerId: any(field),
          hangTimeMs: r.nextBool() ? 4000 + r.nextInt(3000) : null,
          outOfBounds: r.nextInt(5) == 0,
        ),
      );
    }
    for (var step = 0; step < 40 && result == null; step++) {
      if (unfinished && us + them == gameTo + 3 && step == 6) break;
      final roll = r.nextInt(100);
      if (side == Side.offense) {
        if (holder == null) {
          holder = any(field);
          actions.add(StatAction(StatKind.pickup, playerId: holder));
        } else if (roll < 55) {
          final to = any([
            for (final p in field)
              if (p != holder) p,
          ]);
          actions.add(
            StatAction(StatKind.catch_, playerId: to, throwerId: holder),
          );
          holder = to;
        } else if (roll < 70) {
          final to = any([
            for (final p in field)
              if (p != holder) p,
          ]);
          actions.add(
            StatAction(StatKind.goal, playerId: to, throwerId: holder),
          );
          result = PointResult.weScored;
        } else if (roll < 80) {
          actions.add(StatAction(StatKind.throwaway, playerId: holder));
          holder = null;
          side = Side.defense;
        } else if (roll < 87) {
          final to = any([
            for (final p in field)
              if (p != holder) p,
          ]);
          actions.add(
            StatAction(StatKind.drop, playerId: to, throwerId: holder),
          );
          holder = null;
          side = Side.defense;
        } else if (roll < 92) {
          // The holder is hurt: a sub comes on and takes the disc.
          final bench = [
            for (final p in _roster)
              if (!field.contains(p)) p,
          ];
          final sub = any(bench);
          actions.add(
            StatAction(StatKind.sub, playerId: sub, subOutId: holder),
          );
          field[field.indexOf(holder)] = sub;
          holder = sub;
        } else {
          actions.add(StatAction(StatKind.beat, playerId: any(field)));
        }
      } else {
        if (roll < 25) {
          actions.add(StatAction(StatKind.breakup, playerId: any(field)));
          side = Side.offense;
        } else if (roll < 35) {
          actions.add(StatAction(StatKind.handBlock, playerId: any(field)));
          side = Side.offense;
        } else if (roll < 55) {
          actions.add(const StatAction(StatKind.theirTurnover));
          side = Side.offense;
        } else if (roll < 70) {
          actions.add(StatAction(StatKind.beat, playerId: any(field)));
        } else if (roll < 75) {
          final bench = [
            for (final p in _roster)
              if (!field.contains(p)) p,
          ];
          final out = any(field);
          final sub = any(bench);
          actions.add(StatAction(StatKind.sub, playerId: sub, subOutId: out));
          field[field.indexOf(out)] = sub;
        } else {
          result = PointResult.theyScored;
        }
      }
    }
    if (result == null) {
      if (!unfinished) result = PointResult.theyScored;
    }
    points.add(
      StatPoint(
        line: line,
        startedOn: startOn,
        actions: actions,
        result: result,
      ),
    );
    if (result == null) break;
    if (result == PointResult.weScored) {
      us++;
      startOn = Side.defense;
    } else {
      them++;
      startOn = Side.offense;
    }
  }
  return StatsGame(
    id: id,
    opponent: 'Opponent $seed',
    date: DateTime(2026, 5, 1 + seed % 27, 10),
    gameTo: gameTo,
    points: points,
    timeoutsPerHalf: 2,
    timeouts: [
      const GameTimeout(ours: true, half: 1, point: 1, action: 2),
      const GameTimeout(ours: false, half: 1, point: 3),
      const GameTimeout(ours: true, half: 2, point: 9, action: 1),
    ],
  );
}

/// Points that test one rule each.
final _edgePoints = <(String, StatPoint)>[
  (
    'opponent score with no line',
    const StatPoint(
      line: [],
      startedOn: Side.defense,
      result: PointResult.theyScored,
    ),
  ),
  (
    'a sub for someone not on the field changes nothing on it',
    const StatPoint(
      line: ['a', 'b'],
      startedOn: Side.offense,
      actions: [
        StatAction(StatKind.pickup, playerId: 'a'),
        StatAction(StatKind.sub, playerId: 'z', subOutId: 'x'),
        StatAction(StatKind.sub, subOutId: 'b'),
      ],
    ),
  ),
  (
    'a sub for a player who isn\'t holding keeps the holder',
    const StatPoint(
      line: ['a', 'b', 'c'],
      startedOn: Side.offense,
      actions: [
        StatAction(StatKind.pickup, playerId: 'a'),
        StatAction(StatKind.sub, playerId: 'd', subOutId: 'b'),
        StatAction(StatKind.catch_, playerId: 'c', throwerId: 'a'),
        StatAction(StatKind.sub, playerId: 'e', subOutId: 'c'),
      ],
    ),
  ),
  (
    'goals and pulls with no player or thrower',
    const StatPoint(
      line: ['a', 'b'],
      startedOn: Side.defense,
      actions: [
        StatAction(StatKind.pull, hangTimeMs: 5000),
        StatAction(StatKind.theirTurnover),
        StatAction(StatKind.pickup, playerId: 'b'),
        StatAction(StatKind.goal, playerId: 'a'),
      ],
      result: PointResult.weScored,
    ),
  ),
  (
    'block, then turnover on a lost point goes negative',
    const StatPoint(
      line: ['a', 'b', 'c'],
      startedOn: Side.defense,
      actions: [
        StatAction(StatKind.pull, playerId: 'c', outOfBounds: true),
        StatAction(StatKind.handBlock, playerId: 'a'),
        StatAction(StatKind.pickup, playerId: 'b'),
        StatAction(StatKind.throwaway, playerId: 'b'),
        StatAction(StatKind.breakup, playerId: 'b'),
        StatAction(StatKind.pickup, playerId: 'a'),
        StatAction(StatKind.drop, playerId: 'c', throwerId: 'a'),
      ],
      result: PointResult.theyScored,
    ),
  ),
];

Map<String, Object?> _point(StatPoint p) => {
  'point': p.toMap(),
  'onField': p.onField,
  'played': p.played.toList(),
  'side': p.side,
  'holder': p.holder,
  'hasPull': p.hasPull,
};

Map<String, Object?> _gameState(StatsGame g) => {
  'ourScore': g.ourScore,
  'theirScore': g.theirScore,
  'reachedGamePoint': g.reachedGamePoint,
  'over': g.over,
  'halfAt': g.halfAt,
  'halftimePoint': g.halftimePoint,
  'half': g.half,
  'timeoutsLeftOurs': g.timeoutsLeft(ours: true),
  'timeoutsLeftTheirs': g.timeoutsLeft(ours: false),
  'won': g.won,
};

Map<String, Object?> _sheet(StatSheet s) => {
  'players': [
    for (final p in s.players.values)
      {
        'playerId': p.playerId,
        'pointsO': p.pointsO,
        'pointsD': p.pointsD,
        'pickups': p.pickups,
        'catches': p.catches,
        'goals': p.goals,
        'assists': p.assists,
        'completions': p.completions,
        'throwaways': p.throwaways,
        'drops': p.drops,
        'handBlocks': p.handBlocks,
        'breakups': p.breakups,
        'beats': p.beats,
        'pulls': p.pulls,
        'pullsOutOfBounds': p.pullsOutOfBounds,
        'finishedO': p.finishedO,
        'holds': p.holds,
        'finishedD': p.finishedD,
        'breaks': p.breaks,
        'pointsPlayed': p.pointsPlayed,
        'oEfficiency': p.oEfficiency,
        'dEfficiency': p.dEfficiency,
        'oRating': p.oRating,
        'dRating': p.dRating,
        'touches': p.touches,
        'throws': p.throws,
        'catchPct': p.catchPct,
        'completionPct': p.completionPct,
        'avgHangTime': p.avgHangTime,
        'plusMinus': p.plusMinus,
      },
  ],
  'team': {
    'oPoints': s.team.oPoints,
    'holds': s.team.holds,
    'dPoints': s.team.dPoints,
    'breaks': s.team.breaks,
    'oEfficiency': s.team.oEfficiency,
    'breakRate': s.team.breakRate,
  },
  'ranked': [for (final p in s.ranked) p.playerId],
};

void main() {
  final games = [
    _simulated('g1', 1),
    _simulated('g2', 2, gameTo: 15),
    _simulated('g3', 3, gameTo: 7),
    _simulated('g4', 4, unfinished: true),
    _simulated('g5', 5, gameTo: 13),
  ];

  test('points (stats/points.json)', () {
    checkFixture(
      'stats/points.json',
      'For each point (StatPoint.toMap): onField, played (in order), side, '
          'holder and hasPull.',
      [
        for (final (name, p) in _edgePoints) {'name': name, ..._point(p)},
        for (final g in games)
          for (final (i, p) in g.points.indexed)
            {'name': '${g.id} point ${i + 1}', ..._point(p)},
      ],
    );
  });

  test('games and stat sheets (stats/games.json)', () {
    final edge = StatsGame(
      id: 'edge',
      opponent: 'Edge',
      date: DateTime(2026, 4, 1),
      gameTo: 3,
      points: [for (final (_, p) in _edgePoints) p],
    );
    final finishedTied = StatsGame(
      id: 'tied',
      opponent: 'Tied',
      date: DateTime(2026, 4, 2),
      gameTo: 15,
      finished: true,
      timeoutsPerHalf: 1,
      timeouts: const [
        GameTimeout(ours: true, half: 1, point: 0),
        GameTimeout(ours: true, half: 1, point: 1),
        GameTimeout(ours: false, half: 2, point: 1),
      ],
      points: const [
        StatPoint(
          line: ['a'],
          startedOn: Side.offense,
          result: PointResult.weScored,
        ),
        StatPoint(
          line: ['a'],
          startedOn: Side.defense,
          result: PointResult.theyScored,
        ),
      ],
    );
    final all = [...games, edge, finishedTied];
    checkFixture(
      'stats/games.json',
      'For each game (StatsGame.toMap with its id): the score, halftime, '
          'timeouts left and result, and its StatSheet (players in first-seen '
          'order, with ratings, and ranked by +/-). The last case is the '
          'sheet of every game together.',
      [
        for (final g in all)
          {
            'game': {'id': g.id, ...g.toMap()},
            'state': _gameState(g),
            'sheet': _sheet(StatSheet.fromGames([g])),
          },
        {
          'games': [for (final g in all) g.id],
          'sheet': _sheet(StatSheet.fromGames(all)),
        },
      ],
    );
  });

  test('roster order (stats/roster_order.json)', () {
    final players = [
      for (final (i, (name, number)) in [
        ('bob', 7),
        ('Alice', null),
        ('alice', null),
        ('Émile', 3),
        ('Zed', 3),
        ('Ann', 0),
        ('Cy', 99),
        ('Dee', null),
      ].indexed)
        RosterPlayer(id: 'p$i', name: name, number: number),
    ];
    checkFixture(
      'stats/roster_order.json',
      'RosterPlayer.compareRoster (sortPlayers): by number, no number last, '
          'then name.',
      [
        {
          'players': [
            for (final p in players)
              {'id': p.id, 'name': p.name, 'number': p.number},
          ],
          'expected': [
            for (final p in [...players]..sort(RosterPlayer.compareRoster))
              p.id,
          ],
        },
      ],
    );
  });

  test('line sources (stats/lines.json)', () {
    StatLine line(String id, String name, List<String> players, [Side? side]) =>
        StatLine(id: id, name: name, players: players, side: side);
    final tournaments = [
      StatsTournament(
        id: 't1',
        name: 'Spring Fling',
        startDate: DateTime(2026, 4, 11),
        eventId: 'e1',
        lines: [
          line('l1', 'O-line', ['a', 'b', 'c'], Side.offense),
          line('l2', 'D-line', ['d', 'e', 'f'], Side.defense),
        ],
      ),
      StatsTournament(
        id: 't2',
        name: 'No lines',
        startDate: DateTime(2026, 6, 1),
      ),
      StatsTournament(
        id: 't3',
        name: 'Summer',
        startDate: DateTime(2026, 7, 4),
        lines: [
          line('l3', 'Any', ['a', 'd']),
        ],
      ),
    ];
    final games = [
      StatsGame(
        id: 'g1',
        opponent: 'Rivals',
        date: DateTime(2026, 5, 2, 9),
        eventId: 'e1',
        lines: [
          // The same line as t1's O-line, players in another order.
          line('x1', 'O-line', ['c', 'a', 'b'], Side.offense),
          line('x2', 'O-line', ['a', 'b', 'c']),
        ],
      ),
      StatsGame(
        id: 'g2',
        opponent: 'In a tournament',
        date: DateTime(2026, 5, 3),
        tournamentId: 't1',
        eventId: 'e1',
        lines: [
          line('x3', 'Skip me', ['z']),
        ],
      ),
      StatsGame(id: 'g3', opponent: 'No lines', date: DateTime(2026, 8, 1)),
      StatsGame(
        id: 'g4',
        opponent: 'Scrimmage',
        date: DateTime(2026, 4, 11, 18),
        eventId: 'e2',
        lines: [
          line('x4', 'Mixed', ['a', 'e']),
        ],
      ),
    ];
    final sources = LineSource.from(tournaments, games);
    checkFixture(
      'stats/lines.json',
      'LineSource.from(tournaments, games) and LineSource.forEvent for '
          'each event id.',
      [
        {
          'tournaments': [
            for (final t in tournaments) {'id': t.id, ...t.toMap()},
          ],
          'games': [
            for (final g in games) {'id': g.id, ...g.toMap()},
          ],
          'sources': [
            for (final s in sources)
              {
                'id': s.id,
                'name': s.name,
                'eventId': s.eventId,
                'lines': [for (final l in s.lines) l.toMap()],
              },
          ],
          'forEvent': {
            for (final e in ['e1', 'e2', 'e3'])
              e: [for (final l in LineSource.forEvent(e, sources)) l.toMap()],
          },
          'keys': [
            for (final t in tournaments)
              for (final l in t.lines) l.key,
          ],
        },
      ],
    );
  });
}
