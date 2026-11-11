import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/tournament_engine/generator.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../follow/widgets/follow_button.dart';
import '../../group_tournaments/widgets/tournament_widgets.dart';
import '../../teams/widgets/team_post_widgets.dart';
import '../view_models/event_guide.dart';
import '../view_models/hosted_tournament_viewmodel.dart';
import '../view_models/player_signups_viewmodel.dart';
import 'event_guide_cards.dart';
import 'player_signups_tab.dart';
import 'tournament_dialogs.dart';

enum _Menu { edit, delete }

/// "Sat, May 1" or "Sat, May 1 – Sun, May 2".
String hostedDates(HostedTournament t) {
  final f = DateFormat('EEE, MMM d');
  final end = t.endsOn;
  return end == null || DateUtils.isSameDay(end, t.startsOn)
      ? f.format(t.startsOn)
      : '${f.format(t.startsOn)} – ${f.format(end)}';
}

/// A hosted tournament: overview and bids, teams and seeds, schedule,
/// results and news, by division.
class HostedTournamentScreen extends StatefulWidget {
  const HostedTournamentScreen({
    super.key,
    required this.viewModel,
    this.signups,
    this.fallbackHostId,
  });

  final HostedTournamentViewModel viewModel;

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
  /// user turns out to manage it.
  void _syncManager() => signups?.setManager(vm.isManager);

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
        // Players sign up one by one; teams are drafted from them.
        final players = t.takesPlayers && signups != null;
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: Text(t.name),
              actions: [
                if (follow != null && t.status.isPublished)
                  FollowControl(viewModel: follow, compact: true),
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
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  const Tab(text: 'Overview'),
                  Tab(text: players ? 'Players' : 'Teams'),
                  const Tab(text: 'Schedule'),
                  Tab(text: t.isLeague ? 'Standings' : 'Results'),
                  const Tab(text: 'News'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                // Redrawn as signups load too: the guide counts them.
                if (signups case final s?)
                  ListenableBuilder(
                    listenable: s,
                    builder: (_, _) =>
                        _OverviewTab(viewModel: vm, signups: signups),
                  )
                else
                  _OverviewTab(viewModel: vm),
                if (players)
                  PlayersTab(viewModel: vm, signups: signups!)
                else
                  _TeamsTab(viewModel: vm),
                _ScheduleTab(viewModel: vm),
                _ResultsTab(viewModel: vm),
                _NewsTab(viewModel: vm),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---- Shared pieces ---------------------------------------------------------

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
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
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
    final division = b.divisionId;
    switch (b.action) {
      case GuideAction.addDivision:
        _editFormat(context);
      case GuideAction.openRegistration:
        await vm.setStatus.execute(HostedStatus.registration);
      case GuideAction.closeRegistration:
        await vm.setStatus.execute(HostedStatus.seeding);
      case GuideAction.reviewPlayers || GuideAction.reviewTeams:
        tabs.animateTo(1);
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
        tabs.animateTo(2);
      case GuideAction.schedule:
        tabs.animateTo(2);
      case GuideAction.results:
        tabs.animateTo(3);
      case GuideAction.signUp:
        final sign = signups;
        if (sign == null) return;
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
    final theme = Theme.of(context);
    final fee = t.bidFee;
    final guide = EventGuide.of(vm, signups);
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          EventHeader(tournament: t),
          const SizedBox(height: 16),
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
                    onPressed: () => _editFormat(context),
                    icon: const Icon(Icons.tune),
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
              style: theme.textTheme.bodyMedium,
            ),
          for (final d in vm.divisions)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(d.label),
                subtitle: Text(
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
                ),
                trailing: vm.isManager
                    ? PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            _editFormat(context);
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
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Format & divisions'),
                          ),
                          PopupMenuItem(value: 'delete', child: Text('Remove')),
                        ],
                      )
                    : null,
              ),
            ),
          if (!t.takesPlayers && (vm.myEntries.isNotEmpty || vm.canApply)) ...[
            const _Section('Your teams'),
            for (final e in vm.myEntries)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.teamName, style: theme.textTheme.titleSmall),
                      Text(
                        [
                          e.status.label,
                          if (vm.divisionById(e.divisionId) case final d?)
                            d.label,
                          if (fee != null && e.status == EntryStatus.accepted)
                            vm.isPaid(e.teamId)
                                ? 'Bid paid'
                                : vm.isOverdue(e.teamId)
                                ? 'Bid fee overdue'
                                : 'Bid fee unpaid',
                        ].join(' · '),
                      ),
                      if (e.captainIds.isNotEmpty)
                        Text(
                          'Captains: ${[for (final c in e.captainIds) vm.myTeam(e.teamId)?.nameOf(c) ?? 'Member'].join(', ')}',
                          style: theme.textTheme.bodySmall,
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (e.status == EntryStatus.invited &&
                              t.status.acceptsEntries)
                            FilledButton(
                              onPressed: () => _apply(context, invite: e),
                              child: const Text('Accept invite'),
                            ),
                          if (e.status != EntryStatus.invited &&
                              (e.status.isActive ||
                                  e.status == EntryStatus.accepted))
                            TextButton(
                              onPressed: () => _apply(context, editing: e),
                              child: const Text('Captains'),
                            ),
                          if (e.status.isActive ||
                              e.status == EntryStatus.accepted)
                            TextButton(
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
                                e.status == EntryStatus.invited
                                    ? 'Decline'
                                    : 'Withdraw',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (vm.canApply) ...[
              FilledButton.icon(
                onPressed: () => _apply(context),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: const Text('Apply with a team'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _rosterNote(vm.divisions),
                  style: theme.textTheme.bodySmall,
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
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
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
    final fee = vm.tournament?.bidFee;
    final menu = <(String, EntryStatus)>[
      if (e.status != EntryStatus.accepted) ('Accept', EntryStatus.accepted),
      if (e.status != EntryStatus.waitlisted)
        ('Waitlist', EntryStatus.waitlisted),
      if (e.status != EntryStatus.declined) ('Decline', EntryStatus.declined),
    ];
    return ListTile(
      title: Text(e.teamName),
      subtitle: Text(
        [
          e.status.label,
          if (fee != null && e.status == EntryStatus.accepted)
            vm.isPaid(e.teamId)
                ? 'Paid'
                : vm.isOverdue(e.teamId)
                ? 'Overdue'
                : 'Unpaid',
        ].join(' · '),
      ),
      trailing: PopupMenuButton<EntryStatus>(
        onSelected: (s) => vm.decide.execute((entry: e, status: s)),
        itemBuilder: (_) => [
          for (final (label, s) in menu)
            PopupMenuItem(value: s, child: Text(label)),
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
    final theme = Theme.of(context);
    final fee = vm.tournament?.bidFee;
    final seeds = vm.seedsOf(d.id);
    final shown = [
      for (final id in seeds)
        if (!_unpaidOnly || !vm.isPaid(id)) id,
    ];
    final locked = vm.isPublished;
    final pending = [
      for (final s in [
        EntryStatus.applied,
        EntryStatus.invited,
        EntryStatus.waitlisted,
      ])
        ...vm.entriesIn(d.id, status: s),
    ];
    // Teams that withdrew (or were removed) are out: the host doesn't
    // decide on them again. They can apply again, or be invited.
    final out = vm.entriesIn(d.id, status: EntryStatus.declined);
    Widget seedTile(String id, int index) {
      final overdue = fee != null && vm.isOverdue(id);
      return ListTile(
        key: ValueKey(id),
        leading: CircleAvatar(child: Text('${seeds.indexOf(id) + 1}')),
        title: Text(vm.teamName(id)),
        subtitle:
            fee == null ||
                !(vm.isManager || vm.myEntries.any((e) => e.teamId == id))
            ? null
            : Text(
                vm.isPaid(id)
                    ? 'Bid paid'
                    : overdue
                    ? 'Bid fee overdue'
                    : 'Bid fee unpaid',
                style: overdue
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
              ),
        trailing: vm.isManager
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                ],
              )
            : null,
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([vm.saveSeeds, vm.decide, vm.setPaid]),
      builder: (context, _) => ConstrainedContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _DivisionPicker(viewModel: vm),
            _Section(
              'Teams (${seeds.length} of ${d.maxTeams})',
              trailing: vm.isManager
                  ? TextButton.icon(
                      onPressed: () async {
                        final i = await showInviteDialog(
                          context,
                          viewModel: vm,
                          divisions: vm.divisions,
                          divisionId: d.id,
                        );
                        if (i != null) vm.invite.execute(i);
                      },
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Invite'),
                    )
                  : null,
            ),
            if (vm.isManager)
              Text(
                locked
                    ? 'Seeds are set: the schedule is published. Republishing '
                          'on the Schedule tab regenerates every game.'
                    : 'Drag to seed: 1 is the strongest. Pools and brackets '
                          'are built from this order.',
                style: theme.textTheme.bodySmall,
              ),
            if (vm.isManager && fee != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
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
                      ? 'No teams yet. Accept applications below or invite '
                            'teams.'
                      : 'No teams accepted yet.',
                ),
              ),
            if (vm.isManager && !locked && !_unpaidOnly)
              ReorderableListView(
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
                  for (final (i, id) in seeds.indexed) seedTile(id, i),
                ],
              )
            else
              for (final (i, id) in shown.indexed) seedTile(id, i),
            if (vm.isManager) ...[
              if (pending.isNotEmpty) ...[
                const _Section('Waiting'),
                for (final e in pending) _entryTile(e),
              ],
              if (out.isNotEmpty) ...[
                const _Section('Declined'),
                for (final e in out) _entryTile(e),
              ],
            ] else if (pending.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  '${pending.length} more '
                  '${pending.length == 1 ? 'team is' : 'teams are'} '
                  'waiting on the host.',
                  style: theme.textTheme.bodySmall,
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
    final theme = Theme.of(context);
    final games = vm.games;
    final upcoming = vm.myUpcoming;
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
              style: theme.textTheme.bodyMedium,
            ),
            if (vm.isManager) _PublishCard(viewModel: vm),
            if (vm.canSeedBracket) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: vm.seedBracket.running
                    ? null
                    : vm.seedBracket.execute,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Pools are done: seed the bracket'),
              ),
            ],
            if (upcoming.isNotEmpty) ...[
              const _Section('Your next games'),
              for (final g in upcoming.take(3))
                _HostedGameTile(viewModel: vm, game: g),
            ],
            if (games.isEmpty && !vm.isManager)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text(
                  'The schedule appears here once the host publishes it.',
                ),
              ),
            if (games.isNotEmpty) const _Section('All games'),
            for (final (i, g) in games.indexed) ...[
              if (g.startsAt != null &&
                  (i == 0 ||
                      !DateUtils.isSameDay(games[i - 1].startsAt, g.startsAt)))
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vm.tournament?.isLeague == true
                            ? '${g.stage == GameStage.pool ? 'Week ${g.round}' : 'Playoffs'} · ${gameDay(g.startsAt!)}'
                            : gameDay(g.startsAt!),
                        style: theme.textTheme.titleSmall,
                      ),
                      if (vm.tournament?.isLeague == true &&
                          g.stage == GameStage.pool)
                        if (byesIn(d.seeds, games, g.round) case final byes
                            when byes.isNotEmpty)
                          Text(
                            'Bye: ${byes.map(vm.teamName).join(', ')}',
                            style: theme.textTheme.bodySmall,
                          ),
                    ],
                  ),
                ),
              _HostedGameTile(viewModel: vm, game: g),
            ],
          ],
        ),
      ),
    );
  }
}

