import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/tournament_engine/generator.dart';
import '../../../domain/tournament_engine/league_weeks.dart';
import '../../../routing/routes.dart';
import '../../../routing/push_team_route.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';
import '../../core/ui/status_views.dart';
import '../../follow/widgets/follow_button.dart';
import '../../group_tournaments/widgets/tournament_widgets.dart';
import '../../teams/widgets/team_post_widgets.dart';
import '../view_models/event_guide.dart';
import '../view_models/hosted_tournament_viewmodel.dart';
import '../view_models/player_signups_viewmodel.dart';
import 'event_guide_cards.dart';
import 'event_page_header.dart';
import 'live_score_sheet.dart';
import 'player_signups_tab.dart';
import 'share_tournament.dart';
import 'tournament_dialogs.dart';
import 'tournament_parts.dart';

enum _Menu { edit, delete }

/// "Sat, May 1" or "Sat, May 1 – Sun, May 2".
String hostedDates(HostedTournament t) {
  final f = DateFormat('EEE, MMM d');
  final end = t.endsOn;
  return end == null || DateUtils.isSameDay(end, t.startsOn)
      ? f.format(t.startsOn)
      : '${f.format(t.startsOn)} – ${f.format(end)}';
}

/// The tabs of an event's page.
enum EventTab { overview, players, teams, schedule, results, news }

/// [t]'s tabs: Players where people sign up on their own, Teams where
/// teams enter (both, when teams can reserve spots too).
List<EventTab> eventTabs(HostedTournament t, {required bool hasSignups}) => [
  EventTab.overview,
  if (t.takesPlayers && hasSignups) EventTab.players,
  if (t.takesTeams || !hasSignups) EventTab.teams,
  EventTab.schedule,
  EventTab.results,
  EventTab.news,
];

/// The tab [t]'s page opens on: a game to open or an asked-for tab
/// (`schedule` or `results`) first; on a live event, the schedule with the
/// user's game; otherwise the first tab (null).
EventTab? startTab(
  HostedTournament t, {
  String? openGameId,
  String? initialTab,
}) => openGameId != null
    ? EventTab.schedule
    : switch (initialTab) {
        'schedule' => EventTab.schedule,
        'results' => EventTab.results,
        _ when t.status == HostedStatus.live => EventTab.schedule,
        _ => null,
      };

/// Whether [t]'s page wears the scoreboard-navy header: it's live, or its
/// schedule is out and it's on today.
bool onBoard(HostedTournament t, DateTime now) {
  if (t.status == HostedStatus.live) return true;
  if (t.status != HostedStatus.scheduled) return false;
  final today = DateUtils.dateOnly(now);
  final end = DateUtils.dateOnly(t.endsOn ?? t.startsOn);
  return !today.isBefore(DateUtils.dateOnly(t.startsOn)) && !today.isAfter(end);
}

/// Buttons on the navy header: the lighter navy, white text.
ThemeData _boardTheme(ThemeData theme, AppColors c) {
  final style = ButtonStyle(
    backgroundColor: WidgetStatePropertyAll(c.featureHighlight),
    foregroundColor: WidgetStatePropertyAll(c.onFeature),
    iconColor: WidgetStatePropertyAll(c.onFeature),
    side: const WidgetStatePropertyAll(BorderSide.none),
  );
  return theme.copyWith(
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: style.merge(theme.outlinedButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: style.merge(theme.filledButtonTheme.style),
    ),
  );
}

/// A hosted tournament: overview and bids, teams and seeds, schedule,
/// results and news, by division.
class HostedTournamentScreen extends StatefulWidget {
  const HostedTournamentScreen({
    super.key,
    required this.viewModel,
    this.signups,
    this.fallbackHostId,
    this.openGameId,
    this.openDivisionId,
    this.initialTab,
    this.share = shareTournament,
  });

  final HostedTournamentViewModel viewModel;

  /// Share in the app bar: the share sheet (tests pass their own).
  final ShareTournament share;

  /// A game to open (from a tournament-day card's Report score): the page
  /// starts on Schedule, in [openDivisionId], with the game's sheet up.
  final String? openGameId;
  final String? openDivisionId;

  /// `schedule` or `results`: the tab to start on.
  final String? initialTab;

  /// Players' signups, for player-entry tournaments and leagues; without
  /// it the page only takes teams.
  final PlayerSignupsViewModel? signups;

  /// A group whose hat tournament has this id, opened instead when
  /// there's no hosted tournament (follows don't say which it is).
  final String? fallbackHostId;

  @override
  State<HostedTournamentScreen> createState() => _HostedTournamentScreenState();
}

class _HostedTournamentScreenState extends State<HostedTournamentScreen> {
  HostedTournamentViewModel get vm => widget.viewModel;
  PlayerSignupsViewModel? get signups => widget.signups;
  late final List<Command<void>> _commands = [
    ...vm.commands,
    ...?signups?.commands,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
    vm.addListener(_syncManager);
    _syncManager();
  }

  @override
  void dispose() {
    vm.removeListener(_syncManager);
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    super.dispose();
  }

  /// The host loads after the tournament, so tell the signups when this
  /// user turns out to manage it. Also opens [HostedTournamentScreen.
  /// openGameId] once its division's games are in.
  void _syncManager() {
    signups?.setManager(vm.isManager);
    _openGame();
  }

  bool _gameOpened = false;

