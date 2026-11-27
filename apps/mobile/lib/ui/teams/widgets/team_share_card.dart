import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/team_share/team_share_repository.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_share.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../view_models/team_share_viewmodel.dart';

/// Splitting a team fee on the team's page: someone who paid for the whole
/// team (a league's team fee, say) sets each member's share and how to pay
/// them, and marks who has paid. No money passes through Stall 10. Shows
/// nothing to members until there's a split; admins see how to start one.
class TeamShareCard extends StatefulWidget {
  const TeamShareCard({super.key, required this.team});

  final Team team;

  @override
  State<TeamShareCard> createState() => _TeamShareCardState();
}

class _TeamShareCardState extends State<TeamShareCard> {
  TeamShareViewModel? _vm;

  @override
  void initState() {
    super.initState();
    // Optional, so pages built without it (tests) still render.
    final repo = context.read<TeamShareRepository?>();
    if (repo != null) {
      _vm = TeamShareViewModel(teamId: widget.team.id, repository: repo);
    }
  }

  @override
  void dispose() {
    _vm?.dispose();
    super.dispose();
  }

  Future<void> _edit(TeamShareViewModel vm) async {
    final result = await showDialog<({int amountCents, String note})>(
      context: context,
      builder: (_) =>
          _ShareDialog(initial: vm.share, people: widget.team.members.length),
    );
    if (result == null || !mounted) return;
    await vm.save.execute(result);
    if (!mounted) return;
    if (vm.save.result case Error(:final error)) {
      showErrorSnackBar(context, error);
    }
  }

  Future<void> _mark(TeamShareViewModel vm, String uid, bool paid) async {
    await vm.markPaid.execute((uid: uid, paid: paid));
    if (!mounted) return;
    if (vm.markPaid.result case Error(:final error)) {
      showErrorSnackBar(context, error);
    }
  }

  Future<void> _stop(TeamShareViewModel vm) async {
    final ok = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('Stop splitting the fee?'),
        content: const Text("Everyone's paid marks are cleared too."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await vm.clear.execute();
    if (!mounted) return;
    if (vm.clear.result case Error(:final error)) {
      showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    if (vm == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final c = AppColors.of(context);
        final share = vm.share;
        if (share == null) {
          if (!vm.manages) return const SizedBox.shrink();
          return SectionCard(
            title: 'Split a team fee',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Paid for the whole team, like a league's team fee? Set "
                  "each person's share and how to pay you, then mark people "
                  'paid as they do.',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('share-start'),
                  onPressed: () => _edit(vm),
                  icon: const Icon(Icons.call_split, size: 18),
                  label: const Text('Split a fee'),
                ),
              ],
            ),
          );
        }
        final mine = vm.view.mine;
        final t = vm.totals;
        return SectionCard(
          title: 'Team fee',
          action: vm.manages
              ? PopupMenuButton<String>(
                  tooltip: 'Team fee options',
                  onSelected: (v) => v == 'edit' ? _edit(vm) : _stop(vm),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Change')),
                    PopupMenuItem(value: 'stop', child: Text('Stop splitting')),
                  ],
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${shareMoney(share.amountCents)} each, paid to "
                '${mine == null ? 'you' : share.collectorName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (share.note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  share.note,
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ],
              if (mine != null) ...[
                const SizedBox(height: 8),
                Chip(
                  key: const Key('share-mine'),
                  avatar: Icon(
                    mine ? Icons.check_circle : Icons.schedule,
                    size: 18,
                    color: mine ? AppColors.of(context).positive : null,
                  ),
                  label: Text(mine ? "You've paid" : 'Not paid yet'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
              if (vm.manages) ...[
                const SizedBox(height: 8),
                Text(
                  '${t.paid} of ${t.paid + t.owed} paid · '
                  '${shareMoney(t.collectedCents)} in, '
                  '${shareMoney(t.outstandingCents)} to go',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                for (final m in vm.view.members)
                  CheckboxListTile(
                    key: Key('share-paid-${m.uid}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: m.paid,
                    title: Text(m.name),
                    onChanged: vm.markPaid.running
                        ? null
                        : (v) => _mark(vm, m.uid, v ?? false),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.initial, required this.people});

  final TeamShare? initial;

  /// Everyone on the team, the collector included, for an even split.
  final int people;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  late final _amount = TextEditingController(
    text: switch (widget.initial?.amountCents) {
      final c? => (c / 100).toStringAsFixed(c % 100 == 0 ? 0 : 2),
      null => '',
    },
  );
  final _total = TextEditingController();
  late final _note = TextEditingController(text: widget.initial?.note ?? '');
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _total.dispose();
    _note.dispose();
    super.dispose();
  }

  void _split(String typed) {
    final total = parseShareCents(typed);
    if (total == null) return;
    final each = evenShare(total, widget.people);
    setState(() => _amount.text = (each / 100).toStringAsFixed(2));
  }

  void _done() {
    final cents = parseShareCents(_amount.text);
    if (cents == null) {
      setState(() => _error = "Enter each person's share, e.g. 40.");
      return;
    }
    Navigator.pop(context, (amountCents: cents, note: _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Split a team fee' : 'Team fee'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('share-total'),
              controller: _total,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Total fee (optional)',
                prefixText: r'$',
                helperText:
                    'Split evenly among the ${widget.people} people on the '
                    'team, you included.',
                helperMaxLines: 2,
              ),
              onChanged: _split,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('share-amount'),
              controller: _amount,
              autofocus: widget.initial != null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: "Each person's share",
                prefixText: r'$',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('share-note'),
              controller: _note,
              maxLength: teamShareNoteMax,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'How to pay you',
                hintText: 'e.g. Venmo @alex, or cash at practice',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _done, child: const Text('Save')),
      ],
    );
  }
}
