import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/schedule_entry.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import 'event_style.dart';

/// Team events and personal events each get one color on schedules, so the
/// two are easy to tell apart at a glance.
Color scheduleColor(BuildContext context, ScheduleEntry entry) {
  final c = AppColors.of(context);
  if (entry.isShared) return c.muted;
  return entry.isPersonal ? c.personal : c.team;
}

/// Small pill saying whose schedule an event is on: "PERSONAL", or the team
/// ("TEAM", or its name when [showTeamName]).
class ScheduleTag extends StatelessWidget {
  const ScheduleTag({
    super.key,
    required this.entry,
    this.showTeamName = false,
  });

  final ScheduleEntry entry;
  final bool showTeamName;

  @override
  Widget build(BuildContext context) {
    final color = scheduleColor(context, entry);
    final team = entry.team;
    final label = switch ((entry.sharedBy, team)) {
      (final owner?, _) => owner.name.split(' ').first.toUpperCase(),
      (_, null) => 'PERSONAL',
      (_, final t?) => showTeamName ? t.name.toUpperCase() : 'TEAM',
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}

/// "● Team  ● Personal" key for schedule colors.
class ScheduleLegend extends StatelessWidget {
  const ScheduleLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    );
    return Wrap(
      spacing: 14,
      children: [item(c.team, 'Team'), item(c.personal, 'Personal')],
    );
  }
}

/// One event on a schedule: type icon tinted by schedule, title, time and
/// a team/personal tag. Opens the event over the current screen.
class ScheduleEventRow extends StatelessWidget {
  const ScheduleEventRow({
    super.key,
    required this.entry,
    this.showTeamName = false,
    this.showDay = true,
    this.large = false,
  });

  final ScheduleEntry entry;
  final bool showTeamName;

  /// Prefix the time with the weekday, for lists that span several days.
  final bool showDay;

  /// Roomier layout with the location, for the Schedule tab.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final e = entry.event;
    final color = scheduleColor(context, entry);
    final tile = large ? 44.0 : 36.0;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => entry.isShared
          ? showSharedEventSheet(context, entry)
          : context.push(Routes.scheduleEvent(entry)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: large ? 10 : 8),
        child: Row(
          children: [
            Container(
              width: tile,
              height: tile,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(e.type.icon, size: large ? 22 : 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: large ? 15 : 14,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (showDay) DateFormat.E().format(e.startsAt),
                      eventTimeRange(e),
                      if (large && e.location.isNotEmpty) e.location,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ScheduleTag(entry: entry, showTeamName: showTeamName),
            Icon(Icons.chevron_right, size: 20, color: c.muted),
          ],
        ),
      ),
    );
  }
}

/// One day of a week strip: weekday, date, and up to three dots in the
/// schedule colors of that day's events. Today is outlined; the [selected]
/// day is filled.
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
    final size = large ? 40.0 : 32.0;
    final dot = large ? 7.0 : 6.0;
    final weekday = DateFormat.E().format(day);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Text(
              large ? weekday.toUpperCase() : weekday.substring(0, 1),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: isToday || selected ? c.accent : c.muted,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.accent : null,
                shape: BoxShape.circle,
                border: isToday && !selected
                    ? Border.all(color: c.accent, width: 2)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: large ? 16 : 14,
                  color: selected ? c.onAccent : c.ink,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: dot,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final e in entries.take(3))
                    Container(
                      width: dot,
                      height: dot,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: scheduleColor(context, e),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An event on someone's shared calendar: its details, read-only. It has
/// no page of its own (the owner's event isn't the user's to open).
Future<void> showSharedEventSheet(BuildContext context, ScheduleEntry entry) {
  final e = entry.event;
  final owner = entry.sharedBy;
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
              if (owner != null) ...[
                const SizedBox(height: 16),
                Text(
                  "On ${owner.name}'s calendar, shared with you.",
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
