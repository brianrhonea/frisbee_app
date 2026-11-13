import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../shell/widgets/app_shell.dart' show ProfileButton;
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
        leading: ProfileButton.leading(context),
        title: const Text('Teams'),
        actions: [
          ListenableBuilder(
            listenable: vm.joinTeam,
            builder: (context, _) => IconButton(
              tooltip: 'Join, find or start a team',
              icon: const Icon(Icons.add),
              onPressed: vm.joinTeam.running ? null : _add,
            ),
          ),
        ],
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
                    onPressed: () =>
                        context.go(Routes.explore(only: ExploreFilter.groups)),
                    icon: const Icon(Icons.search),
                    label: const Text('Find a group'),
                  ),
                ],
              ),
            );
          }
          final teams = vm.yourTeams;
          final communities = vm.communities;
          return ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (invites.isNotEmpty) ...[
                  const _Heading('Invitations'),
                  ...invites,
                  const SizedBox(height: 8),
                ],
                if (teams.isNotEmpty) ...[
                  const _Heading('Your teams'),
                  for (final t in teams) _TeamCard(team: t, role: vm.roleIn(t)),
                ],
                if (communities.isNotEmpty) ...[
                  if (teams.isNotEmpty) const SizedBox(height: 8),
                  const _Heading('Communities'),
                  for (final c in communities)
                    _CommunityCard(
                      community: c,
                      role: vm.roleIn(c),
                      isOn: vm.isOn,
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// The one add button: join with a code, find a team or community, or
  /// start one.
  Future<void> _add() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('Join with a code'),
              subtitle: const Text('From a team invite or link'),
              onTap: () => Navigator.pop(context, 'join'),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Find a team or community'),
              onTap: () => Navigator.pop(context, 'find'),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Start one'),
              subtitle: const Text(
                'A team, a community group, or a school or club',
              ),
              onTap: () => Navigator.pop(context, 'create'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'join':
        await _join();
      case 'find':
        context.go(Routes.explore(only: ExploreFilter.teams));
      case 'create':
        await _create();
    }
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
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('School or club'),
              subtitle: const Text(
                'A community with several teams, roles that decide who is on '
                'each, and shared chats and events',
              ),
              onTap: () => Navigator.pop(context, TeamKind.organization),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || kind == null) return;
    context.go(switch (kind) {
      TeamKind.team => Routes.createTeam,
      TeamKind.community => Routes.createGroup,
      TeamKind.organization => Routes.createCommunity,
    });
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
          subtitle: Text(
            [
              TeamListing.of(team).subtitle,
              if (team.inCommunity && team.orgName.isNotEmpty)
                'Part of ${team.orgName}',
            ].where((s) => s.isNotEmpty).join(' · '),
          ),
          trailing: role == null
              ? null
              : Chip(label: Text(role!.labelFor(team.kind))),
          onTap: () => context.go(Routes.team(team.id)),
        ),
      ),
    );
  }
}

/// A community with its teams under it: shown when it has [_shownTeams] or
/// fewer, folded behind "Show teams" when it has more.
class _CommunityCard extends StatefulWidget {
  const _CommunityCard({
    required this.community,
    required this.role,
    required this.isOn,
  });

  final Team community;
  final TeamRole? role;

  /// Whether the user is on the team with this id.
  final bool Function(String teamId) isOn;

  @override
  State<_CommunityCard> createState() => _CommunityCardState();
}

const _shownTeams = 3;

class _CommunityCardState extends State<_CommunityCard> {
  late bool _open = widget.community.linkedTeams.length <= _shownTeams;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.community;
    final teams = c.sortedLinkedTeams;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: CircleAvatar(
                child: Icon(
                  c.isOrganization
                      ? Icons.account_balance_outlined
                      : Icons.diversity_3_outlined,
                ),
              ),
              title: Text(c.name),
              subtitle: Text(
                [
                  TeamListing.of(c).subtitle,
                  if (teams.isNotEmpty)
                    '${teams.length} team${teams.length == 1 ? '' : 's'}',
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
              trailing: widget.role == null
                  ? null
                  : Chip(label: Text(widget.role!.labelFor(c.kind))),
              onTap: () => context.go(Routes.team(c.id)),
            ),
            if (_open)
              for (final t in teams)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.fromLTRB(72, 0, 16, 0),
                  leading: const Icon(Icons.shield_outlined, size: 20),
                  title: Text(t.name),
                  subtitle: Text(t.division.label),
                  trailing: widget.isOn(t.id)
                      ? Text(
                          "You're on it",
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : null,
                  onTap: () => context.go(Routes.team(t.id)),
                ),
            if (teams.length > _shownTeams)
              TextButton(
                onPressed: () => setState(() => _open = !_open),
                child: Text(
                  _open ? 'Hide teams' : 'Show ${teams.length} teams',
                ),
              ),
          ],
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
    final what = invite.kind.noun;
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
