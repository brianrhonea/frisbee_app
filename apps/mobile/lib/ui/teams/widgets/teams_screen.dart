import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/personal_details.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/scoreboard.dart' show SectionHeader;
import '../../core/ui/status_views.dart';
import '../../shell/widgets/app_shell.dart' show ProfileButton;
import '../view_models/teams_viewmodel.dart';
import 'join_team_dialog.dart';
import 'team_initials.dart';

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
          ListenableBuilder(
            listenable: vm.joinTeam,
            builder: (context, _) => IconButton(
              tooltip: 'Join, find or start a team',
              icon: const Icon(Icons.add),
              onPressed: vm.joinTeam.running ? null : _add,
            ),
          ),
          ?ProfileButton.action(context),
          const SizedBox(width: 4),
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
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _InviteTile(
                  invite: i,
                  busy: vm.acceptInvite.running || vm.declineInvite.running,
                  onAccept: () => vm.acceptInvite.execute(i),
                  onDecline: () => vm.declineInvite.execute(i),
                  club: vm.isClubInvite(i),
                ),
              ),
          ];
          if (vm.all.isEmpty && invites.isEmpty) {
            return EmptyView(
              icon: Icons.groups_outlined,
              title: 'No teams or communities yet',
              message:
                  'Create a team or community, join a team with an '
                  'invite code, or search for teams and communities near you.',
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
                    label: const Text('Find a community'),
                  ),
                ],
              ),
            );
          }
          final teams = vm.yourTeams;
          final communities = vm.communities;
          return ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                ...invites,
                if (invites.isNotEmpty) const SizedBox(height: 8),
                if (teams.isNotEmpty) ...[
                  _Heading('Your teams', count: teams.length),
                  _Rows(
                    children: [
                      for (final t in teams)
                        _TeamRow(team: t, role: vm.roleIn(t)),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (communities.isNotEmpty) ...[
                  SectionHeader(
                    'Communities',
                    actionLabel: 'Find more',
                    onAction: () =>
                        context.go(Routes.explore(only: ExploreFilter.groups)),
                  ),
                  _Rows(
                    children: [
                      for (final c in communities)
                        _CommunityBlock(
                          community: c,
                          role: vm.roleIn(c),
                          isOn: vm.isOn,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                ListenableBuilder(
                  listenable: vm.joinTeam,
                  builder: (context, _) => _AddTiles(
                    onJoin: vm.joinTeam.running ? null : _join,
                    onFind: () =>
                        context.go(Routes.explore(only: ExploreFilter.teams)),
                    onStart: _create,
                  ),
                ),
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
                'A team, a pickup community, or a school or club',
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
              title: const Text('Pickup community'),
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

/// A section title with how many rows it has.
class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.count});

  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: c.ink,
                ),
              ),
            ),
          ),
          Text('$count', style: TextStyle(fontSize: 13, color: c.muted)),
        ],
      ),
    );
  }
}

/// One card of rows with hairlines between them.
class _Rows extends StatelessWidget {
  const _Rows({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, w) in children.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.border),
            w,
          ],
        ],
      ),
    );
  }
}

/// The user's role: turf for those who run the team, outlined otherwise.
class _RolePill extends StatelessWidget {
  const _RolePill(this.role, this.kind);

  final TeamRole role;
  final TeamKind kind;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final lead = role.canEdit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: lead ? c.accentSoft : null,
        border: lead ? null : Border.all(color: c.border2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.labelFor(kind),
        style: TextStyle(
          fontSize: 11,
          fontWeight: lead ? FontWeight.w700 : FontWeight.w600,
          color: lead ? c.accentInk : c.ink2,
        ),
      ),
    );
  }
}

/// A team or community row: its initials, name, role and what it is.
class _Row extends StatelessWidget {
  const _Row({
    required this.name,
    required this.kind,
    required this.meta,
    required this.role,
    required this.onTap,
  });

  final String name;
  final TeamKind kind;
  final String meta;
  final TeamRole? role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            TeamInitials(name: name, kind: kind),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ),
                      if (role case final r?) ...[
                        const SizedBox(width: 6),
                        _RolePill(r, kind),
                      ],
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 20, color: c.muted),
          ],
        ),
      ),
    );
  }
}

