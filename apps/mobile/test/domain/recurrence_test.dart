import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/recurrence.dart';

void main() {
  group('seriesTimes', () {
    test('keeps the time of day and the length on each date', () {
      final times = seriesTimes(
        DateTime(2026, 11, 20, 18, 30),
        DateTime(2026, 11, 20, 20),
        Repeat(freq: RepeatFrequency.weekly, until: DateTime(2026, 12, 4)),
      );
      expect(times, [
        (DateTime(2026, 11, 20, 18, 30), DateTime(2026, 11, 20, 20)),
        (DateTime(2026, 11, 27, 18, 30), DateTime(2026, 11, 27, 20)),
        (DateTime(2026, 12, 4, 18, 30), DateTime(2026, 12, 4, 20)),
      ]);
    });

    test('never writes more than the most events', () {
      final times = seriesTimes(
        DateTime(2026, 11, 20, 7),
        null,
        Repeat(freq: RepeatFrequency.daily, until: DateTime(2027, 6, 1)),
      );
      expect(times, hasLength(maxRepeatOccurrences));
      expect(times.last.$2, isNull);
    });
  });

  test('moveLater moves later events by the same change', () {
    // 6 pm Friday moved to 7:30 pm Saturday, now two hours long.
    final move = moveLater(
      DateTime(2026, 11, 20, 18),
      DateTime(2026, 11, 21, 19, 30),
      DateTime(2026, 11, 21, 21, 30),
    );
    expect(move(DateTime(2026, 11, 27, 18)), (
      DateTime(2026, 11, 28, 19, 30),
      DateTime(2026, 11, 28, 21, 30),
    ));
  });

  test('EventSeries round-trips and lists its later ids', () {
    final s = EventSeries.fromMap({
      'id': 'abc',
      'index': 1,
      'count': 4,
      'freq': 'biweekly',
      'until': '2026-12-31',
    })!;
    expect(s.laterIds, ['abc_2', 'abc_3']);
    expect(s.toMap()['until'], '2026-12-31');
    expect(EventSeries.fromMap({'id': 'abc'}), isNull);
    expect(
      repeatSummary(s.freq, s.until),
      'Repeats every 2 weeks until Dec 31, 2026',
    );
  });
}
