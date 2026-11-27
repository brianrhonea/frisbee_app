import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart' show DateBadge;
import '../../core/ui/scoreboard.dart' show TeamDot;
import '../../core/ui/status_views.dart';
import '../../teams/view_models/team_detail_viewmodel.dart';
import 'event_detail_screen.dart';
import 'event_editor_screen.dart';
import 'event_style.dart';
import 'rsvp_widgets.dart';

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
  /// the date on a calendar. With Meetings off (Settings › Sections), New
  /// adds an event straight away.
  Future<void> _add() async {
    if (!vm.meetingsOn) {
      await showEventEditor(context, teamId: vm.teamId);
      return;
    }
    final route = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: AppMotion.sheetStyle(context),
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
    if (route == null || !mounted) return;
    if (route == Routes.newEvent(vm.teamId)) {
      await showEventEditor(context, teamId: vm.teamId);
    } else {
      context.push(route);
    }
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
    // Members only, once the team is loaded and has Meetings on.
    final showMeetings = vm.myRole != null && vm.meetingsOn;
    return Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // In the list rather than floating, so it never covers an
              // event.
              // The Meetings list (F17), when the team has Meetings on.
              if (vm.canEdit || showMeetings)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (showMeetings)
                      TextButton.icon(
                        onPressed: () =>
                            context.push(Routes.teamMeetings(vm.teamId)),
                        icon: const Icon(Icons.videocam_outlined, size: 18),
                        label: const Text('Meetings'),
                      ),
                    if (vm.canEdit) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _add,
                        icon: const Icon(Icons.add),
                        label: const Text('New'),
                      ),
                    ],
                  ],
                ),
              if (upcoming.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: EmptyState(
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
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w800,
        color: AppColors.of(context).muted,
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
    child: TeamEventTile(event: event, uid: uid, onTap: onTap),
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
    final c = AppColors.of(context);
    final e = event;
    final mine = e.rsvpOf(uid);
    final going = e.responders(RsvpStatus.going).length;
    final upcoming = (e.endsAt ?? e.startsAt).isAfter(DateTime.now());
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            DateBadge(date: e.startsAt, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TeamDot(color: c.team, size: 7),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          e.type.label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: c.team,
                          ),
                        ),
                      ),
                      if (e.isPublic && showResponses) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Shown on the public team page',
                          child: Icon(Icons.public, size: 14, color: c.muted),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      DateFormat.E().format(e.startsAt),
                      eventTimeRange(e),
                      if (e.location.isNotEmpty) e.location,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ],
              ),
            ),
            if (showResponses) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RsvpStatusPill(
                    status: mine,
                    type: e.type,
                    needsRsvp: upcoming,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$going going',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
