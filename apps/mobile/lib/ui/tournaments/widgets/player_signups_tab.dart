import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/live_draft.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/layout.dart' show PersonAvatar;
import '../../core/ui/status_views.dart';
import '../../group_tournaments/widgets/hat_parts.dart'
    show GenderSplitBar, LegendDot, genderColor;
import '../../payments/widgets/payment_widgets.dart';
import '../view_models/hosted_tournament_viewmodel.dart';
import '../view_models/player_signups_viewmodel.dart';
import 'tournament_dialogs.dart';
import 'tournament_parts.dart' show Pill, PillTone, RowsCard, StatTile;

/// Accepted is settled (turf); everything else is a plain fact. A new
/// signup is the host's to decide, so [hostView] shows it in amber.
PillTone _statusTone(SignupStatus s, {bool hostView = false}) => switch (s) {
  SignupStatus.accepted => PillTone.turf,
  SignupStatus.applied when hostView => PillTone.needsYou,
  _ => PillTone.neutral,
};

/// Where the user stands as a player: a Sign up button, or their signup
/// with its status, fee and Edit/Withdraw. For player-entry tournaments
/// and leagues.
class PlayerSignupCard extends StatelessWidget {
  const PlayerSignupCard({
    super.key,
    required this.viewModel,
    required this.signups,
    this.now,
    this.showSignUp = true,
  });

  final HostedTournamentViewModel viewModel;
  final PlayerSignupsViewModel signups;

  /// For tests.
  final DateTime Function()? now;

  /// False where the page's guide already offers signing up: the card
  /// then only shows an existing signup.
  final bool showSignUp;

