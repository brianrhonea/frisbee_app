import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/play.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/app_segmented_button.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/status_views.dart';
import '../../teams/view_models/team_detail_viewmodel.dart';
import 'play_canvas.dart';

/// The playbook's two views: the team's plays, or the whiteboard.
enum PlaybookView { plays, whiteboard }

class PlaybookTab extends StatefulWidget {
  const PlaybookTab({super.key, required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  State<PlaybookTab> createState() => _PlaybookTabState();
}

class _PlaybookTabState extends State<PlaybookTab> {
  // Which view is showing is view state, like a tab.
  PlaybookView _view = PlaybookView.plays;

  TeamDetailViewModel get viewModel => widget.viewModel;

  Future<void> _delete(BuildContext context, Play play) async {
    if (await confirmDialog(
      context,
      title: 'Delete "${play.name}"?',
      message: play.isWhiteboard
          ? 'This whiteboard will be removed from the playbook.'
          : 'This play will be removed from the playbook.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      viewModel.deletePlay.execute(play.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = viewModel.canEdit;
    final plays = _view == PlaybookView.plays;
    return Scaffold(
      floatingActionButton: canEdit && plays
          ? FloatingActionButton.extended(
              heroTag: 'new-play',
              onPressed: () => context.go(Routes.newPlay(viewModel.teamId)),
              icon: const Icon(Icons.add),
              label: const Text('New play'),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _ViewSwitch(
                view: _view,
                onChanged: (v) => setState(() => _view = v),
              ),
            ),
          ),
          if (plays)
            ..._playSlivers(context, canEdit)
          else
            ..._whiteboardSlivers(context, canEdit),
        ],
      ),
    );
  }

  List<Widget> _playSlivers(BuildContext context, bool canEdit) {
    final plays = viewModel.plays;
    if (plays.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.draw_outlined,
            title: 'No plays yet',
            message: canEdit
                ? 'Draw your first play on the field.'
                : 'Your coaches haven\'t added plays yet.',
          ),
        ),
      ];
    }
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
    return [
      for (final (category, list) in sections) ...[
        _sectionTitle(category.label, list.length, 'play'),
        _grid(context, list, canEdit),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 96)),
    ];
  }

  List<Widget> _whiteboardSlivers(BuildContext context, bool canEdit) {
    final boards = viewModel.whiteboards;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        sliver: SliverToBoxAdapter(
          child: _BlankWhiteboardCard(
            onOpen: () => context.push(Routes.newWhiteboard(viewModel.teamId)),
          ),
        ),
      ),
      if (boards.isNotEmpty) ...[
        _sectionTitle('Saved whiteboards', boards.length, 'whiteboard'),
        _grid(context, boards, canEdit),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ];
  }

  Widget _sectionTitle(String title, int count, String noun) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    sliver: SliverToBoxAdapter(
      child: _SectionTitle(
        title: title,
        count: count == 1 ? '1 $noun' : '$count ${noun}s',
      ),
    ),
  );

  Widget _grid(BuildContext context, List<Play> list, bool canEdit) =>
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.1,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) => _PlayCard(
            play: list[i],
            canEdit: canEdit,
            onOpen: () => list[i].isWhiteboard
                ? context.push(Routes.whiteboard(viewModel.teamId, list[i].id))
                : context.go(Routes.play(viewModel.teamId, list[i].id)),
            onDelete: () => _delete(context, list[i]),
          ),
        ),
      );
}

/// "Plays | Whiteboard" at the top of the playbook, accent-outlined when selected.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.view, required this.onChanged});

  final PlaybookView view;
  final ValueChanged<PlaybookView> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSegmentedButton<PlaybookView>(
      segments: const [
        ButtonSegment(value: PlaybookView.plays, label: Text('Plays')),
        ButtonSegment(
          value: PlaybookView.whiteboard,
          label: Text('Whiteboard'),
        ),
      ],
      selected: {view},
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
      onSelectionChanged: (s) => onChanged(s.single),
    );
  }
}

/// The way into a blank whiteboard: an empty field and "Open whiteboard".
class _BlankWhiteboardCard extends StatelessWidget {
  const _BlankWhiteboardCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
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
            const SizedBox(
              height: 150,
              child: ColoredBox(
                color: FieldColors.grass,
                child: Padding(
                  padding: EdgeInsets.all(AppSpace.sm),
                  child: IgnorePointer(
                    child: PlayDiagram(
                      play: Play(id: '', name: ''),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Blank whiteboard',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sketch a chalk talk: draw, drop players and the '
                          'disc, then save it or throw it away.',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: onOpen,
                    child: const Text('Open whiteboard'),
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

/// A category's heading with its number of plays on the right.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;

  /// e.g. "3 plays".
  final String count;

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
        Text(count, style: TextStyle(fontSize: 13, color: c.muted)),
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
                          play.name.isNotEmpty
                              ? play.name
                              : play.isWhiteboard
                              ? 'Untitled whiteboard'
                              : 'Untitled play',
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
                            play.isWhiteboard
                                ? 'Whiteboard'
                                : play.category.label,
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
