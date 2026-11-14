import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/themes/theme.dart';
import '../../../domain/models/calendar.dart';
import '../../../domain/models/schedule_entry.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/schedule_viewmodel.dart';
import 'event_editor_screen.dart';
import 'schedule_widgets.dart';

/// A week of personal and team events, day by day: the Events tab's
/// schedule.
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
            builder: (context, _) => vm.isCurrentWeek
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: vm.goToToday,
                    child: const Text('Today'),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-schedule-event',
        onPressed: () async {
          final id = await showEventEditor(context, day: vm.selectedDay);
          // Other calendars aren't live.
          if (id != null) await vm.refreshCalendars();
        },
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (!vm.loaded) return const LoadingView();
          return ConstrainedContent(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WeekHeader(viewModel: vm, onPickDay: _pickDay),
                const Divider(height: 1),
                Expanded(
                  // Team and personal events are live; pulling down
                  // reloads the other calendars and invites.
                  child: RefreshIndicator(
                    onRefresh: vm.refreshCalendars,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final invite in vm.invites)
                            _InviteCard(invite: invite, viewModel: vm),
                          for (var i = 0; i < 7; i++)
                            _DaySection(
                              key: _dayKeys[i],
                              day: vm.days[i],
                              viewModel: vm,
                              onSwiped: _onSwiped,
                            ),
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
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
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
                      style: Theme.of(context).textTheme.titleMedium,
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
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < days.length; i++)
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
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              SegmentedButton<ScheduleFilter>(
                segments: [
                  for (final f in ScheduleFilter.values)
                    ButtonSegment(value: f, label: Text(f.label)),
                ],
                selected: {vm.filter},
                showSelectedIcon: false,
                onSelectionChanged: (s) => vm.setFilter(s.first),
              ),
              const ScheduleLegend(),
            ],
          ),
        ],
      ),
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
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: selected || isToday ? c.accent : c.muted,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Text(
                  'TODAY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: c.accent,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Card(
            child: events.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Nothing scheduled',
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final e in events)
                          _SwipeToDelete(
                            entry: e,
                            enabled: vm.canDelete(e),
                            onSwiped: onSwiped,
                            child: ScheduleEventRow(
                              entry: e,
                              showTeamName: vm.teams.length > 1,
                              showDay: false,
                              large: true,
                              onCalendarChanged: vm.refreshCalendars,
                            ),
                          ),
                      ],
                    ),
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
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(entry.key),
      direction: DismissDirection.startToEnd,
      onDismissed: (_) => onSwiped(entry),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: scheme.onError),
            const SizedBox(width: 8),
            Text(
              'Delete',
              style: TextStyle(
                color: scheme.onError,
                fontWeight: FontWeight.w700,
              ),
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
                Icon(Icons.circle, size: 12, color: i.color.color),
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
