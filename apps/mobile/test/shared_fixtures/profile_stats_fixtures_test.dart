// Shared vectors for a profile's Team filter (ProfileStatsChoice in
// lib/domain/models/player_profile.dart), checked by
// packages/shared/test/profile_stats_fixtures.test.ts against
// profileStatsChoice in profile_stats.ts. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';

import 'fixture_file.dart';

Map<String, Object?> _t(int games, int goals) => {
  'games': games,
  'goals': goals,
};

final _twoTeams = {
  't1': {'2025': _t(2, 3), '2026': _t(1, 1)},
  't2': {'2026': _t(2, 4)},
};

final _cases = <Map<String, Object?>>[
  {
    'name': 'no per-team stats: no filter, every team',
    'teams': ['t1', 't2'],
    'stats': {'2026': _t(3, 5)},
    'teamStats': <String, Object?>{},
    'team': null,
  },
  {
    'name': 'two teams with stats: offered in the teams order',
    'teams': ['t2', 't1'],
    'stats': {'2025': _t(2, 3), '2026': _t(3, 5)},
    'teamStats': _twoTeams,
    'team': null,
  },
  {
    'name': 'a team picked shows its seasons',
    'teams': ['t1', 't2'],
    'stats': {'2025': _t(2, 3), '2026': _t(3, 5)},
    'teamStats': _twoTeams,
    'team': 't2',
  },
  {
    'name': 'one team with stats: no filter, the pick is ignored',
    'teams': ['t1', 't2'],
    'stats': {'2026': _t(1, 1)},
    'teamStats': {
      't1': {'2026': _t(1, 1)},
    },
    'team': 't1',
  },
  {
    'name': 'a team not on the published teams is never offered',
    'teams': ['t1'],
    'stats': {'2026': _t(3, 5)},
    'teamStats': _twoTeams,
    'team': 't2',
  },
  {
    'name': 'a team whose seasons are all empty is not offered',
    'teams': ['t1', 't2', 't3'],
    'stats': {'2025': _t(2, 3), '2026': _t(3, 5)},
    'teamStats': {
      ..._twoTeams,
      't3': {'2026': _t(0, 0)},
    },
    'team': 't3',
  },
  {
    'name': 'an unknown pick means every team',
    'teams': ['t1', 't2'],
    'stats': {'2025': _t(2, 3), '2026': _t(3, 5)},
    'teamStats': _twoTeams,
    'team': 'nope',
  },
];

Map<String, StatTotals> _seasons(Object? raw) => {
  for (final e in (raw! as Map).entries)
    '${e.key}': StatTotals.fromMap(Map<String, dynamic>.from(e.value as Map)),
};

void main() {
  test('profile Team filter (profile_stats/choice.json)', () {
    checkFixture(
      'profile_stats/choice.json',
      'ProfileStatsChoice.of(summary, team): the Team filter on a '
          "profile's stats. Offers the published teams that have stats, in "
          'their order, only when there are two or more; a team it does not '
          'offer means every team. `seasons` are the picked season keys, '
          'newest first, and `goals` their total.',
      [
        for (final c in _cases)
          () {
            final summary = ProfileSummary(
              teams: [
                for (final id in c['teams']! as List<String>)
                  ProfileTeam(id: id, name: id),
              ],
              seasons: _seasons(c['stats']),
              teamSeasons: {
                for (final e in (c['teamStats']! as Map).entries)
                  '${e.key}': _seasons(e.value),
              },
            );
            final choice = ProfileStatsChoice.of(summary, c['team'] as String?);
            return {
              ...c,
              'choice': {
                'options': [for (final t in choice.options) t.id],
                'team': choice.teamId,
                'seasons': choice.seasons.keys.toList()
                  ..sort((a, b) => b.compareTo(a)),
                'goals': choice.seasons.values.fold<int>(
                  0,
                  (a, s) => a + s.goals,
                ),
              },
            };
          }(),
      ],
    );
  });
}
