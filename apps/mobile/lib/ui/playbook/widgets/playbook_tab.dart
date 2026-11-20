import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/play.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/status_views.dart';
import '../../teams/view_models/team_detail_viewmodel.dart';
import 'play_canvas.dart';

class PlaybookTab extends StatelessWidget {
  const PlaybookTab({super.key, required this.viewModel});

  final TeamDetailViewModel viewModel;

  Future<void> _delete(BuildContext context, Play play) async {
    if (await confirmDialog(
      context,
      title: 'Delete "${play.name}"?',
      message: 'This play will be removed from the playbook.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      viewModel.deletePlay.execute(play.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plays = viewModel.plays;
    final canEdit = viewModel.canEdit;
    // The playbook in sections, one per category, in the category order.
    final sections = [
      for (final category in PlayCategory.values)
        (
          category,
          [
            for (final p in plays)
              if (p.category == category) p,
          ],
        ),
    ].where((s) => s.$2.isNotEmpty);
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
          : CustomScrollView(
              slivers: [
                for (final (category, list) in sections) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: _SectionTitle(
                        title: category.label,
                        count: list.length,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.1,
                          ),
                      itemCount: list.length,
                      itemBuilder: (context, i) => _PlayCard(
                        play: list[i],
                        canEdit: canEdit,
                        onOpen: () => context.go(
                          Routes.play(viewModel.teamId, list[i].id),
                        ),
                        onDelete: () => _delete(context, list[i]),
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
    );
  }
}

/// A category's heading with its number of plays on the right.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: c.ink,
              ),
            ),
          ),
        ),
        Text(
          count == 1 ? '1 play' : '$count plays',
          style: TextStyle(fontSize: 13, color: c.muted),
        ),
      ],
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
    final c = AppColors.of(context);
    final steps = play.steps.length;
    return Material(
      color: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The field lies on its side to fill the wide thumbnail; the
            // grass behind it makes the margins part of the picture.
            Expanded(
              child: ColoredBox(
                color: FieldColors.grass,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: IgnorePointer(child: PlayDiagram(play: play)),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, canEdit ? 0 : 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          play.name.isEmpty ? 'Untitled play' : play.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            play.category.label,
                            if (steps > 0)
                              steps == 1 ? '1 step' : '$steps steps',
                          ].join(' · '),
                          style: TextStyle(fontSize: 12, color: c.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (canEdit)
                    IconButton(
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                      color: c.muted,
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
