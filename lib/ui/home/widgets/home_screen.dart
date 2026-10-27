import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../core/ui/status_views.dart';
import '../../tournaments/widgets/tournaments_screen.dart' show formatDateRange;
import '../view_models/home_viewmodel.dart';

/// Placeholder landing page — to be designed.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final vm = viewModel;
          return ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Welcome, ${vm.user?.label ?? 'player'}!',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: 'My teams',
                  onSeeAll: () => context.go(Routes.teams),
                ),
                if (vm.teams.isEmpty)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.group_add_outlined),
                      title: const Text('Create or join a team'),
                      onTap: () => context.go(Routes.teams),
                    ),
                  )
                else
                  for (final t in vm.teams)
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(t.name),
                      subtitle: Text('${t.division.label} · ${t.level.label}'),
                      onTap: () => context.go(Routes.team(t.id)),
                    ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: 'Upcoming tournaments',
                  onSeeAll: () => context.go(Routes.tournaments),
                ),
                if (vm.upcomingTournaments.isEmpty)
                  const ListTile(title: Text('Nothing scheduled yet.'))
                else
                  for (final t in vm.upcomingTournaments)
                    ListTile(
                      leading: const Icon(Icons.emoji_events_outlined),
                      title: Text(t.name),
                      subtitle: Text(
                        [
                          formatDateRange(t.startDate, t.endDate),
                          if (t.location.isNotEmpty) t.location,
                        ].join(' · '),
                      ),
                      onTap: () => context.go(Routes.tournament(t.id)),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onSeeAll});

  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      TextButton(onPressed: onSeeAll, child: const Text('See all')),
    ],
  );
}
