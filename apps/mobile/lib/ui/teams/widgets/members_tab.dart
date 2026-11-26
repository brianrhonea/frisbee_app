import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../routing/push_team_route.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/invite_code_viewmodel.dart';
import '../view_models/team_detail_viewmodel.dart';
import 'invite_code_card.dart';
import 'invite_members_dialog.dart';
import 'member_permissions_dialog.dart';
import 'roles_screen.dart';

class MembersTab extends StatelessWidget {
  const MembersTab({super.key, required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final team = viewModel.team!;
    final members = team.members.entries.toList()
      ..sort((a, b) {
        final byRole = a.value.index.compareTo(b.value.index);
        return byRole != 0
            ? byRole
            : team.nameOf(a.key).compareTo(team.nameOf(b.key));
      });
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          if (viewModel.canManageMembers) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () async {
                  await showInviteMembers(context, team);
                  // Anyone just invited shows under Invites pending.
                  viewModel.loadInvites.execute();
                },
                icon: const Icon(Icons.person_search),
                label: Text(
                  team.isCommunity ? 'Invite members' : 'Invite players',
                ),
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
          _RolesHelp(team: team, isOwner: viewModel.isOwner),
          const SizedBox(height: 18),
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
                  ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
                    onTap: () => context.push(Routes.player(m.key)),
                    leading: PersonAvatar(name: team.nameOf(m.key), radius: 18),
                    title: Text.rich(
                      TextSpan(
                        text: team.nameOf(m.key),
                        children: [
                          if (m.key == viewModel.uid)
                            TextSpan(
                              text: ' (you)',
                              style: TextStyle(
                                color: c.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: c.ink,
                      ),
                    ),
                    subtitle: _MemberRoles(
                      team: team,
                      uid: m.key,
                      tier: m.value,
                    ),
                    trailing: viewModel.canManage(m.key)
                        ? _MemberMenu(
                            viewModel: viewModel,
                            uid: m.key,
                            name: team.nameOf(m.key),
                            role: m.value,
                            team: team,
                            statKeeper: team.isStatKeeper(m.key),
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
          if (viewModel.canSeeInvites &&
              viewModel.pendingInvites.isNotEmpty) ...[
            const SizedBox(height: 18),
            _PendingInvites(viewModel: viewModel),
          ],
        ],
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
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: c.ink,
                    ),
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
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(color: c.highlight.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${requests.length} '
            '${requests.length == 1 ? 'person wants' : 'people want'} '
            'to join',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: c.highlightInk,
            ),
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
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
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
    // Staff tiers (owner, coach, captain) and members with permissions of
    // their own stand out as a tag; a plain player or member is just text.
    final Widget tierLabel = tier == TeamRole.player && own.isEmpty
        ? Text(label)
        : Tag(label);
    if (roles.isEmpty) {
      return Align(alignment: Alignment.centerLeft, child: tierLabel);
    }
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        tierLabel,
        for (final r in roles)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RoleDot(color: r.color, size: 9),
              const SizedBox(width: 4),
              Text(r.name),
            ],
          ),
      ],
    );
  }
}

/// Picks which custom roles [uid] has, up to [maxRolesPerMember].
Future<Set<String>?> _pickRoles(
  BuildContext context,
  Team team,
  String uid,
  String name,
) => showDialog<Set<String>>(
  context: context,
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

/// What each tier and custom role can do, and, for the owner, a way to
/// manage roles.
class _RolesHelp extends StatelessWidget {
  const _RolesHelp({required this.team, required this.isOwner});

  final Team team;
  final bool isOwner;

  TeamKind get kind => team.kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final custom = team.sortedRoles;
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.admin_panel_settings_outlined),
        title: const Text('Roles'),
        subtitle: Text(
          custom.isEmpty
              ? 'What each role can do'
              : '${custom.length} custom '
                    '${custom.length == 1 ? 'role' : 'roles'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final r in custom)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs, right: 6),
                    child: RoleDot(color: r.color, size: 10),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      r.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.permissions.isEmpty
                          ? 'Chat rooms that let it in'
                          : [
                              for (final p in TeamPermission.values)
                                if (r.permissions.contains(p)) p.label,
                            ].join(', '),
                    ),
                  ),
                ],
              ),
            ),
          if (isOwner)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    pushTeamRoute(context, Routes.teamRoles(team.id)),
                icon: const Icon(Icons.tune),
                label: const Text('Manage roles'),
              ),
            ),
          for (final r in TeamRole.rolesFor(kind))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      r.labelFor(kind),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(child: Text(r.summaryFor(kind))),
                ],
              ),
            ),
          if (kind == TeamKind.team)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      '+ Stats',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Added to a player by the owner: keep and manage stats',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
