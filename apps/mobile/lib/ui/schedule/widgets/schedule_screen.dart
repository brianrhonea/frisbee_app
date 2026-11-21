import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/themes/theme.dart';
import '../../../domain/models/calendar.dart';
import '../../../domain/models/schedule_entry.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/scoreboard.dart' show TeamDot;
import '../../core/ui/status_views.dart';
import '../view_models/schedule_viewmodel.dart';
import 'event_editor_screen.dart';
import 'schedule_widgets.dart';

/// Personal and team events a week at a time, day by day, or a month at
/// a time with the picked day's events below: the Schedule tab.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.viewModel,
    this.title = 'Schedule',
    this.leading,
    this.bottom,
  });

  final ScheduleViewModel viewModel;

  /// The app bar's title, leading widget and bottom (the Events tabs).
  final String title;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  ScheduleViewModel get vm => widget.viewModel;

  /// One key per day section, to scroll to the day picked in the strip.
  final _dayKeys = List.generate(7, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    vm.deleteEvent.addListener(_onDelete);
  }

  @override
  void dispose() {
    vm.deleteEvent.removeListener(_onDelete);
    super.dispose();
  }

  void _onDelete() {
    if (vm.deleteEvent.error) {
      showErrorSnackBar(context, vm.deleteEvent.result);
      vm.deleteEvent.clearResult();
    }
  }

  void _onSwiped(ScheduleEntry entry) {
    vm.removeWithUndo(entry);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${entry.event.title}"'),
          duration: ScheduleViewModel.undoWindow,
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => vm.undoRemove(entry),
          ),
        ),
      );
  }

  void _pickDay(int index) {
    vm.selectDay(vm.days[index]);
    final target = _dayKeys[index].currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.leading,
        title: Text(widget.title),
        bottom: widget.bottom,
        actions: [
          ListenableBuilder(
            listenable: vm,
            builder: (context, _) => vm.showsToday
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: vm.goToToday,
                    child: const Text('Today'),
                  ),
          ),
          // Sharing, new shared calendars and subscription links, one
          // tap from the schedule.
          ListenableBuilder(
            listenable: vm,
            builder: (context, _) => vm.hasCalendars
                ? IconButton(
                    tooltip: 'Calendars and sharing',
                    icon: const Icon(Icons.calendar_month_outlined),
                    onPressed: () => context.push(Routes.settingsCalendar),
                  )
                : const SizedBox.shrink(),
          ),
          // In the header rather than floating, so it never covers events.
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () async {
                final id = await showEventEditor(context, day: vm.selectedDay);
                // Other calendars aren't live.
                if (id != null) await vm.refreshCalendars();
              },
              icon: const Icon(Icons.add, size: 20),
              label: const Text('New event'),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (!vm.loaded) return const LoadingView();
          final month = vm.view == ScheduleView.month;
          return ConstrainedContent(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: _Segments<ScheduleView>(
                    values: ScheduleView.values,
                    selected: vm.view,
                    label: (v) => v.label,
                    onSelect: vm.setView,
                  ),
                ),
                if (month)
                  _MonthHeader(viewModel: vm)
                else
                  _WeekHeader(viewModel: vm, onPickDay: _pickDay),
                Expanded(
                  // Team and personal events are live; pulling down
                  // reloads the other calendars and invites.
                  child: RefreshIndicator(
                    onRefresh: vm.refreshCalendars,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final invite in vm.invites)
                            _InviteCard(invite: invite, viewModel: vm),
                          if (month)
                            _DaySection(
                              day: vm.selectedDay,
                              viewModel: vm,
                              onSwiped: _onSwiped,
                            )
                          else
                            for (var i = 0; i < 7; i++)
                              _DaySection(
                                key: _dayKeys[i],
                                day: vm.days[i],
                                viewModel: vm,
                                onSwiped: _onSwiped,
                              ),
                          if (vm.hasCalendars) ...[
                            const SizedBox(height: 16),
                            _CalendarsCard(calendars: vm.calendars),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.viewModel, required this.onPickDay});

  final ScheduleViewModel viewModel;
  final ValueChanged<int> onPickDay;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    final days = vm.days;
    final range =
        '${DateFormat.MMMd().format(days.first)} – '
        '${DateFormat.MMMd().format(days.last)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous week',
                icon: const Icon(Icons.chevron_left),
                onPressed: vm.previousWeek,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      range,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      vm.weekCount == 1 ? '1 event' : '${vm.weekCount} events',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Next week',
                icon: const Icon(Icons.chevron_right),
                onPressed: vm.nextWeek,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                children: [
                  for (var i = 0; i < days.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: WeekDayCell(
                        day: days[i],
                        entries: vm.eventsOn(days[i]),
                        isToday: days[i] == vm.today,
                        selected: days[i] == vm.selectedDay,
                        large: true,
                        onTap: () => onPickDay(i),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _FilterTabs(selected: vm.filter, onSelect: vm.setFilter),
        ],
      ),
    );
  }
}

