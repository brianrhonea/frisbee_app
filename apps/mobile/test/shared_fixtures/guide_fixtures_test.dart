// Stall 10's guides (lib/domain/models/guides.dart): the rules of ultimate
// and Help, checked by packages/shared/test/guide_fixtures.test.ts against
// guides.ts so both platforms say the same. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/guides.dart';

import 'fixture_file.dart';

void main() {
  test('guides (guides/guides.json)', () {
    checkFixture(
      'guides/guides.json',
      'The Rules of ultimate page and Help in Settings: the official rule '
          'books linked, then each section (id, title, intro, points) in '
          'order. The website shows the same words.',
      [
        {
          'officialRules': [for (final l in officialRules) l.toMap()],
        },
        {
          'rules': [for (final s in rulesGuide) s.toMap()],
        },
        {
          'help': [for (final s in helpTopics) s.toMap()],
        },
      ],
    );
  });

  test('section ids are unique', () {
    for (final list in [rulesGuide, helpTopics]) {
      expect(list.map((s) => s.id).toSet().length, list.length);
    }
  });
}
