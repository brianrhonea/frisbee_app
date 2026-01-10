import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories.dart';
import '../practice/plan_editor_screen.dart';

class DrillDetailScreen extends ConsumerWidget {
  final String drillId;
  const DrillDetailScreen({super.key, required this.drillId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drill = ref.read(drillsRepoProvider).getById(drillId);
    if (drill == null) {
      return const Scaffold(body: Center(child: Text('Drill not found')));
    }

    return Scaffold(
      appBar: AppBar(title: Text(drill.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final plans = ref.read(plansRepoProvider).getAll();
          // If none exist, create a default plan.
          final plan = plans.isNotEmpty
              ? plans.first
              : await ref.read(plansRepoProvider).createPlan(title: 'My Practice');

          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlanEditorScreen(planId: plan.id, addDrillId: drill.id),
              ),
            );
          }
        },
        label: const Text('Add to Plan'),
        icon: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: drill.skills.map((s) => Chip(label: Text(s))).toList(),
          ),
          const SizedBox(height: 16),
          _Section(title: 'Setup', body: drill.setup),
          _Section(title: 'Steps', body: drill.steps),
          _Section(title: 'Coaching points', body: drill.coachingPoints),
          _Section(title: 'Variations', body: drill.variations),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }
}