/// The month view's header: the month with its count and arrows, the
/// grid of days with dots for what's on (team blue, personal magenta,
/// amber when one needs an answer; today in turf), and the filter.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.viewModel});

  final ScheduleViewModel viewModel;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    final days = vm.monthDays;
    final count = vm.monthCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: vm.previousMonth,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      DateFormat.yMMMM().format(vm.monthStart),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      count == 1 ? '1 event' : '$count events',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: vm.nextMonth,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final d in _weekdays)
                        Expanded(
                          child: Text(
                            d,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (var w = 0; w < days.length ~/ 7; w++)
                    Row(
                      children: [
                        for (final day in days.sublist(w * 7, w * 7 + 7))
                          Expanded(
                            child: _MonthDayCell(
                              day: day,
                              inMonth: day.month == vm.monthStart.month,
                              isToday: day == vm.today,
                              selected: day == vm.selectedDay,
                              marks: vm.marksOn(day),
                              onTap: () => vm.selectDay(day),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _FilterTabs(selected: vm.filter, onSelect: vm.setFilter),
        ],
      ),
    );
  }
}

/// One day in the month grid: its number (turf on today, outlined when
/// picked, faint outside the month) over its dots.
class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.selected,
    required this.marks,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool selected;
  final DayMarks marks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dots = [
      if (marks.team) c.team,
      if (marks.personal) c.personal,
      if (marks.needsRsvp) c.highlight,
    ];
    final fg = isToday
        ? c.onAccent
        : selected
        ? c.accentInk
        : inMonth
        ? c.ink
        : c.muted.withValues(alpha: 0.6);
    return Semantics(
      button: true,
      selected: selected,
      label: DateFormat.MMMMEEEEd().format(day),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday
                      ? c.accent
                      : selected
                      ? c.accentSoft
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: selected && !isToday
                      ? Border.all(color: c.accent, width: 1.5)
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isToday || selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final (i, color) in dots.indexed) ...[
                      if (i > 0) const SizedBox(width: 3),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Week / Month as a segmented track.
class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelect,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: Semantics(
                selected: v == selected,
                button: true,
                child: Material(
                  color: v == selected ? c.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(controlRadius - 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(controlRadius - 2),
                    onTap: () => onSelect(v),
                    child: SizedBox(
                      height: 34,
                      child: Center(
                        child: Text(
                          label(v),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: v == selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: v == selected ? c.ink : c.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// All / Team / Personal as a segmented track, each with its schedule
/// colour's dot.
class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.selected, required this.onSelect});

  final ScheduleFilter selected;
  final ValueChanged<ScheduleFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget tab(ScheduleFilter f) {
      final on = f == selected;
      final dot = switch (f) {
        ScheduleFilter.all => null,
        ScheduleFilter.team => c.team,
        ScheduleFilter.personal => c.personal,
      };
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: Material(
            color: on ? c.card : Colors.transparent,
            borderRadius: BorderRadius.circular(controlRadius - 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(controlRadius - 2),
              onTap: () => onSelect(f),
              child: SizedBox(
                height: 38,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (dot != null) ...[
                      TeamDot(color: dot),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        f.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                          color: on ? c.ink : c.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      child: Row(children: [for (final f in ScheduleFilter.values) tab(f)]),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    super.key,
    required this.day,
    required this.viewModel,
    required this.onSwiped,
  });

  final DateTime day;
  final ScheduleViewModel viewModel;
  final ValueChanged<ScheduleEntry> onSwiped;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final events = vm.eventsOn(day);
    final isToday = day == vm.today;
    final selected = day == vm.selectedDay;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                DateFormat('EEEE, MMM d').format(day).toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: selected && !isToday ? c.accentInk : c.ink2,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: c.feature,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'TODAY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: c.onFeature,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: events.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Nothing scheduled',
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < events.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _SwipeToDelete(
                          entry: events[i],
                          enabled: vm.canDelete(events[i]),
                          onSwiped: onSwiped,
                          child: ScheduleEventRow(
                            entry: events[i],
                            showDay: false,
                            large: true,
                            rsvp: vm.myRsvp(events[i]),
                            needsRsvp: vm.needsRsvp(events[i]),
                            onCalendarChanged: vm.refreshCalendars,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Swipe right to delete, for events the user may delete. Others render
/// [child] as is, so they can't be swiped.
class _SwipeToDelete extends StatelessWidget {
  const _SwipeToDelete({
    required this.entry,
    required this.enabled,
    required this.onSwiped,
    required this.child,
  });

  final ScheduleEntry entry;
  final bool enabled;
  final ValueChanged<ScheduleEntry> onSwiped;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final c = AppColors.of(context);
    return Dismissible(
      key: ValueKey(entry.key),
      direction: DismissDirection.startToEnd,
      onDismissed: (_) => onSwiped(entry),
      // Neutral, not red: red is only for live games.
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: c.field,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: c.ink2),
            const SizedBox(width: 8),
            Text(
              'Delete',
              style: TextStyle(color: c.ink2, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// An invite to someone's calendar: nothing is shared until it's accepted.
class _InviteCard extends StatefulWidget {
  const _InviteCard({required this.invite, required this.viewModel});

  final CalendarInvite invite;
  final ScheduleViewModel viewModel;

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  bool _busy = false;

  Future<void> _answer(bool accept) async {
    setState(() => _busy = true);
    final r = await widget.viewModel.answerInvite(widget.invite, accept);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r is Error) showErrorSnackBar(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.invite;
    final c = AppColors.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TeamDot(color: i.color.color, size: 12),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${i.from.name} invited you to ${i.calendarName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              i.role == CalendarRole.edit
                  ? 'You could see and add events.'
                  : 'You could see its events.',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => context.push(Routes.settingsCalendar),
                  child: const Text('Calendars'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _answer(false),
                  child: const Text('Decline'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _answer(true),
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The user's calendars under the schedule, as the website's: each with
/// who owns it, and the way to share one, start a shared one or see the
/// schedule in Outlook, Apple or Google Calendar (all on Calendars).
class _CalendarsCard extends StatelessWidget {
  const _CalendarsCard({required this.calendars});

  final List<CalendarInfo> calendars;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    void open() => context.push(Routes.settingsCalendar);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Calendars',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(onPressed: open, child: const Text('Manage')),
              ],
            ),
            for (final cal in calendars)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    TeamDot(color: cal.color.color, size: 10),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: cal.name,
                          children: [
                            if (!cal.isMine)
                              TextSpan(
                                text:
                                    '  ·  ${cal.owner.name}  ·  '
                                    '${cal.role.label}',
                                style: TextStyle(color: c.muted, fontSize: 13),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: open,
                  icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                  label: const Text('Share a calendar'),
                ),
                OutlinedButton.icon(
                  onPressed: open,
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Outlook, Apple or Google'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
