import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/roster_player.dart';
import '../../../domain/models/stats.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/tournament_viewmodel.dart';
import 'game_to_field.dart';
import 'line_picker.dart';
import 'line_tile.dart';
import 'player_chooser.dart' show JerseyNumber;
import 'stat_sheet.dart';
import 'game_screen.dart' show confirmDeleteGame;
import 'stats_tab.dart' show GameRow, confirmDeleteTournament, runDelete;

/// A tournament folder: games, the attending roster, saved lines and stats.
class TournamentScreen extends StatelessWidget {
  const TournamentScreen({super.key, required this.viewModel});

  final TournamentViewModel viewModel;

  Future<void> _addGame(BuildContext context) async {
    final vm = viewModel;
    final last = vm.games.lastOrNull;
    final game = await showDialog<NewTournamentGame>(
      context: context,
      builder: (_) => _AddGameDialog(
        gameTo: last?.gameTo ?? 15,
        timeouts: last?.timeoutsPerHalf ?? 2,
      ),
    );
    if (game == null || !context.mounted) return;
    await vm.addGame.execute(game);
    final r = vm.addGame.result;
    if (!context.mounted) return;
    if (r case Ok(:final value)) {
      context.push(Routes.statsGame(vm.teamId, value));
    } else {
      showErrorSnackBar(context, r);
    }
  }

  Future<void> _delete(BuildContext context, StatsTournament t) async {
    final vm = viewModel;
    if (!await confirmDeleteTournament(context, t, vm.games.length)) return;
    await vm.deleteTournament.execute();
    if (!context.mounted) return;
    if (vm.deleteTournament.error) {
      showErrorSnackBar(context, vm.deleteTournament.result);
      vm.deleteTournament.clearResult();
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      final t = vm.tournament;
      if (!vm.loaded) {
        return Scaffold(appBar: AppBar(), body: const LoadingView());
      }
      if (t == null) {
        return Scaffold(
          appBar: AppBar(),
          body: vm.error != null
              ? ErrorView(error: vm.error)
              : const EmptyView(
                  icon: Icons.folder_off_outlined,
                  title: 'Tournament not found',
                ),
        );
      }
      return DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name),
                Text(
                  [
                    DateFormat.yMMMd().format(t.startDate),
                    if (t.location.isNotEmpty) t.location,
                    '${vm.wins}–${vm.losses}',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              if (vm.canDelete)
                IconButton(
                  tooltip: 'Delete tournament',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(context, t),
                ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Games'),
                Tab(text: 'Roster & lines'),
                Tab(text: 'Stats'),
              ],
            ),
          ),
          floatingActionButton: vm.canEdit
              ? FloatingActionButton.extended(
                  heroTag: 'add-game',
                  onPressed: () => _addGame(context),
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Add game'),
                )
              : null,
          body: TabBarView(
            children: [
              vm.games.isEmpty
                  ? const EmptyView(
                      icon: Icons.description_outlined,
                      title: 'No games yet',
                      message: 'Add a game to start tracking stats.',
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 96),
                      children: [
                        for (final (i, g) in vm.games.indexed)
                          GameRow(
                            game: g,
                            onTap: () =>
                                context.push(Routes.statsGame(vm.teamId, g.id)),
                            onDelete: vm.canDelete
                                ? () async {
                                    if (await confirmDeleteGame(context, g)) {
                                      if (!context.mounted) return;
                                      await runDelete(
                                        context,
                                        vm.deleteGame,
                                        () => vm.deleteGame.execute(g.id),
                                      );
                                    }
                                  }
                                : null,
                          ).withRound(i + 1),
                      ],
                    ),
              _RosterAndLines(viewModel: vm),
              StatSheetTable(sheet: vm.sheet, nameOf: vm.nameOf),
            ],
          ),
        ),
      );
    },
  );
}

extension on GameRow {
  /// Prefixes the row with its round number.
  Widget withRound(int round) => Row(
    children: [
      SizedBox(width: 48, child: Center(child: Text('R$round'))),
      Expanded(child: this),
    ],
  );
}

class _RosterAndLines extends StatelessWidget {
  const _RosterAndLines({required this.viewModel});

  final TournamentViewModel viewModel;

