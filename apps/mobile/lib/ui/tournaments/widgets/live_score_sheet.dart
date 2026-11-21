import 'package:flutter/material.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/scoreboard.dart';
import '../../group_tournaments/widgets/tournament_widgets.dart'
    show showScoreDialog;
import '../view_models/hosted_tournament_viewmodel.dart';
import 'tournament_parts.dart';

/// Opens [gameId]'s running score for its captains and the host.
Future<void> showLiveScoreSheet(
  BuildContext context,
  HostedTournamentViewModel viewModel,
  String gameId,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => LiveScoreSheet(viewModel: viewModel, gameId: gameId),
);

/// A game's running score while it's played, kept by its teams' captains
/// or the host: Start game, then +1 for whoever scores and −1 to undo.
/// Everyone following sees it live. It isn't the final: "Report final
/// score" opens the usual score (pre-filled from it), which the other
/// captain confirms, or the host sets.
class LiveScoreSheet extends StatelessWidget {
  const LiveScoreSheet({
    super.key,
    required this.viewModel,
    required this.gameId,
  });

  final HostedTournamentViewModel viewModel;
  final String gameId;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: Listenable.merge([
        vm,
        vm.stopLive,
        vm.report,
        vm.setFinalScore,
      ]),
      builder: (context, _) {
        final g = vm.games.where((x) => x.id == gameId).firstOrNull;
        if (g == null) return const SizedBox(height: 120);
        final c = AppColors.of(context);
        final live = vm.liveOf(g);
        final canKeep = vm.canKeepLive(g);
        final nameA = vm.slotLabel(g, a: true);
        final nameB = vm.slotLabel(g, a: false);
        final captain = vm.actionFor(g) == HostedGameAction.report;
        final host = !captain && vm.canSetScore(g);
        final busy =
            vm.stopLive.running ||
            vm.report.running ||
            vm.setFinalScore.running;

        Future<void> finalScore() async {
          final score = await showScoreDialog(
            context,
            title: captain ? 'Report the final score' : 'Set the final score',
            nameA: nameA,
            nameB: nameB,
            scoreA: live?.scoreA,
            scoreB: live?.scoreB,
            message: captain
                ? 'The other captain confirms it before it counts.'
                : 'As the host, this is final right away.',
          );
          if (score == null) return;
          final s = (gameId: g.id, scoreA: score.$1, scoreB: score.$2);
          if (captain) {
            await vm.report.execute(s);
          } else {
            await vm.setFinalScore.execute(s);
          }
          final done = captain
              ? vm.report.completed
              : vm.setFinalScore.completed;
          if (done && context.mounted) Navigator.of(context).maybePop();
        }

        Future<void> stop() async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Stop the live score?'),
              content: const Text(
                'The running score comes off for everyone. Start again any '
                'time.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Stop'),
                ),
              ],
            ),
          );
          if (ok == true) await vm.stopLive.execute(g.id);
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Live score',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (live != null) const LivePill(),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    'Game ${vm.gameNumber(g)}',
                    g.label,
                    'Field ${g.field}',
                    if (vm.division case final d?) d.settings.scoreLabel,
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      _TeamStepper(
                        name: nameA,
                        score: live?.scoreA,
                        side: 'a',
                        enabled: canKeep && live != null,
                        onPlus: () => vm.bumpLive(g.id, teamA: true),
                        onMinus: () => vm.bumpLive(g.id, teamA: true, by: -1),
                      ),
                      const Divider(height: 1),
                      _TeamStepper(
                        name: nameB,
                        score: live?.scoreB,
                        side: 'b',
                        enabled: canKeep && live != null,
                        onPlus: () => vm.bumpLive(g.id, teamA: false),
                        onMinus: () => vm.bumpLive(g.id, teamA: false, by: -1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (live == null)
                  FilledButton.icon(
                    key: const Key('live-start'),
                    onPressed: canKeep && !busy
                        ? () => vm.startLive(g.id)
                        : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start game'),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    !canKeep && live == null
                        ? _whyNot(vm, g)
                        : 'Everyone following sees this score. It isn\'t '
                              'final until the score is reported and '
                              'confirmed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ),
                if (captain || host) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.highlight,
                      foregroundColor: c.onHighlight,
                    ),
                    onPressed: busy ? null : finalScore,
                    child: Text(
                      captain ? 'Report final score' : 'Set final score',
                    ),
                  ),
                ],
                if (live != null && canKeep)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: c.muted),
                    onPressed: busy ? null : stop,
                    child: const Text('Stop live score'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _whyNot(HostedTournamentViewModel vm, GroupGame g) {
    if (!vm.canKeepLiveScores) {
      return "Live scores aren't available in this version of the app. "
          'Update the app, or use stall10.app.';
    }
    if (!g.hasTeams) return 'Teams are decided by earlier games.';
    if (vm.tournament?.status == HostedStatus.finished) {
      return 'This event is over.';
    }
    return 'Live scores are kept on the day the game is played.';
  }
}

/// One team's line: name, −1, its score in the scoreboard face, and +1.
class _TeamStepper extends StatelessWidget {
  const _TeamStepper({
    required this.name,
    required this.score,
    required this.side,
    required this.enabled,
    required this.onPlus,
    required this.onMinus,
  });

  final String name;
  final int? score;

  /// `a` or `b`, for the buttons' keys.
  final String side;
  final bool enabled;
  final VoidCallback onPlus;
  final VoidCallback onMinus;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final s = score;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          TeamMark(name: name, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ),
          IconButton.outlined(
            key: Key('live-minus-$side'),
            tooltip: 'Undo a point for $name',
            onPressed: enabled && (s ?? 0) > 0 ? onMinus : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 64,
            child: Center(child: ScoreText(s == null ? '–' : '$s', size: 40)),
          ),
          SizedBox(
            width: 64,
            height: 52,
            child: FilledButton(
              key: Key('live-plus-$side'),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontFamily: scoreFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              onPressed: enabled && (s ?? 0) < 99 ? onPlus : null,
              child: Text('+1', semanticsLabel: 'Point for $name'),
            ),
          ),
        ],
      ),
    );
  }
}
