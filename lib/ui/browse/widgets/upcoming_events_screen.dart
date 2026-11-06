import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/browse.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../schedule/widgets/event_style.dart';
import '../view_models/upcoming_events_viewmodel.dart';
import 'browse_widgets.dart';

/// What's coming up on Stall 10: group tournaments and teams' public
/// events (pickup, tryouts, socials…), for everyone.
class UpcomingEventsScreen extends StatelessWidget {
  const UpcomingEventsScreen({super.key, required this.viewModel});

  final UpcomingEventsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => BrowsePage(
        eyebrow: 'Events',
        title: "What's coming up",
        subtitle:
            'Tournaments, pickup, tryouts and more from teams and '
            'groups on Stall 10.',
        load: vm.load,
        loaded: vm.load.completed,
        children: [
          if (vm.isEmpty)
            const EmptyView(
              icon: Icons.event_outlined,
              title: 'Nothing coming up yet',
              message: 'Public events from teams and groups show up here.',
            ),
          if (vm.upcoming.tournaments.isNotEmpty)
            SectionCard(
              title: 'Tournaments',
              child: Column(
                children: [
                  for (final t in vm.upcoming.tournaments)
                    _TournamentRow(tournament: t),
                ],
              ),
            ),
          if (vm.upcoming.events.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Team events',
              child: Column(
                children: [
                  for (final e in vm.upcoming.events) _EventRow(event: e),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TournamentRow extends StatelessWidget {
  const _TournamentRow({required this.tournament});

  final TournamentListing tournament;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final c = AppColors.of(context);
    final day = DateFormat.MMMd();
    final dates = t.endsOn == null
        ? DateFormat('EEE, MMM d').format(t.startsAt)
        : '${day.format(t.startsAt)} – ${day.format(t.endsOn!)}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: DateBadge(date: t.startsAt),
      title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(dates, style: TextStyle(color: c.muted)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(Routes.team(t.groupId)),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final PublicEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event.event;
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: DateBadge(date: e.startsAt),
      title: Row(
        children: [
          Icon(e.type.icon, size: 16, color: e.type.color(scheme)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              e.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      subtitle: Text(
        [
          event.teamName,
          eventWhen(e.startsAt),
          if (e.location.isNotEmpty) e.location,
        ].join(' · '),
        style: TextStyle(color: c.muted),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(Routes.team(event.teamId)),
    );
  }
}