/// Generate and publish (or regenerate) the selected division's games.
class _PublishCard extends StatelessWidget {
  const _PublishCard({required this.viewModel});

  final HostedTournamentViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final d = vm.division!;
    final (:plan, :problem) = vm.preview();
    final theme = Theme.of(context);
    final played = vm.games.any((g) => g.status != GameStatus.scheduled);
    final days = plan?.days ?? const <ScheduleDay>[];
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vm.isPublished ? 'Schedule published' : 'Schedule',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            if (plan == null)
              Text(
                problem ??
                    (vm.tournament!.takesPlayers
                        ? 'Draft and save at least two teams first.'
                        : 'Accept at least two teams first.'),
              )
            else
              Text(
                '${d.seeds.length} teams · ${plan.games.length} games'
                '${d.settings.format.hasPools && d.settings.format != TournamentFormat.roundRobin ? ' · ${d.settings.poolCount} pools' : ''}\n'
                '${[for (final day in days) '${DateFormat('EEE').format(day.startsAt)} ${DateFormat.jm().format(day.startsAt)}–${DateFormat.jm().format(day.endsAt)}'].join(' · ')}',
              ),
            if (!vm.tournament!.isLeague &&
                d.seeds.length >= 2 &&
                d.settings.format != suggestedFormat(d.seeds.length))
              Text(
                'Tip: for ${d.seeds.length} teams, '
                '${suggestedFormat(d.seeds.length).label.toLowerCase()} '
                'usually works best.',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: plan == null || vm.publish.running
                  ? null
                  : () async {
                      if (vm.isPublished &&
                          !await confirmDialog(
                            context,
                            title: 'Regenerate the schedule?',
                            message: played
                                ? 'Scores already entered are lost: every '
                                      'game is regenerated from the current '
                                      'seeds.'
                                : 'Every game is regenerated from the '
                                      'current seeds.',
                            confirmLabel: 'Regenerate',
                            destructive: played,
                          )) {
                        return;
                      }
                      vm.publish.execute();
                    },
              icon: Icon(vm.isPublished ? Icons.refresh : Icons.publish),
              label: Text(
                vm.isPublished ? 'Regenerate schedule' : 'Publish schedule',
              ),
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
    return GameTile(
      game: g,
      number: vm.gameNumber(g),
      nameA: vm.slotLabel(g, a: true),
      nameB: vm.slotLabel(g, a: false),
      highlight: action != null,
      skipped: vm.isSkipped(g),
      badge: switch (action) {
        HostedGameAction.report => 'Report score',
        HostedGameAction.confirm => 'Confirm score',
        HostedGameAction.awaiting => 'Waiting for the other captain',
        null => null,
      },
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _GameSheet(viewModel: vm, gameId: g.id),
      ),
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
        final theme = Theme.of(context);
        final nameA = vm.slotLabel(g, a: true);
        final nameB = vm.slotLabel(g, a: false);
        final r = g.report;
        final busy =
            vm.report.running || vm.confirm.running || vm.setFinalScore.running;
        final action = vm.actionFor(g);

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
                    if (vm.division case final d?) d.settings.scoreLabel,
                  ].join(' · '),
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
                  Text(
                    '${vm.teamName(r.byTeamId)} reported $nameA ${r.scoreA}, '
                    '$nameB ${r.scoreB}.',
                  ),
                ],
                const SizedBox(height: 16),
                if (action == HostedGameAction.report)
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
                if (action == HostedGameAction.confirm) ...[
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
                            submit: vm.report.execute,
                          ),
                    child: const Text("That's not right"),
                  ),
                ],
                if (action == HostedGameAction.awaiting)
                  const Text('Waiting for the other captain to confirm.'),
                if (vm.canSetScore(g)) ...[
                  const SizedBox(height: 8),
                  TextButton(
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
              ],
            ),
          ),
        );
      },
    );
  }
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
    final theme = Theme.of(context);
    final places = vm.placements;
    final pools = vm.poolStandings;
    final columns = <(GameStage, int), List<GroupGame>>{};
    for (final g in vm.bracketGames) {
      columns.putIfAbsent((g.stage, g.round), () => []).add(g);
    }
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          _DivisionPicker(viewModel: vm),
          if (vm.games.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text('Results show up here once games are played.'),
            ),
          if (places.isNotEmpty) ...[
            Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.emoji_events, size: 36),
                title: Text(vm.teamName(places.first)),
                subtitle: Text('${d.label} champion'),
              ),
            ),
            const _Section('Final standings'),
            for (final (i, id) in places.indexed)
              ListTile(
                dense: true,
                leading: Text(
                  ordinal(i + 1),
                  style: theme.textTheme.titleSmall,
                ),
                title: Text(vm.teamName(id)),
                trailing: d.seedOf(id) == null
                    ? null
                    : Text('Seed ${d.seedOf(id)}'),
              ),
          ],
          if (pools.isNotEmpty) ...[
            _Section(vm.tournament?.isLeague == true ? 'Standings' : 'Pools'),
            for (final e in pools.entries) ...[
              if (pools.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    'Pool ${e.key}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              StandingsTable(rows: e.value, nameOf: vm.teamName),
            ],
          ],
          if (columns.isNotEmpty) ...[
            const _Section('Bracket'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
                              e.value.map((g) => g.label).toSet().length == 1
                                  ? e.value.first.label
                                  : 'Round ${e.key.$2}',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            for (final g in e.value)
                              _HostedGameTile(viewModel: vm, game: g),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
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