  void _openGame() {
    final id = widget.openGameId;
    if (id == null || _gameOpened || !vm.loaded) return;
    final division = widget.openDivisionId;
    if (division != null && vm.division?.id != division) {
      vm.selectDivision(division);
      if (vm.division?.id != division) return;
    }
    if (!vm.games.any((g) => g.id == id)) return;
    _gameOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _GameSheet(viewModel: vm, gameId: id),
      );
    });
  }

  void _onCommand() {
    if (vm.delete.completed) {
      vm.delete.clearResult();
      final host = vm.tournament?.hostId;
      context.go(host == null ? Routes.home : Routes.teamTournaments(host));
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
        context.push(Routes.editTournament(vm.tournamentId));
      case _Menu.delete:
        if (await confirmDialog(
          context,
          title: 'Delete ${vm.tournament?.name ?? 'tournament'}?',
          message:
              'Its divisions, teams, bids, schedule and scores are deleted '
              'for everyone.',
          confirmLabel: 'Delete',
          destructive: true,
        )) {
          vm.delete.execute();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        if (!vm.loaded) {
          return Scaffold(appBar: AppBar(), body: const LoadingView());
        }
        final t = vm.tournament;
        final fallback = widget.fallbackHostId;
        if (t == null && fallback != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.replace(
                Routes.groupTournament(fallback, vm.tournamentId),
              );
            }
          });
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
                    message: 'It may have been deleted or not published yet.',
                  ),
          );
        }
        final follow = vm.follow;
        final tabs = eventTabs(t, hasSignups: signups != null);
        final start = startTab(
          t,
          openGameId: widget.openGameId,
          initialTab: widget.initialTab,
        );
        final c = AppColors.of(context);
        final board = onBoard(t, DateTime.now());
        Widget actions(Widget child) => board
            ? Theme(data: _boardTheme(Theme.of(context), c), child: child)
            : child;
        return DefaultTabController(
          length: tabs.length,
          initialIndex: start == null ? 0 : tabs.indexOf(start).clamp(0, 99),
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 48,
              backgroundColor: board ? c.feature : c.background,
              foregroundColor: board ? c.onFeature : c.ink,
              actions: [
                if (follow != null && t.status.isPublished)
                  actions(FollowControl(viewModel: follow, compact: true)),
                // A draft has no public page to link to yet.
                if (t.status.isPublished)
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: 'Share',
                      icon: const Icon(Icons.ios_share_rounded),
                      onPressed: () {
                        final s = tournamentShare(t);
                        widget.share(context, s.text, s.link);
                      },
                    ),
                  ),
                if (vm.isManager)
                  PopupMenuButton<_Menu>(
                    onSelected: _onMenu,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _Menu.edit,
                        child: Text('Edit details'),
                      ),
                      PopupMenuItem(value: _Menu.delete, child: Text('Delete')),
                    ],
                  ),
                const SizedBox(width: 4),
              ],
              bottom: EventPageHeader.of(
                context,
                tournament: t,
                board: board,
                live: _liveHeadline(vm),
                tabs: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                  labelColor: board ? c.onFeature : null,
                  unselectedLabelColor: board ? c.onFeatureMuted : null,
                  indicator: board
                      ? UnderlineTabIndicator(
                          borderSide: BorderSide(color: c.onFeature, width: 3),
                        )
                      : null,
                  dividerColor: board ? Colors.transparent : null,
                  labelStyle: const TextStyle(
                    fontFamily: appFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: appFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                  tabs: [
                    for (final tab in tabs)
                      Tab(
                        text: switch (tab) {
                          EventTab.overview => 'Overview',
                          EventTab.players => 'Players',
                          EventTab.teams => 'Teams',
                          EventTab.schedule => 'Schedule',
                          EventTab.results =>
                            t.isLeague ? 'Standings' : 'Results',
                          EventTab.news => 'News',
                        },
                      ),
                  ],
                ),
              ),
            ),
            body: TabBarView(
              children: [
                for (final tab in tabs)
                  switch (tab) {
                    // Redrawn as signups load too: the guide counts them.
                    EventTab.overview => switch (signups) {
                      final s? => ListenableBuilder(
                        listenable: s,
                        builder: (_, _) =>
                            _OverviewTab(viewModel: vm, signups: signups),
                      ),
                      null => _OverviewTab(viewModel: vm),
                    },
                    EventTab.players => PlayersTab(
                      viewModel: vm,
                      signups: signups!,
                    ),
                    EventTab.teams => _TeamsTab(viewModel: vm),
                    EventTab.schedule => _ScheduleTab(viewModel: vm),
                    EventTab.results => _ResultsTab(viewModel: vm),
                    EventTab.news => _NewsTab(viewModel: vm),
                  },
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---- Shared pieces ---------------------------------------------------------

/// The game being played for the navy header: the user's own first, else
/// the first on the schedule; null when none is live.
LiveHeadline? _liveHeadline(HostedTournamentViewModel vm) {
  final live = vm.liveGames;
  if (live.isEmpty) return null;
  final g = live.firstWhere(
    (x) => vm.myTeamIn(x) != null,
    orElse: () => live.first,
  );
  final l = vm.liveOf(g)!;
  return (
    nameA: vm.slotLabel(g, a: true),
    nameB: vm.slotLabel(g, a: false),
    scoreA: l.scoreA,
    scoreB: l.scoreB,
    more: live.length - 1,
  );
}

/// "Teams need at least 7 players on their roster to register." When
/// divisions differ, the range.
String _rosterNote(List<TournamentDivision> divisions) {
  final mins = {
    for (final d in divisions) d.effectiveMinRoster,
    if (divisions.isEmpty) TournamentDivision.defaultMinRoster,
  }.toList()..sort();
  final need = mins.length == 1
      ? 'at least ${mins.first}'
      : 'at least ${mins.first}-${mins.last} (by division)';
  return 'Teams need $need players on their roster to register.';
}

class _Section extends StatelessWidget {
  const _Section(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Row(
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
                color: AppColors.of(context).ink,
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Chips to pick the division the tab shows.
class _DivisionPicker extends StatelessWidget {
  const _DivisionPicker({required this.viewModel});

  final HostedTournamentViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final divisions = vm.divisions;
    if (divisions.length < 2) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          for (final d in divisions)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(d.label),
                selected: d.id == vm.division?.id,
                onSelected: (_) => vm.selectDivision(d.id),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _noDivisions(HostedTournamentViewModel vm) => EmptyView(
  icon: Icons.category_outlined,
  title: 'No divisions yet',
  message: vm.isManager
      ? 'Add a division on the Overview tab.'
      : 'The host is still setting up divisions.',
);

// ---- Overview --------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.viewModel, this.signups});

  final HostedTournamentViewModel viewModel;
  final PlayerSignupsViewModel? signups;

  /// The format and which divisions are open live in the event form.
  void _editFormat(BuildContext context) =>
      context.push(Routes.editTournament(viewModel.tournamentId));

  /// Starts a team and reserves it a spot, then offers to invite players.
  Future<void> _reserve(BuildContext context) async {
    final vm = viewModel;
    if (signups?.isSignedUp ?? false) {
      showErrorSnackBar(
        context,
        Result<void>.error(
          Exception(
            "You're signed up on your own. Withdraw first to bring a team.",
          ),
        ),
      );
      return;
    }
    final t = vm.tournament!;
    final r = await showReserveSpotDialog(
      context,
      divisions: vm.divisions,
      fee: t.spotFee,
      minRoster: t.formatOr(vm.divisions.firstOrNull).effectiveMinRoster,
    );
    if (r == null || !context.mounted) return;
    await vm.reserveSpot.execute(r);
    if (!context.mounted) return;
    final result = vm.reserveSpot.result;
    vm.reserveSpot.clearResult();
    if (result case Ok(:final value)) {
      if (await confirmDialog(
        context,
        title: 'Spot reserved',
        message:
            '${r.name} is in, waiting for the host to accept it. Invite '
            'your players now: they join the team with its link.',
        confirmLabel: 'Invite players',
      )) {
        if (context.mounted) pushTeamRoute(context, Routes.teamMembers(value));
      }
    } else {
      showErrorSnackBar(context, result);
    }
  }

  Future<void> _apply(
    BuildContext context, {
    TournamentEntry? invite,
    TournamentEntry? editing,
  }) async {
    final vm = viewModel;
    final teams = invite != null || editing != null
        ? [?vm.myTeam((invite ?? editing)!.teamId)]
        : vm.teamsToEnter;
    final a = await showApplyDialog(
      context,
      teams: teams,
      divisions: vm.divisions,
      uid: vm.uid,
      invite: invite,
      editing: editing,
    );
    if (a == null) return;
    if (editing != null) {
      vm.updateCaptains.execute((entry: editing, captainIds: a.captainIds));
    } else {
      vm.apply.execute(a);
    }
  }

  /// Does what a guide button says: a dialog, a status change, a tab or
  /// a screen.
  Future<void> _act(BuildContext context, GuideButton b) async {
    final vm = viewModel;
    final tabs = DefaultTabController.of(context);
    final order = eventTabs(vm.tournament!, hasSignups: signups != null);
    void go(EventTab tab) {
      final i = order.indexOf(tab);
      if (i >= 0) tabs.animateTo(i);
    }

    final division = b.divisionId;
    switch (b.action) {
      case GuideAction.addDivision:
        _editFormat(context);
      case GuideAction.openRegistration:
        await vm.setStatus.execute(HostedStatus.registration);
      case GuideAction.closeRegistration:
        await vm.setStatus.execute(HostedStatus.seeding);
      case GuideAction.reviewPlayers:
        go(EventTab.players);
      case GuideAction.reviewTeams:
        go(EventTab.teams);
      case GuideAction.draftTeams:
        if (division != null) {
          context.push(Routes.tournamentDraft(vm.tournamentId, division));
        }
      case GuideAction.captainsDraft || GuideAction.watchDraft:
        if (division != null) {
          context.push(Routes.tournamentLiveDraft(vm.tournamentId, division));
        }
      case GuideAction.createTeams:
        final d = vm.divisionById(division);
        if (d == null) return;
        if (await confirmDialog(
          context,
          title: 'Create ${d.teams.length} teams?',
          message:
              'Each team is created with its captain as owner and the other '
              "players as members. You won't be able to redraft afterwards; "
              'rosters are managed on each team.',
          confirmLabel: 'Create teams',
        )) {
          await vm.createTeams.execute(d.id);
        }
      case GuideAction.publishSchedule:
        if (division != null) vm.selectDivision(division);
        go(EventTab.schedule);
      case GuideAction.schedule:
        go(EventTab.schedule);
      case GuideAction.results:
        go(EventTab.results);
      case GuideAction.reserveTeam:
        await _reserve(context);
      case GuideAction.signUp:
        final sign = signups;
        if (sign == null) return;
        if (vm.myActiveEntry case final e?) {
          showErrorSnackBar(
            context,
            Result<void>.error(
              Exception(
                "You're on ${e.teamName}, which is entered here, so you "
                "don't sign up on your own.",
              ),
            ),
          );
          return;
        }
        final a = await showPlayerSignupDialog(
          context,
          divisions: vm.divisions,
          initial: sign.mine?.status == SignupStatus.withdrawn
              ? null
              : sign.mine,
          fee: vm.tournament?.entryFee,
        );
        if (a != null) await sign.signUp.execute(a);
      case GuideAction.apply:
        await _apply(context);
      case GuideAction.acceptInvite:
        final invite = vm.myEntries
            .where((e) => e.status == EntryStatus.invited)
            .firstOrNull;
        if (invite != null) await _apply(context, invite: invite);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final t = vm.tournament!;
    final c = AppColors.of(context);
    final fee = t.spotFee;
    final guide = EventGuide.of(vm, signups);
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          EventHeader(tournament: t),
          const SizedBox(height: 12),
          GuideCard(guide: guide, onAction: (b) => _act(context, b)),
          if (vm.isManager && guide.steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            HostChecklist(
              steps: guide.steps,
              onAction: (b) => _act(context, b),
            ),
          ],
          // Their signup, until they're on a team.
          if (t.takesPlayers &&
              signups != null &&
              signups!.isSignedUp &&
              vm.myTeamIds.isEmpty)
            PlayerSignupCard(
              viewModel: vm,
              signups: signups!,
              showSignUp: false,
            ),
          _Section(
            'Divisions',
            trailing: vm.isManager
                ? TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    onPressed: () => _editFormat(context),
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Format & divisions'),
                  )
                : null,
          ),
          if (vm.divisions.isEmpty)
            Text(
              vm.isManager
                  ? 'Tick the divisions you run, e.g. Mixed and Women. They '
                        'all play the format you set.'
                  : 'No divisions yet.',
              style: TextStyle(color: c.ink2, fontSize: 14),
            ),
          if (vm.divisions.isNotEmpty)
            RowsCard(
              children: [
                for (final d in vm.divisions)
                  _DivisionRow(
                    division: d,
                    tournament: t,
                    viewModel: vm,
                    onEdit: () => _editFormat(context),
                  ),
              ],
            ),
          if (t.takesTeams &&
              (vm.myEntries.isNotEmpty || vm.canApply || vm.canReserve)) ...[
            const _Section('Your teams'),
            for (final e in vm.myEntries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MyEntryCard(
                  entry: e,
                  viewModel: vm,
                  fee: fee,
                  onApply: () => _apply(context, invite: e),
                  onCaptains: () => _apply(context, editing: e),
                ),
              ),
            if (vm.canReserve && vm.myActiveEntry == null) ...[
              FilledButton.icon(
                onPressed: () => _reserve(context),
                icon: const Icon(Icons.group_add_outlined),
                label: Text(
                  t.spotFee == null
                      ? 'Reserve a team spot'
                      : 'Reserve a team spot · ${t.spotFee!.label}',
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (vm.canApply && vm.myActiveEntry == null) ...[
              (t.mixedEntry ? OutlinedButton.icon : FilledButton.icon)(
                onPressed: () => _apply(context),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: Text(
                  t.mixedEntry
                      ? 'Use a team you already run'
                      : 'Apply with a team',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _rosterNote(vm.divisions),
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
              ),
            ],
          ] else if (!t.takesPlayers &&
              t.status.acceptsEntries &&
              t.visibility == TournamentVisibility.inviteOnly &&
              !vm.isManager) ...[
            const SizedBox(height: 16),
            Text(
              'Invite only: teams the host invites can play. Follow along '
              'for the schedule and results.',
              style: TextStyle(color: c.ink2, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}

/// A division on the overview: its name, how full it is (a turf bar for
/// events teams enter) and its format, with the host's menu.
class _DivisionRow extends StatelessWidget {
  const _DivisionRow({
    required this.division,
    required this.tournament,
    required this.viewModel,
    required this.onEdit,
  });

  final TournamentDivision division;
  final HostedTournament tournament;
  final HostedTournamentViewModel viewModel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final d = division;
    final t = tournament;
    final vm = viewModel;
    final filled = d.maxTeams == 0
        ? 0.0
        : (d.seeds.length / d.maxTeams).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (!t.takesPlayers)
                      '${d.seeds.length} of ${d.maxTeams} teams'
                    else if (d.teams.isNotEmpty)
                      '${d.teams.length} teams',
                    '${d.settings.playersOnField}v${d.settings.playersOnField}',
                    if (!t.takesPlayers) '${d.effectiveMinRoster}+ roster',
                    t.isLeague ? 'weekly' : d.settings.format.label,
                    d.settings.scoreLabel,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
                if (!t.takesPlayers) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: filled,
                      minHeight: 6,
                      color: d.isFull ? c.ink2 : c.accent,
                      backgroundColor: c.field,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (vm.isManager)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  onEdit();
                } else if (await confirmDialog(
                  context,
                  title: 'Remove ${d.label}?',
                  message: 'Its schedule and scores are deleted.',
                  confirmLabel: 'Remove',
                  destructive: true,
                )) {
                  vm.deleteDivision.execute(d.id);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Format & divisions')),
                PopupMenuItem(value: 'delete', child: Text('Remove')),
              ],
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }
}

/// One of the user's teams entered here: where its entry stands, its fee,
/// captains and roster, and what its admins can do.
class _MyEntryCard extends StatelessWidget {
  const _MyEntryCard({
    required this.entry,
    required this.viewModel,
    required this.fee,
    required this.onApply,
    required this.onCaptains,
  });

  final TournamentEntry entry;
  final HostedTournamentViewModel viewModel;
  final BidFee? fee;
  final VoidCallback onApply;
  final VoidCallback onCaptains;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final e = entry;
    final t = vm.tournament!;
    final accepted = e.status == EntryStatus.accepted;
    final (String, PillTone)? feePill = fee != null && accepted
        ? vm.isPaid(e.teamId)
              ? ('Bid paid', PillTone.turf)
              : vm.isOverdue(e.teamId)
              ? ('Bid fee overdue', PillTone.needsYou)
              : ('Bid fee unpaid', PillTone.needsYou)
        : null;
    final active = e.status.isActive || accepted;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TeamMark(name: e.teamName, mine: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.teamName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      Text(
                        [
                          e.status.label,
                          if (vm.divisionById(e.divisionId) case final d?)
                            d.label,
                        ].join(' · '),
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (feePill != null) ...[
              const SizedBox(height: 8),
              Pill(feePill.$1, tone: feePill.$2),
            ],
            if (e.captainIds.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Captains: ${[for (final id in e.captainIds) vm.myTeam(e.teamId)?.nameOf(id) ?? 'Member'].join(', ')}',
                style: TextStyle(fontSize: 12.5, color: c.ink2),
              ),
            ],
            if (vm.playersShort(e.teamId) case final short?
                when short > 0 && e.status != EntryStatus.withdrawn)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Needs $short more '
                  '${short == 1 ? 'player' : 'players'} for the '
                  'roster minimum.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.highlightInk,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (e.status == EntryStatus.invited && t.status.acceptsEntries)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.highlight,
                      foregroundColor: c.onHighlight,
                    ),
                    onPressed: onApply,
                    child: const Text('Accept invite'),
                  ),
                if (e.status != EntryStatus.invited && active)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    onPressed: onCaptains,
                    child: const Text('Captains'),
                  ),
                if (active)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    onPressed: () =>
                        pushTeamRoute(context, Routes.teamMembers(e.teamId)),
                    child: const Text('Invite players'),
                  ),
                if (active)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: c.muted),
                    onPressed: () async {
                      if (await confirmDialog(
                        context,
                        title: e.status == EntryStatus.invited
                            ? 'Decline the invite?'
                            : 'Withdraw ${e.teamName}?',
                        message: e.status == EntryStatus.invited
                            ? "${e.teamName} won't play. The host "
                                  'can invite you again.'
                            : '${e.teamName} is taken out of '
                                  '${t.name} and off your schedule. '
                                  'To play after all, you would '
                                  'have to apply again.',
                        confirmLabel: e.status == EntryStatus.invited
                            ? 'Decline'
                            : 'Withdraw',
                        destructive: true,
                      )) {
                        vm.decide.execute((
                          entry: e,
                          status: EntryStatus.withdrawn,
                        ));
                      }
                    },
                    child: Text(
                      e.status == EntryStatus.invited ? 'Decline' : 'Withdraw',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Teams -----------------------------------------------------------------

class _TeamsTab extends StatefulWidget {
  const _TeamsTab({required this.viewModel});

  final HostedTournamentViewModel viewModel;

  @override
  State<_TeamsTab> createState() => _TeamsTabState();
}

class _TeamsTabState extends State<_TeamsTab> {
  bool _unpaidOnly = false;

  HostedTournamentViewModel get vm => widget.viewModel;

  Widget _entryTile(TournamentEntry e) {
    final c = AppColors.of(context);
    final fee = vm.owesSpotFee(e.teamId) ? vm.tournament?.spotFee : null;
    final menu = <(String, EntryStatus)>[
      if (e.status != EntryStatus.accepted) ('Accept', EntryStatus.accepted),
      if (e.status != EntryStatus.waitlisted)
        ('Waitlist', EntryStatus.waitlisted),
      if (e.status != EntryStatus.declined) ('Decline', EntryStatus.declined),
    ];
    final decide = e.status == EntryStatus.applied;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.teamName,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                Text(
                  [
                    e.status.label,
                    if (fee != null && e.status == EntryStatus.accepted)
                      vm.isPaid(e.teamId)
                          ? 'Paid'
                          : vm.isOverdue(e.teamId)
                          ? 'Overdue'
                          : 'Unpaid',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ],
            ),
          ),
          if (decide) ...[
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: vm.decide.running
                  ? null
                  : () => vm.decide.execute((
                      entry: e,
                      status: EntryStatus.accepted,
                    )),
              child: const Text('Accept'),
            ),
          ],
          PopupMenuButton<EntryStatus>(
            onSelected: (s) => vm.decide.execute((entry: e, status: s)),
            itemBuilder: (_) => [
              for (final (label, s) in menu)
                PopupMenuItem(value: s, child: Text(label)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paidSwitch(String teamId) => Switch(
    value: vm.isPaid(teamId),
    onChanged: vm.setPaid.running
        ? null
        : (v) => vm.setPaid.execute((teamId: teamId, paid: v)),
  );

  @override
  Widget build(BuildContext context) {
    final d = vm.division;
    if (d == null) return _noDivisions(vm);
    final c = AppColors.of(context);
    final spotFee = vm.tournament?.spotFee;
    final fee = spotFee;
    final seeds = vm.seedsOf(d.id);
    final shown = [
      for (final id in seeds)
        if (!_unpaidOnly || !vm.isPaid(id)) id,
    ];
    final locked = vm.isPublished;
    final applied = vm.entriesIn(d.id, status: EntryStatus.applied);
    final waitlisted = vm.entriesIn(d.id, status: EntryStatus.waitlisted);
    final pending = [
      ...applied,
      ...vm.entriesIn(d.id, status: EntryStatus.invited),
      ...waitlisted,
    ];
    // Teams that withdrew (or were removed) are out: the host doesn't
    // decide on them again. They can apply again, or be invited.
    final out = vm.entriesIn(d.id, status: EntryStatus.declined);
    Widget seedTile(String id, int index) {
      // Drafted teams' players pay one by one, not as a team.
      final fee = d.draftedIds.contains(id) || !vm.owesSpotFee(id)
          ? null
          : spotFee;
      final overdue = fee != null && vm.isOverdue(id);
      final mine = vm.myEntries.any((e) => e.teamId == id);
      final showFee = fee != null && (vm.isManager || mine);
      return Material(
        key: ValueKey(id),
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 8, vm.isManager ? 4 : 14, 8),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.field,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ScoreText(
                  '${seeds.indexOf(id) + 1}',
                  size: 17,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vm.teamName(id),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    if (showFee) ...[
                      const SizedBox(height: 4),
                      Pill(
                        vm.isPaid(id)
                            ? 'Bid paid'
                            : overdue
                            ? 'Bid fee overdue'
                            : 'Bid fee unpaid',
                        // The user's own unpaid fee is theirs to do.
                        tone: vm.isPaid(id)
                            ? PillTone.turf
                            : mine
                            ? PillTone.needsYou
                            : PillTone.neutral,
                      ),
                    ],
                  ],
                ),
              ),
              if (vm.isManager) ...[
                if (fee != null) _paidSwitch(id),
                PopupMenuButton<EntryStatus>(
                  onSelected: (s) async {
                    final e = vm.entryOf(id);
                    if (e == null) return;
                    if (s == EntryStatus.withdrawn &&
                        !await confirmDialog(
                          context,
                          title: 'Remove ${e.teamName}?',
                          message:
                              "They're taken out of the tournament and off "
                              'their schedule. They can apply again, or '
                              'you can invite them.',
                          confirmLabel: 'Remove',
                          destructive: true,
                        )) {
                      return;
                    }
                    vm.decide.execute((entry: e, status: s));
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: EntryStatus.waitlisted,
                      child: Text('Move to waitlist'),
                    ),
                    PopupMenuItem(
                      value: EntryStatus.withdrawn,
                      child: Text('Remove'),
                    ),
                  ],
                ),
                if (!locked && !_unpaidOnly)
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle, color: c.muted),
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    List<Widget> divided(List<Widget> rows) => [
      for (final (i, r) in rows.indexed) ...[
        if (i > 0) Divider(key: ValueKey('divider-$i'), height: 1),
        r,
      ],
    ];

    return ListenableBuilder(
      listenable: Listenable.merge([vm.saveSeeds, vm.decide, vm.setPaid]),
      builder: (context, _) => ConstrainedContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _DivisionPicker(viewModel: vm),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    value: '${seeds.length}',
                    of: '/${d.maxTeams}',
                    label: 'Accepted',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    value: '${waitlisted.length}',
                    label: 'Waitlist',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    value: '${applied.length}',
                    label: 'Applied',
                    highlight: vm.isManager && applied.isNotEmpty,
                  ),
                ),
              ],
            ),
            if (vm.isManager && pending.isNotEmpty) ...[
              _Section(
                'Waiting',
                trailing: applied.isEmpty
                    ? null
                    : Text(
                        'Waiting on you',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c.highlightInk,
                        ),
                      ),
              ),
              RowsCard(children: [for (final e in pending) _entryTile(e)]),
            ],
            _Section(
              'Teams (${seeds.length} of ${d.maxTeams})',
              trailing: vm.isManager
                  ? TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: c.accent),
                      onPressed: () async {
                        final i = await showInviteDialog(
                          context,
                          viewModel: vm,
                          divisions: vm.divisions,
                          divisionId: d.id,
                        );
                        if (i != null) vm.invite.execute(i);
                      },
                      icon: const Icon(Icons.person_add_alt, size: 18),
                      label: const Text('Invite'),
                    )
                  : null,
            ),
            if (vm.isManager)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  locked
                      ? 'Seeds are set: the schedule is published. '
                            'Republishing on the Schedule tab regenerates '
                            'every game.'
                      : 'Drag to seed: 1 is the strongest. Pools and '
                            'brackets are built from this order.',
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ),
            if (vm.isManager && fee != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    label: const Text('Unpaid only'),
                    selected: _unpaidOnly,
                    onSelected: (v) => setState(() => _unpaidOnly = v),
                  ),
                ),
              ),
            if (seeds.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  vm.isManager
                      ? 'No teams yet. Accept applications above or invite '
                            'teams.'
                      : 'No teams accepted yet.',
                  style: TextStyle(color: c.ink2, fontSize: 14),
                ),
              )
            else if (vm.isManager && !locked && !_unpaidOnly)
              Card(
                child: ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: (from, to) {
                    final next = [...seeds];
                    final id = next.removeAt(from);
                    next.insert(to > from ? to - 1 : to, id);
                    vm.saveSeeds.execute(next);
                  },
                  children: [
                    for (final (i, id) in seeds.indexed)
                      DecoratedBox(
                        key: ValueKey(id),
                        decoration: BoxDecoration(
                          border: i == 0
                              ? null
                              : Border(top: BorderSide(color: c.border)),
                        ),
                        child: seedTile(id, i),
                      ),
                  ],
                ),
              )
            else if (shown.isNotEmpty)
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: divided([
                    for (final (i, id) in shown.indexed) seedTile(id, i),
                  ]),
                ),
              ),
            if (vm.isManager) ...[
              if (out.isNotEmpty) ...[
                const _Section('Declined'),
                RowsCard(children: [for (final e in out) _entryTile(e)]),
              ],
            ] else if (pending.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  '${pending.length} more '
                  '${pending.length == 1 ? 'team is' : 'teams are'} '
                  'waiting on the host.',
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- Schedule --------------------------------------------------------------

class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({required this.viewModel});

  final HostedTournamentViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final d = vm.division;
    if (d == null) return _noDivisions(vm);
    final c = AppColors.of(context);
    final games = vm.games;
    final focus = vm.gameNeedingMe;
    final upcoming = [
      for (final g in vm.myUpcoming)
        if (g.id != focus?.id) g,
    ];
    final league = vm.tournament?.isLeague == true;
    // The games, a card per day.
    final days = <List<GroupGame>>[];
    for (final (i, g) in games.indexed) {
      if (i == 0 ||
          g.startsAt == null ||
          !DateUtils.isSameDay(games[i - 1].startsAt, g.startsAt)) {
        days.add([g]);
      } else {
        days.last.add(g);
      }
    }
    return ListenableBuilder(
      listenable: Listenable.merge([vm.publish, vm.seedBracket]),
      builder: (context, _) => ConstrainedContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
          children: [
            _DivisionPicker(viewModel: vm),
            Text(
              '${d.label} · ${d.settings.format.label} · '
              '${d.settings.scoreLabel} · ${d.settings.fields} '
              '${d.settings.fields == 1 ? 'field' : 'fields'}',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
            if (focus != null) ...[
              const SizedBox(height: 12),
              _YourGameCard(viewModel: vm, game: focus),
            ],
            if (vm.isManager) _PublishCard(viewModel: vm),
            if (vm.canSeedBracket) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: c.highlight,
                  foregroundColor: c.onHighlight,
                ),
                onPressed: vm.seedBracket.running
                    ? null
                    : vm.seedBracket.execute,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Pools are done: seed the bracket'),
              ),
            ],
            if (upcoming.isNotEmpty) ...[
              const _Section('Your next games'),
              RowsCard(
                children: [
                  for (final g in upcoming.take(3))
                    _HostedGameTile(viewModel: vm, game: g),
                ],
              ),
            ],
            if (games.isEmpty && !vm.isManager)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  'The schedule appears here once the host publishes it.',
                  style: TextStyle(color: c.ink2, fontSize: 14),
                ),
              ),
            if (games.isNotEmpty) const _Section('All games'),
            // A league's season, a night at a time.
            if (league && games.isNotEmpty)
              _LeagueWeeks(viewModel: vm, division: d, games: games),
            // A tournament's, a card per day.
            if (!league)
              for (final day in days) ...[
                if (day.first.startsAt case final at?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Text(
                      gameDay(at),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink2,
                      ),
                    ),
                  ),
                RowsCard(
                  children: [
                    for (final g in day)
                      _HostedGameTile(viewModel: vm, game: g),
                  ],
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

/// A league's games a night at a time: "‹ Week 3 ›" with the night's
/// date and byes, then its games. Opens on tonight's night, else the next
/// one (the last once the season is over).
class _LeagueWeeks extends StatefulWidget {
  const _LeagueWeeks({
    required this.viewModel,
    required this.division,
    required this.games,
  });

  final HostedTournamentViewModel viewModel;
  final TournamentDivision division;
  final List<GroupGame> games;

  @override
  State<_LeagueWeeks> createState() => _LeagueWeeksState();
}

class _LeagueWeeksState extends State<_LeagueWeeks> {
  int? _picked;
  String? _divisionId;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final d = widget.division;
    final c = AppColors.of(context);
    final weeks = leagueWeeks(widget.games);
    if (weeks.isEmpty) return const SizedBox.shrink();
    // Another division starts over on its own current week.
    if (_divisionId != d.id) {
      _divisionId = d.id;
      _picked = null;
    }
    final i = (_picked ?? currentWeekIndex(weeks, vm.now())).clamp(
      0,
      weeks.length - 1,
    );
    final week = weeks[i];
    final rounds = {
      for (final g in week.games)
        if (g.stage == GameStage.pool) g.round,
    };
    final byes = {for (final r in rounds) ...byesIn(d.seeds, widget.games, r)};
    final arrows = IconButton.styleFrom(foregroundColor: c.accent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('week-previous'),
              tooltip: 'Previous week',
              style: arrows,
              onPressed: i > 0 ? () => setState(() => _picked = i - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded, size: 28),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    week.labelOf(leagueNights(weeks)),
                    key: const Key('week-label'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: scoreFont,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: c.ink,
                    ),
                  ),
                  if (week.day case final day?)
                    Text(
                      gameDay(day),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                ],
              ),
            ),
            IconButton(
              key: const Key('week-next'),
              tooltip: 'Next week',
              style: arrows,
              onPressed: i < weeks.length - 1
                  ? () => setState(() => _picked = i + 1)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded, size: 28),
            ),
          ],
        ),
        if (byes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(
              'Bye: ${byes.map(vm.teamName).join(', ')}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ),
        const SizedBox(height: 8),
        RowsCard(
          children: [
            for (final g in week.games) _HostedGameTile(viewModel: vm, game: g),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// The user's game that needs a score from them, up top with an amber
/// edge: the two teams, where and when, and Report (or Confirm) score.
class _YourGameCard extends StatelessWidget {
  const _YourGameCard({required this.viewModel, required this.game});

  final HostedTournamentViewModel viewModel;
  final GroupGame game;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final g = game;
    final confirm = vm.actionFor(g) == HostedGameAction.confirm;
    final r = g.report;
    final live = vm.liveOf(g);
    final mine = vm.myTeamIn(g);
    Widget side(String? team, bool a, int? score) {
      final name = vm.slotLabel(g, a: a);
      final me = team != null && team == mine;
      return Row(
        children: [
          TeamMark(name: name, mine: me),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: me ? FontWeight.w800 : FontWeight.w600,
                color: me ? c.ink : c.ink2,
              ),
            ),
          ),
          ScoreText(
            score == null ? '–' : '$score',
            size: 24,
            color: me ? c.ink : c.ink2,
          ),
        ],
      );
    }

    return Card(
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: c.highlight, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.highlightSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Eyebrow(
                        confirm
                            ? 'Your game · confirm the score'
                            : 'Your game · needs a score',
                        color: c.highlightInk,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (live != null) ...[
                  const LivePill(),
                  const SizedBox(width: 8),
                ],
                Text(
                  [
                    'Field ${g.field}',
                    if (g.startsAt != null) gameTime(g.startsAt),
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            side(g.teamA, true, confirm ? r?.scoreA : live?.scoreA),
            const SizedBox(height: 8),
            side(g.teamB, false, confirm ? r?.scoreB : live?.scoreB),
            const SizedBox(height: 10),
            Text(
              [
                'Game ${vm.gameNumber(g)}',
                g.label,
                if (vm.division case final d?) d.settings.scoreLabel,
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
            const SizedBox(height: 12),
            if (!confirm && vm.canKeepLive(g)) ...[
              FilledButton.icon(
                onPressed: () => showLiveScoreSheet(context, vm, g.id),
                icon: Icon(
                  live == null
                      ? Icons.play_arrow_rounded
                      : Icons.exposure_plus_1_rounded,
                ),
                label: Text(live == null ? 'Start game' : 'Update live score'),
              ),
              const SizedBox(height: 8),
            ],
            HighlightButton(
              label: confirm ? 'Confirm score' : 'Report score',
              icon: Icons.scoreboard_outlined,
              onPressed: () => _openGame(context, vm, g.id),
            ),
          ],
        ),
      ),
    );
  }
}

void _openGame(BuildContext context, HostedTournamentViewModel vm, String id) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _GameSheet(viewModel: vm, gameId: id),
    );

/// Generate and publish (or regenerate) the selected division's games.
class _PublishCard extends StatelessWidget {
  const _PublishCard({required this.viewModel});

  final HostedTournamentViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final d = vm.division!;
    final (:plan, :problem) = vm.preview();
    final c = AppColors.of(context);
    final played = vm.games.any((g) => g.status != GameStatus.scheduled);
    final days = plan?.days ?? const <ScheduleDay>[];
    final pools =
        d.settings.format.hasPools &&
        d.settings.format != TournamentFormat.roundRobin;
    final ready = plan != null && !vm.isPublished;
    final lastEnd = days.isEmpty ? null : days.last.endsAt;
    Future<void> publish() async {
      if (vm.isPublished &&
          !await confirmDialog(
            context,
            title: 'Regenerate the schedule?',
            message: played
                ? 'Scores already entered are lost: every game is '
                      'regenerated from the current seeds.'
                : 'Every game is regenerated from the current seeds.',
            confirmLabel: 'Regenerate',
            destructive: played,
          )) {
        return;
      }
      vm.publish.execute();
    }

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              vm.isPublished
                  ? 'Schedule published'
                  : ready
                  ? 'Schedule is ready to publish'
                  : 'Schedule',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 4),
            if (plan == null)
              Text(
                problem ??
                    (vm.tournament!.takesPlayers
                        ? 'Draft and save at least two teams first.'
                        : 'Accept at least two teams first.'),
                style: TextStyle(fontSize: 13.5, color: c.ink2),
              )
            else ...[
              Text(
                '${d.seeds.length} teams'
                '${pools ? ' · ${d.settings.poolCount} pools' : ''}\n'
                '${[for (final day in days) '${DateFormat('EEE').format(day.startsAt)} ${DateFormat.jm().format(day.startsAt)}–${DateFormat.jm().format(day.endsAt)}'].join(' · ')}',
                style: TextStyle(fontSize: 13.5, color: c.ink2),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      value: '${plan.games.length}',
                      label: 'Games',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      value: '${d.settings.fields}',
                      label: d.settings.fields == 1 ? 'Field' : 'Fields',
                    ),
                  ),
                  if (lastEnd != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatTile(
                        value: DateFormat('h:mm').format(lastEnd),
                        label: 'Last finish',
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (!vm.tournament!.isLeague &&
                d.seeds.length >= 2 &&
                d.settings.format != suggestedFormat(d.seeds.length))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tip: for ${d.seeds.length} teams, '
                  '${suggestedFormat(d.seeds.length).label.toLowerCase()} '
                  'usually works best.',
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ),
            const SizedBox(height: 12),
            if (vm.isPublished)
              OutlinedButton.icon(
                onPressed: plan == null || vm.publish.running ? null : publish,
                icon: const Icon(Icons.refresh),
                label: const Text('Regenerate schedule'),
              )
            else
              // Publishing is the host's to do: amber.
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: c.highlight,
                  foregroundColor: c.onHighlight,
                ),
                onPressed: plan == null || vm.publish.running ? null : publish,
                icon: const Icon(Icons.publish),
                label: const Text('Publish schedule'),
              ),
          ],
        ),
      ),
    );
  }
}

