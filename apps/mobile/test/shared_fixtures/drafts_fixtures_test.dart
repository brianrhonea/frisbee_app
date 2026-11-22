// Shared vectors for drafting players onto teams
// (lib/domain/tournament_engine/team_builder.dart, seeded_random.dart and
// LiveDraft's snake order), checked by
// packages/shared/test/drafts_fixtures.test.ts against drafts.ts and
// group_tournaments.ts's groupEngine. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/live_draft.dart';
import 'package:frisbee_app/domain/tournament_engine/seeded_random.dart';
import 'package:frisbee_app/domain/tournament_engine/team_builder.dart';

import 'fixture_file.dart';

/// [n] players with skills and genders from a fixed pattern.
List<DraftPlayer> _players(int n, {bool genders = false}) => [
  for (var i = 0; i < n; i++)
    (
      uid: 'u${i.toString().padLeft(2, '0')}',
      name: 'Player $i',
      skill: 1 + (i * 7 + 3) % 5,
      gender: !genders || i % 7 == 6
          ? null
          : (i * 5 % 3 == 0 ? GenderMatch.wmp : GenderMatch.mmp),
    ),
];

Map<String, Object?> _player(DraftPlayer p) => {
  'uid': p.uid,
  'name': p.name,
  'skill': p.skill,
  'gender': p.gender?.name,
};

List<Map<String, Object?>> _teams(List<TournamentTeam> teams) => [
  for (final t in teams) t.toMap(),
];

final _named = [
  const TournamentTeam(id: 'red', name: 'Red'),
  const TournamentTeam(
    id: 'blue',
    name: 'Blue',
    captainId: 'old',
    playerIds: ['old'],
    playerNames: {'old': 'Old Player'},
  ),
  const TournamentTeam(id: 'green', name: 'Green'),
];

