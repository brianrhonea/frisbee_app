import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/schedule_entry.dart';
import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../calendar/widgets/add_to_calendar.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/scoreboard.dart' show TeamDot;
import 'rsvp_widgets.dart';

/// Team events and personal events each get one color on schedules, so the
/// two are easy to tell apart at a glance; other calendars have their own.
Color scheduleColor(BuildContext context, ScheduleEntry entry) {
  final c = AppColors.of(context);
  if (entry.calendar case final cal?) return cal.color.color;
  return entry.isPersonal ? c.personal : c.team;
}

/// Whose schedule an entry is on, for its meta line: the team's name,
/// the calendar's, or "Personal".
String scheduleOwner(ScheduleEntry entry) =>
    switch ((entry.calendar, entry.team)) {
      (final cal?, _) => cal.name,
      (_, final t?) => t.name,
      _ => 'Personal',
    };

/// One event on a schedule: its time on the left, then the title on a
/// line of its own over a meta line (a dot in the schedule's colour, whose
/// schedule it is and where), then the user's RSVP. An unanswered team
/// event is tinted amber with "Needs RSVP". Opens the event.
class ScheduleEventRow extends StatelessWidget {
  const ScheduleEventRow({
    super.key,
    required this.entry,
    this.showDay = true,
    this.large = false,
    this.rsvp,
    this.needsRsvp = false,
    this.onCalendarChanged,
  });

  final ScheduleEntry entry;

  /// After an event on another calendar was edited from its sheet (those
  /// aren't live), e.g. to reload the schedule.
  final VoidCallback? onCalendarChanged;

  /// Prefix the place with the weekday, for lists that span several days.
  final bool showDay;

  /// Roomier layout with the location, for the Schedule tab.
  final bool large;

  /// The user's answer, for team events and meetings.
  final RsvpStatus? rsvp;

  /// Unanswered and still ahead: marked as the user's to do.
  final bool needsRsvp;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final e = entry.event;
    final time = DateFormat.jm();
    final end = e.endsAt;
    final meta = [
      if (showDay) DateFormat.E().format(e.startsAt),
      if (large && e.location.isNotEmpty) e.location,
    ].join(' · ');
    final metaStyle = TextStyle(fontSize: 12, color: c.muted);
    final todo = needsRsvp && rsvp == null;
    return Material(
      color: todo ? c.highlightSoft : Colors.transparent,
      child: InkWell(
        onTap: () => entry.isOnCalendar
            ? showCalendarEventSheet(
                context,
                entry,
                onChanged: onCalendarChanged,
              )
            : context.push(Routes.scheduleEvent(entry)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: large ? 12 : 10,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time.format(e.startsAt),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      switch (end) {
                        null => e.type.label,
                        _ when DateUtils.isSameDay(e.startsAt, end) =>
                          time.format(end),
                        // Ends another day (overnight or multi-day).
                        _ => '– ${DateFormat.MMMd().format(end)}',
                      },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: large ? 15 : 14,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Whose it is gets most of the line; the place what's
                    // left.
                    LayoutBuilder(
                      builder: (context, box) => Row(
                        children: [
                          TeamDot(color: scheduleColor(context, entry)),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: meta.isEmpty
                                  ? box.maxWidth - 14
                                  : (box.maxWidth - 14) * 0.7,
                            ),
                            child: Text(
                              scheduleOwner(entry),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: metaStyle,
                            ),
                          ),
                          if (meta.isNotEmpty)
                            Expanded(
                              child: Text(
                                ' · $meta',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metaStyle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (rsvp != null || todo) ...[
                const SizedBox(width: 8),
                RsvpStatusPill(
                  status: rsvp,
                  type: e.type,
                  needsRsvp: todo,
                  strong: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One day of a week strip: weekday, date, and up to three dots in the
/// schedule colours of that day's events. Today is filled turf; the
/// [selected] day (where a new event goes) is soft turf.
class WeekDayCell extends StatelessWidget {
  const WeekDayCell({
    super.key,
    required this.day,
    required this.entries,
    this.isToday = false,
    this.selected = false,
    this.onTap,
    this.large = false,
  });

  final DateTime day;
  final List<ScheduleEntry> entries;
  final bool isToday;
  final bool selected;
  final VoidCallback? onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dot = large ? 6.0 : 5.0;
    final weekday = DateFormat.E().format(day);
    final fill = isToday ? c.accent : (selected ? c.accentSoft : null);
    final label = isToday ? c.onAccent : (selected ? c.accentInk : c.muted);
    final number = isToday ? c.onAccent : (selected ? c.accentInk : c.ink);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: fill ?? Colors.transparent,
        borderRadius: BorderRadius.circular(controlRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(controlRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Text(
                  large ? weekday.toUpperCase() : weekday.substring(0, 1),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: 0.4,
                    color: label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontFamily: scoreFont,
                    fontWeight: FontWeight.w800,
                    fontSize: large ? 20 : 17,
                    height: 1.1,
                    color: number,
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: dot,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final e in entries.take(3))
                        Container(
                          width: dot,
                          height: dot,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: isToday
                                ? c.onAccent
                                : scheduleColor(context, e),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An event on one of the user's other calendars: its details, "Add to
/// calendar", and Edit for people who can edit that calendar. These have
/// no page of their own. [onChanged] runs after an edit.
Future<void> showCalendarEventSheet(
  BuildContext context,
  ScheduleEntry entry, {
  VoidCallback? onChanged,
}) {
  final e = entry.event;
  final cal = entry.calendar;
  final router = GoRouter.maybeOf(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final c = AppColors.of(context);
      final when = DateFormat.yMMMEd().add_jm().format(e.startsAt);
      final until = e.endsAt == null
          ? ''
          : ' – ${DateFormat.jm().format(e.endsAt!)}';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${e.type.label} · $when$until',
                style: TextStyle(color: c.muted),
              ),
              if (e.location.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 18, color: c.muted),
                    const SizedBox(width: 6),
                    Expanded(child: Text(e.location)),
                  ],
                ),
              ],
              if (e.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(e.notes),
              ],
              if (cal != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    TeamDot(color: cal.color.color, size: 10),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cal.isMine
                            ? 'On ${cal.name}'
                            : "On ${cal.owner.name}'s ${cal.name} · "
                                  '${cal.role.label.toLowerCase()}',
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AddToCalendarButton(
                    event: e,
                    uid: '${cal?.id ?? 'me'}-${e.id}@stall10.app',
                  ),
                  if (cal != null && cal.canEdit && router != null)
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        final saved = await router.push<bool>(
                          Routes.editCalendarEvent(cal.id, e.id),
                        );
                        if (saved == true) onChanged?.call();
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
