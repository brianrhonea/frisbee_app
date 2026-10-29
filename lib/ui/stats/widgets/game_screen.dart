import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/roster_player.dart';
import '../../../domain/models/stats.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/status_views.dart';
import '../view_models/game_tracker_viewmodel.dart';
import 'line_picker.dart';
import 'game_to_field.dart';
import 'line_tile.dart';
import 'player_chooser.dart';
import 'pull_timer.dart';
import 'stat_sheet.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.viewModel});

  final GameTrackerViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      final game = vm.game;
      if (!vm.loaded) {
        return Scaffold(appBar: AppBar(), body: const LoadingView());
      }
      if (game == null) {
        return Scaffold(
          appBar: AppBar(),
          body: vm.error != null
              ? ErrorView(error: vm.error)
              : const EmptyView(
                  icon: Icons.sports_score,
                  title: 'Game not found',
                ),
        );
      }
      return DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('vs ${game.opponent}'),
                Text(
                  vm.tournament?.name ?? DateFormat.yMMMd().format(game.date),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              if (vm.canEdit) ...[
                IconButton(
                  tooltip: 'Undo',
                  icon: const Icon(Icons.undo),
                  onPressed: vm.canUndo ? vm.undo : null,
                ),
                PopupMenuButton<_Menu>(
                  onSelected: (m) => _onMenu(context, m),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _Menu.gameTo,
                      child: Text('Change game point'),
                    ),
                    const PopupMenuItem(
                      value: _Menu.timeouts,
                      child: Text('Timeouts'),
                    ),
                    PopupMenuItem(
                      value: game.finished ? _Menu.resume : _Menu.end,
                      child: Text(
                        game.finished ? 'Resume tracking' : 'End game early',
                      ),
                    ),
                  ],
                ),
              ],
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Track'),
                Tab(text: 'Lines'),
                Tab(text: 'Points'),
                Tab(text: 'Stats'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _TrackTab(viewModel: vm),
              _LinesTab(viewModel: vm),
              _PointLog(viewModel: vm),
              StatSheetTable(sheet: vm.sheet, nameOf: vm.nameOf),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _onMenu(BuildContext context, _Menu m) async {
    final vm = viewModel;
    final game = vm.game!;
    switch (m) {
      case _Menu.gameTo:
        await editGameTo(context, vm);
      case _Menu.timeouts:
        await openTimeouts(context, vm);
      case _Menu.end:
        if (await confirmDialog(
          context,
          title: 'End game early?',
          message:
              'For a time cap or forfeit. Final score '
              '${game.ourScore}–${game.theirScore}.',
          confirmLabel: 'End game',
        )) {
          vm.setFinished(true);
        }
      case _Menu.resume:
        vm.setFinished(false);
    }
  }
}

enum _Menu { gameTo, timeouts, end, resume }

const _linesTab = 1;
const _statsTab = 3;

/// Builds a new line, or edits [line], and saves it.
Future<void> editLine(
  BuildContext context,
  GameTrackerViewModel vm, {
  StatLine? line,
  List<String>? players,
  Side? side,
}) async {
  final choice = await showLinePicker(
    context,
    available: vm.available,
    initial: line?.players ?? players ?? const [],
    title: line == null ? 'New line' : 'Edit ${line.name}',
    requireName: true,
    defaultSide: line?.side ?? side,
  );
  if (choice != null) {
    vm.saveLine(
      choice.saveAs ?? line?.name ?? 'Line',
      choice.players,
      id: line?.id,
      side: choice.side,
    );
  }
}

/// Opens the pull timer and records the pull.
Future<void> openPull(BuildContext context, GameTrackerViewModel vm) async {
  final pull = await showPullTimer(
    context,
    pullers: [for (final id in vm.onField) (id: id, name: vm.nameOf(id))],
    initial: vm.lastPuller,
  );
  if (pull != null) {
    vm.recordPull(
      pull.playerId,
      hangTime: pull.hangTime,
      outOfBounds: pull.outOfBounds,
    );
  }
}

