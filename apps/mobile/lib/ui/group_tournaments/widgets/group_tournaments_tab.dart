import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart' show DateBadge;
import '../../tournaments/widgets/tournament_parts.dart'
    show Pill, PillTone, RowsCard;
import '../view_models/group_tournaments_viewmodel.dart';
import 'hat_parts.dart';
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
        final c = AppColors.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HatHeading(
              'Hat tournaments',
              top: 24,
              trailing: vm.isOrganizer
                  ? TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: c.accent),
                      onPressed: () =>
                          context.push(Routes.newGroupTournament(vm.groupId)),
                      icon: const Icon(Icons.add),
                      label: const Text('New'),
                    )
                  : null,
            ),
            if (vm.tournaments.isEmpty)
              Text(
                'Teams made from who RSVPs to a Tournament event: import '
                "who's coming, make teams and generate the schedule.",
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            if (vm.tournaments.isNotEmpty)
              RowsCard(
                children: [
                  for (final t in vm.tournaments)
                    InkWell(
                      onTap: () => context.push(
                        t.status == TournamentStatus.setup && vm.isOrganizer
                            ? Routes.editGroupTournament(vm.groupId, t.id)
                            : Routes.groupTournament(vm.groupId, t.id),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                        child: Row(
                          children: [
                            DateBadge(date: t.settings.startsAt, size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.name,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: c.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${tournamentWhen(t.settings.startsAt)}\n'
                                    '${t.settings.format.label} · '
                                    '${t.teams.length} teams',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: c.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Pill(
                              tournamentStatusLabel(t),
                              tone: t.status == TournamentStatus.scheduled
                                  ? PillTone.turf
                                  : PillTone.neutral,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}
