import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show DateBadge;
import '../../core/ui/status_views.dart';
import '../../follow/view_models/follow_viewmodel.dart';
import '../../follow/widgets/follow_button.dart';
import '../../tournaments/widgets/tournament_parts.dart'
    show RowsCard, StatTile;
import '../view_models/group_tournament_viewmodel.dart';
import 'hat_parts.dart';
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
        final follow = vm.follow;
        final listing = vm.listing;
        if (t == null && listing != null) {
          return Scaffold(
            appBar: AppBar(title: Text(listing.name)),
            body: _PublicTournament(
              listing: listing,
              follow: follow,
              onOpenGroup: () => context.push(Routes.teamOver(vm.groupId)),
            ),
          );
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
                if (follow != null)
                  FollowControl(viewModel: follow, compact: true),
                if (vm.isOrganizer)
                  PopupMenuButton<_Menu>(
                    onSelected: _onMenu,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: _Menu.edit, child: Text('Setup')),
                      PopupMenuItem(value: _Menu.delete, child: Text('Delete')),
                    ],
                  ),
              ],
              bottom: SegmentedTabBar(tabs: tabs),
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
    final c = AppColors.of(context);
    final champ = vm.championId;
    final mine = vm.myTeam;
    final upcoming = vm.myUpcoming;
    final played = vm.games.where((g) => g.isDone).length;
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // The name is in the app bar; the hero says when and how.
          Row(
            children: [
              DateBadge(date: t.settings.startsAt, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tournamentWhen(t.settings.startsAt),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.accent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tournamentSummary(t),
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (vm.isScheduled) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: StatTile(value: '${t.teams.length}', label: 'Teams'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(value: '${vm.games.length}', label: 'Games'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    value: '$played',
                    of: '/${vm.games.length}',
                    label: 'Final',
                  ),
                ),
              ],
            ),
          ],
          if (champ != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(cardRadius),
              ),
              child: Row(
                children: [
                  Icon(Icons.emoji_events, color: c.accentInk, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${vm.teamName(champ)} wins!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.accentInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (mine != null) ...[
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c.accentSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        size: 20,
                        color: c.accentInk,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "You're on ${mine.name}",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (mine.captainId == vm.uid)
                                "You're the captain: report your scores"
                              else if (mine.captainId case final id?)
                                'Captain: ${mine.nameOf(id)}',
                              if (upcoming.isNotEmpty)
                                'Next: ${gameTime(upcoming.first.startsAt)}, '
                                    'field ${upcoming.first.field}',
                            ].join('\n'),
                            style: TextStyle(fontSize: 13, color: c.ink2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (vm.canSeedBracket) ...[
            const SizedBox(height: 12),
            NeedsYouPanel(
              eyebrow: 'Needs you · organizer',
              title: 'Every pool game is final',
              action: AmberButton(
                onPressed: vm.seedBracket.running
                    ? null
                    : vm.seedBracket.execute,
                icon: Icons.account_tree_outlined,
                label: 'Pools are done: seed the bracket',
              ),
            ),
          ],
          if (!vm.isScheduled) ...[
            const SizedBox(height: 14),
            if (vm.isOrganizer)
              NeedsYouPanel(
                eyebrow: 'Needs you · organizer',
                title:
                    'No schedule yet. Open Setup to make teams and '
                    'publish it.',
                action: AmberButton(
                  onPressed: () => _onMenu(_Menu.edit),
                  icon: Icons.groups_outlined,
                  label: 'Open setup',
                ),
              )
            else
              NotePanel(
                icon: Icons.schedule,
                title:
                    'The schedule will appear here once organizers publish '
                    'it.',
              ),
          ],
          for (final (i, g) in vm.games.indexed) ...[
            if (i == 0 ||
                (t.settings.laterDays.isNotEmpty &&
                    g.startsAt != null &&
                    !DateUtils.isSameDay(vm.games[i - 1].startsAt, g.startsAt)))
              HatHeading(
                g.startsAt != null ? gameDay(g.startsAt!) : 'Schedule',
                top: i == 0 ? 18 : 12,
              ),
            _gameTile(g),
          ],
        ],
      ),
    );
  }

  Widget _standings(BuildContext context) {
    final c = AppColors.of(context);
    final pools = vm.poolStandings;
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (pools.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'No pool games yet.',
                style: TextStyle(color: c.muted),
              ),
            ),
          for (final e in pools.entries) ...[
            if (pools.length > 1) HatHeading('Pool ${e.key}', top: 8),
            StandingsTable(rows: e.value, nameOf: vm.teamName),
            const SizedBox(height: 16),
          ],
          if (vm.awaitingBracketSeeds && !vm.canSeedBracket)
            Text(
              'The bracket is seeded from these standings once every pool '
              'game is final.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
        ],
      ),
    );
  }

  Widget _bracket(BuildContext context) {
    final c = AppColors.of(context);
    final columns = <(GameStage, int), List<GroupGame>>{};
    for (final g in vm.bracketGames) {
      columns.putIfAbsent((g.stage, g.round), () => []).add(g);
    }
    if (columns.isEmpty) {
      return Center(
        child: Text('No bracket games yet.', style: TextStyle(color: c.muted)),
      );
    }
    String title((GameStage, int) key, List<GroupGame> games) =>
        switch (key.$1) {
          GameStage.winners ||
          GameStage.crossover ||
          GameStage.placement => games.first.label,
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: c.ink,
                      ),
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
    final c = AppColors.of(context);
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          for (final team in t.teams)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              color: team.id == vm.myTeam?.id ? c.accentSoft : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            team.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: c.ink,
                            ),
                          ),
                        ),
                        Text(
                          '${team.playerIds.length}',
                          style: TextStyle(
                            fontFamily: scoreFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final uid in team.playerIds)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                              uid == team.captainId
                                  ? Icons.star
                                  : Icons.person_outline,
                              size: 18,
                              color: uid == team.captainId ? c.accent : c.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                team.nameOf(uid) +
                                    (uid == team.captainId
                                        ? ' (captain)'
                                        : '') +
                                    (uid == vm.uid ? ' · you' : ''),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: uid == vm.uid
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: c.ink,
                                ),
                              ),
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

        final c = AppColors.of(context);
        // Reporting and confirming are the captain's to do: amber.
        final todo = FilledButton.styleFrom(
          backgroundColor: c.highlight,
          foregroundColor: c.onHighlight,
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(
            fontFamily: appFont,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        );
        final note = TextStyle(fontSize: 13.5, color: c.ink2);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Game ${vm.gameNumber(g)} · ${g.label}',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (g.startsAt != null) gameTime(g.startsAt),
                    'Field ${g.field}',
                    if (vm.tournament case final t?)
                      'to ${t.settings.scoreCap}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                const SizedBox(height: 14),
                GameTile(game: g, nameA: nameA, nameB: nameB),
                if (vm.isSkipped(g))
                  Text(
                    "Not needed: the winners' bracket champion won the final.",
                    style: note,
                  )
                else if (!g.hasTeams)
                  Text('Teams are decided by earlier games.', style: note),
                if (r != null && !g.isDone) ...[
                  const SizedBox(height: 8),
                  Text(reported(r), style: note),
                ],
                const SizedBox(height: 14),
                if (action == GameAction.report)
                  FilledButton(
                    style: todo,
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
                    style: todo,
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
                  Text(
                    'Waiting for the other captain to confirm.',
                    style: note,
                  ),
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

/// What someone outside the tournament sees: when it is, how it's played,
/// and a Follow button for its updates.
class _PublicTournament extends StatelessWidget {
  const _PublicTournament({
    required this.listing,
    required this.follow,
    required this.onOpenGroup,
  });

  final TournamentListing listing;
  final FollowViewModel? follow;
  final VoidCallback onOpenGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = DateFormat('EEEE, MMM d');
    final end = listing.endsOn;
    final when = end == null
        ? '${day.format(listing.startsAt)} at '
              '${DateFormat.jm().format(listing.startsAt)}'
        : '${day.format(listing.startsAt)} to ${day.format(end)}';
    final status = switch (listing.status) {
      TournamentStatus.setup => 'Teams are being picked',
      TournamentStatus.scheduled => 'Schedule published',
      TournamentStatus.done => 'Finished',
    };
    final follow = this.follow;
    final c = AppColors.of(context);
    Widget fact(IconData icon, String title, [String? subtitle]) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return ConstrainedContent(
      maxWidth: 640,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              DateBadge(date: listing.startsAt, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hat tournament',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.accent,
                      ),
                    ),
                    Text(
                      listing.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          RowsCard(
            children: [
              fact(Icons.event_outlined, when),
              fact(Icons.account_tree_outlined, listing.format.label, status),
            ],
          ),
          const SizedBox(height: 14),
          if (follow != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FollowControl(viewModel: follow, showCount: true),
            ),
          const SizedBox(height: 16),
          Text(
            'Follow to see its updates on Home. To play, join the community and '
            'sign up there.',
            style: TextStyle(fontSize: 13.5, color: c.muted),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onOpenGroup,
              icon: const Icon(Icons.diversity_3_outlined),
              label: const Text('Open the community'),
            ),
          ),
        ],
      ),
    );
  }
}