void main() {
  test('the seeded generator (drafts/seeded_random.json)', () {
    checkFixture(
      'drafts/seeded_random.json',
      'SeededRandom(seed) (mulberry32, seededRandom in drafts.ts): the first '
          'ten nextDouble values, then a fresh generator\'s first ten '
          'nextInt(10).',
      [
        for (final seed in [
          0,
          1,
          2,
          7,
          42,
          1234,
          65535,
          0x7fffffff,
          0xffffffff,
        ])
          {
            'seed': seed,
            'doubles': () {
              final r = SeededRandom(seed);
              return [for (var i = 0; i < 10; i++) r.nextDouble()];
            }(),
            'ints': () {
              final r = SeededRandom(seed);
              return [for (var i = 0; i < 10; i++) r.nextInt(10)];
            }(),
          },
      ],
    );
  });

  test('balanced drafts (drafts/balanced_draft.json)', () {
    final cases = [
      ('8 players, 2 teams', _players(8), blankTeams(2), 1, false),
      ('17 players, 3 teams', _players(17), blankTeams(3), 7, false),
      (
        '17 players, 3 teams, another seed',
        _players(17),
        blankTeams(3),
        8,
        false,
      ),
      ('23 players, 4 teams', _players(23), blankTeams(4), 40000, false),
      (
        'mixed, 20 players, 4 teams',
        _players(20, genders: true),
        blankTeams(4),
        5,
        true,
      ),
      (
        'mixed, 31 players, 3 teams',
        _players(31, genders: true),
        blankTeams(3),
        65535,
        true,
      ),
      ('mixed flag with no genders', _players(9), blankTeams(2), 3, true),
      (
        'named teams keep their names; rosters are replaced',
        _players(10),
        _named,
        12,
        false,
      ),
      ('more teams than players', _players(3), blankTeams(5), 9, false),
      ('no players', <DraftPlayer>[], blankTeams(2), 1, false),
      ('no teams', _players(4), <TournamentTeam>[], 1, false),
      (
        'a player listed twice counts once',
        [..._players(6), _players(6)[2]],
        blankTeams(2),
        2,
        false,
      ),
    ];
    checkFixture(
      'drafts/balanced_draft.json',
      'balancedDraft(players, teams, seed, mixed): the teams it deals.',
      [
        for (final (name, players, teams, seed, mixed) in cases)
          {
            'name': name,
            'players': [for (final p in players) _player(p)],
            'teams': _teams(teams),
            'seed': seed,
            'mixed': mixed,
            'expected': _teams(
              balancedDraft(players, teams, seed: seed, mixed: mixed),
            ),
          },
      ],
    );
  });

  test('random deals, blank teams and moves (drafts/team_builder.json)', () {
    final players = [for (final p in _players(11)) (uid: p.uid, name: p.name)];
    final dealt = dealPlayers(players, blankTeams(3), random: SeededRandom(21));
    checkFixture(
      'drafts/team_builder.json',
      'dealPlayers with SeededRandom(seed); blankTeams(count, existing); '
          'movePlayer(teams, player, teamId).',
      [
        for (final (players, count, seed) in [
          (players, 3, 21),
          (players.take(4).toList(), 4, 99),
          (players, 2, 0),
        ])
          {
            'kind': 'dealPlayers',
            'players': [
              for (final p in players) {'uid': p.uid, 'name': p.name},
            ],
            'teams': _teams(blankTeams(count)),
            'seed': seed,
            'expected': _teams(
              dealPlayers(
                players,
                blankTeams(count),
                random: SeededRandom(seed),
              ),
            ),
          },
        for (final (count, existing) in [
          (3, <TournamentTeam>[]),
          (2, _named),
          (
            2,
            [
              const TournamentTeam(id: 'team2', name: 'Team 2'),
              const TournamentTeam(id: 'team4', name: 'Team 4'),
            ],
          ),
        ])
          {
            'kind': 'blankTeams',
            'count': count,
            'existing': _teams(existing),
            'expected': _teams(blankTeams(count, existing: existing)),
          },
        for (final (player, teamId) in [
          (players[0], 'team2'),
          (players[1], 'team1'),
          (players[0], null),
          (players[3], 'team3'),
          ((uid: 'new', name: 'New Player'), 'team1'),
          (players[2], 'nowhere'),
        ])
          () {
            final before = dealt;
            return {
              'kind': 'movePlayer',
              'teams': _teams(before),
              'player': {'uid': player.uid, 'name': player.name},
              'teamId': teamId,
              'expected': _teams(movePlayer(before, player, teamId: teamId)),
            };
          }(),
      ],
    );
  });

  test('signup order (drafts/signup_order.json)', () {
    final names = [
      'bob',
      'Alice',
      'alice b',
      'Émile',
      'Zoe',
      'zed',
      '_x',
      'Aaron-Lee',
      'aaron lee',
      '9 Lives',
      '',
    ];
    final signups = [
      for (final (i, n) in names.indexed)
        PlayerSignup(uid: 'u$i', name: n, divisionId: 'open'),
    ];
    // Equal names (any case) go by uid; listed out of uid order.
    final sameNames = [
      for (final (uid, n) in [
        ('u9', 'Sam'),
        ('u2', 'sam'),
        ('u5', 'Sam'),
        ('u1', 'Alex'),
        ('u10', 'SAM'),
      ])
        PlayerSignup(uid: uid, name: n, divisionId: 'open'),
    ];
    checkFixture(
      'drafts/signup_order.json',
      'PlayerSignup.compareByName (signupOrder): the order players are '
          'listed and drafted in; equal names go by uid.',
      [
        for (final list in [signups, sameNames])
          {
            'signups': [
              for (final s in list) {'uid': s.uid, 'name': s.name},
            ],
            'expected': [
              for (final s in [...list]..sort(PlayerSignup.compareByName))
                s.uid,
            ],
          },
      ],
    );
  });

  test('snake order (drafts/snake_order.json)', () {
    checkFixture(
      'drafts/snake_order.json',
      'LiveDraft: snakeIndex for every pick, then onTheClock and teamOf '
          'as the picks come in (captains pick in snake order).',
      [
        for (final (captains, pool) in [(2, 5), (3, 9), (4, 10), (5, 4)])
          () {
            final caps = [
              for (var i = 0; i < captains; i++)
                DraftCaptain(uid: 'c$i', name: 'Captain $i'),
            ];
            final poolMap = {for (var i = 0; i < pool; i++) 'p$i': 'Pick $i'};
            final picks = <DraftPick>[];
            final clock = <String?>[];
            for (var i = 0; i <= pool; i++) {
              final d = LiveDraft(
                divisionId: 'open',
                status: DraftStatus.live,
                captains: caps,
                picks: [...picks],
                pool: poolMap,
              );
              clock.add(d.onTheClock);
              if (d.onTheClock case final c?) {
                picks.add(DraftPick(uid: 'p$i', captainId: c));
              }
            }
            final done = LiveDraft(
              divisionId: 'open',
              status: DraftStatus.done,
              captains: caps,
              picks: picks,
              pool: poolMap,
            );
            return {
              'captains': [for (final c in caps) c.uid],
              'poolSize': pool,
              'snake': [
                for (var p = 0; p < pool; p++)
                  LiveDraft.snakeIndex(captains, p),
              ],
              'onTheClock': clock,
              'picks': [
                for (final p in picks) {'uid': p.uid, 'captainId': p.captainId},
              ],
              'teams': {for (final c in caps) c.uid: done.teamOf(c.uid)},
            };
          }(),
      ],
    );
  });
}
