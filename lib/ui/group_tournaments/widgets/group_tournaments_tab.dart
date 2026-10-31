import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../routing/routes.dart';
import '../../core/ui/status_views.dart';
import '../view_models/group_tournaments_viewmodel.dart';
import 'tournament_widgets.dart';

/// A group's tournaments. Organizers start new ones here.
class GroupTournamentsTab extends StatelessWidget {
  const GroupTournamentsTab({super.key, required this.viewModel});

  final GroupTournamentsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final fab = vm.isOrganizer
            ? FloatingActionButton.extended(
                onPressed: () =>
                    context.push(Routes.newGroupTournament(vm.groupId)),
                icon: const Icon(Icons.add),
                label: const Text('New tournament'),
              )
            : null;
        final Widget body;
        if (!vm.loaded) {
          body = const LoadingView();
        } else if (vm.error != null) {
          body = ErrorView(error: vm.error);
        } else if (vm.tournaments.isEmpty) {
          body = EmptyView(
            icon: Icons.emoji_events_outlined,
            title: 'No tournaments yet',
            message: vm.isOrganizer
                ? 'Post a Tournament event so people can RSVP, then set up '
                      'the tournament: import who is coming, make teams and '
                      'generate the schedule.'
                : "Tournaments you're playing in show up here once "
                      'organizers put you on a team.',
          );
        } else {
          body = ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final t in vm.tournaments)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.emoji_events_outlined),
                      ),
                      title: Text(t.name),
                      subtitle: Text(
                        '${tournamentWhen(t.settings.startsAt)}\n'
                        '${t.settings.format.label} · '
                        '${t.teams.length} teams',
                      ),
                      isThreeLine: true,
                      trailing: Chip(label: Text(tournamentStatusLabel(t))),
                      onTap: () => context.push(
                        t.status == TournamentStatus.setup && vm.isOrganizer
                            ? Routes.editGroupTournament(vm.groupId, t.id)
                            : Routes.groupTournament(vm.groupId, t.id),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }
        return Scaffold(floatingActionButton: fab, body: body);
      },
    );
  }
}
