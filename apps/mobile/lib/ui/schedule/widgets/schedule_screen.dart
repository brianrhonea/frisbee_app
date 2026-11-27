import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/themes/theme.dart';
import '../../../domain/models/calendar.dart';
import '../../../domain/models/schedule_entry.dart';
import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/app_segmented_button.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/scoreboard.dart' show TeamDot;
import '../../core/ui/status_views.dart';
import '../view_models/schedule_viewmodel.dart';
import 'event_editor_screen.dart';
import 'schedule_widgets.dart';

/// Personal and team events a week at a time, day by day, or a month at
/// a time with the picked day's week below: the Schedule tab.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.viewModel,
    this.title = 'Schedule',
    this.profile,
    this.bottom,
  });

  final ScheduleViewModel viewModel;

  /// The app bar's title, the profile button (last of the actions, at the
  /// top right) and bottom (the Events tabs).
  final String title;
  final Widget? profile;
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

  void _onSwiped(ScheduleEntry entry, SeriesScope scope) {
    vm.removeWithUndo(entry, scope: scope);
    final what = scope == SeriesScope.following
        ? '"${entry.event.title}" and later ones'
        : '"${entry.event.title}"';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted $what'),
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
    _scrollToDay(index);
  }

  /// Picks [day] in the month grid and scrolls its week's list to it.
  void _pickMonthDay(DateTime day) {
    vm.selectDay(day);
    // After the list rebuilds for the (maybe new) week.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToDay(day.weekday - 1);
    });
  }

  void _scrollToDay(int index) {
    final target = _dayKeys[index].currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  /// Below this width "New event" is an icon, to leave the title room.
  static const _wideHeader = 480.0;

  Future<void> _newEvent() async {
    final id = await showEventEditor(context, day: vm.selectedDay);
    // Other calendars aren't live.
    if (id != null) await vm.refreshCalendars();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: widget.bottom,
        actions: [
          ListenableBuilder(
            listenable: vm,
            builder: (context, _) => vm.showsToday
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Today',
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    icon: const Icon(Icons.today_outlined),
                    onPressed: vm.goToToday,
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
          // Icon-only on phones, so the title keeps its room next to the
          // avatar and the other actions.
          Padding(
            padding: EdgeInsets.only(
              left: AppSpace.xs,
              right: widget.profile == null ? 12 : AppSpace.xs,
            ),
            child: MediaQuery.sizeOf(context).width < _wideHeader
                ? IconButton.filled(
                    tooltip: 'New event',
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    onPressed: _newEvent,
                    icon: const Icon(Icons.add),
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: _newEvent,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('New event'),
                  ),
          ),
          if (widget.profile case final profile?) ...[
            profile,
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (!vm.loaded) return const LoadingState();
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
                  _MonthHeader(viewModel: vm, onPickDay: _pickMonthDay)
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
                          // The week, or in the month the picked day's week.
                          for (final (i, day)
                              in (month ? vm.selectedWeek : vm.days).indexed)
                            _DaySection(
                              key: _dayKeys[i],
                              day: day,
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
/// amber when one needs an answer; today in turf) and the picked day's
/// week tinted, and the filter.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.viewModel, required this.onPickDay});

  final ScheduleViewModel viewModel;
  final ValueChanged<DateTime> onPickDay;

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
                    Builder(
                      builder: (context) {
                        final week = days.sublist(w * 7, w * 7 + 7);
                        final picked = week.contains(vm.selectedDay);
                        return Container(
                          key: picked ? const ValueKey('picked-week') : null,
                          decoration: BoxDecoration(
                            color: picked
                                ? c.accentSoft.withValues(alpha: 0.45)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                          ),
                          child: Row(
                            children: [
                              for (final day in week)
                                Expanded(
                                  child: _MonthDayCell(
                                    day: day,
                                    inMonth: day.month == vm.monthStart.month,
                                    isToday: day == vm.today,
                                    selected: day == vm.selectedDay,
                                    marks: vm.marksOn(day),
                                    onTap: () => onPickDay(day),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
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

/// Week / Month as a segmented control.
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
  Widget build(BuildContext context) => AppSegmentedButton<T>(
    expandedInsets: EdgeInsets.zero,
    showSelectedIcon: false,
    segments: [
      for (final v in values) ButtonSegment(value: v, label: Text(label(v))),
    ],
    selected: {selected},
    onSelectionChanged: (s) => onSelect(s.single),
  );
}

/// All / Team / Personal as a segmented control, each with its schedule
/// colour's dot.
class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.selected, required this.onSelect});

  final ScheduleFilter selected;
  final ValueChanged<ScheduleFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppSegmentedButton<ScheduleFilter>(
      expandedInsets: EdgeInsets.zero,
      showSelectedIcon: false,
      segments: [
        for (final f in ScheduleFilter.values)
          ButtonSegment(
            value: f,
            label: Text(f.label),
            icon: switch (f) {
              ScheduleFilter.all => null,
              ScheduleFilter.team => TeamDot(color: c.team),
              ScheduleFilter.personal => TeamDot(color: c.personal),
            },
          ),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onSelect(s.single),
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
  final void Function(ScheduleEntry, SeriesScope) onSwiped;

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
                    border: Border.all(color: c.border),
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
  final void Function(ScheduleEntry, SeriesScope) onSwiped;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final c = AppColors.of(context);
    var scope = SeriesScope.one;
    return Dismissible(
      key: ValueKey(entry.key),
      direction: DismissDirection.startToEnd,
      // A repeating event asks whether the later ones go too.
      confirmDismiss: entry.event.series == null
          ? null
          : (_) async {
              final picked = await askSeriesScope(
                context,
                title: 'Delete "${entry.event.title}"?',
                action: 'Delete',
              );
              if (picked != null) scope = picked;
              return picked != null;
            },
      onDismissed: (_) => onSwiped(entry, scope),
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

/// The user's calendars under the schedule, as the website's: a compact
/// card naming them, with one button to Calendars (sharing, new shared
/// calendars and Outlook, Apple or Google subscriptions).
class _CalendarsCard extends StatelessWidget {
  const _CalendarsCard({required this.calendars});

  final List<CalendarInfo> calendars;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Calendars',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  if (calendars.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        for (final cal in calendars)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TeamDot(color: cal.color.color, size: 8),
                              const SizedBox(width: 5),
                              Text(
                                cal.isMine
                                    ? cal.name
                                    : '${cal.name} · ${cal.owner.name}',
                                style: TextStyle(fontSize: 13, color: c.ink2),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Share them or see them in Outlook, Apple or Google '
                    'Calendar.',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => context.push(Routes.settingsCalendar),
              child: const Text('Manage'),
            ),
          ],
        ),
      ),
    );
  }
}
