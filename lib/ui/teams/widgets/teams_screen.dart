import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/teams_viewmodel.dart';
import 'join_team_dialog.dart';

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key, required this.viewModel});

  final TeamsViewModel viewModel;

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  TeamsViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.joinTeam.addListener(_onJoin);
    vm.acceptInvite.addListener(_onAccept);
    vm.declineInvite.addListener(_onDecline);
  }

  @override
  void dispose() {
    vm.joinTeam.removeListener(_onJoin);
    vm.acceptInvite.removeListener(_onAccept);
    vm.declineInvite.removeListener(_onDecline);
    super.dispose();
  }

  void _onAccept() {
    final cmd = vm.acceptInvite;
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        context.go(Routes.team(value));
      case Error<String>():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  void _onDecline() {
    if (vm.declineInvite.result is Error) {
      showErrorSnackBar(context, vm.declineInvite.result);
      vm.declineInvite.clearResult();
    }
  }

  void _onJoin() {
    final cmd = vm.joinTeam;
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        context.go(Routes.team(value));
      case Error<String>():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  Future<void> _join() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const JoinTeamDialog(),
    );
    if (code != null) vm.joinTeam.execute(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teams'),
        actions: [
          IconButton(
            tooltip: 'Find a team',
            icon: const Icon(Icons.search),
            onPressed: () => context.push(Routes.searchTeams),
          ),
          ListenableBuilder(
            listenable: vm.joinTeam,
            builder: (context, _) => TextButton.icon(
              onPressed: vm.joinTeam.running ? null : _join,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Join'),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.acceptInvite, vm.declineInvite]),
        builder: (context, _) {
          if (vm.loading) return const LoadingView();
          if (vm.error != null) {
            return ErrorView(error: vm.error, onRetry: vm.retry);
          }
          final invites = [
            for (final i in vm.invites)
              _InviteTile(
                invite: i,
                busy: vm.acceptInvite.running || vm.declineInvite.running,
                onAccept: () => vm.acceptInvite.execute(i),
                onDecline: () => vm.declineInvite.execute(i),
              ),
          ];
          if (vm.all.isEmpty && invites.isEmpty) {
            return EmptyView(
              icon: Icons.groups_outlined,
              title: 'No teams or groups yet',
              message:
                  'Create a team or community group, join a team with an '
                  'invite code, or search for teams and groups near you.',
              action: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _join,
                    child: const Text('Join with code'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push(Routes.searchTeams),
                    icon: const Icon(Icons.search),
                    label: const Text('Find a group'),
                  ),
                ],
              ),
            );
          }
          final teams = vm.teams;
          final groups = vm.groups;
          return ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (invites.isNotEmpty) ...[
                  const _Heading('Invitations'),
                  ...invites,
                  const SizedBox(height: 8),
                ],
                if (teams.isNotEmpty) ...[
                  if (groups.isNotEmpty) const _Heading('My teams'),
                  for (final t in teams) _TeamCard(team: t, role: vm.roleIn(t)),
                ],
                if (groups.isNotEmpty) ...[
                  if (teams.isNotEmpty) const SizedBox(height: 8),
                  const _Heading('My groups'),
                  for (final g in groups)
                    _TeamCard(team: g, role: vm.roleIn(g)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _create() async {
    final kind = await showModalBottomSheet<TeamKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Team'),
              subtitle: const Text(
                'Invite-only, with roster, playbook, videos and stats',
              ),
              onTap: () => Navigator.pop(context, TeamKind.team),
            ),
            ListTile(
              leading: const Icon(Icons.diversity_3_outlined),
              title: const Text('Community group'),
              subtitle: const Text(
                'Open to anyone, with pickup events and tournaments',
              ),
              onTap: () => Navigator.pop(context, TeamKind.community),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || kind == null) return;
    context.go(
      kind == TeamKind.community ? Routes.createGroup : Routes.createTeam,
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team, required this.role});

  final Team team;
  final TeamRole? role;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: CircleAvatar(
            child: team.isCommunity
                ? const Icon(Icons.diversity_3_outlined)
                : Text(team.name.isEmpty ? '?' : team.name[0].toUpperCase()),
          ),
          title: Text(team.name),
          subtitle: Text(TeamListing.of(team).subtitle),
          trailing: role == null
              ? null
              : Chip(label: Text(role!.labelFor(team.kind))),
          onTap: () => context.go(Routes.team(team.id)),
        ),
      ),
    );
  }
}

/// An invitation to join a team or group, with Accept and Decline.
class _InviteTile extends StatelessWidget {
  const _InviteTile({
    required this.invite,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final TeamInvite invite;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final what = invite.isCommunity ? 'group' : 'team';
    final from = invite.invitedByName.isEmpty
        ? 'You were invited to join this $what.'
        : '${invite.invitedByName} invited you to join this $what.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(invite.isCommunity ? Icons.diversity_3 : Icons.groups),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invite.teamName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(from, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            TextButton(
              onPressed: busy ? null : onDecline,
              child: const Text('Decline'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: busy ? null : onAccept,
              child: const Text('Accept'),
            ),
          ],
        ),
      ),
    );
  }
}
