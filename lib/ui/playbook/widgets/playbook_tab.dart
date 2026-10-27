import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/play.dart';
import '../../../routing/routes.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/status_views.dart';
import '../../teams/view_models/team_detail_viewmodel.dart';
import 'play_canvas.dart';

class PlaybookTab extends StatelessWidget {
  const PlaybookTab({super.key, required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final plays = viewModel.plays;
    final canEdit = viewModel.canEdit;
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              heroTag: 'new-play',
              onPressed: () => context.go(Routes.newPlay(viewModel.teamId)),
              icon: const Icon(Icons.add),
              label: const Text('New play'),
            )
          : null,
      body: plays.isEmpty
          ? EmptyView(
              icon: Icons.draw_outlined,
              title: 'No plays yet',
              message: canEdit
                  ? 'Draw your first play on the field.'
                  : 'Your coaches haven\'t added plays yet.',
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.5,
              ),
              itemCount: plays.length,
              itemBuilder: (context, i) => _PlayCard(
                play: plays[i],
                canEdit: canEdit,
                onOpen: () =>
                    context.go(Routes.play(viewModel.teamId, plays[i].id)),
                onDelete: () async {
                  if (await confirmDialog(
                    context,
                    title: 'Delete "${plays[i].name}"?',
                    message: 'This play will be removed from the playbook.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  )) {
                    viewModel.deletePlay.execute(plays[i].id);
                  }
                },
              ),
            ),
    );
  }
}

class _PlayCard extends StatelessWidget {
  const _PlayCard({
    required this.play,
    required this.canEdit,
    required this.onOpen,
    required this.onDelete,
  });

  final Play play;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IgnorePointer(child: PlayDiagram(play: play)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          play.name.isEmpty ? 'Untitled play' : play.name,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          play.category.label,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (canEdit)
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: onDelete,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
