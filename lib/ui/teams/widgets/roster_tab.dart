import 'package:flutter/material.dart';

import '../../../domain/models/roster_player.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/status_views.dart';
import '../view_models/team_detail_viewmodel.dart';
import 'player_dialog.dart';

class RosterTab extends StatelessWidget {
  const RosterTab({super.key, required this.viewModel});

  final TeamDetailViewModel viewModel;

  Future<void> _edit(BuildContext context, [RosterPlayer? player]) async {
    final result = await showDialog<RosterPlayer>(
      context: context,
      builder: (_) => PlayerDialog(initial: player),
    );
    if (result != null) viewModel.savePlayer.execute(result);
  }

  Future<void> _delete(BuildContext context, RosterPlayer player) async {
    if (await confirmDialog(
      context,
      title: 'Remove ${player.name}?',
      message: 'They will be removed from the roster.',
      confirmLabel: 'Remove',
      destructive: true,
    )) {
      viewModel.deletePlayer.execute(player.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roster = viewModel.roster;
    final canEdit = viewModel.canEdit;
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              heroTag: 'add-player',
              onPressed: () => _edit(context),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add player'),
            )
          : null,
      body: roster.isEmpty
          ? EmptyView(
              icon: Icons.badge_outlined,
              title: 'No players on the roster',
              message: canEdit ? 'Add players to build your roster.' : null,
            )
          : ConstrainedContent(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                itemCount: roster.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final p = roster[i];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(p.number?.toString() ?? '–'),
                    ),
                    title: Text(p.name),
                    subtitle: Text(p.position.label),
                    onTap: canEdit ? () => _edit(context, p) : null,
                    trailing: canEdit
                        ? IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(context, p),
                          )
                        : null,
                  );
                },
              ),
            ),
    );
  }
}
