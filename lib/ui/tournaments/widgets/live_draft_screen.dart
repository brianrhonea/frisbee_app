import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/live_draft.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/live_draft_viewmodel.dart';

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
          return Scaffold(appBar: AppBar(), body: const LoadingView());
        }
        if (d == null) {
          return Scaffold(
            appBar: AppBar(),
            body: vm.error != null
                ? ErrorView(error: vm.error)
                : const EmptyView(
                    icon: Icons.groups_outlined,
                    title: 'Division not found',
                    message: 'It may have been removed.',
                  ),
          );
        }
        final draft = vm.draft;
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (draft == null) ..._setup(context) else ..._board(draft),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- Before it starts ---------------------------------------------------

  List<Widget> _setup(BuildContext context) {
    final theme = Theme.of(context);
    if (!vm.isManager) {
      return [
        const EmptyView(
          icon: Icons.how_to_reg_outlined,
          title: "The draft hasn't started",
          message: 'You can watch it here once the host starts it.',
        ),
      ];
    }
    final players = vm.accepted;
    return [
      Text('Choose the captains', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        'Each captain owns a team and picks players in turn, snaking back '
        'on every round. The order is drawn at random.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
      if (players.length < 4)
        const Text('Accept at least four players first.')
      else
        for (final p in players)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: vm.chosen.contains(p.uid),
            onChanged: (_) => vm.toggleCaptain(p.uid),
            title: Text(p.name),
            subtitle: Text(_describe(p.skill, p.gender)),
          ),
      const SizedBox(height: 12),
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
      const SizedBox(height: 4),
      Text(
        'The clock is a guide: when time is up, you can auto-pick for the '
        'captain.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      if (vm.startProblem != null && vm.chosen.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            vm.startProblem!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      FilledButton.icon(
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
    final theme = Theme.of(context);
    final clock = draft.onTheClock;
    return [
      _banner(draft),
      if (vm.isManager) ..._hostControls(draft),
      if (draft.status == DraftStatus.finished && vm.isManager) ...[
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => context.push(
            Routes.tournamentDraft(vm.tournamentId, vm.divisionId),
          ),
          icon: const Icon(Icons.groups_outlined),
          label: const Text('Open the teams'),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        draft.status == DraftStatus.finished
            ? 'Teams'
            : 'Teams (${draft.picks.length} of ${draft.pool.length} picked)',
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in draft.captains) _teamCard(draft, c, c.uid == clock),
        ],
      ),
      if (draft.status != DraftStatus.finished) ...[
        const SizedBox(height: 16),
        ..._pool(draft),
      ],
    ];
  }

  Widget _banner(LiveDraft draft) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final left = vm.secondsLeft;
    final (String headline, String? sub, Color color) = switch (draft.status) {
      DraftStatus.finished => (
        'The draft is finished',
        'The captains\' teams are saved.',
        scheme.surfaceContainerHighest,
      ),
      DraftStatus.done => (
        'Every player has been picked',
        vm.isManager ? 'Finish the draft to make the teams.' : null,
        scheme.tertiaryContainer,
      ),
      DraftStatus.paused => (
        'The draft is paused',
        null,
        scheme.surfaceContainerHighest,
      ),
      DraftStatus.live => (
        vm.isMyTurn ? "You're on the clock" : '${vm.onClockName} is picking',
        left == null
            ? null
            : vm.timeUp
            ? "Time's up"
            : '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')} left',
        vm.isMyTurn ? scheme.primaryContainer : scheme.secondaryContainer,
      ),
    };
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(headline, style: theme.textTheme.titleMedium),
            if (sub != null) Text(sub),
          ],
        ),
      ),
    );
  }

  List<Widget> _hostControls(LiveDraft draft) {
    final running = vm.control.running || vm.finish.running;
    return [
      Wrap(
        spacing: 8,
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
            (vm.timeUp ? FilledButton.icon : OutlinedButton.icon)(
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
      ),
    ];
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
    final theme = Theme.of(context);
    final members = draft.teamOf(captain.uid);
    return SizedBox(
      width: 220,
      child: Card(
        shape: onClock && draft.running
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.primary, width: 2),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Team ${captain.name}',
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              for (final (i, uid) in members.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${i == 0 ? '© ' : ''}${draft.nameOf(uid)}'
                    '${vm.details?[uid] == null ? '' : ' · ${vm.details![uid]!.skill}'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _pool(LiveDraft draft) {
    final theme = Theme.of(context);
    final pool = vm.pool;
    final canPick = vm.canPick && !vm.pick.running;
    return [
      Text(
        'Players left (${draft.available.length})',
        style: theme.textTheme.titleMedium,
      ),
      if (vm.details != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 8,
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
        ),
      if (pool.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Nobody is left.'),
        ),
      for (final p in pool)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(p.value),
          subtitle: vm.details?[p.key] == null
              ? null
              : Text(
                  _describe(
                    vm.details![p.key]!.skill,
                    vm.details![p.key]!.gender,
                  ),
                ),
          trailing: canPick
              ? FilledButton(
                  onPressed: () => vm.pick.execute(p.key),
                  child: const Text('Draft'),
                )
              : null,
        ),
    ];
  }
}
