import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../core/ui/status_views.dart';
import '../../teams/view_models/team_detail_viewmodel.dart';
import 'event_detail_screen.dart';
import 'event_style.dart';

/// Opens [e] over the current page: an event's details and RSVP in a
/// popup, a meeting on its own page.
void openTeamEvent(BuildContext context, String teamId, TeamEvent e) {
  if (e.type == EventType.meeting) {
    context.push(Routes.teamEvent(teamId, e));
  } else {
    showEventDetails(context, teamId: teamId, eventId: e.id);
  }
}

/// Team Events: cards for what's coming up, soonest first and grouped by
/// month, then past events on request. Tapping one opens its details.
class TeamEventsTab extends StatefulWidget {
  const TeamEventsTab({super.key, required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  State<TeamEventsTab> createState() => _TeamEventsTabState();
}

class _TeamEventsTabState extends State<TeamEventsTab> {
  bool _showPast = false;

  TeamDetailViewModel get vm => widget.viewModel;

  /// Events and meetings are added from the same button. Their editors pick
  /// the date on a calendar.
  Future<void> _add() async {
    final route = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Event'),
              subtitle: const Text('Practice, game, social…'),
              onTap: () => Navigator.pop(context, Routes.newEvent(vm.teamId)),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Meeting'),
              subtitle: const Text('A video call for the team or some of it'),
              onTap: () => Navigator.pop(context, Routes.newMeeting(vm.teamId)),
            ),
          ],
        ),
      ),
    );
    if (route != null && mounted) context.push(route);
  }

  /// [events] as cards under a heading for each month.
  List<Widget> _byMonth(List<TeamEvent> events) {
    final out = <Widget>[];
    String? month;
    for (final e in events) {
      final m = DateFormat.yMMMM().format(e.startsAt);
      if (m != month) {
        month = m;
        out.add(_Heading(m));
      }
      out.add(
        TeamEventCard(
          event: e,
          uid: vm.uid,
          onTap: () => openTeamEvent(context, vm.teamId, e),
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = vm.upcomingEvents;
    final past = vm.pastEvents;
    return Scaffold(
      floatingActionButton: vm.canEdit
          ? FloatingActionButton.extended(
              heroTag: 'new-event',
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('New'),
            )
          : null,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (upcoming.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: EmptyView(
                    icon: Icons.event_available_outlined,
                    title: 'Nothing scheduled',
                    message: vm.canEdit
                        ? 'Add practices, games, socials and meetings so the '
                              'team can RSVP.'
                        : "Nothing's been scheduled yet.",
                  ),
                )
              else
                ..._byMonth(upcoming),
              if (past.isNotEmpty) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showPast = !_showPast),
                    icon: Icon(
                      _showPast ? Icons.expand_less : Icons.history,
                      size: 18,
                    ),
                    label: Text(
                      _showPast
                          ? 'Hide past events'
                          : 'Show past events (${past.length})',
                    ),
                  ),
                ),
                if (_showPast) ..._byMonth(past),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        letterSpacing: 1,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// [TeamEventTile] on a card, for the Events tab's list.
class TeamEventCard extends StatelessWidget {
  const TeamEventCard({
    super.key,
    required this.event,
    required this.uid,
    required this.onTap,
  });

  final TeamEvent event;
  final String uid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TeamEventTile(event: event, uid: uid, onTap: onTap),
    ),
  );
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
