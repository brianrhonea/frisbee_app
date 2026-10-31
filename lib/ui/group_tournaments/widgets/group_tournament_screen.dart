import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/tournament_engine/standings.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/group_tournament_viewmodel.dart';
import 'tournament_widgets.dart';

enum _Menu { edit, delete }

/// A tournament: schedule, pools, bracket and teams. Captains report and
/// confirm scores from a game; organizers can set any score.
class GroupTournamentScreen extends StatefulWidget {
  const GroupTournamentScreen({super.key, required this.viewModel});

  final GroupTournamentViewModel viewModel;

  @override
  State<GroupTournamentScreen> createState() => _GroupTournamentScreenState();
}

class _GroupTournamentScreenState extends State<GroupTournamentScreen> {
  GroupTournamentViewModel get vm => widget.viewModel;

  late final List<Command<void>> _commands = [
    vm.report,
    vm.confirm,
    vm.setFinalScore,
    vm.seedBracket,
    vm.delete,
  ];

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
    if (vm.delete.completed) {
      vm.delete.clearResult();
      context.go(Routes.teamTournaments(vm.groupId));
      return;
    }
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  Future<void> _onMenu(_Menu action) async {
    switch (action) {
      case _Menu.edit:
        context.push(Routes.editGroupTournament(vm.groupId, vm.tournamentId));
      case _Menu.delete:
        if (await confirmDialog(
          context,
          title: 'Delete ${vm.tournament?.name ?? 'tournament'}?',
          message: 'Its teams, schedule and scores are deleted for everyone.',
          confirmLabel: 'Delete',
          destructive: true,
        )) {
          vm.delete.execute();
        }
    }
  }

