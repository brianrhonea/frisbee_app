import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/roster_player.dart';
import '../../../routing/routes.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/status_views.dart';
import '../view_models/team_detail_viewmodel.dart';
import 'player_dialog.dart';

class RosterTab extends StatelessWidget {
  const RosterTab({super.key, required this.viewModel});

  final TeamDetailViewModel viewModel;

  Future<void> _edit(BuildContext context, [RosterPlayer? player]) async {
    final result = await showDialog<RosterPlayer>(
      context: context,
      builder: (_) => PlayerDialog(
        initial: player,
        members: _members(),
        linkedElsewhere: {
          for (final p in viewModel.roster)
            if (p.id != player?.id && p.userId != null) p.userId!,
        },
      ),
    );
    if (result != null) viewModel.savePlayer.execute(result);
  }

  /// Members by name, for linking a roster spot to an account.
  Map<String, String> _members() {
    final team = viewModel.team;
    if (team == null) return const {};
    final entries = [
      for (final uid in team.members.keys) MapEntry(uid, team.nameOf(uid)),
    ]..sort((a, b) => a.value.compareTo(b.value));
    return Map.fromEntries(entries);
  }

  Future<void> _delete(BuildContext context, RosterPlayer player) async {
    if (await confirmDialog(
      context,
      title: 'Remove ${player.name}?',
      message: 'They will be removed from the roster.',
      confirmLabel: 'Remove',
      destructive: true,
    )) {
      viewModel.deletePlayer.execute(player.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roster = viewModel.visibleRoster;
    final canEdit = viewModel.canEdit;
    final showStatus = viewModel.canSeeRosterStatus;
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              heroTag: 'add-player',
              onPressed: () => _edit(context),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add player'),
            )
          : null,
      body: ConstrainedContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
          children: [
            if (showStatus) _UsauCard(viewModel: viewModel),
            if (viewModel.roster.isEmpty)
              EmptyView(
                icon: Icons.badge_outlined,
                title: 'No players on the roster',
                message: canEdit
                    ? 'Add players one by one, or import them from USA '
                          'Ultimate.'
                    : null,
              )
            else if (roster.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Everyone is confirmed.')),
              ),
            for (final (i, p) in roster.indexed) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(child: Text(p.number?.toString() ?? '–')),
                title: Text(p.name),
                subtitle: showStatus
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(p.position.label),
                            if (p.onUsau != null) _UsauBadge(onUsau: p.onUsau!),
                            _PaidBadge(
                              paid: p.paid,
                              onTap: canEdit
                                  ? () => viewModel.togglePaid(p)
                                  : null,
                            ),
                          ],
                        ),
                      )
                    : Text(p.position.label),
                onTap: canEdit ? () => _edit(context, p) : null,
                trailing: canEdit
                    ? IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(context, p),
                      )
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// USA Ultimate link, sync button and confirmation counts.
class _UsauCard extends StatelessWidget {
  const _UsauCard({required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final team = vm.team!;
    final theme = Theme.of(context);
    final linked = team.usauUrl != null;
    final total = vm.roster.length;
    final synced = team.usauSyncedAt;
    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    linked
                        ? (team.usauName?.isNotEmpty ?? false)
                              ? team.usauName!
                              : 'USA Ultimate team linked'
                        : 'USA Ultimate roster',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (vm.canEdit)
                  FilledButton.tonalIcon(
                    onPressed: () => context.push(Routes.usauRoster(team.id)),
                    icon: Icon(linked ? Icons.sync : Icons.download),
                    label: Text(linked ? 'Sync' : 'Import'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (!linked)
              Text(
                'Import your roster from USA Ultimate and track who has '
                'accepted a spot.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(
                '${vm.confirmedCount}/$total confirmed  ·  '
                '${vm.onUsauCount} on USA Ultimate  ·  ${vm.paidCount} paid',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                synced == null
                    ? 'Not synced yet'
                    : 'Last synced ${DateFormat.yMMMd().add_jm().format(synced)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilterChip(
                  label: const Text('Unconfirmed only'),
                  selected: vm.unconfirmedOnly,
                  onSelected: vm.setUnconfirmedOnly,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UsauBadge extends StatelessWidget {
  const _UsauBadge({required this.onUsau});

  final bool onUsau;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = onUsau ? scheme.primary : scheme.error;
    return _Badge(
      icon: onUsau ? Icons.check_circle : Icons.error_outline,
      label: onUsau ? 'On USAU' : 'Not on USAU',
      color: color,
    );
  }
}

class _PaidBadge extends StatelessWidget {
  const _PaidBadge({required this.paid, this.onTap});

  final bool paid;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = _Badge(
      icon: paid ? Icons.paid : Icons.money_off_outlined,
      label: paid ? 'Paid' : 'Unpaid',
      color: paid ? scheme.primary : scheme.onSurfaceVariant,
    );
    if (onTap == null) return badge;
    return Tooltip(
      message: paid ? 'Mark unpaid' : 'Mark paid',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: badge,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: color.withValues(alpha: 0.6)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    ),
  );
}
