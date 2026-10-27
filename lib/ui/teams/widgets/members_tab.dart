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
          if (team.inviteCode != null)
            _InviteCard(viewModel: viewModel, code: team.inviteCode!),
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
              subtitle: Text(m.value.label),
              trailing: viewModel.canManage(m.key)
                  ? _MemberMenu(
                      viewModel: viewModel,
                      uid: m.key,
                      name: team.nameOf(m.key),
                      role: m.value,
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
            if (viewModel.canEdit)
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
  });

  final TeamDetailViewModel viewModel;
  final String uid;
  final String name;
  final TeamRole role;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (action) async {
        switch (action) {
          case 'coach':
            viewModel.setMemberRole.execute((uid: uid, role: TeamRole.coach));
          case 'player':
            viewModel.setMemberRole.execute((uid: uid, role: TeamRole.player));
          case 'remove':
            if (await confirmDialog(
              context,
              title: 'Remove $name?',
              message: 'They will lose access to this team.',
              confirmLabel: 'Remove',
              destructive: true,
            )) {
              viewModel.removeMember.execute(uid);
            }
        }
      },
      itemBuilder: (_) => [
        if (viewModel.isOwner && role == TeamRole.player)
          const PopupMenuItem(value: 'coach', child: Text('Make coach')),
        if (viewModel.isOwner && role == TeamRole.coach)
          const PopupMenuItem(value: 'player', child: Text('Make player')),
        const PopupMenuItem(value: 'remove', child: Text('Remove from team')),
      ],
    );
  }
}
