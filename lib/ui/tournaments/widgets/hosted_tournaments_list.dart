import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../routing/routes.dart';
import '../../core/ui/status_views.dart';
import '../view_models/hosted_tournaments_viewmodel.dart';
import 'hosted_tournament_screen.dart';

/// One tournament in a list.
class HostedTournamentCard extends StatelessWidget {
  const HostedTournamentCard({
    super.key,
    required this.tournament,
    this.showHost = true,
  });

  final HostedTournament tournament;
  final bool showHost;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final divisions = t.divisions.map((d) => d.label).join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.emoji_events_outlined)),
        title: Text(t.name),
        subtitle: Text(
          [
            [hostedDates(t), if (t.location.isNotEmpty) t.location].join(' · '),
            [
              if (showHost) t.hostName,
              if (divisions.isNotEmpty) divisions,
              if (t.visibility == TournamentVisibility.inviteOnly)
                'Invite only',
              if (t.bidFee case final f?) '${f.label} bid',
            ].join(' · '),
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: Chip(label: Text(t.status.label)),
        onTap: () => context.push(Routes.tournament(t.id)),
      ),
    );
  }
}

/// A host's tournaments, as a section of its page. Managers host new
/// ones here and see drafts.
class HostedTournamentsSection extends StatelessWidget {
  const HostedTournamentsSection({
    super.key,
    required this.viewModel,
    this.footer = const [],
  });

  final HostedTournamentsViewModel viewModel;

  /// More below the list (a group's hat tournaments).
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final fab = vm.canHost
            ? FloatingActionButton.extended(
                heroTag: 'host-tournament',
                onPressed: () => context.push(Routes.newTournament(vm.hostId!)),
                icon: const Icon(Icons.add),
                label: const Text('Host a tournament'),
              )
            : null;
        final Widget body;
        if (!vm.loaded) {
          body = const LoadingView();
        } else if (vm.error != null) {
          body = ErrorView(error: vm.error);
        } else {
          body = ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (vm.playingIn.isNotEmpty) ...[
                  const _Heading('Playing in'),
                  for (final e in vm.playingIn) _EnteredCard(entry: e),
                  if (vm.tournaments.isNotEmpty || vm.canHost)
                    const _Heading('Hosted here'),
                ],
                if (vm.tournaments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      vm.canHost
                          ? 'Host a tournament: pick divisions, set a bid fee, '
                                'take applications or invite teams, seed them '
                                'and publish the schedule.'
                          : 'No tournaments hosted here yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final t in vm.tournaments)
                  HostedTournamentCard(tournament: t, showHost: false),
                ...footer,
              ],
            ),
          );
        }
        return Scaffold(floatingActionButton: fab, body: body);
      },
    );
  }
}

/// Upcoming tournaments anyone can find, apply to or follow.
class FindTournamentsScreen extends StatelessWidget {
  const FindTournamentsScreen({super.key, required this.viewModel});

  final HostedTournamentsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Scaffold(
      appBar: AppBar(title: const Text('Tournaments')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (!vm.loaded) return const LoadingView();
          if (vm.error != null) return ErrorView(error: vm.error);
          return ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name, host or place',
                  ),
                  onChanged: vm.setQuery,
                ),
                const SizedBox(height: 12),
                if (vm.tournaments.isEmpty)
                  const EmptyView(
                    icon: Icons.emoji_events_outlined,
                    title: 'No upcoming tournaments',
                    message:
                        'Teams, groups and schools/clubs host tournaments '
                        'from their Tournaments section.',
                  ),
                for (final t in vm.tournaments)
                  HostedTournamentCard(tournament: t),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// A tournament the team entered: its dates, where, and where the entry
/// stands (Accepted, Applied, Invited, Waitlist).
class _EnteredCard extends StatelessWidget {
  const _EnteredCard({required this.entry});

  final EnteredTournament entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final scheme = Theme.of(context).colorScheme;
    final accepted = e.status == EntryStatus.accepted;
    final when = switch ((e.startsOn, e.endsOn)) {
      (final s?, final end?) when !DateUtils.isSameDay(s, end) =>
        '${DateFormat.MMMd().format(s)} – ${DateFormat.MMMd().format(end)}',
      (final s?, _) => DateFormat.yMMMd().format(s),
      _ => '',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.emoji_events_outlined)),
        title: Text(e.name),
        subtitle: Text(
          [
            [
              when,
              if (e.location.isNotEmpty) e.location,
            ].where((x) => x.isNotEmpty).join(' · '),
            if (e.hostName.isNotEmpty) 'Hosted by ${e.hostName}',
          ].where((x) => x.isNotEmpty).join('\n'),
        ),
        trailing: Chip(
          label: Text(e.status.label),
          backgroundColor: accepted ? scheme.primaryContainer : null,
          visualDensity: VisualDensity.compact,
        ),
        onTap: () => context.push(Routes.tournament(e.tournamentId)),
      ),
    );
  }
}
