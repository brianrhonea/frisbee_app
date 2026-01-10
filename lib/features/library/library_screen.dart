import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories.dart';
import '../../models/drill.dart';
import 'drill_detail_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drillsAsync = ref.watch(drillsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Drill Library')),
      body: drillsAsync.when(
        data: (drills) => _DrillList(drills: drills),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _DrillList extends StatelessWidget {
  final List<Drill> drills;
  const _DrillList({required this.drills});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: drills.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final d = drills[i];
        return Card(
          child: ListTile(
            title: Text(d.title),
            subtitle: Text('${d.category} • ${d.suggestedMinutes} min • '
                '${d.minPlayers}-${d.maxPlayers} players'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DrillDetailScreen(drillId: d.id)),
            ),
          ),
        );
      },
    );
  }
}