String _halfName(int half) => half == 1 ? '1st half' : '2nd half';

/// Timeouts left per team this half; call or take one back, or change
/// how many each team gets.
Future<void> openTimeouts(BuildContext context, GameTrackerViewModel vm) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ListenableBuilder(
        listenable: vm,
        builder: (context, _) => _TimeoutSheet(viewModel: vm),
      ),
    );

/// Picks a new target score, e.g. when the game is really to 15, not 11.
Future<void> editGameTo(BuildContext context, GameTrackerViewModel vm) async {
  final game = vm.game!;
  final minimum = [
    game.ourScore,
    game.theirScore,
  ].reduce((a, b) => a > b ? a : b);
  final picked = await showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Game to'),
      children: [
        for (final t in StatsGame.targets)
          if (t >= minimum)
            ListTile(
              leading: Icon(
                t == game.gameTo
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text('$t'),
              subtitle: t == minimum && game.reachedGamePoint
                  ? const Text('Current score: game over')
                  : null,
              onTap: () => Navigator.pop(context, t),
            ),
      ],
    ),
  );
  if (picked != null) vm.setGameTo(picked);
}

class _TrackTab extends StatelessWidget {
  const _TrackTab({required this.viewModel});

  final GameTrackerViewModel viewModel;

  Future<void> _pickLine(BuildContext context) async {
    final vm = viewModel;
    final choice = await showLinePicker(
      context,
      available: vm.available,
      saved: vm.linesFor(vm.side),
      initial: vm.currentPoint?.line ?? const [],
      canSave: true,
      title: 'Line for point ${vm.pointNumber} (${vm.side.short})',
      defaultSide: vm.side,
    );
    if (choice != null) {
      vm.useLine(choice.players, saveAs: choice.saveAs, saveSide: choice.side);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final point = vm.currentPoint;
    final tracking = vm.canEdit && point != null && !vm.over;
    final pickingLine = vm.canEdit && point == null && !vm.over;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  if (vm.saveError != null) ...[
                    _Banner(
                      icon: Icons.cloud_off,
                      highlight: true,
                      text:
                          'Couldn\'t save the last change. It\'s kept on '
                          'this device and will retry.',
                    ),
                    const SizedBox(height: 8),
                  ],
                  _Scoreboard(viewModel: vm),
                  const SizedBox(height: 12),
                  if (vm.over)
                    _GameOver(viewModel: vm)
                  else if (!vm.canEdit)
                    const _Banner(
                      icon: Icons.visibility_outlined,
                      text:
                          'View only. Coaches and owners keep stats; follow '
                          'along in Points and Stats.',
                    )
                  else if (point == null)
                    _LineupCard(viewModel: vm)
                  else ...[
                    _LineBar(viewModel: vm, onChange: () => _pickLine(context)),
                    const SizedBox(height: 8),
                    _StatusBanner(viewModel: vm),
                    const SizedBox(height: 8),
                    _PlayerGrid(viewModel: vm),
                  ],
                ],
              ),
            ),
            // Pinned so the buttons never scroll away mid-point.
            if (tracking || pickingLine)
              Material(
                elevation: 3,
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: pickingLine
                        ? _StartBar(viewModel: vm)
                        : vm.side == Side.offense
                        ? _OffenseActions(viewModel: vm)
                        : _DefenseActions(viewModel: vm),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.viewModel});

  final GameTrackerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final game = vm.game!;
    final theme = Theme.of(context);
    final score = theme.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
    );
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text('Us', style: theme.textTheme.labelLarge),
                      Text('${game.ourScore}', style: score),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(
                      vm.over ? 'FINAL' : 'Point ${vm.pointNumber}',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    ActionChip(
                      avatar: const Icon(Icons.flag_outlined, size: 16),
                      label: Text('Game to ${game.gameTo}'),
                      onPressed: vm.canEdit
                          ? () => editGameTo(context, vm)
                          : null,
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        game.opponent,
                        style: theme.textTheme.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text('${game.theirScore}', style: score),
                      TextButton.icon(
                        onPressed: vm.canOpponentScore ? vm.theyScored : null,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Opp score'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<Side>(
                segments: const [
                  ButtonSegment(
                    value: Side.offense,
                    label: Text('On O'),
                    icon: Icon(Icons.north),
                  ),
                  ButtonSegment(
                    value: Side.defense,
                    label: Text('On D'),
                    icon: Icon(Icons.shield_outlined),
                  ),
                ],
                selected: {vm.side},
                onSelectionChanged: vm.canSetSide
                    ? (s) => vm.setSide(s.first)
                    : null,
              ),
            ),
            if (vm.timeoutsPerHalf > 0) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => openTimeouts(context, vm),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Timeouts · Us ${vm.timeoutsLeft(ours: true)} · '
                          'Them ${vm.timeoutsLeft(ours: false)} · '
                          '${_halfName(vm.half)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GameOver extends StatelessWidget {
  const _GameOver({required this.viewModel});

  final GameTrackerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final game = vm.game!;
    final theme = Theme.of(context);
    final result = switch (game.won) {
      true => 'We won',
      false => 'We lost',
      null => 'Tied',
    };
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Game over · $result ${game.ourScore}–${game.theirScore}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              game.finished
                  ? 'Ended early. Resume tracking from the menu to continue.'
                  : 'Someone reached ${game.gameTo}. If the game is to a '
                        'higher score, change game point to keep tracking.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (!game.finished && vm.canEdit)
                  FilledButton.tonalIcon(
                    onPressed: () => editGameTo(context, vm),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Change game point'),
                  ),
                OutlinedButton(
                  onPressed: () =>
                      DefaultTabController.of(context).animateTo(_statsTab),
                  child: const Text('View stats'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown between points: pick the next seven from the last line for this
/// side, a saved line, or the full roster. The pinned start button sits in
/// [_StartBar].
class _LineupCard extends StatelessWidget {
  const _LineupCard({required this.viewModel});

  final GameTrackerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final side = vm.nextSide;
    final last = vm.lastLineFor(side);
    final picked = vm.draftLine;
    final lines = vm.linesFor(side);
    bool showing(List<String> ids) =>
        ids.length == picked.length && ids.every(picked.contains);
    final previous = vm.points.lastOrNull;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (previous?.result case final result?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  result == PointResult.weScored
                      ? previous!.startedOn == Side.defense
                            ? 'Break! Now we pull.'
                            : 'We scored! Now we pull.'
                      : '${vm.game!.opponent} scored. We receive.',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: result == PointResult.weScored
                        ? Colors.green.shade700
                        : scheme.error,
                  ),
                ),
              ),
            Text(
              'Point ${vm.pointNumber} · '
              '${side == Side.offense ? 'O line' : 'D line'}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (last != null)
                  ChoiceChip(
                    avatar: const Icon(Icons.replay, size: 18),
                    label: Text('Last ${side.short} line'),
                    selected: showing(last),
                    onSelected: (_) => vm.fillDraft(last),
                  ),
                for (final l in lines)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      child: Text(
                        l.side?.short ?? '•',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    label: Text(l.name),
                    selected: showing(l.players),
                    onSelected: (_) => vm.fillDraft(l.players),
                  ),
              ],
            ),
            if (last == null && lines.isEmpty)
              Text(
                'No ${side.short} lines yet. Pick ${StatLine.size} below.',
                style: theme.textTheme.bodySmall,
              ),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      DefaultTabController.of(context).animateTo(_linesTab),
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('Set up lines'),
                ),
                if (vm.draftReady && !lines.any((l) => showing(l.players)))
                  TextButton.icon(
                    onPressed: () => editLine(
                      context,
                      vm,
                      players: picked.toList(),
                      side: side,
                    ),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save as line'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text('Players', style: theme.textTheme.titleSmall),
                ),
                if (picked.isNotEmpty)
                  TextButton(
                    onPressed: vm.clearDraft,
                    child: const Text('Clear'),
                  ),
              ],
            ),
            PlayerChooser(
              players: vm.available,
              selected: picked,
              onToggle: vm.toggleDraft,
              max: StatLine.size,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinned "Start point" with the 7/7 count. A D line goes straight to the
/// pull timer.
class _StartBar extends StatelessWidget {
  const _StartBar({required this.viewModel});

  final GameTrackerViewModel viewModel;

  Future<void> _start(BuildContext context) async {
    final vm = viewModel;
    vm.startDraft();
    if (vm.canPull && context.mounted) await openPull(context, vm);
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final count = vm.draftLine.length;
    final pull = vm.nextSide == Side.defense;
    return Row(
      children: [
        Text(
          '$count/${StatLine.size}',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: vm.draftReady
                ? Colors.green.shade600
                : theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: vm.draftReady ? () => _start(context) : null,
            icon: Icon(pull ? Icons.timer_outlined : Icons.play_arrow),
            label: Text(
              !vm.draftReady
                  ? 'Pick ${StatLine.size - count} more'
                  : pull
                  ? 'Start point & pull'
                  : 'Start point',
            ),
          ),
        ),
      ],
    );
  }
}