class _HostedGameTile extends StatelessWidget {
  const _HostedGameTile({required this.viewModel, required this.game});

  final HostedTournamentViewModel viewModel;
  final GroupGame game;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final g = game;
    final action = vm.actionFor(g);
    return HostedGameRow(
      game: g,
      number: vm.gameNumber(g),
      nameA: vm.slotLabel(g, a: true),
      nameB: vm.slotLabel(g, a: false),
      mine: vm.myTeamIn(g) != null,
      skipped: vm.isSkipped(g),
      action: switch (action) {
        HostedGameAction.report => 'Report score',
        HostedGameAction.confirm => 'Confirm score',
        _ => null,
      },
      waiting: action == HostedGameAction.awaiting,
      live: vm.liveOf(g),
      onTap: () => _openGame(context, vm, g.id),
    );
  }
}

/// A game's details, with score reporting for captains and overrides
/// for the host.
class _GameSheet extends StatelessWidget {
  const _GameSheet({required this.viewModel, required this.gameId});

  final HostedTournamentViewModel viewModel;
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
        final c = AppColors.of(context);
        final nameA = vm.slotLabel(g, a: true);
        final nameB = vm.slotLabel(g, a: false);
        final r = g.report;
        final live = vm.liveOf(g);
        final busy =
            vm.report.running || vm.confirm.running || vm.setFinalScore.running;
        final action = vm.actionFor(g);
        final mine = vm.myTeamIn(g);
        final amber = FilledButton.styleFrom(
          backgroundColor: c.highlight,
          foregroundColor: c.onHighlight,
        );

