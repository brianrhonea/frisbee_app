import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/live_draft.dart';
import '../../../routing/routes.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/status_views.dart';
import '../view_models/hosted_tournament_viewmodel.dart';
import '../view_models/player_signups_viewmodel.dart';
import 'tournament_dialogs.dart';

Color _statusColor(BuildContext context, SignupStatus s) {
  final scheme = Theme.of(context).colorScheme;
  return switch (s) {
    SignupStatus.accepted => scheme.primaryContainer,
    SignupStatus.waitlisted => scheme.tertiaryContainer,
    SignupStatus.declined || SignupStatus.withdrawn => scheme.errorContainer,
    SignupStatus.applied => scheme.surfaceContainerHighest,
  };
}

/// Where the user stands as a player: a Sign up button, or their signup
/// with its status, fee and Edit/Withdraw. For player-entry tournaments
/// and leagues.
class PlayerSignupCard extends StatelessWidget {
  const PlayerSignupCard({
    super.key,
    required this.viewModel,
    required this.signups,
    this.now,
  });

  final HostedTournamentViewModel viewModel;
  final PlayerSignupsViewModel signups;

  /// For tests.
  final DateTime Function()? now;

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
    final theme = Theme.of(context);
    final t = viewModel.tournament!;
    final fee = t.entryFee;
    final mine = signups.mine;
    final isIn = signups.isSignedUp;
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
              child: Text(note, style: theme.textTheme.bodyMedium),
            );
    }
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isIn) ...[
              Text('Play in ${t.name}', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                [
                  if (fee != null) '${fee.label} entry fee.',
                  'Sign up on your own; the host builds balanced teams from '
                      'everyone who signs up.',
                ].join(' '),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: signups.signUp.running
                    ? null
                    : () => _signUp(context),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: Text(fee == null ? 'Sign up' : 'Sign up · ${fee.label}'),
              ),
            ] else ...[
              Row(
                children: [
                  Text('Your signup', style: theme.textTheme.titleSmall),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(mine!.status.label),
                    backgroundColor: _statusColor(context, mine.status),
                    visualDensity: VisualDensity.compact,
                  ),
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
              ),
              if (signups.myDraft case final draft?
                  when draft.status != DraftStatus.finished)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.tonalIcon(
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
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    signups.isPaid(mine.uid)
                        ? 'Entry fee paid.'
                        : signups.isOverdue(
                            mine.uid,
                            fee,
                            (now ?? DateTime.now)(),
                          )
                        ? 'Entry fee overdue: ${fee.label}. ${fee.instructions}'
                        : 'Entry fee ${fee.label} to pay. '
                              '${fee.instructions}'
                              '${fee.dueAt == null ? '' : ' Due ${DateFormat.yMMMd().format(fee.dueAt!)}.'}',
                  ),
                ),
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
        final theme = Theme.of(context);
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
                  style: theme.textTheme.bodyMedium,
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
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(
          children: [
            Expanded(child: Text('Teams', style: theme.textTheme.titleMedium)),
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
          style: theme.textTheme.bodyMedium,
        ),
      if (vm.isManager &&
          vm.tournament!.isLeague &&
          d.teams.isNotEmpty &&
          !d.teamsCreated &&
          !vm.isPublished)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Make the teams', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                const Text(
                  'A league plays as real teams, each with chat, a roster '
                  'and its games on the schedule. Create them from your '
                  'drafted teams before you publish the schedule.',
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
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
            style: theme.textTheme.bodySmall,
          ),
        ),
      if (vm.isManager && vm.isPublished && !d.teamsCreated)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'The schedule is published: you can still move players, rename '
            'teams and change captains, but not add or remove teams.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      for (final team in d.teams)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(team.name),
            subtitle: Text(
              [
                for (final id in team.playerIds)
                  '${team.nameOf(id)}${id == team.captainId ? ' (C)' : ''}',
              ].join(', '),
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
    final theme = Theme.of(context);
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
    return [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text('Players', style: theme.textTheme.titleMedium),
            ),
            if (fee != null)
              FilterChip(
                label: Text('Unpaid (${signups.unpaidCount(fee)})'),
                selected: _unpaidOnly,
                onSelected: (v) => setState(() => _unpaidOnly = v),
              ),
          ],
        ),
      ),
      Text(
        '${all.length} signed up · ${count(SignupStatus.accepted)} accepted'
        '${count(SignupStatus.waitlisted) > 0 ? ' · ${count(SignupStatus.waitlisted)} waitlisted' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      if (shown.isEmpty)
        Text(
          all.isEmpty ? 'No one has signed up yet.' : 'Everyone here has paid.',
        ),
      for (final s in shown)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(s.name),
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
            ),
            leading: Chip(
              label: Text(s.status.label),
              backgroundColor: _statusColor(context, s.status),
              visualDensity: VisualDensity.compact,
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
        ),
    ];
  }
}