class _LineBar extends StatelessWidget {
  const _LineBar({required this.viewModel, required this.onChange});

  final GameTrackerViewModel viewModel;
  final VoidCallback onChange;

  Future<void> _sub(BuildContext context) async {
    final vm = viewModel;
    final swap = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SubSheet(viewModel: vm),
    );
    if (swap != null) vm.substitute(swap.$1, swap.$2);
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final point = vm.currentPoint!;
    final line = point.line.toSet();
    final name = vm.savedLines
        .where((l) => l.players.toSet().containsAll(line))
        .firstOrNull
        ?.name;
    final subs = point.actions.where((a) => a.kind == StatKind.sub).length;
    return Row(
      children: [
        const Icon(Icons.groups_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            [
              name ?? 'Custom line',
              if (subs > 0) '$subs sub${subs > 1 ? 's' : ''}',
            ].join(' · '),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (point.actions.isEmpty)
          TextButton(onPressed: onChange, child: const Text('Change line'))
        else
          TextButton.icon(
            onPressed: vm.bench.isEmpty ? null : () => _sub(context),
            icon: const Icon(Icons.swap_vert),
            label: const Text('Sub'),
          ),
      ],
    );
  }
}

/// Pick who comes off, then who goes on.
class _SubSheet extends StatefulWidget {
  const _SubSheet({required this.viewModel});

