import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/team.dart';
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
          if (team.inviteCode != null && viewModel.canShareCode) ...[
            _InviteCard(viewModel: viewModel, code: team.inviteCode!),
            const SizedBox(height: 16),
          ],
          const _RolesHelp(),
          const SizedBox(height: 16),
          Text(
            '${members.length} member${members.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final m in members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(team.nameOf(m.key)[0].toUpperCase()),
              ),
              title: Text(
                team.nameOf(m.key) + (m.key == viewModel.uid ? ' (you)' : ''),
              ),
              subtitle: Text(
                team.isStatKeeper(m.key)
                    ? '${m.value.label} · Stats'
                    : m.value.label,
              ),
              trailing: viewModel.canManage(m.key)
                  ? _MemberMenu(
                      viewModel: viewModel,
                      uid: m.key,
                      name: team.nameOf(m.key),
                      role: m.value,
                      statKeeper: team.isStatKeeper(m.key),
                    )
                  : null,
            ),
        ],
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
    required this.statKeeper,
  });

  final TeamDetailViewModel viewModel;
  final String uid;
  final String name;
  final TeamRole role;
  final bool statKeeper;

  Future<void> _changeRole(BuildContext context) async {
    final picked = await showDialog<TeamRole>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Role for $name'),
        children: [
          for (final r in TeamRole.values)
            if (r != TeamRole.owner)
              ListTile(
                leading: Icon(
                  r == role
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(r.label),
                subtitle: Text(r.summary),
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
              message:
                  'They get full control of the team. You become a player '
                  "and can't undo this yourself.",
              confirmLabel: 'Transfer ownership',
              destructive: true,
            )) {
              vm.transferOwnership.execute(uid);
            }
          case 'remove':
            if (await confirmDialog(
              context,
              title: 'Remove $name?',
              message: 'They will lose access to this team.',
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
          // Every other role already keeps stats.
          if (role == TeamRole.player)
            PopupMenuItem(
              value: 'stats',
              child: Text(
                statKeeper ? 'Remove stats access' : 'Give stats access',
              ),
            ),
          const PopupMenuItem(value: 'owner', child: Text('Make owner')),
        ],
        if (vm.canRemove(uid))
          const PopupMenuItem(value: 'remove', child: Text('Remove from team')),
      ],
    );
  }
}

/// What each role can do.
class _RolesHelp extends StatelessWidget {
  const _RolesHelp();

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
          for (final r in TeamRole.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      r.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(child: Text(r.summary)),
                ],
              ),
            ),
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