  Future<void> _editRoster(BuildContext context) async {
    final vm = viewModel;
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (_) => _RosterDialog(
        players: vm.allPlayers,
        initial: vm.tournament!.roster.toSet(),
      ),
    );
    if (picked != null) vm.setRoster(picked);
  }

  Future<void> _editLine(BuildContext context, [StatLine? line]) async {
    final vm = viewModel;
    final choice = await showLinePicker(
      context,
      available: vm.roster,
      initial: line?.players ?? const [],
      title: line == null ? 'New line' : 'Edit ${line.name}',
      requireName: true,
      defaultSide: line?.side,
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

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final roster = vm.roster;
    final lines = vm.tournament!.lines;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tournament roster (${roster.length})',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (vm.canEdit)
              TextButton.icon(
                onPressed: () => _editRoster(context),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
          ],
        ),
        if (roster.length < StatLine.size)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Add at least ${StatLine.size} players to build lines.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in roster)
              Chip(
                avatar: p.number == null ? null : JerseyNumber(p.number!),
                label: Text(p.name),
              ),
          ],
        ),
        const Divider(height: 32),
        Row(
          children: [
            Expanded(child: Text('Lines', style: theme.textTheme.titleMedium)),
            if (vm.canEdit)
              TextButton.icon(
                onPressed: roster.length < StatLine.size
                    ? null
                    : () => _editLine(context),
                icon: const Icon(Icons.add),
                label: const Text('New line'),
              ),
          ],
        ),
        Text(
          'Saved lines can be imported in any game in this tournament.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final l in lines)
          LineTile(
            line: l,
            nameOf: vm.nameOf,
            onTap: vm.canEdit ? () => _editLine(context, l) : null,
            onDelete: vm.canEdit ? () => vm.deleteLine(l.id) : null,
          ),
      ],
    );
  }
}

class _RosterDialog extends StatefulWidget {
  const _RosterDialog({required this.players, required this.initial});

  final List<RosterPlayer> players;
  final Set<String> initial;

  @override
  State<_RosterDialog> createState() => _RosterDialogState();
}

class _RosterDialogState extends State<_RosterDialog> {
  late final Set<String> _picked = {...widget.initial};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Who\'s attending? (${_picked.length})'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in widget.players)
              FilterChip(
                label: Text(p.name),
                selected: _picked.contains(p.id),
                onSelected: (on) => setState(
                  () => on ? _picked.add(p.id) : _picked.remove(p.id),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => setState(() {
          _picked
            ..clear()
            ..addAll(widget.players.map((p) => p.id));
        }),
        child: const Text('Select all'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, [
          for (final p in widget.players)
            if (_picked.contains(p.id)) p.id,
        ]),
        child: const Text('Save'),
      ),
    ],
  );
}

/// Opponent, game point and timeouts for a new tournament game.
class _AddGameDialog extends StatefulWidget {
  const _AddGameDialog({required this.gameTo, required this.timeouts});

  final int gameTo;
  final int timeouts;

  @override
  State<_AddGameDialog> createState() => _AddGameDialogState();
}

class _AddGameDialogState extends State<_AddGameDialog> {
  final _opponent = TextEditingController();
  late int _gameTo = widget.gameTo;
  late int _timeouts = widget.timeouts;

  @override
  void dispose() {
    _opponent.dispose();
    super.dispose();
  }

  void _done() {
    final name = _opponent.text.trim();
    if (name.isEmpty) return;
    Navigator.pop<NewTournamentGame>(context, (
      opponent: name,
      gameTo: _gameTo,
      timeoutsPerHalf: _timeouts,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add game'),
    content: SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _opponent,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Opponent'),
              onSubmitted: (_) => _done(),
            ),
            const SizedBox(height: 12),
            GameToField(
              value: _gameTo,
              onChanged: (v) => setState(() => _gameTo = v),
            ),
            const SizedBox(height: 12),
            TimeoutsField(
              value: _timeouts,
              onChanged: (v) => setState(() => _timeouts = v),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      ValueListenableBuilder(
        valueListenable: _opponent,
        builder: (context, value, _) => FilledButton(
          onPressed: value.text.trim().isEmpty ? null : _done,
          child: const Text('Add'),
        ),
      ),
    ],
  );
}