  final GameTrackerViewModel viewModel;

  @override
  State<_SubSheet> createState() => _SubSheetState();
}

class _SubSheetState extends State<_SubSheet> {
  String? _out;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final theme = Theme.of(context);
    final out = _out;
    Widget tile(
      RosterPlayer? p,
      String id, {
      bool enabled = true,
      VoidCallback? onTap,
    }) => ListTile(
      enabled: enabled,
      leading: CircleAvatar(
        child: Text(p?.number == null ? '–' : '${p!.number}'),
      ),
      title: Text(p?.name ?? 'Player'),
      subtitle: id == vm.holder
          ? const Text('Has the disc. The sub takes it and throws next.')
          : null,
      onTap: onTap,
    );
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            out == null
                ? 'Who\'s coming off?'
                : 'Who\'s going in for ${vm.nameOf(out)}?',
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        if (out == null)
          for (final id in vm.onField)
            tile(
              vm.player(id),
              id,
              enabled: vm.canSubOut(id),
              onTap: () => setState(() => _out = id),
            )
        else ...[
          for (final p in vm.bench)
            tile(p, p.id, onTap: () => Navigator.pop(context, (out, p.id))),
          TextButton(
            onPressed: () => setState(() => _out = null),
            child: const Text('Back'),
          ),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.highlight = false,
  });

  final IconData icon;
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: highlight ? scheme.onTertiaryContainer : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: highlight ? scheme.onTertiaryContainer : null,
                fontWeight: highlight ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.viewModel});

  final GameTrackerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final armed = vm.armed;
    if (armed != null) {
      return _Banner(
        icon: Icons.touch_app,
        highlight: true,
        text: switch (armed) {
          StatKind.goal => 'Score! Tap who caught it in the endzone',
          StatKind.drop => 'Tap who dropped it',
          StatKind.handBlock => 'Tap who got the hand block (+2)',
          StatKind.breakup => 'Tap who got the D (+1)',
          _ => 'Tap who got beat (−1)',
        },
      );
    }
    if (vm.side == Side.defense) {
      return _Banner(
        icon: Icons.shield_outlined,
        text: vm.canPull
            ? 'We\'re pulling. Tap Pull to time it.'
            : 'On D. Pick a play below, then tap the player.',
      );
    }
    final holder = vm.holder;
    final chain = vm.passChain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Banner(
          icon: Icons.album_outlined,
          text: holder == null
              ? 'On O. Tap who picked up the disc.'
              : '${vm.nameOf(holder)} has it. Tap who caught the pass.',
        ),
        if (chain.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Text(
                [
                  for (final id in chain) vm.nameOf(id).split(' ').first,
                ].join('  →  '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}

class _PlayerGrid extends StatelessWidget {
  const _PlayerGrid({required this.viewModel});

  final GameTrackerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final idle = vm.side == Side.defense && vm.armed == null;
    return GridView.extent(
      // Four across on phones so the action buttons stay on screen.
      maxCrossAxisExtent: 112,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.95,
      children: [
        for (final id in vm.onField)
          _PlayerTile(
            player: vm.player(id),
            holding: vm.holder == id,
            dimmed: idle,
            onTap: () => vm.tapPlayer(id),
          ),
      ],
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.player,
    required this.holding,
    required this.dimmed,
    required this.onTap,
  });

  final RosterPlayer? player;
  final bool holding;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = player;
    final fg = holding ? scheme.onPrimary : scheme.onSurface;
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Material(
        color: holding ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p?.number == null ? '–' : '#${p!.number}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (holding) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.album, size: 18, color: fg),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  p?.name ?? 'Player',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OffenseActions extends StatelessWidget {
  const _OffenseActions({required this.viewModel});

  final GameTrackerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final scheme = Theme.of(context).colorScheme;
    final hasDisc = vm.holder != null;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _ArmButton(
            viewModel: vm,
            kind: StatKind.goal,
            label: 'Score',
            icon: Icons.sports_score,
            enabled: vm.canScore,
            color: Colors.green.shade600,
            filled: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: scheme.error,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            onPressed: hasDisc ? vm.throwaway : null,
            child: const Text('Throwaway', textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ArmButton(
            viewModel: vm,
            kind: StatKind.drop,
            label: 'Drop',
            enabled: hasDisc,
            color: scheme.error,
          ),
        ),
      ],
    );
  }
}

