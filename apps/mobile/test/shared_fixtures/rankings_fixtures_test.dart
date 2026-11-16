// Shared vectors for the Rankings page's filters (RankingChoice in
// lib/domain/models/ranking.dart), checked by
// packages/shared/test/rankings_fixtures.test.ts against rankings.ts. See
// fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/ranking.dart';

import 'fixture_file.dart';

const _all = [
  'club-mixed',
  'club-open',
  'college-women',
  'league-mixed',
  'pickup-open',
];

final _cases = <Map<String, Object?>>[
  {'name': 'nothing ranked', 'keys': <String>[], 'query': <String, String>{}},
  {'name': 'the default is Club Mixed', 'keys': _all, 'query': {}},
  {
    'name': 'without Club Mixed, the first by level then division',
    'keys': ['pickup-open', 'college-women', 'club-open'],
    'query': {},
  },
  {
    'name': 'a level and division with data',
    'keys': _all,
    'query': {'level': 'college', 'division': 'women'},
  },
  {
    'name': 'a level whose division has no data: its first division',
    'keys': _all,
    'query': {'level': 'college', 'division': 'mixed'},
  },
  {
    'name': 'a level alone',
    'keys': _all,
    'query': {'level': 'pickup'},
  },
  {
    'name': 'a division alone: the first level that has it',
    'keys': _all,
    'query': {'division': 'women'},
  },
  {
    'name': 'a level that lacks the division asked for keeps the level',
    'keys': _all,
    'query': {'level': 'pickup', 'division': 'mixed'},
  },
  {
    'name': 'a level without data: the division asked for elsewhere',
    'keys': ['club-mixed', 'college-open'],
    'query': {'level': 'league', 'division': 'open'},
  },
  {
    'name': 'youth is never a level, even with data',
    'keys': [..._all, 'youth-mixed', 'youth-open'],
    'query': {'level': 'youth', 'division': 'open'},
  },
  {
    'name': 'only youth: nothing ranked',
    'keys': ['youth-mixed'],
    'query': {},
  },
  {
    'name': 'unknown and malformed keys are left out',
    'keys': ['elite-mixed', 'club-coed', 'club', 'club-mixed-x', 'league-open'],
    'query': {'level': 'elite'},
  },
  {
    'name': 'the old ?division=<key> link',
    'keys': _all,
    'query': {'division': 'college-women'},
  },
  {
    'name': "the app's old ?d=<key> link",
    'keys': _all,
    'query': {'d': 'league-mixed'},
  },
  {
    'name': 'an old youth key reads as nothing asked for',
    'keys': [..._all, 'youth-open'],
    'query': {'division': 'youth-open'},
  },
  {
    'name': 'a level wins over an old key',
    'keys': _all,
    'query': {'level': 'pickup', 'division': 'club-mixed'},
  },
];

void main() {
  test('ranking filters (rankings/choice.json)', () {
    checkFixture(
      'rankings/choice.json',
      'RankingChoice.wantFromQuery(query) then RankingChoice.choose(keys, '
          'want): the Rankings page\'s Level and Division filters, their '
          'options and default. Youth is never ranked.',
      [
        for (final c in _cases)
          () {
            final q = Map<String, String>.from(c['query']! as Map);
            final want = RankingChoice.wantFromQuery(
              level: q['level'],
              division: q['division'],
              d: q['d'],
            );
            final choice = RankingChoice.choose(
              c['keys']! as List<String>,
              level: want.level,
              division: want.division,
            );
            return {
              ...c,
              'want': {'level': want.level, 'division': want.division},
              'choice': choice == null
                  ? null
                  : {
                      'key': choice.key,
                      'level': choice.level,
                      'division': choice.division,
                      'levels': choice.levels,
                      'divisions': choice.divisions,
                    },
            };
          }(),
      ],
    );
  });
}
