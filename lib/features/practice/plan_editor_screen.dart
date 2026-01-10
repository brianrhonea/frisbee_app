import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories.dart';
import '../../models/plan.dart';

class PlanEditorScreen extends ConsumerStatefulWidget {
  final String planId;
  final String? addDrillId; // optional: push a drill into the plan on open
  const PlanEditorScreen({super.key, required this.planId, this.addDrillId});

  @override
  ConsumerState<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends ConsumerState<PlanEditorScreen> {
  bool _added = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Add drill once if provided
    if (!_added && widget.addDrillId != null) {
      _added = true;
      final repo = ref.read(plansRepoProvider);
      final plan = repo.getById(widget.planId);
      if (plan != null) {
        final drill = ref.read(drillsRepoProvider).getById(widget.addDrillId!);
        final minutes = drill?.suggestedMinutes ?? 10;
        final updated = PracticePlan(
          id: plan.id,
          title: plan.title,
          items: [...plan.items, PlanItem(drillId: widget.addDrillId!, minutes: minutes)],
        );
        repo.save(updated);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(plansRepoProvider);
    final plan = repo.getById(widget.planId);

    if (plan == null) {
      return const Scaffold(body: Center(child: Text('Plan not found')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(plan.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await repo.delete(plan.id);
              if (context.mounted) Navigator.pop(context);
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text('Total: ${plan.totalMinutes} min',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    final drillList = ref.read(drillsRepoProvider).getAll();
                    final picked = await showModalBottomSheet<String>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => ListView(
                        children: [
                          const ListTile(title: Text('Add drill')),
                          ...drillList.map(
                            (d) => ListTile(
                              title: Text(d.title),
                              subtitle: Text('${d.category} • ${d.suggestedMinutes} min'),
                              onTap: () => Navigator.pop(context, d.id),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (picked != null) {
                      final drill = ref.read(drillsRepoProvider).getById(picked);
                      final updated = PracticePlan(
                        id: plan.id,
                        title: plan.title,
                        items: [...plan.items, PlanItem(drillId: picked, minutes: drill?.suggestedMinutes ?? 10)],
                      );
                      await repo.save(updated);
                      setState(() {});
                    }
                  },
                  child: const Text('Add drill'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: plan.items.length,
              onReorder: (oldIndex, newIndex) async {
                final items = [...plan.items];
                if (newIndex > oldIndex) newIndex -= 1;
                final item = items.removeAt(oldIndex);
                items.insert(newIndex, item);
                await repo.save(PracticePlan(id: plan.id, title: plan.title, items: items));
                setState(() {});
              },
              itemBuilder: (context, i) {
                final item = plan.items[i];
                final drill = ref.read(drillsRepoProvider).getById(item.drillId);
                return Card(
                  key: ValueKey('${plan.id}_${item.drillId}_$i'),
                  child: ListTile(
                    title: Text(drill?.title ?? 'Unknown drill'),
                    subtitle: Text(drill?.category ?? ''),
                    leading: const Icon(Icons.drag_handle),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MinutesStepper(
                          minutes: item.minutes,
                          onChanged: (m) async {
                            final items = [...plan.items];
                            items[i] = PlanItem(drillId: item.drillId, minutes: m);
                            await repo.save(PracticePlan(id: plan.id, title: plan.title, items: items));
                            setState(() {});
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            final items = [...plan.items]..removeAt(i);
                            await repo.save(PracticePlan(id: plan.id, title: plan.title, items: items));
                            setState(() {});
                          },
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MinutesStepper extends StatelessWidget {
  final int minutes;
  final ValueChanged<int> onChanged;
  const _MinutesStepper({required this.minutes, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: minutes <= 1 ? null : () => onChanged(minutes - 1),
        ),
        Text('$minutes'),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => onChanged(minutes + 1),
        ),
      ],
    );
  }
}
