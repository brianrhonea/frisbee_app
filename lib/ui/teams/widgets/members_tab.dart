import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/team_detail_viewmodel.dart';

class MembersTab extends StatelessWidget {
  const MembersTab({super.key, required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.all(16),
        children: [
          if (viewModel.inviteCode case final code?
              when viewModel.canShareCode) ...[
            _InviteCard(viewModel: viewModel, code: code),
            const SizedBox(height: 16),
          ],
          if (team.isCommunity && viewModel.joinRequests.isNotEmpty) ...[
            _JoinRequests(viewModel: viewModel),
            const SizedBox(height: 16),
          ],
          _RolesHelp(kind: team.kind),
          const SizedBox(height: 16),
          Text(
            '${members.length} member${members.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final m in members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => context.push(Routes.person(m.key)),
              leading: CircleAvatar(
                child: Text(team.nameOf(m.key)[0].toUpperCase()),
              ),
              title: Text(
                team.nameOf(m.key) + (m.key == viewModel.uid ? ' (you)' : ''),
              ),
              subtitle: Text(
                team.isStatKeeper(m.key)
                    ? '${team.roleLabel(m.value)} · Stats'
                    : team.roleLabel(m.value),
              ),
              trailing: viewModel.canManage(m.key)
                  ? _MemberMenu(
                      viewModel: viewModel,
                      uid: m.key,
                      name: team.nameOf(m.key),
                      role: m.value,
                      kind: team.kind,
                      statKeeper: team.isStatKeeper(m.key),
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

/// People waiting to join a group that requires approval.
class _JoinRequests extends StatelessWidget {
  const _JoinRequests({required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requests = viewModel.joinRequests;
    return Card(
      color: theme.colorScheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${requests.length} '
              '${requests.length == 1 ? 'person wants' : 'people want'} '
              'to join',
              style: theme.textTheme.titleSmall,
            ),
            for (final r in requests)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(r.name.isEmpty ? '?' : r.name[0].toUpperCase()),
                ),
                title: Text(r.name.isEmpty ? 'Someone' : r.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Decline',
                      icon: const Icon(Icons.close),
                      onPressed: viewModel.declineJoinRequest.running
                          ? null
                          : () => viewModel.declineJoinRequest.execute(r.uid),
                    ),
                    FilledButton.tonal(
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
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.viewModel, required this.code});

  final TeamDetailViewModel viewModel;
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Invite code', style: theme.textTheme.labelLarge),
                  SelectableText(
                    code,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Share this code so teammates can join as players.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) {
                  showSnackBar(context, 'Invite code copied');
                }
              },
            ),
            if (viewModel.canRegenerateCode)
              IconButton(
                tooltip: 'New code',
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  if (await confirmDialog(
                    context,
                    title: 'Generate a new code?',
                    message: 'The current code will stop working.',
                    confirmLabel: 'Generate',
                  )) {
                    viewModel.regenerateInviteCode.execute();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberMenu extends StatelessWidget {
  const _MemberMenu({
    required this.viewModel,
    required this.uid,
    required this.name,
    required this.role,
    required this.kind,
    required this.statKeeper,
  });

  final TeamDetailViewModel viewModel;
  final String uid;
  final String name;
  final TeamRole role;
  final TeamKind kind;
  final bool statKeeper;

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
          case 'stats':
            vm.setStatKeeper.execute((uid: uid, on: !statKeeper));
          case 'owner':
            if (await confirmDialog(
              context,
              title: 'Make $name the owner?',
              message: _isGroup
                  ? 'They get full control of the group. You become a '
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
                  'They will lose access to this ${_isGroup ? 'group' : 'team'}.',
              confirmLabel: 'Remove',
              destructive: true,
            )) {
              vm.removeMember.execute(uid);
            }
        }
      },
      itemBuilder: (_) => [
        if (vm.canSetRoles) ...[
          const PopupMenuItem(value: 'role', child: Text('Change role')),
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
            child: Text('Remove from ${_isGroup ? 'group' : 'team'}'),
          ),
      ],
    );
  }
}

/// What each role can do.
class _RolesHelp extends StatelessWidget {
  const _RolesHelp({required this.kind});

  final TeamKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.admin_panel_settings_outlined),
        title: const Text('Roles'),
        subtitle: const Text('What each role can do'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
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
