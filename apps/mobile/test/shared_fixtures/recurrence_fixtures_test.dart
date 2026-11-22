// Shared vectors for repeating events (lib/domain/models/recurrence.dart),
// checked by packages/shared/test/recurrence_fixtures.test.ts against
// repeatDates, repeatProblem and repeatSummary in recurrence.ts. See
// fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/recurrence.dart';

import 'fixture_file.dart';

final _cases = <(String, String, RepeatFrequency, String)>[
  ('weekly for a month', '2026-11-20', RepeatFrequency.weekly, '2026-12-18'),
  ('weekly ends between', '2026-11-20', RepeatFrequency.weekly, '2026-12-16'),
  ('daily over a month end', '2026-11-28', RepeatFrequency.daily, '2026-12-03'),
  ('every 2 weeks', '2026-11-03', RepeatFrequency.biweekly, '2027-01-12'),
  ('monthly on the 15th', '2026-11-15', RepeatFrequency.monthly, '2027-03-15'),
  (
    'monthly on the 31st skips short months',
    '2027-01-31',
    RepeatFrequency.monthly,
    '2027-08-31',
  ),
  (
    'monthly on Feb 29 in a leap year',
    '2028-02-29',
    RepeatFrequency.monthly,
    '2029-03-01',
  ),
  ('across the year end', '2026-12-29', RepeatFrequency.weekly, '2027-01-12'),
  ('ends before it starts', '2026-11-20', RepeatFrequency.weekly, '2026-11-19'),
  ('only one event', '2026-11-20', RepeatFrequency.weekly, '2026-11-25'),
  ('more than a year', '2026-11-20', RepeatFrequency.weekly, '2027-11-22'),
  ('too many events', '2026-11-20', RepeatFrequency.daily, '2027-03-30'),
  ('exactly 100 events', '2026-11-20', RepeatFrequency.daily, '2027-02-27'),
];

void main() {
  test('recurrence matches fixtures/recurrence/dates.json', () {
    checkFixture(
      'recurrence/dates.json',
      'repeatDates, repeatProblem and repeatSummary (recurrence.dart) for '
          'a repeat starting on [start]; dates are local days.',
      [
        for (final (name, start, freq, until) in _cases)
          () {
            final repeat = Repeat(freq: freq, until: DateTime.parse(until));
            final from = DateTime.parse(start);
            return {
              'name': name,
              'start': start,
              'freq': freq,
              'until': until,
              'dates': [for (final d in repeatDates(from, repeat)) dateOnly(d)],
              'problem': repeatProblem(from, repeat),
              'summary': repeatSummary(freq, repeat.until),
            };
          }(),
      ],
    );
  });
}
