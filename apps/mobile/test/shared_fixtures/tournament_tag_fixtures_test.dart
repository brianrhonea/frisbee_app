// Shared vectors for "At a tournament" tags (lib/domain/models/follow.dart),
// checked by packages/shared/test/tournament_tag_fixtures.test.ts against
// parseTournamentKey and tournamentTagOpen in follows.ts. See
// fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/follow.dart';

import 'fixture_file.dart';

void main() {
  test('tags match fixtures/tournament_tags/cases.json', () {
    final start = DateTime.utc(2026, 12, 12, 9);
    final end = DateTime.utc(2026, 12, 13);
    final windows = <(String, DateTime?, DateTime)>[
      ('8 days before', null, start.subtract(const Duration(days: 8))),
      ('7 days before', null, start.subtract(const Duration(days: 7))),
      ('the day before', end, start.subtract(const Duration(days: 1))),
      ('during', end, start.add(const Duration(hours: 3))),
      ('the last day', end, end.add(const Duration(hours: 20))),
      ('the day after the last', end, end.add(const Duration(hours: 25))),
      ('one day, that evening', null, start.add(const Duration(hours: 12))),
      ('one day, the day after', null, start.add(const Duration(days: 1))),
      ('ends before it starts', DateTime.utc(2026, 12, 1), start),
    ];
    final keys = [
      'tournament_host1_t1',
      'tournament_group9_abc',
      'tournament_',
      'tournament_x',
      'tournament_x_',
      'team_abc',
    ];
    checkFixture(
      'tournament_tags/cases.json',
      'parseTournamentKey and tournamentTagOpen (follow.dart).',
      [
        for (final (name, endsOn, now) in windows)
          {
            'name': name,
            'startsOn': start.toIso8601String(),
            'endsOn': endsOn?.toIso8601String(),
            'now': now.toIso8601String(),
            'open': tournamentTagOpen(start, endsOn, now),
          },
        for (final key in keys)
          {
            'name': 'key $key',
            'key': key,
            'parsed': switch (FollowTarget.parseTournamentKey(key)) {
              final p? => {'hostId': p.hostId, 'tournamentId': p.tournamentId},
              null => null,
            },
          },
      ],
    );
  });
}
