import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories.dart';
import 'plan_editor_screen.dart';
import 'runner_screen.dart';

class PracticeScreen extends ConsumerWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(plansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Practice Plans')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final repo = ref.read(plansRepoProvider);
          final plan = await repo.createPlan(title: 'New Practice');
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PlanEditorScreen(planId: plan.id)),
            );
          }
        },
        child: const Icon(Icons.add),
      ),
      body: plansAsync.when(
        data: (plans) {
          if (plans.isEmpty) {
            return const Center(child: Text('Create your first practice plan.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: plans.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = plans[i];
              return Card(
                child: ListTile(
                  title: Text(p.title),
                  subtitle: Text('${p.items.length} drills • ${p.totalMinutes} min'),
                  leading: IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: p.items.isEmpty
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => RunnerScreen(planId: p.id)),
                            ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PlanEditorScreen(planId: p.id)),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
