// Shared vectors for "Add to calendar" files (lib/utils/ics.dart), checked
// by packages/shared/test/ical_fixtures.test.ts against ical.ts. See
// fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/utils/ics.dart';

import 'fixture_file.dart';

const _now = '2026-11-13T12:00:00.000Z';

final _events = <Map<String, Object?>>[
  {
    'name': 'an hour by default; no location or notes',
    'uid': 'e1@stall10.app',
    'title': 'Track session',
    'startsAt': '2026-11-15T17:00:00.000Z',
  },
  {
    'name': 'escaped text, an end and a location',
    'uid': 'team1/e2,x;y@stall10.app',
    'title': r'Track; easy, then \ hills',
    'startsAt': '2026-11-15T17:00:00.000Z',
    'endsAt': '2026-11-15T19:30:00.000Z',
    'location': 'Track, lane 1',
    'description': 'Bring water.\nSpikes optional.\r\nCarpool: Main St.',
  },
  {
    'name': 'long lines fold at 75 octets without splitting characters',
    'uid': 'e3@stall10.app',
    'title': 'Hat tournament ${'é' * 40} 🥏 finals',
    'startsAt': '2026-07-04T23:30:00.000Z',
    'location': 'A' * 160,
    'description':
        '${'Long notes ' * 12}with an emoji 🥏 near the end of a line.',
  },
];

void main() {
  test('add to calendar files (ics/events.json)', () {
    checkFixture(
      'ics/events.json',
      'Ics.event(event, uid, description, now) for one event (the event '
          'notes are its description), and Ics.fileName(title).',
      [
        for (final e in _events)
          {
            ...e,
            'now': _now,
            'ics': Ics.event(
              TeamEvent(
                id: 'id',
                title: e['title']! as String,
                startsAt: date(e['startsAt']! as String),
                endsAt: e['endsAt'] == null
                    ? null
                    : date(e['endsAt']! as String),
                location: e['location'] as String? ?? '',
                notes: e['description'] as String? ?? '',
              ),
              uid: e['uid']! as String,
              now: date(_now),
            ),
            'fileName': Ics.fileName(e['title']! as String),
          },
      ],
    );
  });

  test('pieces (ics/pieces.json)', () {
    checkFixture(
      'ics/pieces.json',
      'Ics.text, Ics.date, Ics.fold and Ics.fileName.',
      [
        for (final s in [r'a\b;c,d', 'line\nbreak\r\nand\rreturn', 'plain', ''])
          {'kind': 'text', 'input': s, 'output': Ics.text(s)},
        for (final d in [
          '2026-11-15T11:00:00.000-06:00',
          '2026-01-01T00:00:00.000Z',
          '2026-12-31T23:59:59.000Z',
        ])
          {'kind': 'date', 'input': d, 'output': Ics.date(date(d))},
        for (final line in [
          'SHORT:x',
          'X:${'a' * 73}',
          'X:${'a' * 74}',
          'SUMMARY:${'é' * 60}',
          'SUMMARY:${'🥏' * 30}',
          'D:${'ab' * 100}',
        ])
          {'kind': 'fold', 'input': line, 'output': Ics.fold(line)},
        for (final title in [
          'Track session',
          '  Hat: finals!! (day 2) ',
          '???',
          'Ünïcödé names_and-dashes',
          'x' * 80,
        ])
          {'kind': 'fileName', 'input': title, 'output': Ics.fileName(title)},
      ],
    );
  });
}
