import 'package:flutter/material.dart';

import '../../../domain/models/roster_player.dart';
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
            if (showStatus && viewModel.roster.isNotEmpty)
              _PaidCard(viewModel: viewModel),
            if (viewModel.roster.isEmpty)
              EmptyView(
                icon: Icons.badge_outlined,
                title: 'No players on the roster',
                message: canEdit ? 'Add players one by one.' : null,
              )
            else if (roster.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Everyone has paid.')),
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

/// How many players have paid, with a filter for those who haven't.
class _PaidCard extends StatelessWidget {
  const _PaidCard({required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${vm.paidCount}/${vm.roster.length} paid',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            FilterChip(
              label: const Text('Unpaid only'),
              selected: vm.unpaidOnly,
              onSelected: vm.setUnpaidOnly,
            ),
          ],
        ),
      ),
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
