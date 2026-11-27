import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../routing/push_team_route.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/app_segmented_button.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/status_pill.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/invite_code_viewmodel.dart';
import '../view_models/team_detail_viewmodel.dart';
import 'invite_code_card.dart';
import 'invite_members_dialog.dart';
import 'member_permissions_dialog.dart';
import 'roles_screen.dart' show RoleDot;
import 'roster_tab.dart' show showPlayerEditor;
import 'team_section_screen.dart' show TeamSection;

/// What the Members tab shows: the people, or each role with who holds it.
enum _MembersView { members, roles }

class MembersTab extends StatefulWidget {
  const MembersTab({super.key, required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  _MembersView _view = _MembersView.members;

  TeamDetailViewModel get viewModel => widget.viewModel;

  @override
  Widget build(BuildContext context) {
    final team = viewModel.team!;
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          Center(
            child: AppSegmentedButton<_MembersView>(
              segments: const [
                ButtonSegment(
                  value: _MembersView.members,
                  label: Text('People'),
                ),
                ButtonSegment(value: _MembersView.roles, label: Text('Roles')),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _view = s.single),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          if (_view == _MembersView.roles)
            _RolesView(viewModel: viewModel, team: team)
          else
            ..._people(context, team),
        ],
      ),
    );
  }

  List<Widget> _people(BuildContext context, Team team) {
    final c = AppColors.of(context);
    final members = team.members.entries.toList()
      ..sort((a, b) {
        final byRole = a.value.index.compareTo(b.value.index);
        return byRole != 0
            ? byRole
            : team.nameOf(a.key).compareTo(team.nameOf(b.key));
      });
    return [
      if (viewModel.canManageMembers) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _addMember(context, team),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add member'),
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (viewModel.canShareCode) ...[
        ViewModelHost(
          create: (c) => InviteCodeViewModel(
            teamId: team.id,
            teamRepository: c.read(),
            authRepository: c.read(),
          ),
          builder: (_, vm) => InviteCodeCard(viewModel: vm),
        ),
        const SizedBox(height: 16),
      ],
      if (viewModel.joinRequests.isNotEmpty) ...[
        _JoinRequests(viewModel: viewModel),
        const SizedBox(height: 16),
      ],
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Eyebrow(
          '${members.length} member${members.length == 1 ? '' : 's'}',
        ),
      ),
      Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (i, m) in members.indexed) ...[
              if (i > 0) Divider(height: 1, color: c.border),
              _MemberRow(
                viewModel: viewModel,
                team: team,
                uid: m.key,
                tier: m.value,
              ),
            ],
          ],
        ),
      ),
      if (viewModel.canSeeInvites && viewModel.pendingInvites.isNotEmpty) ...[
        const SizedBox(height: 18),
        _PendingInvites(viewModel: viewModel),
      ],
    ];
  }

  /// "Add member": invite people, and on a team with a roster, add a player
  /// to it.
  Future<void> _addMember(BuildContext context, Team team) async {
    final hasRoster = TeamSection.forTeam(team).contains(TeamSection.roster);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      sheetAnimationStyle: AppMotion.sheetStyle(context),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                0,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: Text(
                'Add member',
                style: AppText.section.copyWith(
                  color: AppColors.of(context).ink,
                ),
              ),
            ),
            ListTile(
              minVerticalPadding: 12,
              leading: const Icon(Icons.person_search),
              title: const Text('Invite people'),
              subtitle: Text(
                team.isCommunity
                    ? 'Find people to invite, or share the invite link'
                    : 'Find players to invite, or share the invite link',
              ),
              onTap: () => Navigator.pop(context, 'invite'),
            ),
            if (hasRoster && viewModel.canEdit)
              ListTile(
                minVerticalPadding: 12,
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Add player to roster'),
                subtitle: const Text(
                  'A roster spot, optionally linked to a member',
                ),
                onTap: () => Navigator.pop(context, 'player'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case 'invite':
        await showInviteMembers(context, team);
        // Anyone just invited shows under Invites pending.
        viewModel.loadInvites.execute();
      case 'player':
        await showPlayerEditor(context, viewModel);
    }
  }
}

