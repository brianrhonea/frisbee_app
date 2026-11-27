import '../../../domain/models/recurrence.dart';
import '../../../domain/models/team_event.dart';

/// How long an event with no end time is taken to last when looking for
/// overlaps.
const defaultEventLength = Duration(hours: 1);

/// The end used for [e] when comparing times: its own, or an hour after
/// its start when it has none (or when it ends before it starts).
DateTime _endOf(DateTime start, DateTime? end) =>
    end != null && end.isAfter(start) ? end : start.add(defaultEventLength);

bool _overlaps(DateTime aStart, DateTime aEnd, TeamEvent b) =>
    aStart.isBefore(_endOf(b.startsAt, b.endsAt)) && b.startsAt.isBefore(aEnd);

/// The first event in [known] that [draft] overlaps in time, or null.
///
/// [known] is only what the schedule has already loaded (nothing is
/// queried). With a [repeat], every date of the series is checked. The
/// draft itself is left out when editing (same id), as are the other
/// occurrences of the series being edited. Events are timed (there are no
/// all-day or cancelled events in the model), and one with no end time
/// counts as [defaultEventLength] long. Events that only touch (one ends
/// when the other starts) don't overlap.
TeamEvent? firstOverlap(
  TeamEvent draft,
  Iterable<TeamEvent> known, {
  Repeat? repeat,
}) {
  final others = [
    for (final e in known)
      if ((draft.id.isEmpty || e.id != draft.id) &&
          (draft.series == null || e.series?.id != draft.series!.id))
        e,
  ];
  final times = repeat == null
      ? [(draft.startsAt, draft.endsAt)]
      : seriesTimes(draft.startsAt, draft.endsAt, repeat);
  for (final (start, end) in times) {
    final until = _endOf(start, end);
    for (final e in others) {
      if (_overlaps(start, until, e)) return e;
    }
  }
  return null;
}