  void _openGame(GroupGame g) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _GameSheet(viewModel: vm, gameId: g.id),
  );

  Widget _gameTile(GroupGame g) {
    final action = vm.actionFor(g);
    return GameTile(
      game: g,
      number: vm.gameNumber(g),
      nameA: vm.slotLabel(g, a: true),
      nameB: vm.slotLabel(g, a: false),
      highlight: g.involves(vm.myTeam?.id),
      skipped: vm.isSkipped(g),
      badge: switch (action) {
        GameAction.report => 'Report score',
        GameAction.confirm => 'Confirm score',
        GameAction.awaiting => 'Waiting for the other captain',
        null => null,
      },
      onTap: () => _openGame(g),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
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
                    icon: Icons.emoji_events_outlined,
                    title: 'Tournament not available',
                    message:
                        "It may have been deleted, or you're not on a team "
                        'in it.',
                  ),
          );
        }
        final format = t.settings.format;
        final tabs = [
          const Tab(text: 'Schedule'),
          if (format.hasPools) const Tab(text: 'Standings'),
          if (format.hasBracket) const Tab(text: 'Bracket'),
          const Tab(text: 'Teams'),
        ];
        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(t.name),
              actions: [
                if (vm.isOrganizer)
                  PopupMenuButton<_Menu>(
                    onSelected: _onMenu,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: _Menu.edit, child: Text('Setup')),
                      PopupMenuItem(value: _Menu.delete, child: Text('Delete')),
                    ],
                  ),
              ],
              bottom: TabBar(tabs: tabs, isScrollable: true),
            ),
            body: TabBarView(
              children: [
                _schedule(context, t),
                if (format.hasPools) _standings(context),
                if (format.hasBracket) _bracket(context),
                _teams(context, t),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _schedule(BuildContext context, GroupTournament t) {
    final theme = Theme.of(context);
    final champ = vm.championId;
    final mine = vm.myTeam;
    final upcoming = vm.myUpcoming;
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            tournamentWhen(t.settings.startsAt),
            style: theme.textTheme.titleSmall,
          ),
          Text(tournamentSummary(t), style: theme.textTheme.bodySmall),
          if (champ != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.amber.shade100,
              child: ListTile(
                leading: const Icon(Icons.emoji_events, color: Colors.amber),
                title: Text('${vm.teamName(champ)} wins!'),
                textColor: Colors.black87,
              ),
            ),
          ],
          if (mine != null) ...[
            const SizedBox(height: 12),
            Card.outlined(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text("You're on ${mine.name}"),
                subtitle: Text(
                  [
                    if (mine.captainId == vm.uid)
                      "You're the captain: report your scores"
                    else if (mine.captainId case final c?)
                      'Captain: ${mine.nameOf(c)}',
                    if (upcoming.isNotEmpty)
                      'Next: ${gameTime(upcoming.first.startsAt)}, field '
                          '${upcoming.first.field}',
                  ].join('\n'),
                ),
              ),
            ),
          ],
          if (vm.canSeedBracket) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: vm.seedBracket.running ? null : vm.seedBracket.execute,
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Pools are done: seed the bracket'),
            ),
          ],
          const SizedBox(height: 16),
          if (!vm.isScheduled)
            Text(
              vm.isOrganizer
                  ? 'No schedule yet. Open Setup to make teams and publish it.'
                  : 'The schedule will appear here once organizers publish it.',
              style: theme.textTheme.bodyMedium,
            ),
          for (final g in vm.games) _gameTile(g),
        ],
      ),
    );
  }

  Widget _standings(BuildContext context) {
    final theme = Theme.of(context);
    final pools = vm.poolStandings;
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (pools.isEmpty) const Text('No pool games yet.'),
          for (final e in pools.entries) ...[
            if (pools.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  'Pool ${e.key}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            _StandingsTable(rows: e.value, nameOf: vm.teamName),
            const SizedBox(height: 16),
          ],
          if (vm.awaitingBracketSeeds && !vm.canSeedBracket)
            Text(
              'The bracket is seeded from these standings once every pool '
              'game is final.',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _bracket(BuildContext context) {
    final theme = Theme.of(context);
    final columns = <(GameStage, int), List<GroupGame>>{};
    for (final g in vm.bracketGames) {
      columns.putIfAbsent((g.stage, g.round), () => []).add(g);
    }
    if (columns.isEmpty) {
      return const Center(child: Text('No bracket games yet.'));
    }
    String title((GameStage, int) key, List<GroupGame> games) =>
        switch (key.$1) {
          GameStage.winners => games.first.label,
          GameStage.losers => "Losers' round ${key.$2}",
          GameStage.grandFinal => 'Final',
          GameStage.reset => 'Final (if needed)',
          GameStage.pool => 'Pool',
        };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in columns.entries)
            SizedBox(
              width: 260,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title(e.key, e.value),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final g in e.value) _gameTile(g),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _teams(BuildContext context, GroupTournament t) {
    final theme = Theme.of(context);
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final team in t.teams)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: team.id == vm.myTeam?.id
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    for (final uid in team.playerIds)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              uid == team.captainId
                                  ? Icons.star
                                  : Icons.person_outline,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              team.nameOf(uid) +
                                  (uid == team.captainId ? ' (captain)' : '') +
                                  (uid == vm.uid ? ' · you' : ''),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StandingsTable extends StatelessWidget {
  const _StandingsTable({required this.rows, required this.nameOf});

  final List<Standing> rows;
  final String Function(String?) nameOf;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(36),
            1: FlexColumnWidth(),
            2: FixedColumnWidth(44),
            3: FixedColumnWidth(44),
            4: FixedColumnWidth(52),
          },
          children: [
            TableRow(
              children: [
                for (final h in ['#', 'Team', 'W', 'L', '+/-'])
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(h, style: style),
                  ),
              ],
            ),
            for (var i = 0; i < rows.length; i++)
              TableRow(
                children: [
                  for (final cell in [
                    '${i + 1}',
                    nameOf(rows[i].teamId),
                    '${rows[i].wins}',
                    '${rows[i].losses}',
                    '${rows[i].pointDiff > 0 ? '+' : ''}${rows[i].pointDiff}',
                  ])
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(cell),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A game's details and what the user can do: report, confirm or dispute
/// a score as a captain, or set it as an organizer.
class _GameSheet extends StatelessWidget {
  const _GameSheet({required this.viewModel, required this.gameId});

  final GroupTournamentViewModel viewModel;
  final String gameId;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: Listenable.merge([
        vm,
        vm.report,
        vm.confirm,
        vm.setFinalScore,
      ]),
      builder: (context, _) {
        final g = vm.games.where((x) => x.id == gameId).firstOrNull;
        if (g == null) return const SizedBox(height: 120);
        final theme = Theme.of(context);
        final nameA = vm.slotLabel(g, a: true);
        final nameB = vm.slotLabel(g, a: false);
        final r = g.report;
        final busy =
            vm.report.running || vm.confirm.running || vm.setFinalScore.running;
        final action = vm.actionFor(g);
        String reported(ScoreReport r) =>
            '${vm.teamName(r.byTeamId)} reported $nameA ${r.scoreA}, '
            '$nameB ${r.scoreB}.';

        Future<void> enter({
          required String title,
          required void Function(GameScore) submit,
          String? message,
        }) async {
          final score = await showScoreDialog(
            context,
            title: title,
            nameA: nameA,
            nameB: nameB,
            scoreA: g.scoreA ?? r?.scoreA,
            scoreB: g.scoreB ?? r?.scoreB,
            message: message,
          );
          if (score != null) {
            submit((gameId: g.id, scoreA: score.$1, scoreB: score.$2));
          }
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Game ${vm.gameNumber(g)} · ${g.label}',
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  [
                    if (g.startsAt != null) gameTime(g.startsAt),
                    'Field ${g.field}',
                    if (vm.tournament case final t?)
                      'to ${t.settings.scoreCap}',
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                GameTile(game: g, nameA: nameA, nameB: nameB),
                if (vm.isSkipped(g))
                  const Text(
                    "Not needed: the winners' bracket champion won the final.",
                  )
                else if (!g.hasTeams)
                  const Text('Teams are decided by earlier games.'),
                if (r != null && !g.isDone) ...[
                  const SizedBox(height: 8),
                  Text(reported(r)),
                ],
                const SizedBox(height: 16),
                if (action == GameAction.report)
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => enter(
                            title: 'Report the score',
                            message:
                                'The other captain confirms it before it '
                                'counts.',
                            submit: vm.report.execute,
                          ),
                    child: const Text('Report score'),
                  ),
                if (action == GameAction.confirm) ...[
                  FilledButton(
                    onPressed: busy ? null : () => vm.confirm.execute(g),
                    child: Text('Confirm ${r!.scoreA}–${r.scoreB}'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => enter(
                            title: 'Report a different score',
                            message:
                                'The other captain will be asked to confirm '
                                'yours instead.',
                            submit: vm.report.execute,
                          ),
                    child: const Text("That's not right"),
                  ),
                ],
                if (action == GameAction.awaiting) ...[
                  const Text('Waiting for the other captain to confirm.'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => enter(
                            title: 'Change your report',
                            submit: vm.report.execute,
                          ),
                    child: const Text('Change my report'),
                  ),
                ],
                if (vm.canSetScore(g)) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => enter(
                            title: g.isDone
                                ? 'Correct the score'
                                : 'Set the final score',
                            message:
                                'As an organizer, this is final right '
                                'away.',
                            submit: vm.setFinalScore.execute,
                          ),
                    child: Text(
                      g.isDone ? 'Correct the score' : 'Set final score',
                    ),
                  ),
                ],
                if (vm.report.error ||
                    vm.confirm.error ||
                    vm.setFinalScore.error)
                  Text(
                    errorMessage(
                      vm.report.result ??
                          vm.confirm.result ??
                          vm.setFinalScore.result,
                    ),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