/// One member: avatar, name, role pills, and the manage menu for those who
/// can. A 64 px row that opens their profile.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.viewModel,
    required this.team,
    required this.uid,
    required this.tier,
  });

  final TeamDetailViewModel viewModel;
  final Team team;
  final String uid;
  final TeamRole tier;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final name = team.nameOf(uid);
    return InkWell(
      onTap: () => context.push(Routes.player(uid)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(
            children: [
              PersonAvatar(name: name, radius: 18),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: name,
                        children: [
                          if (uid == viewModel.uid)
                            TextSpan(
                              text: ' (you)',
                              style: AppText.body.copyWith(color: c.muted),
                            ),
                        ],
                      ),
                      style: AppText.bodyStrong.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    _MemberRoles(team: team, uid: uid, tier: tier),
                  ],
                ),
              ),
              if (viewModel.canManage(uid))
                _MemberMenu(
                  viewModel: viewModel,
                  uid: uid,
                  name: name,
                  role: tier,
                  team: team,
                  statKeeper: team.isStatKeeper(uid),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Invites pending": who's been invited and hasn't answered, for those
/// who invite people, each with who invited them and Withdraw. Neutral:
/// it's the invitees' move, not the admin's.
class _PendingInvites extends StatelessWidget {
  const _PendingInvites({required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final invites = viewModel.pendingInvites;
    final day = DateFormat.MMMd();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Eyebrow('Invites pending · ${invites.length}'),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, invite) in invites.indexed) ...[
                if (i > 0) Divider(height: 1, color: c.border),
                ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
                  leading: PersonAvatar(
                    name: invite.name,
                    photoUrl: invite.photoUrl,
                    radius: 18,
                  ),
                  title: Text(
                    invite.name,
                    style: AppText.bodyStrong.copyWith(color: c.ink),
                  ),
                  subtitle: Text(
                    [
                      if (invite.invitedByName.isNotEmpty)
                        'Invited by ${invite.invitedByName}'
                      else
                        'Invited',
                      if (invite.invitedAt case final at?) day.format(at),
                    ].join(' · '),
                  ),
                  trailing: TextButton(
                    onPressed: viewModel.withdrawInvite.running
                        ? null
                        : () async {
                            if (await confirmDialog(
                              context,
                              title: 'Withdraw the invite to ${invite.name}?',
                              message:
                                  "They won't be able to join with it any more.",
                              confirmLabel: 'Withdraw',
                            )) {
                              viewModel.withdrawInvite.execute(invite.uid);
                            }
                          },
                    child: const Text('Withdraw'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// People waiting to join a group that requires approval, or a team that
/// allows join requests (F26). Approving runs the server's join checks
/// (a club team's age rule among them), so it can be refused.
class _JoinRequests extends StatelessWidget {
  const _JoinRequests({required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final requests = viewModel.joinRequests;
    // Requests are the admin's to act on: the one amber card on the tab.
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
      decoration: BoxDecoration(
        color: c.highlightSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.highlight.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${requests.length} '
            '${requests.length == 1 ? 'person wants' : 'people want'} '
            'to join',
            style: AppText.label.copyWith(color: c.highlightInk),
          ),
          for (final r in requests)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: PersonAvatar(
                name: r.name.isEmpty ? '?' : r.name,
                radius: 18,
              ),
              title: Text(
                r.name.isEmpty ? 'Someone' : r.name,
                style: AppText.bodyStrong.copyWith(color: c.ink),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    style: _compactAction,
                    onPressed: viewModel.declineJoinRequest.running
                        ? null
                        : () => viewModel.declineJoinRequest.execute(r.uid),
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.highlight,
                      foregroundColor: c.onHighlight,
                      visualDensity: const VisualDensity(horizontal: -2),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: viewModel.approveJoinRequest.running
                        ? null
                        : () => viewModel.approveJoinRequest.execute(r),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Tighter horizontal padding for buttons in a list row's trailing slot,
/// so the name keeps its width. Keeps the 48 px tap height.
final ButtonStyle _compactAction = TextButton.styleFrom(
  visualDensity: const VisualDensity(horizontal: -2),
  padding: const EdgeInsets.symmetric(horizontal: 8),
  minimumSize: const Size(0, 48),
);

/// A member's tier, stats access and custom roles.
class _MemberRoles extends StatelessWidget {
  const _MemberRoles({
    required this.team,
    required this.uid,
    required this.tier,
  });

  final Team team;
  final String uid;
  final TeamRole tier;

  @override
  Widget build(BuildContext context) {
    final roles = team.rolesOf(uid);
    // Their own permissions (the owner's switches) by preset name, or
    // Custom; stats access alone reads as before.
    final own = tier == TeamRole.player
        ? team.ownPermissionsOf(uid)
        : const <TeamPermission>{};
    final preset = RolePreset.matching(own, team.isCommunity);
    final label = own.isEmpty
        ? team.roleLabel(tier)
        : '${team.roleLabel(tier)} · '
              '${preset?.id == 'statKeeper' ? 'Stats' : preset?.name ?? 'Custom'}';
    // Staff tiers and members with permissions of their own stand out as an
    // accent pill; a plain player or member is a quiet neutral one.
    final plain = tier == TeamRole.player && own.isEmpty;
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StatusPill(label, tone: plain ? PillTone.neutral : PillTone.accent),
        for (final r in roles) _RoleChip(role: r),
      ],
    );
  }
}

/// A custom role: its colour dot and name.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final CustomRole role;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      RoleDot(color: role.color, size: 9),
      const SizedBox(width: AppSpace.xs),
      Text(
        role.name,
        style: AppText.caption.copyWith(color: AppColors.of(context).ink2),
      ),
    ],
  );
}

/// Picks which custom roles [uid] has, up to [maxRolesPerMember].
Future<Set<String>?> _pickRoles(
  BuildContext context,
  Team team,
  String uid,
  String name,
) => showDialog<Set<String>>(
  context: context,
  animationStyle: AppMotion.dialogStyle(context),
  builder: (context) {
    var picked = {...?team.memberRoles[uid]};
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Roles for $name'),
        content: SizedBox(
          width: 400,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final r in team.sortedRoles)
                CheckboxListTile(
                  value: picked.contains(r.id),
                  secondary: RoleDot(color: r.color, size: 14),
                  title: Text(r.name),
                  onChanged:
                      picked.contains(r.id) || picked.length < maxRolesPerMember
                      ? (on) => setState(
                          () => picked = on ?? false
                              ? {...picked, r.id}
                              : ({...picked}..remove(r.id)),
                        )
                      : null,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, picked),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  },
);

class _MemberMenu extends StatelessWidget {
  const _MemberMenu({
    required this.viewModel,
    required this.uid,
    required this.name,
    required this.role,
    required this.team,
    required this.statKeeper,
  });

  final TeamDetailViewModel viewModel;
  final String uid;
  final String name;
  final TeamRole role;
  final Team team;
  final bool statKeeper;

  TeamKind get kind => team.kind;
  bool get _isGroup => kind == TeamKind.community;

  Future<void> _changeRole(BuildContext context) async {
    final picked = await showDialog<TeamRole>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => SimpleDialog(
        title: Text('Role for $name'),
        children: [
          for (final r in TeamRole.rolesFor(kind))
            if (r != TeamRole.owner)
              ListTile(
                leading: Icon(
                  r == role
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(r.labelFor(kind)),
                subtitle: Text(r.summaryFor(kind)),
                onTap: () => Navigator.pop(context, r),
              ),
        ],
      ),
    );
    if (picked != null && picked != role) {
      viewModel.setMemberRole.execute((uid: uid, role: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return PopupMenuButton<String>(
      onSelected: (action) async {
        switch (action) {
          case 'role':
            await _changeRole(context);
          case 'roles':
            final picked = await _pickRoles(context, team, uid, name);
            if (picked != null) {
              vm.setMemberRoles.execute((uid: uid, roleIds: picked));
            }
          case 'perms':
            final picked = await showMemberPermissions(
              context,
              team: team,
              uid: uid,
            );
            if (picked != null) {
              vm.setMemberPermissions.execute((uid: uid, permissions: picked));
            }
          case 'stats':
            vm.setStatKeeper.execute((uid: uid, on: !statKeeper));
          case 'owner':
            if (await confirmDialog(
              context,
              title: 'Make $name the owner?',
              message: _isGroup
                  ? 'They get full control of the community. You become a '
                        "member and can't undo this yourself."
                  : 'They get full control of the team. You become a '
                        "player and can't undo this yourself.",
              confirmLabel: 'Transfer ownership',
              destructive: true,
            )) {
              vm.transferOwnership.execute(uid);
            }
          case 'remove':
            if (await confirmDialog(
              context,
              title: 'Remove $name?',
              message:
                  'They will lose access to this ${_isGroup ? 'community' : 'team'}.',
              confirmLabel: 'Remove',
              destructive: true,
            )) {
              vm.removeMember.execute(uid);
            }
        }
      },
      itemBuilder: (_) => [
        if (vm.canSetRoles) ...[
          // There's one tier below owner; roles do the rest. Coaches and
          // captains from before roles can still be moved down.
          if (role != TeamRole.player)
            const PopupMenuItem(value: 'role', child: Text('Change role')),
          // A preset or per-person switches (players and members only:
          // the owner and legacy coaches and captains have everything).
          if (vm.canSetPermissions(uid))
            const PopupMenuItem(value: 'perms', child: Text('Permissions')),
          if (team.roles.isNotEmpty)
            const PopupMenuItem(value: 'roles', child: Text('Assign roles')),
          // Every other role already keeps stats; groups don't keep any.
          if (role == TeamRole.player && !_isGroup)
            PopupMenuItem(
              value: 'stats',
              child: Text(
                statKeeper ? 'Remove stats access' : 'Give stats access',
              ),
            ),
          const PopupMenuItem(value: 'owner', child: Text('Make owner')),
        ],
        if (vm.canRemove(uid))
          PopupMenuItem(
            value: 'remove',
            child: Text('Remove from ${_isGroup ? 'community' : 'team'}'),
          ),
      ],
    );
  }
}

/// The Roles view: each tier and custom role with the people who hold it.
/// Whoever sets roles (the owner) gets "Edit roles", which opens the roles
/// and permissions editor in team settings.
class _RolesView extends StatelessWidget {
  const _RolesView({required this.viewModel, required this.team});

  final TeamDetailViewModel viewModel;
  final Team team;

  List<String> _holders(bool Function(String uid, TeamRole tier) test) => [
    for (final e in team.members.entries)
      if (test(e.key, e.value)) e.key,
  ]..sort((a, b) => team.nameOf(a).compareTo(team.nameOf(b)));

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final kind = team.kind;
    final tiers = [
      (
        name: team.roleLabel(TeamRole.owner),
        summary: TeamRole.owner.summaryFor(kind),
        uids: _holders((_, t) => t == TeamRole.owner),
        always: true,
      ),
      // Coach and captain are tiers from before custom roles: listed while
      // someone still holds one.
      for (final t in [TeamRole.coach, TeamRole.captain])
        (
          name: team.roleLabel(t),
          summary: t.summaryFor(kind),
          uids: _holders((_, tier) => tier == t),
          always: false,
        ),
      if (!team.isCommunity)
        (
          name: 'Stats',
          summary: 'Keep and manage stats',
          uids: _holders(
            (uid, tier) => tier == TeamRole.player && team.isStatKeeper(uid),
          ),
          always: true,
        ),
    ];
    final custom = team.sortedRoles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewModel.canSetRoles) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () =>
                  pushTeamRoute(context, Routes.teamRoles(team.id)),
              icon: const Icon(Icons.tune),
              label: const Text('Edit roles'),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        for (final t in tiers)
          if (t.always || t.uids.isNotEmpty) ...[
            _RoleCard(
              team: team,
              name: t.name,
              summary: t.summary,
              uids: t.uids,
            ),
            const SizedBox(height: AppSpace.md),
          ],
        if (custom.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: AppSpace.sm),
            child: Eyebrow('Custom roles · ${custom.length}'),
          ),
        for (final r in custom) ...[
          _RoleCard(
            team: team,
            name: r.name,
            dot: r.color,
            summary: r.permissions.isEmpty
                ? 'Chat rooms that let it in'
                : [
                    for (final p in TeamPermission.values)
                      if (r.permissions.contains(p)) p.label,
                  ].join(', '),
            uids: _holders(
              (uid, _) => team.rolesOf(uid).any((x) => x.id == r.id),
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (custom.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Text(
              viewModel.canSetRoles
                  ? 'No custom roles yet. Edit roles to make some, like '
                        'Handlers or Organizers.'
                  : 'No custom roles yet.',
              style: AppText.secondary.copyWith(color: c.muted),
            ),
          ),
      ],
    );
  }
}

/// One role: its name, what it can do, and the people who hold it.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.team,
    required this.name,
    required this.summary,
    required this.uids,
    this.dot,
  });

  final Team team;
  final String name;
  final String summary;
  final List<String> uids;
  final int? dot;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (dot != null) ...[
                  RoleDot(color: dot!, size: 10),
                  const SizedBox(width: AppSpace.sm),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      name,
                      style: AppText.bodyStrong.copyWith(color: c.ink),
                    ),
                  ),
                ),
                StatusPill('${uids.length}'),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(summary, style: AppText.caption.copyWith(color: c.muted)),
            const SizedBox(height: AppSpace.sm),
            if (uids.isEmpty)
              Text(
                'Nobody yet',
                style: AppText.secondary.copyWith(color: c.muted),
              )
            else
              for (final uid in uids)
                InkWell(
                  onTap: () => context.push(Routes.player(uid)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        PersonAvatar(name: team.nameOf(uid), radius: 14),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Text(
                            team.nameOf(uid),
                            style: AppText.body.copyWith(color: c.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
