import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../routing/routes.dart';
import '../view_models/group_tournaments_viewmodel.dart';
import 'tournament_widgets.dart';

/// A group's hat tournaments (teams made from event RSVPs), listed under
/// its hosted tournaments in the Tournaments section.
class HatTournamentsList extends StatelessWidget {
  const HatTournamentsList({super.key, required this.viewModel});

  final GroupTournamentsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        if (!vm.loaded || (vm.tournaments.isEmpty && !vm.isOrganizer)) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hat tournaments',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (vm.isOrganizer)
                    TextButton.icon(
                      onPressed: () =>
                          context.push(Routes.newGroupTournament(vm.groupId)),
                      icon: const Icon(Icons.add),
                      label: const Text('New'),
                    ),
                ],
              ),
            ),
            if (vm.tournaments.isEmpty)
              Text(
                'Teams made from who RSVPs to a Tournament event: import '
                "who's coming, make teams and generate the schedule.",
                style: theme.textTheme.bodySmall,
              ),
            for (final t in vm.tournaments)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.shuffle)),
                  title: Text(t.name),
                  subtitle: Text(
                    '${tournamentWhen(t.settings.startsAt)}\n'
                    '${t.settings.format.label} · ${t.teams.length} teams',
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
        );
      },
    );
  }
}