        Future<void> enter({
          required String title,
          required void Function(HostedScore) submit,
          String? message,
        }) async {
          final score = await showScoreDialog(
            context,
            title: title,
            nameA: nameA,
            nameB: nameB,
            // A running score fills it in; it's still checked and confirmed.
            scoreA: g.scoreA ?? r?.scoreA ?? live?.scoreA,
            scoreB: g.scoreB ?? r?.scoreB ?? live?.scoreB,
            message: message,
          );
          if (score != null) {
            submit((gameId: g.id, scoreA: score.$1, scoreB: score.$2));
          }
        }

        // The score shown: final, else the one reported, else the running one.
        final shownA = g.isDone ? g.scoreA : r?.scoreA ?? live?.scoreA;
        final shownB = g.isDone ? g.scoreB : r?.scoreB ?? live?.scoreB;
        Widget side(String name, String? team, int? score) {
          final me = team != null && team == mine;
          final won = g.winner != null && g.winner == team;
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                TeamMark(name: name, mine: me, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      if (me)
                        Text(
                          'Your team',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                    ],
                  ),
                ),
                ScoreText(
                  score == null ? '–' : '$score',
                  size: 34,
                  color: g.isDone && !won ? c.muted : c.ink,
                ),
              ],
            ),
          );
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
                        'Game ${vm.gameNumber(g)} · ${g.label}',
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
                    if (g.startsAt != null) gameTime(g.startsAt),
                    'Field ${g.field}',
                    if (vm.division case final d?) d.settings.scoreLabel,
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                if (r != null && !g.isDone) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: action == HostedGameAction.confirm
                          ? c.highlightSoft
                          : c.field,
                      borderRadius: BorderRadius.circular(controlRadius),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: action == HostedGameAction.confirm
                              ? c.highlightInk
                              : c.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${vm.teamName(r.byTeamId)} reported $nameA '
                            '${r.scoreA}, $nameB ${r.scoreB}.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: action == HostedGameAction.confirm
                                  ? c.highlightInk
                                  : c.ink2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      side(nameA, g.teamA, shownA),
                      const Divider(height: 1),
                      side(nameB, g.teamB, shownB),
                    ],
                  ),
                ),
                if (vm.isSkipped(g))
                  _SheetNote(
                    "Not needed: the winners' bracket champion won the final.",
                  )
                else if (!g.hasTeams)
                  _SheetNote('Teams are decided by earlier games.')
                else if (g.isDone)
                  _SheetNote('Final.')
                else if (live != null)
                  _SheetNote("Live score. It isn't final until it's reported."),
                const SizedBox(height: 16),
                if (vm.canKeepLive(g)) ...[
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () {
                            // Opened from the page, as this sheet closes.
                            final nav = Navigator.of(context)..pop();
                            showLiveScoreSheet(nav.context, vm, g.id);
                          },
                    icon: Icon(
                      live == null
                          ? Icons.play_arrow_rounded
                          : Icons.exposure_plus_1_rounded,
                    ),
                    label: Text(
                      live == null ? 'Start game' : 'Update live score',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (action == HostedGameAction.report)
                  FilledButton(
                    style: amber,
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
                if (action == HostedGameAction.confirm) ...[
                  FilledButton(
                    style: amber,
                    onPressed: busy ? null : () => vm.confirm.execute(g),
                    child: Text('Confirm ${r!.scoreA}–${r.scoreB}'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => enter(
                            title: 'Report a different score',
                            submit: vm.report.execute,
                          ),
                    child: const Text("That's not right"),
                  ),
                ],
                if (action == HostedGameAction.awaiting)
                  _SheetNote('Waiting for the other captain to confirm.'),
                if (vm.canSetScore(g)) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    onPressed: busy
                        ? null
                        : () => enter(
                            title: g.isDone
                                ? 'Correct the score'
                                : 'Set the final score',
                            message: 'As the host, this is final right away.',
                            submit: vm.setFinalScore.execute,
                          ),
                    child: Text(
                      g.isDone ? 'Correct the score' : 'Set final score',
                    ),
                  ),
                ],
                if (action == HostedGameAction.report ||
                    action == HostedGameAction.confirm)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      action == HostedGameAction.confirm
                          ? "Once you confirm, it's final and the standings "
                                "update. If it's wrong, send a different "
                                'score back.'
                          : 'The other captain confirms it before it counts.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SheetNote extends StatelessWidget {
  const _SheetNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      text,
      style: TextStyle(fontSize: 13.5, color: AppColors.of(context).ink2),
    ),
  );
}