  Future<void> _signUp(BuildContext context) async {
    final t = viewModel.tournament!;
    final a = await showPlayerSignupDialog(
      context,
      divisions: viewModel.divisions,
      initial: signups.mine?.status == SignupStatus.withdrawn
          ? null
          : signups.mine,
      fee: t.entryFee,
    );
    if (a != null) signups.signUp.execute(a);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = viewModel.tournament!;
    final fee = t.entryFee;
    final mine = signups.mine;
    final isIn = signups.isSignedUp;
    if (!isIn && !showSignUp) return const SizedBox.shrink();
    final open =
        t.status.acceptsEntries &&
        t.visibility == TournamentVisibility.public &&
        viewModel.divisions.isNotEmpty;
    if (!isIn && !open) {
      final note = !t.status.isPublished
          ? null
          : t.visibility == TournamentVisibility.inviteOnly
          ? 'Invite only. Follow along for the schedule and results.'
          : !t.status.acceptsEntries
          ? 'Signups are closed.'
          : null;
      return note == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                note,
                style: TextStyle(fontSize: 13.5, color: c.ink2),
              ),
            );
    }
    final title = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: c.ink,
    );
    final body = TextStyle(fontSize: 13.5, color: c.ink2, height: 1.35);
    final paid = mine != null && signups.isPaid(mine.uid);
    final overdue =
        fee != null &&
        mine != null &&
        !paid &&
        signups.isOverdue(mine.uid, fee, (now ?? DateTime.now)());
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isIn) ...[
              Text('Play in ${t.name}', style: title),
              const SizedBox(height: 4),
              Text(
                [
                  if (fee != null) '${fee.label} entry fee.',
                  t.draftMode == DraftMode.captains
                      ? 'Sign up on your own; captains chosen by the host '
                            'draft the teams.'
                      : 'Sign up on your own; the host builds balanced teams '
                            'from everyone who signs up.',
                ].join(' '),
                style: body,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: signups.signUp.running
                    ? null
                    : () => _signUp(context),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: Text(fee == null ? 'Sign up' : 'Sign up · ${fee.label}'),
              ),
            ] else ...[
              Row(
                children: [
                  Text('Your signup', style: title),
                  const SizedBox(width: 8),
                  Pill(mine!.status.label, tone: _statusTone(mine.status)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (viewModel.divisionById(mine.divisionId) case final d?)
                    d.label,
                  'Skill ${mine.skill}',
                  if (mine.gender != null) mine.gender!.label,
                ].join(' · '),
                style: body,
              ),
              if (signups.myDraft case final draft?
                  when draft.status != DraftStatus.finished)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  // Live: scoreboard navy.
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.feature,
                      foregroundColor: c.onFeature,
                    ),
                    onPressed: () => context.push(
                      Routes.tournamentLiveDraft(
                        viewModel.tournamentId,
                        mine.divisionId,
                      ),
                    ),
                    icon: const Icon(Icons.how_to_reg_outlined),
                    label: Text(
                      draft.captains.any((c) => c.uid == signups.uid)
                          ? "The draft is live: you're a captain"
                          : 'The draft is live: watch it',
                    ),
                  ),
                ),
              if (fee != null &&
                  (mine.status == SignupStatus.accepted ||
                      mine.status == SignupStatus.applied))
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    // Paying is the player's to do; paid is settled.
                    color: paid ? c.accentSoft : c.highlightSoft,
                    borderRadius: BorderRadius.circular(controlRadius),
                  ),
                  child: Text(
                    paid
                        ? 'Entry fee paid.'
                        : overdue
                        ? 'Entry fee overdue: ${fee.label}. ${fee.instructions}'
                        : 'Entry fee ${fee.label} to pay. '
                              '${fee.instructions}'
                              '${fee.dueAt == null ? '' : ' Due ${DateFormat.yMMMd().format(fee.dueAt!)}.'}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: paid ? c.accentInk : c.highlightInk,
                    ),
                  ),
                ),
              if (fee != null &&
                  !signups.isPaid(mine.uid) &&
                  (mine.status == SignupStatus.accepted ||
                      mine.status == SignupStatus.applied))
                PayOnlineButton(tournamentId: viewModel.tournamentId),
              Wrap(
                spacing: 8,
                children: [
                  if (t.status.acceptsEntries &&
                      mine.status != SignupStatus.accepted)
                    TextButton(
                      onPressed: () => _signUp(context),
                      child: const Text('Edit'),
                    ),
                  TextButton(
                    onPressed: () async {
                      if (await confirmDialog(
                        context,
                        title: 'Withdraw from ${t.name}?',
                        message: t.status.acceptsEntries
                            ? 'You can sign up again while registration is '
                                  'open.'
                            : 'Registration has closed, so you may not be '
                                  'able to sign up again.',
                        confirmLabel: 'Withdraw',
                        destructive: true,
                      )) {
                        signups.withdraw.execute();
                      }
                    },
                    child: const Text('Withdraw'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Players tab of a player-entry tournament or league: the host's
/// list of signups (accept, waitlist, decline, mark paid) and the draft;
/// everyone else sees their own signup and, once the schedule is out, the
/// teams.
class PlayersTab extends StatefulWidget {
  const PlayersTab({
    super.key,
    required this.viewModel,
    required this.signups,
    this.now,
  });

  final HostedTournamentViewModel viewModel;
  final PlayerSignupsViewModel signups;

  /// For tests.
  final DateTime Function()? now;

  @override
  State<PlayersTab> createState() => _PlayersTabState();
}

class _PlayersTabState extends State<PlayersTab> {
  bool _unpaidOnly = false;

  HostedTournamentViewModel get vm => widget.viewModel;
  PlayerSignupsViewModel get signups => widget.signups;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([vm, signups]),
      builder: (context, _) {
        final t = vm.tournament!;
        final d = vm.division;
        final c = AppColors.of(context);
        final published = t.status.index >= HostedStatus.scheduled.index;
        return ConstrainedContent(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
            children: [
              if (vm.divisions.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      for (final x in vm.divisions)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(x.label),
                            selected: x.id == d?.id,
                            onSelected: (_) => vm.selectDivision(x.id),
                          ),
                        ),
                    ],
                  ),
                ),
              if (vm.divisions.isEmpty)
                Text(
                  vm.isManager
                      ? 'Add a division on the Overview tab so players can '
                            'sign up.'
                      : 'The host is still setting up divisions.',
                  style: TextStyle(fontSize: 13.5, color: c.ink2),
                ),
              PlayerSignupCard(
                viewModel: vm,
                signups: signups,
                now: widget.now,
              ),
              if (d != null && (vm.isManager || published))
                ..._teams(context, d, published),
              if (vm.isManager && d != null) ..._manage(context, t, d),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _teams(
    BuildContext context,
    TournamentDivision d,
    bool published,
  ) {
    final c = AppColors.of(context);
    final note = TextStyle(fontSize: 12.5, color: c.muted);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(
          children: [
            Expanded(child: Text('Teams', style: _heading(c))),
            if (vm.isManager)
              FilledButton.icon(
                onPressed:
                    signups.acceptedIn(d.id).length < 2 && d.teams.isEmpty
                    ? null
                    : () => context.push(
                        d.teams.isEmpty &&
                                vm.tournament!.draftMode == DraftMode.captains
                            ? Routes.tournamentLiveDraft(vm.tournamentId, d.id)
                            : Routes.tournamentDraft(vm.tournamentId, d.id),
                      ),
                icon: const Icon(Icons.groups_outlined),
                label: Text(
                  d.teams.isEmpty
                      ? vm.tournament!.draftMode == DraftMode.captains
                            ? "Captains' draft"
                            : 'Draft teams'
                      : d.teamsCreated
                      ? 'View teams'
                      : 'Edit teams',
                ),
              ),
          ],
        ),
      ),
      if (d.teams.isEmpty)
        Text(
          vm.isManager
              ? 'Accept players below, then draft teams from them.'
              : 'Teams are drawn once registration closes.',
          style: TextStyle(fontSize: 13.5, color: c.ink2),
        ),
      if (vm.isManager &&
          vm.tournament!.isLeague &&
          d.teams.isNotEmpty &&
          !d.teamsCreated &&
          !vm.isPublished)
        // The host's to do before publishing: amber.
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: c.highlightSoft,
            borderRadius: BorderRadius.circular(cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make the teams',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'A league plays as real teams, each with chat, a roster '
                  'and its games on the schedule. Create them from your '
                  'drafted teams before you publish the schedule.',
                  style: TextStyle(fontSize: 13, color: c.ink2),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.highlight,
                    foregroundColor: c.onHighlight,
                  ),
                  onPressed: vm.createTeams.running
                      ? null
                      : () async {
                          if (await confirmDialog(
                            context,
                            title: 'Create ${d.teams.length} teams?',
                            message:
                                'Each team is created with its captain as '
                                'owner and the other players as members. '
                                "You won't be able to redraft afterwards; "
                                'rosters are managed on each team.',
                            confirmLabel: 'Create teams',
                          )) {
                            vm.createTeams.execute(d.id);
                          }
                        },
                  icon: const Icon(Icons.groups_2_outlined),
                  label: Text(
                    vm.createTeams.running ? 'Creating…' : 'Create teams',
                  ),
                ),
              ],
            ),
          ),
        ),
      if (vm.isManager && d.teamsCreated)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'These are real teams: each captain owns theirs and manages '
            'its roster.',
            style: note,
          ),
        ),
      if (vm.isManager && vm.isPublished && !d.teamsCreated)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'The schedule is published: you can still move players, rename '
            'teams and change captains, but not add or remove teams.',
            style: note,
          ),
        ),
      for (final team in d.teams)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: team.playerIds.contains(vm.uid) ? c.accentSoft : null,
          child: ListTile(
            title: Text(
              team.name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            subtitle: Text(
              [
                for (final id in team.playerIds)
                  '${team.nameOf(id)}${id == team.captainId ? ' (C)' : ''}',
              ].join(', '),
              style: TextStyle(fontSize: 12.5, color: c.ink2),
            ),
            // Members open their team (others can't read it).
            trailing: d.teamsCreated && team.playerIds.contains(vm.uid)
                ? const Icon(Icons.chevron_right)
                : null,
            onTap: d.teamsCreated && team.playerIds.contains(vm.uid)
                ? () => context.push(Routes.teamOver(team.id))
                : null,
          ),
        ),
    ];
  }

  List<Widget> _manage(
    BuildContext context,
    HostedTournament t,
    TournamentDivision d,
  ) {
    final c = AppColors.of(context);
    final fee = t.entryFee;
    final all = signups.signupsIn(d.id);
    final shown = [
      for (final s in all)
        if (!_unpaidOnly ||
            (fee != null &&
                s.status != SignupStatus.withdrawn &&
                s.status != SignupStatus.declined &&
                !signups.isPaid(s.uid)))
          s,
    ];
    int count(SignupStatus s) => all.where((x) => x.status == s).length;
    final now = (widget.now ?? DateTime.now)();
    // Who is still in: the split and average skill count only them.
    final active = [
      for (final s in all)
        if (s.status != SignupStatus.withdrawn &&
            s.status != SignupStatus.declined)
          s,
    ];
    final mmp = active.where((s) => s.gender == GenderMatch.mmp).length;
    final wmp = active.where((s) => s.gender == GenderMatch.wmp).length;
    final avgSkill = active.isEmpty
        ? null
        : active.fold<int>(0, (sum, s) => sum + s.skill) / active.length;
    final pending = count(SignupStatus.applied);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(
          children: [
            Expanded(child: Text('Players', style: _heading(c))),
            if (fee != null)
              FilterChip(
                label: Text('Unpaid (${signups.unpaidCount(fee)})'),
                selected: _unpaidOnly,
                onSelected: (v) => setState(() => _unpaidOnly = v),
              ),
          ],
        ),
      ),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${all.length} signed up · ${count(SignupStatus.accepted)} accepted'
                '${count(SignupStatus.waitlisted) > 0 ? ' · ${count(SignupStatus.waitlisted)} waitlisted' : ''}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              if (all.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        value: '${count(SignupStatus.accepted)}',
                        label: 'Accepted',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      // New signups are the host's to decide.
                      child: StatTile(
                        value: '$pending',
                        label: 'To decide',
                        highlight: pending > 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatTile(
                        value: '${count(SignupStatus.waitlisted)}',
                        label: 'Waitlist',
                      ),
                    ),
                  ],
                ),
              ],
              if (mmp + wmp > 0) ...[
                const SizedBox(height: 12),
                GenderSplitBar(
                  mmp: mmp,
                  wmp: wmp,
                  unknown: active.length - mmp - wmp,
                  height: 10,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    LegendDot(
                      color: genderColor(c, mmp: true),
                      label: '$mmp MMP',
                    ),
                    LegendDot(
                      color: genderColor(c, mmp: false),
                      label: '$wmp WMP',
                    ),
                    if (active.length > mmp + wmp)
                      LegendDot(
                        color: genderColor(c, mmp: null),
                        label: '${active.length - mmp - wmp} not set',
                      ),
                    if (avgSkill != null)
                      Text(
                        'Avg skill ${avgSkill.toStringAsFixed(1)}',
                        style: TextStyle(fontSize: 12, color: c.ink2),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      if (shown.isEmpty)
        Text(
          all.isEmpty ? 'No one has signed up yet.' : 'Everyone here has paid.',
          style: TextStyle(fontSize: 13.5, color: c.ink2),
        ),
      if (shown.isNotEmpty)
        RowsCard(
          children: [
            for (final s in shown)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 14, right: 4),
                leading: PersonAvatar(name: s.name, radius: 18),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Pill(
                      s.status.label,
                      tone: _statusTone(s.status, hostView: true),
                    ),
                  ],
                ),
                subtitle: Text(
                  [
                    'Skill ${s.skill}',
                    if (s.gender != null) s.gender!.label,
                    if (fee != null &&
                        s.status != SignupStatus.withdrawn &&
                        s.status != SignupStatus.declined)
                      signups.isPaid(s.uid)
                          ? 'Paid'
                          : signups.isOverdue(s.uid, fee, now)
                          ? 'Overdue'
                          : 'Unpaid',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (fee != null &&
                        s.status != SignupStatus.withdrawn &&
                        s.status != SignupStatus.declined)
                      Switch(
                        value: signups.isPaid(s.uid),
                        onChanged: (v) =>
                            signups.setPaid.execute((uid: s.uid, paid: v)),
                      ),
                    PopupMenuButton<SignupStatus>(
                      tooltip: 'Change status',
                      onSelected: (status) =>
                          signups.decide.execute((uid: s.uid, status: status)),
                      itemBuilder: (_) => [
                        for (final status in const [
                          SignupStatus.accepted,
                          SignupStatus.waitlisted,
                          SignupStatus.declined,
                        ])
                          if (status != s.status)
                            PopupMenuItem(
                              value: status,
                              child: Text(switch (status) {
                                SignupStatus.accepted => 'Accept',
                                SignupStatus.waitlisted => 'Waitlist',
                                _ => 'Decline',
                              }),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
    ];
  }
}

TextStyle _heading(AppColors c) => TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.2,
  color: c.ink,
);
