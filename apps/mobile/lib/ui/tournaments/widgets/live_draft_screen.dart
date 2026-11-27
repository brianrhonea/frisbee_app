import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/live_draft.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show PersonAvatar, initialsOf;
import '../../core/ui/scoreboard.dart' show ScoreText;
import '../../core/ui/status_views.dart';
import '../../group_tournaments/widgets/hat_parts.dart' show GenderSplitBar;
import '../view_models/live_draft_viewmodel.dart';
import 'tournament_parts.dart' show RowsCard;

/// The captains' draft: the host chooses captains and starts it, then the
/// captains take turns picking players while everyone watches the board.
class LiveDraftScreen extends StatefulWidget {
  const LiveDraftScreen({super.key, required this.viewModel});

  final LiveDraftViewModel viewModel;

  @override
  State<LiveDraftScreen> createState() => _LiveDraftScreenState();
}

class _LiveDraftScreenState extends State<LiveDraftScreen> {
  LiveDraftViewModel get vm => widget.viewModel;
  late final List<Command<void>> _commands = vm.commands;

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
  }

  @override
  void dispose() {
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    super.dispose();
  }

  void _onCommand() {
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final d = vm.division;
        final title = d == null ? "Captains' draft" : "Draft · ${d.label}";
        if (!vm.loaded) {
          return Scaffold(appBar: AppBar(), body: const LoadingState());
        }
        if (d == null) {
          return Scaffold(
            appBar: AppBar(),
            body: vm.error != null
                ? ErrorState(error: vm.error)
                : const EmptyState(
                    icon: Icons.groups_outlined,
                    title: 'Division not found',
                    message: 'It may have been removed.',
                  ),
          );
        }
        final draft = vm.draft;
        final c = AppColors.of(context);
        // A draft under way is live: the header turns scoreboard navy.
        final live = draft != null && draft.status != DraftStatus.finished;
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            backgroundColor: live ? c.feature : null,
            foregroundColor: live ? c.onFeature : null,
            titleTextStyle: live
                ? TextStyle(
                    fontFamily: appFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: c.onFeature,
                  )
                : null,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (draft == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _setup(context),
                    ),
                  )
                else
                  ..._board(draft),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- Before it starts ---------------------------------------------------

  List<Widget> _setup(BuildContext context) {
    final c = AppColors.of(context);
    if (!vm.isManager) {
      return [
        const EmptyState(
          icon: Icons.how_to_reg_outlined,
          title: "The draft hasn't started",
          message: 'You can watch it here once the host starts it.',
        ),
      ];
    }
    final players = vm.accepted;
    return [
      Text(
        'Choose the captains',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: c.ink,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Each captain owns a team and picks players in turn, snaking back '
        'on every round. The order is drawn at random.',
        style: TextStyle(fontSize: 13.5, color: c.ink2),
      ),
      const SizedBox(height: 12),
      if (players.length < 4)
        Text(
          'Accept at least four players first.',
          style: TextStyle(fontSize: 13.5, color: c.ink2),
        )
      else
        RowsCard(
          children: [
            for (final p in players)
              CheckboxListTile(
                contentPadding: const EdgeInsets.only(left: 14, right: 8),
                value: vm.chosen.contains(p.uid),
                onChanged: (_) => vm.toggleCaptain(p.uid),
                title: Text(
                  p.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                subtitle: Text(
                  _describe(p.skill, p.gender),
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
          ],
        ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        initialValue: vm.pickSeconds,
        decoration: const InputDecoration(labelText: 'Time per pick'),
        items: const [
          DropdownMenuItem(value: 0, child: Text('No limit')),
          DropdownMenuItem(value: 30, child: Text('30 seconds')),
          DropdownMenuItem(value: 60, child: Text('1 minute')),
          DropdownMenuItem(value: 90, child: Text('90 seconds')),
          DropdownMenuItem(value: 180, child: Text('3 minutes')),
        ],
        onChanged: (v) => vm.setPickSeconds(v ?? 0),
      ),
      const SizedBox(height: 6),
      Text(
        'The clock is a guide: when time is up, you can auto-pick for the '
        'captain.',
        style: TextStyle(fontSize: 12.5, color: c.muted),
      ),
      const SizedBox(height: 14),
      if (vm.startProblem != null && vm.chosen.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            vm.startProblem!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        onPressed: vm.startProblem != null || vm.start.running
            ? null
            : vm.start.execute,
        icon: const Icon(Icons.play_arrow),
        label: Text('Start the draft (${vm.chosen.length} captains)'),
      ),
    ];
  }

  String _describe(int skill, GenderMatch? gender) =>
      'Skill $skill${gender == null ? '' : ' · ${gender.name.toUpperCase()}'}';

  // ---- The board ----------------------------------------------------------

  List<Widget> _board(LiveDraft draft) {
    final c = AppColors.of(context);
    final clock = draft.onTheClock;
    final finished = draft.status == DraftStatus.finished;
    const side = EdgeInsets.symmetric(horizontal: 16);
    return [
      // The navy header continues under the app bar while it's live.
      Container(
        color: finished ? null : c.feature,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: _banner(draft),
      ),
      if (vm.isManager)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _hostControls(draft),
        ),
      if (finished && vm.isManager)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: FilledButton.icon(
            onPressed: () => context.push(
              Routes.tournamentDraft(vm.tournamentId, vm.divisionId),
            ),
            icon: const Icon(Icons.groups_outlined),
            label: const Text('Open the teams'),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(
          finished
              ? 'Teams'
              : 'Teams (${draft.picks.length} of ${draft.pool.length} picked)',
          style: _heading(c),
        ),
      ),
      Padding(
        padding: side,
        child: LayoutBuilder(
          builder: (context, box) {
            // Two across on phones, more on wider screens.
            final across = (box.maxWidth / 170).floor().clamp(2, 4);
            final width = (box.maxWidth - 8 * (across - 1)) / across;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cap in draft.captains)
                  SizedBox(
                    width: width,
                    child: _teamCard(draft, cap, cap.uid == clock),
                  ),
              ],
            );
          },
        ),
      ),
      if (!finished)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _pool(draft),
          ),
        ),
    ];
  }

  Widget _banner(LiveDraft draft) {
    final c = AppColors.of(context);
    final left = vm.secondsLeft;
    final mine = draft.status == DraftStatus.live && vm.isMyTurn;
    final (String headline, String? sub) = switch (draft.status) {
      DraftStatus.finished => (
        'The draft is finished',
        'The captains\' teams are saved.',
      ),
      DraftStatus.done => (
        'Every player has been picked',
        vm.isManager ? 'Finish the draft to make the teams.' : null,
      ),
      DraftStatus.paused => ('The draft is paused', null),
      DraftStatus.live => (
        vm.isMyTurn ? "You're on the clock" : '${vm.onClockName} is picking',
        left == null
            ? null
            : vm.timeUp
            ? "Time's up"
            : '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')} left',
      ),
    };
    // Amber only when it's the user's pick; navy-on-navy otherwise; a plain
    // card once the draft is over.
    final finished = draft.status == DraftStatus.finished;
    final (Color bg, Color fg, Color soft) = mine
        ? (c.highlight, c.onHighlight, c.onHighlight)
        : finished
        ? (c.card, c.ink, c.muted)
        : (c.featureHighlight, c.onFeature, c.onFeatureMuted);
    final captain = draft.captains
        .where((x) => x.uid == draft.onTheClock)
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(cardRadius),
        border: finished ? Border.all(color: c.border) : null,
      ),
      child: Row(
        children: [
          if (draft.status == DraftStatus.live && captain != null) ...[
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: mine ? c.onHighlight : c.feature,
                shape: BoxShape.circle,
              ),
              child: Text(
                initialsOf(captain.name),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: mine ? c.highlight : c.onFeature,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ] else ...[
            Icon(
              finished
                  ? Icons.check_circle_outline
                  : draft.status == DraftStatus.paused
                  ? Icons.pause_circle_outline
                  : Icons.flag_outlined,
              color: finished ? c.positive : fg,
              size: 28,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: soft,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (draft.status == DraftStatus.live && left != null) ...[
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: ScoreText(
                '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
                size: 36,
                color: fg,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hostControls(LiveDraft draft) {
    final running = vm.control.running || vm.finish.running;
    final c = AppColors.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (draft.status == DraftStatus.live)
          OutlinedButton.icon(
            onPressed: running
                ? null
                : () => vm.control.execute(DraftControl.pause),
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          ),
        if (draft.status == DraftStatus.paused)
          OutlinedButton.icon(
            onPressed: running
                ? null
                : () => vm.control.execute(DraftControl.resume),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Resume'),
          ),
        if (draft.status != DraftStatus.finished && draft.picks.isNotEmpty)
          OutlinedButton.icon(
            onPressed: running
                ? null
                : () => vm.control.execute(DraftControl.undo),
            icon: const Icon(Icons.undo),
            label: const Text('Undo pick'),
          ),
        if (draft.status == DraftStatus.live)
          // Once time is up, auto-picking is the host's to do: amber.
          vm.timeUp
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.highlight,
                    foregroundColor: c.onHighlight,
                  ),
                  onPressed: running
                      ? null
                      : () => vm.control.execute(DraftControl.autopick),
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Auto-pick'),
                )
              : OutlinedButton.icon(
                  onPressed: running
                      ? null
                      : () => vm.control.execute(DraftControl.autopick),
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Auto-pick'),
                ),
        if (draft.status != DraftStatus.finished && !vm.locked)
          FilledButton.icon(
            onPressed: running ? null : _finish,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Finish'),
          ),
        if (draft.status != DraftStatus.finished)
          TextButton.icon(
            onPressed: running ? null : _cancel,
            icon: const Icon(Icons.close),
            label: const Text('Cancel draft'),
          ),
      ],
    );
  }

  Future<void> _cancel() async {
    final ok = await confirmDialog(
      context,
      title: 'Cancel the draft?',
      message:
          'Every pick is thrown away. You can then choose captains and '
          'start again.',
      confirmLabel: 'Cancel draft',
      destructive: true,
    );
    if (ok) await vm.control.execute(DraftControl.cancel);
  }

  Future<void> _finish() async {
    final draft = vm.draft!;
    final left = draft.pool.length - draft.picks.length;
    final ok = await confirmDialog(
      context,
      title: 'Finish the draft?',
      message: left == 0
          ? 'This saves each captain\'s picks as the division\'s teams.'
          : '$left players have not been picked and will be left off the '
                'teams. You can still add them on the teams screen.',
      confirmLabel: 'Finish',
    );
    if (ok) await vm.finish.execute();
  }

  Widget _teamCard(LiveDraft draft, DraftCaptain captain, bool onClock) {
    final c = AppColors.of(context);
    final members = draft.teamOf(captain.uid);
    final details = vm.details;
    var mmp = 0, wmp = 0;
    for (final uid in members) {
      switch (details?[uid]?.gender) {
        case GenderMatch.mmp:
          mmp++;
        case GenderMatch.wmp:
          wmp++;
        case null:
          break;
      }
    }
    final picking = onClock && draft.running;
    // The team picking now is outlined: amber when it's the user's pick.
    final edge = !picking
        ? BorderSide(color: c.border)
        : BorderSide(color: vm.isMyTurn ? c.highlight : c.accent, width: 2);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(controlRadius),
        border: Border.fromBorderSide(edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Team ${captain.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ),
              ScoreText('${members.length}', size: 20),
            ],
          ),
          if (draft.mixed && details != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs, bottom: 2),
              child: GenderSplitBar(
                mmp: mmp,
                wmp: wmp,
                unknown: members.length - mmp - wmp,
                height: 6,
              ),
            ),
          const SizedBox(height: 4),
          for (final (i, uid) in members.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Text(
                '${i == 0 ? '© ' : ''}${draft.nameOf(uid)}'
                '${vm.details?[uid] == null ? '' : ' · ${vm.details![uid]!.skill}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                  color: i == 0 ? c.ink : c.ink2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _pool(LiveDraft draft) {
    final c = AppColors.of(context);
    final pool = vm.pool;
    final canPick = vm.canPick && !vm.pick.running;
    return [
      Text('Players left (${draft.available.length})', style: _heading(c)),
      if (vm.details != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Best first'),
                selected: vm.bySkill,
                onSelected: vm.setBySkill,
              ),
              if (draft.mixed)
                for (final g in GenderMatch.values)
                  FilterChip(
                    label: Text(g.name.toUpperCase()),
                    selected: vm.genderFilter == g,
                    onSelected: (v) => vm.setGenderFilter(v ? g : null),
                  ),
            ],
          ),
        )
      else
        const SizedBox(height: 8),
      if (pool.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Nobody is left.',
            style: TextStyle(fontSize: 13.5, color: c.ink2),
          ),
        )
      else
        RowsCard(
          children: [
            for (final p in pool)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 14, right: 10),
                leading: PersonAvatar(name: p.value, radius: 18),
                title: Text(
                  p.value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                subtitle: vm.details?[p.key] == null
                    ? null
                    : Text(
                        _describe(
                          vm.details![p.key]!.skill,
                          vm.details![p.key]!.gender,
                        ),
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                trailing: canPick
                    ? FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(72, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        onPressed: () => vm.pick.execute(p.key),
                        child: const Text('Draft'),
                      )
                    : null,
              ),
          ],
        ),
    ];
  }

  TextStyle _heading(AppColors c) => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    color: c.ink,
  );
}