class _DefenseActions extends StatelessWidget {
  const _DefenseActions({required this.viewModel});

  final GameTrackerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (vm.canPull) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => openPull(context, vm),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('Pull'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: _ArmButton(
                viewModel: vm,
                kind: StatKind.breakup,
                label: 'D +1',
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ArmButton(
                viewModel: vm,
                kind: StatKind.handBlock,
                label: 'Hand block +2',
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ArmButton(
                viewModel: vm,
                kind: StatKind.beat,
                label: 'Got beat −1',
                color: scheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: vm.weGotIt,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Their turnover'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: vm.theyScored,
                icon: const Icon(Icons.sentiment_dissatisfied_outlined),
                label: const Text('They scored'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Toggle for actions credited to the next player tapped.
class _ArmButton extends StatelessWidget {
  const _ArmButton({
    required this.viewModel,
    required this.kind,
    required this.label,
    required this.color,
    this.icon,
    this.enabled = true,
    this.filled = false,
  });

  final GameTrackerViewModel viewModel;
  final StatKind kind;
  final String label;
  final Color color;
  final IconData? icon;
  final bool enabled;

  /// Solid when idle too, for the main action.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final armed = viewModel.armed == kind;
    final solid = armed || filled;
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      foregroundColor: solid ? Colors.white : color,
      backgroundColor: solid ? color : null,
      side: BorderSide(color: color, width: armed ? 3 : 1),
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
    final text = Text(armed ? '$label…' : label, textAlign: TextAlign.center);
    final onPressed = enabled ? () => viewModel.arm(kind) : null;
    return icon == null
        ? OutlinedButton(style: style, onPressed: onPressed, child: text)
        : OutlinedButton.icon(
            style: style,
            onPressed: onPressed,
            icon: Icon(icon),
            label: text,
          );
  }
}

/// Label, icon and color for a play in the point log.
(String, IconData, Color) _playStyle(StatKind kind, ColorScheme scheme) =>
    switch (kind) {
      StatKind.pull => ('PULL', Icons.sports, scheme.tertiary),
      StatKind.pickup => (
        'PICKUP',
        Icons.pan_tool_alt_outlined,
        scheme.onSurfaceVariant,
      ),
      StatKind.catch_ => ('CATCH', Icons.swap_horiz, scheme.primary),
      StatKind.goal => ('GOAL', Icons.emoji_events, Colors.green.shade700),
      StatKind.throwaway => ('THROWAWAY', Icons.call_missed, scheme.error),
      StatKind.drop => ('DROP', Icons.south, scheme.error),
      StatKind.handBlock => ('HAND BLOCK', Icons.front_hand, Colors.indigo),
      StatKind.breakup => ('BLOCK', Icons.shield, Colors.indigo),
      StatKind.beat => ('BEAT', Icons.directions_run, Colors.orange.shade800),
      StatKind.theirTurnover => ('THEIR TURN', Icons.swap_vert, Colors.indigo),
      StatKind.sub => ('SUB', Icons.sync_alt, scheme.onSurfaceVariant),
    };

/// A colored tag such as GOAL or DROP.
class _PlayTag extends StatelessWidget {
  const _PlayTag({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 108,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Every point of the game, newest first: who played, each play tagged by
/// kind, possession changes, timeouts and halftime.
class _PointLog extends StatelessWidget {
  const _PointLog({required this.viewModel});

  final GameTrackerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final game = vm.game!;
    final points = vm.points;
    if (points.isEmpty && vm.timeouts.isEmpty) {
      return const EmptyView(
        icon: Icons.list_alt_outlined,
        title: 'No points yet',
        message: 'Each point is logged here as you track it.',
      );
    }
    var us = 0, them = 0;
    final scores = [
      for (final p in points)
        if (p.result == PointResult.weScored)
          '${++us}–$them'
        else if (p.result == PointResult.theyScored)
          '$us–${++them}'
        else
          '$us–$them',
    ];
    final half = game.halftimePoint;
    final items = <Widget>[
      for (var i = points.length - 1; i >= 0; i--) ...[
        if (half == i) _HalftimeRow(score: scores[i]),
        _PointCard(
          viewModel: vm,
          index: i,
          score: scores[i],
          expanded: i == points.length - 1,
        ),
      ],
    ];
    // Timeouts called after the last point, before the next one starts.
    final pending = [
      for (final t in vm.timeouts)
        if (t.point >= points.length) t,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        for (final t in pending.reversed)
          _TimeoutRow(viewModel: vm, timeout: t),
        ...items,
      ],
    );
  }
}

class _HalftimeRow extends StatelessWidget {
  const _HalftimeRow({required this.score});

  final String score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'HALFTIME · $score',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class _TimeoutRow extends StatelessWidget {
  const _TimeoutRow({required this.viewModel, required this.timeout});

  final GameTrackerViewModel viewModel;
  final GameTimeout timeout;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        _PlayTag(
          label: 'TIMEOUT',
          icon: Icons.timer_outlined,
          color: Colors.amber.shade800,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${timeout.ours ? 'We' : viewModel.game!.opponent} called '
            'timeout · ${_halfName(timeout.half)}',
          ),
        ),
      ],
    ),
  );
}

class _PointCard extends StatelessWidget {
  const _PointCard({
    required this.viewModel,
    required this.index,
    required this.score,
    required this.expanded,
  });

  final GameTrackerViewModel viewModel;
  final int index;
  final String score;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = vm.points[index];
    final (label, color) = switch (p.result) {
      PointResult.weScored when p.startedOn == Side.defense => (
        'Break',
        Colors.green.shade800,
      ),
      PointResult.weScored => ('Score', Colors.green.shade700),
      PointResult.theyScored => ('Opp score', scheme.error),
      null => ('In play', scheme.tertiary),
    };
    final passes = p.actions.where((a) => a.kind == StatKind.catch_).length;
    final turns = p.actions.where((a) => a.turnsOver).length;
    final timeouts = [
      for (final t in vm.timeouts)
        if (t.point == index) t,
    ];

    // Plays in order, with timeouts slotted in where they were called and
    // a marker each time possession changes.
    final rows = <Widget>[];
    var side = p.startedOn;
    void addTimeouts(int at) {
      for (final t in timeouts) {
        if (t.action == at) rows.add(_TimeoutRow(viewModel: vm, timeout: t));
      }
    }

    for (final (k, a) in p.actions.indexed) {
      addTimeouts(k);
      var (tag, icon, c) = _playStyle(a.kind, scheme);
      // A goal by a line that started on D is a break.
      if (a.kind == StatKind.goal && p.startedOn == Side.defense) {
        tag = 'BREAK';
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PlayTag(label: tag, icon: icon, color: c),
              const SizedBox(width: 10),
              Expanded(child: Text(vm.describe(a))),
            ],
          ),
        ),
      );
      if (a.turnsOver) {
        side = side.flipped;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2, bottom: 6),
            child: Text(
              side == Side.offense
                  ? '↳ Our disc. We\'re on O.'
                  : '↳ Their disc. We\'re on D.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        );
      }
    }
    addTimeouts(p.actions.length);

    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: expanded,
        leading: CircleAvatar(
          backgroundColor: p.startedOn == Side.offense
              ? scheme.primaryContainer
              : scheme.secondaryContainer,
          child: Text(p.startedOn.short),
        ),
        title: Text(
          'Point ${index + 1} · '
          '${p.startedOn == Side.offense ? 'O line' : 'D line'}',
        ),
        subtitle: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: label,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
              if (p.line.isNotEmpty)
                TextSpan(
                  text:
                      ' · $passes pass${passes == 1 ? '' : 'es'}'
                      ' · $turns turn${turns == 1 ? '' : 's'}',
                ),
              if (timeouts.isNotEmpty)
                TextSpan(
                  text:
                      ' · ${timeouts.length} timeout'
                      '${timeouts.length == 1 ? '' : 's'}',
                ),
            ],
          ),
        ),
        trailing: Text(score, style: theme.textTheme.titleMedium),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (p.line.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                [for (final id in p.played) vm.nameOf(id)].join(', '),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (rows.isEmpty)
            Text(p.line.isEmpty ? 'Score only, no stats' : 'No stats recorded')
          else
            ...rows,
        ],
      ),
    );
  }
}