// ---- Results ---------------------------------------------------------------

class _ResultsTab extends StatelessWidget {
  const _ResultsTab({required this.viewModel});

  final HostedTournamentViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final d = vm.division;
    if (d == null) return _noDivisions(vm);
    final c = AppColors.of(context);
    final places = vm.placements;
    final pools = vm.poolStandings;
    final mine = vm.myTeamIds;
    final hasBracket = vm.bracketGames.isNotEmpty;
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          _DivisionPicker(viewModel: vm),
          if (vm.games.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'Results show up here once games are played.',
                style: TextStyle(color: c.ink2, fontSize: 14),
              ),
            ),
          if (places.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: c.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.emoji_events_outlined,
                        size: 26,
                        color: c.accentInk,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${d.label} champion',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: c.muted,
                            ),
                          ),
                          Text(
                            vm.teamName(places.first),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: c.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const _Section('Final standings'),
            RowsCard(
              children: [
                for (final (i, id) in places.indexed)
                  Container(
                    color: mine.contains(id) ? c.accentSoft : null,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: ScoreText(
                            ordinal(i + 1),
                            size: 19,
                            color: mine.contains(id) ? c.accentInk : c.ink,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            vm.teamName(id),
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: mine.contains(id) ? c.accentInk : c.ink,
                            ),
                          ),
                        ),
                        if (d.seedOf(id) case final seed?)
                          Text(
                            'Seed $seed',
                            style: TextStyle(fontSize: 12.5, color: c.muted),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (pools.isNotEmpty) ...[
            _Section(vm.tournament?.isLeague == true ? 'Standings' : 'Pools'),
            for (final e in pools.entries) ...[
              if (pools.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  child: Text(
                    'Pool ${e.key}',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: c.ink2,
                    ),
                  ),
                ),
              HostedStandingsTable(
                rows: e.value,
                nameOf: vm.teamName,
                mine: mine,
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (hasBracket) ...[
            _Section(
              'Bracket',
              trailing: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: c.accent),
                onPressed: () => context.push(
                  Routes.tournamentBracket(vm.tournamentId, d.id),
                ),
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: const Text('Open bracket'),
              ),
            ),
            HostedBracket(viewModel: vm),
          ],
        ],
      ),
    );
  }
}

