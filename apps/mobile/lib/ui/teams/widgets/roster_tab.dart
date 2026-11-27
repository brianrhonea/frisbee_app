import 'package:flutter/material.dart';

import '../../../domain/models/roster_player.dart';
import '../../../domain/models/team.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';
import '../../core/ui/status_views.dart';
import '../view_models/team_detail_viewmodel.dart';
import 'player_dialog.dart';
import '../../core/ui/app_segmented_button.dart';

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
    final c = AppColors.of(context);
    final roster = viewModel.visibleRoster;
    final canEdit = viewModel.canEdit;
    final showStatus = viewModel.canSeeRosterStatus;
    final editing = viewModel.editingLines;
    final groups = viewModel.lineGroups;
    Widget card(List<RosterPlayer> players) => Card(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, p) in players.indexed) ...[
            if (i > 0) Divider(height: 1, color: c.border),
            _row(context, p, canEdit: canEdit, showStatus: showStatus),
          ],
        ],
      ),
    );
    return Scaffold(
      floatingActionButton: canEdit && !editing
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
            // Admins who also play: one tap to a spot linked to them.
            if (canEdit && viewModel.team != null && !viewModel.onRoster)
              Card.outlined(
                margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: ListTile(
                  leading: const Icon(Icons.person_pin_outlined),
                  title: const Text("You're not on the roster"),
                  subtitle: const Text('Add yourself if you play.'),
                  trailing: FilledButton.tonal(
                    onPressed: () => _edit(context, viewModel.selfDraft),
                    child: const Text('Add yourself'),
                  ),
                ),
              ),
            if (showStatus && viewModel.roster.isNotEmpty && !editing)
              _PaidCard(viewModel: viewModel),
            if (viewModel.canEditLines && viewModel.roster.isNotEmpty)
              _LinesBar(viewModel: viewModel),
            if (viewModel.roster.isEmpty)
              EmptyState(
                icon: Icons.badge_outlined,
                title: 'No players on the roster',
                message: canEdit ? 'Add players one by one.' : null,
              )
            else if (roster.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpace.xl),
                child: Center(child: Text('Everyone has paid.')),
              ),
            // O-line, D-line, Both lines, Unassigned; one list until anyone
            // has a line (and while editing them).
            if (groups.isEmpty && roster.isNotEmpty) card(roster),
            for (final g in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Eyebrow(
                  '${g.line?.label ?? RosterLine.unassignedLabel} '
                  '· ${g.players.length}',
                ),
              ),
              card(g.players),
            ],
          ],
        ),
      ),
    );
  }

  /// A player: jersey number on navy, name, their role on the team (for a
  /// spot linked to a member), position (and paid status). While editing
  /// lines, the O / D / Both picker takes the place of Remove.
  Widget _row(
    BuildContext context,
    RosterPlayer p, {
    required bool canEdit,
    required bool showStatus,
  }) {
    final c = AppColors.of(context);
    final editing = viewModel.editingLines;
    final team = viewModel.team;
    final uid = p.userId;
    final tier = uid == null ? null : team?.roleOf(uid);
    final roles = uid == null || team == null
        ? const <String>[]
        : [for (final r in team.rolesOf(uid)) r.name];
    final details = Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Staff tiers stand out as a tag; custom roles follow as text.
        if (team != null && tier != null && tier != TeamRole.player)
          Tag(team.roleLabel(tier)),
        for (final r in roles) Text(r),
        Text(p.position.label),
        if (showStatus && !editing)
          _PaidBadge(
            paid: p.paid,
            onTap: canEdit ? () => viewModel.togglePaid(p) : null,
          ),
      ],
    );
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.feature,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: ScoreText(
          p.number?.toString() ?? '–',
          size: 21,
          color: c.onFeature,
        ),
      ),
      title: Text(
        p.name,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: c.ink,
        ),
      ),
      subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: details),
      onTap: canEdit && !editing ? () => _edit(context, p) : null,
      trailing: editing
          ? _LinePicker(
              line: viewModel.lineOf(p),
              onPick: (l) => viewModel.pickLine(p, l),
            )
          : canEdit
          ? IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, p),
            )
          : null,
    );
  }
}

/// "Edit lines" for the team's admins; while editing, Cancel and Save.
class _LinesBar extends StatelessWidget {
  const _LinesBar({required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: vm.saveLines,
      builder: (context, _) {
        final saving = vm.saveLines.running;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  vm.editingLines
                      ? 'Tap O, D or Both for each player.'
                      : 'Group the roster into O-line and D-line.',
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ),
              if (vm.editingLines) ...[
                TextButton(
                  onPressed: saving ? null : vm.cancelEditingLines,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: saving ? null : vm.saveLines.execute,
                  child: Text(saving ? 'Saving…' : 'Save lines'),
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: vm.startEditingLines,
                  icon: const Icon(Icons.swap_vert, size: 18),
                  label: const Text('Edit lines'),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// O / D / Both for one player; tapping the picked one clears it.
class _LinePicker extends StatelessWidget {
  const _LinePicker({required this.line, required this.onPick});

  final RosterLine? line;
  final ValueChanged<RosterLine> onPick;

  @override
  Widget build(BuildContext context) => AppSegmentedButton<RosterLine>(
    segments: [
      for (final l in RosterLine.values)
        ButtonSegment(value: l, label: Text(l.short), tooltip: l.label),
    ],
    selected: {?line},
    emptySelectionAllowed: true,
    showSelectedIcon: false,
    // Tapping the picked segment empties the set: that clears it.
    onSelectionChanged: (picked) =>
        onPick(picked.isEmpty ? line! : picked.single),
  );
}

// How many players have paid, with a filter for those who haven't.
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
      color: paid ? AppColors.of(context).positive : scheme.onSurfaceVariant,
    );
    if (onTap == null) return badge;
    return Tooltip(
      message: paid ? 'Mark unpaid' : 'Mark paid',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
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
      borderRadius: BorderRadius.circular(AppRadius.control),
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