/// Timeouts left for both teams this half.
class _TimeoutSheet extends StatelessWidget {
  const _TimeoutSheet({required this.viewModel});

  final GameTrackerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final game = vm.game!;
    final thisHalf = [
      for (final t in vm.timeouts)
        if (t.half == vm.half) t,
    ];
    Widget team({required bool ours}) {
      final left = vm.timeoutsLeft(ours: ours);
      return Expanded(
        child: Column(
          children: [
            Text(
              ours ? 'Us' : game.opponent,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                for (var n = 0; n < vm.timeoutsPerHalf; n++)
                  Icon(
                    n < left ? Icons.circle : Icons.circle_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
            Text('$left left', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: vm.canCallTimeout(ours: ours)
                  ? () => vm.callTimeout(ours: ours)
                  : null,
              child: const Text('Call timeout'),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            'Timeouts · ${_halfName(vm.half)}',
            style: theme.textTheme.titleLarge,
          ),
          Text(
            vm.half == 1
                ? 'Halftime at ${game.halfAt}. Timeouts reset for the 2nd '
                      'half.'
                : 'Second half.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              team(ours: true),
              const SizedBox(width: 12),
              team(ours: false),
            ],
          ),
          if (thisHalf.isNotEmpty) ...[
            const Divider(height: 32),
            Text('Called this half', style: theme.textTheme.titleSmall),
            for (final t in thisHalf.reversed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timer_outlined),
                title: Text(t.ours ? 'Us' : game.opponent),
                subtitle: Text('Point ${t.point + 1}'),
                trailing: vm.canEdit
                    ? IconButton(
                        tooltip: 'Remove timeout',
                        icon: const Icon(Icons.close),
                        onPressed: () => vm.removeTimeout(t),
                      )
                    : null,
              ),
          ],
          if (vm.canEdit) ...[
            const Divider(height: 32),
            TimeoutsField(
              value: vm.timeoutsPerHalf,
              onChanged: vm.setTimeoutsPerHalf,
            ),
          ],
        ],
      ),
    );
  }
}