/// The selected division's bracket: a column per round, left to right,
/// each game a tile that opens its sheet (Report score and the rest).
/// On the Results tab and the bracket's own page.
class HostedBracket extends StatelessWidget {
  const HostedBracket({super.key, required this.viewModel});

  final HostedTournamentViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final columns = <(GameStage, int), List<GroupGame>>{};
    for (final g in vm.bracketGames) {
      columns.putIfAbsent((g.stage, g.round), () => []).add(g);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in columns.entries)
            SizedBox(
              width: 300,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Eyebrow(
                      e.value.map((g) => g.label).toSet().length == 1
                          ? e.value.first.label
                          : 'Round ${e.key.$2}',
                    ),
                    const SizedBox(height: 8),
                    for (final g in e.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: RowsCard(
                          children: [_HostedGameTile(viewModel: vm, game: g)],
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

// ---- News ------------------------------------------------------------------

class _NewsTab extends StatelessWidget {
  const _NewsTab({required this.viewModel});

  final HostedTournamentViewModel viewModel;

  Future<void> _post(BuildContext context) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Post an update'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Headline',
                  hintText: 'e.g. Semis start at 2pm on field 3',
                ),
              ),
              TextField(
                controller: body,
                maxLength: 2000,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Details'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    if (ok == true) {
      viewModel.postNews.execute((title: title.text, body: body.text));
    }
    title.dispose();
    body.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final t = vm.tournament!;
    final news = vm.news;
    final fab = vm.canPostNews && t.status.isPublished
        ? FloatingActionButton.extended(
            heroTag: 'tournament-news',
            onPressed: () => _post(context),
            icon: const Icon(Icons.campaign_outlined),
            label: const Text('Post update'),
          )
        : null;
    return Scaffold(
      floatingActionButton: fab,
      body: news.isEmpty
          ? EmptyView(
              icon: Icons.campaign_outlined,
              title: 'No news yet',
              message: vm.canPostNews
                  ? t.status.isPublished
                        ? "Post updates here: they go on ${t.hostName}'s "
                              'page too, and followers get them.'
                        : 'Publish the tournament to post updates.'
                  : 'Updates from ${t.hostName} show up here. Follow the '
                        'tournament to get them.',
            )
          : ConstrainedContent(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  for (final p in news)
                    TeamPostCard(
                      post: p,
                      loadImage: vm.loadImage,
                      teamName: t.hostName,
                      onOpenTeam: () => context.push(Routes.teamOver(t.hostId)),
                    ),
                ],
              ),
            ),
    );
  }
}
