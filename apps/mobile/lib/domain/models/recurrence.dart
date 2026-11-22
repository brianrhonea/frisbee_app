// Repeating events: a repeat (daily, weekly, every two weeks or monthly
// until an end date) is written out as one ordinary event per occurrence,
// so RSVPs, reminders, the iCal feed and every list keep working
// unchanged. The port of packages/shared/src/recurrence.ts (which the API
// and website use); both are checked against
// packages/shared/fixtures/recurrence.
import 'package:intl/intl.dart';

enum RepeatFrequency {
  daily('Daily', 'daily'),
  weekly('Weekly', 'weekly'),
  biweekly('Every 2 weeks', 'every 2 weeks'),
  monthly('Monthly', 'monthly');

  const RepeatFrequency(this.label, this.words);

  /// How it reads in a picker ("Every 2 weeks").
  final String label;

  /// How it reads in a sentence ("repeats every 2 weeks").
  final String words;
}

/// The most events one repeat writes out.
const maxRepeatOccurrences = 100;

/// The furthest a repeat's end date can be after its first event, in days.
const maxRepeatDays = 366;

/// How a new event repeats: [until] is the last day (inclusive) it can
/// fall on.
class Repeat {
  Repeat({required this.freq, required DateTime until})
    : until = DateTime(until.year, until.month, until.day);

  final RepeatFrequency freq;
  final DateTime until;

  Map<String, Object> toJson() => {'freq': freq.name, 'until': dateOnly(until)};
}

/// Editing or deleting an event in a series: it alone, or it and every
/// later one (`?scope=` on the API).
enum SeriesScope { one, following }

/// `series` on each event of a repeating series: which series, its place
/// and size (so "this and following" knows the later ones' ids without a
/// query), and the repeat, for "Repeats weekly until …".
class EventSeries {
  const EventSeries({
    required this.id,
    required this.index,
    required this.count,
    required this.freq,
    required this.until,
  });

  final String id;
  final int index;
  final int count;
  final RepeatFrequency freq;
  final DateTime until;

  /// The ids of the events after this one (some may have been deleted).
  List<String> get laterIds => [
    for (var i = index + 1; i < count && i < maxRepeatOccurrences; i++)
      occurrenceId(id, i),
  ];

  Map<String, Object> toMap() => {
    'id': id,
    'index': index,
    'count': count,
    'freq': freq.name,
    'until': dateOnly(until),
  };

  static EventSeries? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final index = raw['index'];
    final count = raw['count'];
    final freq = RepeatFrequency.values
        .where((f) => f.name == raw['freq'])
        .firstOrNull;
    final until = DateTime.tryParse('${raw['until']}');
    if (id is! String || index is! num || count is! num) return null;
    if (freq == null || until == null) return null;
    return EventSeries(
      id: id,
      index: index.toInt(),
      count: count.toInt(),
      freq: freq,
      until: until,
    );
  }
}

/// The document id of a series' [index]th event.
String occurrenceId(String seriesId, int index) => '${seriesId}_$index';

/// `YYYY-MM-DD`.
String dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// The dates (local midnights) a repeat starting on [start] falls on,
/// [start]'s first, up to and including [Repeat.until]. Monthly keeps the
/// day of the month and skips months without it (the 31st skips 30-day
/// months), as RFC 5545 does. Stops one past [maxRepeatOccurrences] so
/// [repeatProblem] can tell.
List<DateTime> repeatDates(DateTime start, Repeat repeat) {
  final end = _day(repeat.until);
  final out = <DateTime>[];
  const cap = maxRepeatOccurrences + 1;
  if (repeat.freq == RepeatFrequency.monthly) {
    for (var k = 0; out.length < cap; k++) {
      final first = DateTime.utc(start.year, start.month + k);
      final days = DateTime.utc(first.year, first.month + 1, 0).day;
      if (start.day > days) continue;
      final d = DateTime.utc(first.year, first.month, start.day);
      if (d.isAfter(end)) break;
      out.add(DateTime(d.year, d.month, d.day));
    }
    return out;
  }
  final step = switch (repeat.freq) {
    RepeatFrequency.daily => 1,
    RepeatFrequency.weekly => 7,
    _ => 14,
  };
  for (
    var d = _day(start);
    !d.isAfter(end) && out.length < cap;
    d = DateTime.utc(d.year, d.month, d.day + step)
  ) {
    out.add(DateTime(d.year, d.month, d.day));
  }
  return out;
}

/// Why a repeat from [start] can't be saved, or null when it can.
String? repeatProblem(DateTime start, Repeat repeat) {
  final from = _day(start);
  final until = _day(repeat.until);
  if (until.isBefore(from)) return "The repeat can't end before the event.";
  if (until.difference(from).inDays > maxRepeatDays) {
    return 'Repeat for at most a year.';
  }
  final n = repeatDates(start, repeat).length;
  if (n > maxRepeatOccurrences) {
    return "That's more than $maxRepeatOccurrences events. "
        'Pick an earlier end date.';
  }
  if (n < 2) return 'Pick an end date that makes it repeat at least once.';
  return null;
}

/// "Repeats weekly until Mar 3, 2027".
String repeatSummary(RepeatFrequency freq, DateTime until) =>
    'Repeats ${freq.words} until ${DateFormat('MMM d, y', 'en_US').format(until)}';

/// Each occurrence's start and end: the same wall-clock time on each of
/// [repeatDates], lasting as long as the first.
List<(DateTime, DateTime?)> seriesTimes(
  DateTime startsAt,
  DateTime? endsAt,
  Repeat repeat,
) {
  final length = endsAt?.difference(startsAt);
  return [
    for (final d in repeatDates(startsAt, repeat).take(maxRepeatOccurrences))
      () {
        final s = DateTime(
          d.year,
          d.month,
          d.day,
          startsAt.hour,
          startsAt.minute,
          startsAt.second,
        );
        return (s, length == null ? null : s.add(length));
      }(),
  ];
}

/// How a later event moves when an event that started at [before] is
/// changed to [after] / [afterEnd] for "this and following": the same
/// change of date and of time of day (wall clock), the new length.
(DateTime, DateTime?) Function(DateTime later) moveLater(
  DateTime before,
  DateTime after,
  DateTime? afterEnd,
) {
  final days = _day(after).difference(_day(before)).inDays;
  final minutes =
      after.hour * 60 + after.minute - (before.hour * 60 + before.minute);
  final length = afterEnd?.difference(after);
  return (later) {
    final s = DateTime(
      later.year,
      later.month,
      later.day + days,
      later.hour,
      later.minute + minutes,
      later.second,
    );
    return (s, length == null ? null : s.add(length));
  };
}