/// Lines for this game (or its tournament): build, edit, delete or import.
class _LinesTab extends StatelessWidget {
  const _LinesTab({required this.viewModel});

  final GameTrackerViewModel viewModel;

  void _imported(BuildContext context, int n) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'Nothing new to import'
                : 'Imported $n line${n == 1 ? '' : 's'}',
          ),
        ),
      );

  Future<void> _import(BuildContext context) async {
    final vm = viewModel;
    final event = vm.game?.eventId;
    final source = await showModalBottomSheet<LineSource>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Import lines from')),
            for (final s in vm.lineSources)
              ListTile(
                leading: Icon(
                  event != null && s.eventId == event
                      ? Icons.event_available
                      : Icons.folder_outlined,
                ),
                title: Text(s.name),
                subtitle: Text(
                  [
                    if (event != null && s.eventId == event) 'Same event',
                    s.lines.map((l) => l.name).join(', '),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, s),
              ),
          ],
        ),
      ),
    );
    if (source != null && context.mounted) {
      _imported(context, vm.importLines(source.lines));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final lines = [
      for (final side in [Side.offense, Side.defense, null])
        ...vm.savedLines.where((l) => l.side == side),
    ];
    final fromEvent = vm.eventLinesToImport;
    final tooFew = vm.available.length < StatLine.size;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              vm.tournament != null
                  ? 'Lines for ${vm.tournament!.name}, shared by every game '
                        'in it.'
                  : 'Lines for this game.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (vm.canEdit)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: tooFew ? null : () => editLine(context, vm),
                    icon: const Icon(Icons.add),
                    label: const Text('New line'),
                  ),
                  if (vm.lineSources.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _import(context),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Import lines'),
                    ),
                ],
              ),
            if (vm.canEdit && fromEvent.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card.filled(
                child: ListTile(
                  leading: const Icon(Icons.event_available),
                  title: Text(
                    '${fromEvent.length} line'
                    '${fromEvent.length == 1 ? '' : 's'} from the linked event',
                  ),
                  subtitle: Text(fromEvent.map((l) => l.name).join(', ')),
                  trailing: TextButton(
                    onPressed: () =>
                        _imported(context, vm.importLines(fromEvent)),
                    child: const Text('Import'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (lines.isEmpty)
              const EmptyView(
                icon: Icons.groups_outlined,
                title: 'No lines yet',
                message:
                    'Build O and D lines here and they show up when you pick '
                    'the line for each point.',
              )
            else
              for (final l in lines)
                LineTile(
                  line: l,
                  nameOf: vm.nameOf,
                  onTap: vm.canEdit
                      ? () => editLine(context, vm, line: l)
                      : null,
                  onDelete: vm.canEdit ? () => vm.deleteLine(l.id) : null,
                ),
          ],
        ),
      ),
    );
  }
}