String _members(int n) => '$n ${n == 1 ? 'member' : 'members'}';

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team, required this.role});

  final Team team;
  final TeamRole? role;

  @override
  Widget build(BuildContext context) => _Row(
    name: team.name,
    kind: team.kind,
    role: role,
    meta: [
      TeamListing.of(team).subtitle,
      if (team.members.isNotEmpty) _members(team.members.length),
      if (team.inCommunity && team.orgName.isNotEmpty)
        'Part of ${team.orgName}',
    ].where((s) => s.isNotEmpty).join(' · '),
    onTap: () => context.go(Routes.team(team.id)),
  );
}

/// A community with its teams under it: shown when it has [_shownTeams] or
/// fewer, folded behind "Show teams" when it has more.
class _CommunityBlock extends StatefulWidget {
  const _CommunityBlock({
    required this.community,
    required this.role,
    required this.isOn,
  });

  final Team community;
  final TeamRole? role;

  /// Whether the user is on the team with this id.
  final bool Function(String teamId) isOn;

  @override
  State<_CommunityBlock> createState() => _CommunityBlockState();
}

const _shownTeams = 3;

class _CommunityBlockState extends State<_CommunityBlock> {
  late bool _open = widget.community.linkedTeams.length <= _shownTeams;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final c = widget.community;
    final teams = c.sortedLinkedTeams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          name: c.name,
          kind: c.kind,
          role: widget.role,
          meta: [
            TeamListing.of(c).subtitle,
            if (teams.isNotEmpty)
              '${teams.length} team${teams.length == 1 ? '' : 's'}',
            if (c.members.isNotEmpty) _members(c.members.length),
          ].where((s) => s.isNotEmpty).join(' · '),
          onTap: () => context.go(Routes.team(c.id)),
        ),
        if (_open)
          for (final t in teams)
            InkWell(
              onTap: () => context.go(Routes.team(t.id)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(70, 6, 14, 6),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: colors.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: colors.ink,
                            ),
                          ),
                          Text(
                            t.division.label,
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isOn(t.id))
                      Text(
                        "You're on it",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        if (teams.length > _shownTeams)
          Padding(
            padding: const EdgeInsets.only(left: 58, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _open = !_open),
                child: Text(
                  _open ? 'Hide teams' : 'Show ${teams.length} teams',
                ),
              ),
            ),
          ),
        if (_open && teams.isNotEmpty && teams.length <= _shownTeams)
          const SizedBox(height: 6),
      ],
    );
  }
}

/// Join with a code, find a team, or start one: the add button's choices
/// as three tiles under the lists.
class _AddTiles extends StatelessWidget {
  const _AddTiles({
    required this.onJoin,
    required this.onFind,
    required this.onStart,
  });

  final VoidCallback? onJoin;
  final VoidCallback onFind;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget tile(IconData icon, String label, VoidCallback? onTap) => Expanded(
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm,
              vertical: 12,
            ),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: c.accentInk),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile(Icons.vpn_key_outlined, 'Join with code', onJoin),
        const SizedBox(width: 8),
        tile(Icons.search, 'Find a team', onFind),
        const SizedBox(width: 8),
        tile(Icons.add, 'Start a team', onStart),
      ],
    );
  }
}

/// An invitation to join a team or group, with Accept and Decline: the
/// user's to do, so it's amber.
class _InviteTile extends StatelessWidget {
  const _InviteTile({
    required this.invite,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    this.club = false,
  });

  final TeamInvite invite;
  final bool busy;

  /// A club team: says it's for players 16 and over.
  final bool club;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final what = invite.kind.noun;
    final from = invite.invitedByName.isEmpty
        ? 'You were invited to join this $what.'
        : '${invite.invitedByName} invited you to join this $what.';
    final small = TextStyle(fontSize: 12, color: c.ink2);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: c.highlightSoft,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          TeamInitials(name: invite.teamName, kind: invite.kind, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INVITATION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: c.highlightInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  invite.teamName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(from, style: small),
                if (club) Text(clubTooYoungMessage, style: small),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: c.ink2,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 44),
            ),
            onPressed: busy ? null : onDecline,
            child: const Text('Decline'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.highlight,
              foregroundColor: c.onHighlight,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 44),
            ),
            onPressed: busy ? null : onAccept,
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }
}
