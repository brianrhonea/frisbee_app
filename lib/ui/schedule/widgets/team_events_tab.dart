import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../core/ui/status_views.dart';
import '../../teams/view_models/team_detail_viewmodel.dart';
import 'event_style.dart';

/// Team Events: a month calendar plus the selected day's (or upcoming) events.
class TeamEventsTab extends StatefulWidget {
  const TeamEventsTab({super.key, required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  State<TeamEventsTab> createState() => _TeamEventsTabState();
}

class _TeamEventsTabState extends State<TeamEventsTab> {
  // Ephemeral view state: which month is shown and which day is picked.
  DateTime _month = _thisMonth();
  DateTime? _selected;

  TeamDetailViewModel get vm => widget.viewModel;

  static DateTime _thisMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  void _select(DateTime day) => setState(
    () => _selected = _selected != null && DateUtils.isSameDay(_selected, day)
        ? null
        : day,
  );

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final events = selected == null ? vm.upcomingEvents : vm.eventsOn(selected);
    final calendar = _MonthCalendar(
      month: _month,
      selected: selected,
      events: vm.events,
      onPrev: () => _shiftMonth(-1),
      onNext: () => _shiftMonth(1),
      onToday: () => setState(() {
        _month = _thisMonth();
        _selected = DateUtils.dateOnly(DateTime.now());
      }),
      onSelect: _select,
    );
    final header = _ListHeader(
      title: selected == null
          ? 'Upcoming'
          : DateFormat.MMMMEEEEd().format(selected),
      onClear: selected == null ? null : () => setState(() => _selected = null),
    );
    final empty = EmptyView(
      icon: Icons.event_available_outlined,
      title: selected == null ? 'Nothing scheduled' : 'No events this day',
      message: vm.canEdit
          ? 'Add practices, games and socials so the team can RSVP.'
          : "Your coaches haven't scheduled anything yet.",
    );
    final tiles = [
      for (final e in events)
        TeamEventTile(
          event: e,
          uid: vm.uid,
          onTap: () => context.push(Routes.event(vm.teamId, e.id)),
        ),
    ];

    return Scaffold(
      floatingActionButton: vm.canEdit
          ? FloatingActionButton.extended(
              heroTag: 'new-event',
              onPressed: () =>
                  context.push(Routes.newEvent(vm.teamId, day: selected)),
              icon: const Icon(Icons.add),
              label: const Text('New event'),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth >= 840) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 400,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: calendar,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      header,
                      Expanded(
                        child: tiles.isEmpty
                            ? empty
                            : ListView(
                                padding: const EdgeInsets.only(bottom: 96),
                                children: tiles,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(padding: const EdgeInsets.all(12), child: calendar),
              header,
              if (tiles.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: empty,
                )
              else
                ...tiles,
            ],
          );
        },
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.title, this.onClear});

  final String title;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
    child: SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (onClear != null)
            TextButton(onPressed: onClear, child: const Text('Show upcoming')),
        ],
      ),
    ),
  );
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.selected,
    required this.events,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onSelect,
  });

  /// First day of the displayed month.
  final DateTime month;
  final DateTime? selected;
  final List<TeamEvent> events;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final firstDow = loc.firstDayOfWeekIndex; // 0 = Sunday
    final leading = (month.weekday % 7 - firstDow + 7) % 7;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final today = DateUtils.dateOnly(DateTime.now());

    final byDay = <int, List<TeamEvent>>{};
    for (final e in events) {
      if (e.startsAt.year == month.year && e.startsAt.month == month.month) {
        (byDay[e.startsAt.day] ??= []).add(e);
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat.yMMMM().format(month),
                style: theme.textTheme.titleLarge,
              ),
            ),
            TextButton(onPressed: onToday, child: const Text('Today')),
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: onPrev,
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: onNext,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    loc.narrowWeekdays[(i + firstDow) % 7],
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < leading; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++)
              _DayCell(
                day: d,
                isToday: DateUtils.isSameDay(
                  DateTime(month.year, month.month, d),
                  today,
                ),
                isSelected: DateUtils.isSameDay(
                  DateTime(month.year, month.month, d),
                  selected,
                ),
                events: byDay[d] ?? const [],
                onTap: () => onSelect(DateTime(month.year, month.month, d)),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.events,
    required this.onTap,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final List<TeamEvent> events;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSelected ? scheme.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isToday && !isSelected
              ? BorderSide(color: scheme.primary, width: 1.5)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                  fontWeight: events.isEmpty ? null : FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final e in events.take(3))
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? scheme.onPrimary
                              : e.type.color(scheme),
                        ),
                      ),
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

/// A team event in a list: date badge, title, time and place, and the
/// member's RSVP. Public events are marked with a globe.
class TeamEventTile extends StatelessWidget {
  const TeamEventTile({
    super.key,
    required this.event,
    required this.uid,
    required this.onTap,
    this.showResponses = true,
  });

  final TeamEvent event;
  final String uid;
  final VoidCallback onTap;

  /// RSVP prompt and head count; off on the public page, which has none.
  final bool showResponses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = event;
    final color = e.type.color(scheme);
    final mine = e.rsvpOf(uid);
    final going = e.responders(RsvpStatus.going).length;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat.MMM().format(e.startsAt).toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${e.startsAt.day}',
              style: theme.textTheme.titleMedium?.copyWith(height: 1.1),
            ),
          ],
        ),
      ),
      title: Row(
        children: [
          Icon(e.type.icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (e.isPublic && showResponses)
            Tooltip(
              message: 'Shown on the public team page',
              child: Icon(Icons.public, size: 16, color: scheme.outline),
            ),
        ],
      ),
      subtitle: Text(
        [
          DateFormat.E().format(e.startsAt),
          eventTimeRange(e),
          if (e.location.isNotEmpty) e.location,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: !showResponses
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (mine != null)
                  Icon(mine.icon, size: 20, color: mine.color(scheme))
                else
                  Text(
                    'RSVP',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text('$going going', style: theme.textTheme.bodySmall),
              ],
            ),
    );
  }
}
