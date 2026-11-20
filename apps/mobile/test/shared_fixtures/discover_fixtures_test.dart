// Shared vectors for spots left (TournamentSpots in
// lib/domain/models/discover.dart) and the Learn guide's lessons and
// progress (learnSections, LearnViewModel), checked by
// packages/shared/test/discover_fixtures.test.ts against discover.ts. See
// fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/discover.dart';
import 'package:frisbee_app/ui/learn/learn_content.dart';

import 'fixture_file.dart';

void main() {
  test('spots left labels', () {
    checkFixture(
      'discover/spots.json',
      'TournamentSpots.label: what a tournament card says while '
          'registration is open, from the team spots left of the cap.',
      [
        for (final (name, left, cap) in [
          ('room', 5, 16),
          ('one left', 1, 8),
          ('full', 0, 8),
          ('over full', -1, 4),
        ])
          () {
            final s = TournamentSpots(left: left, cap: cap);
            return {
              'name': name,
              'left': left,
              'cap': cap,
              'label': s.label,
              'full': s.isFull,
            };
          }(),
      ],
    );
  });

  test('Learn lessons and progress', () {
    final ids = {for (final s in learnSections) s.id};
    Map<String, Object?> progress(String name, List<String> read) => {
      'name': name,
      'read': read,
      'ids': [
        for (final s in learnSections)
          if (read.contains(s.id)) s.id,
      ],
      'label': learnProgressLabel(
        read.where(ids.contains).toSet().length,
        learnSections.length,
      ),
    };
    checkFixture(
      'discover/learn.json',
      "The Learn guide's lessons (ids and titles, in order: the first case), "
          'then reading progress: the ids read that are still lessons, in '
          'the guide\'s order, and "N of M read".',
      [
        {
          'lessons': [
            for (final s in learnSections) {'id': s.id, 'title': s.title},
          ],
        },
        progress('nothing read', []),
        progress('some read, out of order', ['stall', 'basics']),
        progress('an old id is ignored', ['basics', 'gone']),
        progress('everything', [for (final s in learnSections) s.id]),
      ],
    );
  });
}
