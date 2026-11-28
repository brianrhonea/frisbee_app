import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/team_history/team_history_repository.dart';
import '../../../domain/models/player_profile.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_history.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/skeleton.dart';
import '../../core/ui/status_pill.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/team_history_viewmodel.dart';

/// The profile's "Team history": every team a team admin linked the player
/// to, current teams first and the ones they left marked "Past", each with
/// the player's spot and their stats from that team. The server says what
/// the viewer may see; on someone else's profile the section appears only
/// when it returns teams.
///
/// Website counterpart: the profile's Team history section (apps/web).
class TeamHistorySection extends StatelessWidget {
  const TeamHistorySection({super.key, required this.uid, required this.isMe});

  final String uid;
  final bool isMe;

  /// The most games the server counts per team.
  static const partialNote = 'Totals cover up to 1000 games';

  @override
  Widget build(BuildContext context) {
    // Without the repository (tests that provide only what a page needs)
    // there is no section.
    if (readOptional<TeamHistoryRepository>(context) == null) {
      return const SizedBox.shrink();
    }
    return ViewModelHost<TeamHistoryViewModel>(
      key: ValueKey('$uid/$isMe'),
      create: (c) => TeamHistoryViewModel(
        uid: uid,
        isMe: isMe,
        repository: c.read<TeamHistoryRepository>(),
      ),
      builder: (_, vm) => ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          // Someone else's: nothing until there is something to show.
          if (!isMe && vm.status != TeamHistoryStatus.loaded) {
            return const SizedBox.shrink();
          }
          if (!vm.visible) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SectionCard(
              title: 'Team history',
              child: _body(context, vm),
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, TeamHistoryViewModel vm) {
    final c = AppColors.of(context);
    switch (vm.status) {
      case TeamHistoryStatus.loading:
        return const Skeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonTile(titleWidth: 160),
              SizedBox(height: 8),
              SkeletonTile(titleWidth: 120),
            ],
          ),
        );
      case TeamHistoryStatus.error:
        return ErrorState(
          error: vm.error,
          onRetry: vm.load,
          title: "Couldn't load your team history",
        );
      case TeamHistoryStatus.loaded:
        if (vm.isEmpty) {
          return Text(
            'No team history yet. A team admin links you to your spot on a '
            'roster.',
            style: AppText.secondary.copyWith(color: c.muted),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final t in vm.teams)
              _HistoryRow(key: ValueKey('${t.teamId}/${t.spot.id}'), entry: t),
            if (vm.partial)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  partialNote,
                  style: AppText.caption.copyWith(color: c.muted),
                ),
              ),
          ],
        );
    }
  }
}

String _count(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// "3 games · 10 points · 4 goals · 2 assists · 1 block".
String historyStatLine(StatTotals t) => [
  _count(t.games, 'game'),
  _count(t.points, 'point'),
  _count(t.goals, 'goal'),
  _count(t.assists, 'assist'),
  _count(t.blocks, 'block'),
].join(' · ');

class _HistoryRow extends StatefulWidget {
  const _HistoryRow({super.key, required this.entry});

  final TeamHistoryEntry entry;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = widget.entry;
    final seasons = t.seasonsNewestFirst;
    final shown = _expanded ? seasons : seasons.take(1).toList();
    final spot = [
      if (t.spot.name.isNotEmpty) t.spot.name,
      if (t.spot.number != null) '#${t.spot.number}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TeamBadge(size: 38, community: t.kind != TeamKind.team),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          t.teamName,
                          style: AppText.label.copyWith(color: c.ink),
                        ),
                        if (!t.current) const StatusPill('Past'),
                      ],
                    ),
                    if (spot.isNotEmpty)
                      Text(
                        spot,
                        style: AppText.caption.copyWith(color: c.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48, top: 6),
            child: seasons.isEmpty
                ? Text(
                    'No games tracked yet',
                    style: AppText.caption.copyWith(color: c.muted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in shown)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$s  ',
                                  style: AppText.caption.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: c.ink,
                                  ),
                                ),
                                TextSpan(text: historyStatLine(t.seasons[s]!)),
                              ],
                            ),
                            style: AppText.caption.copyWith(color: c.ink2),
                          ),
                        ),
                      if (seasons.length > 1)
                        Semantics(
                          button: true,
                          expanded: _expanded,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              alignment: Alignment.centerLeft,
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.padded,
                            ),
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
                            child: Text(
                              _expanded
                                  ? 'Hide other seasons'
                                  : 'Show all seasons (${seasons.length})',
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
