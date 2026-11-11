import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../routing/routes.dart';
import '../../core/ui/status_views.dart';
import '../view_models/host_event_viewmodel.dart';

/// Pick which group, school or club (or team) hosts a new tournament, hat
/// tournament or league, or start one to host from.
class HostEventScreen extends StatelessWidget {
  const HostEventScreen({super.key, required this.viewModel});

  final HostEventViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Host an event')),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          if (!viewModel.loaded) return const LoadingView();
          if (viewModel.error != null) return ErrorView(error: viewModel.error);
          final hosts = viewModel.hosts;
          return ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Run a tournament, a hat tournament where players sign up '
                  'on their own, or a weekly league. Events are hosted by a '
                  'group, school or club, so players can find and follow '
                  'them there.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  'What are you hosting?',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<HostedType>(
                  segments: [
                    for (final t in [
                      HostedType.league,
                      HostedType.tournament,
                      HostedType.hat,
                    ])
                      ButtonSegment(value: t, label: Text(t.label)),
                  ],
                  selected: {viewModel.type},
                  onSelectionChanged: (s) => viewModel.setType(s.first),
                ),
                const SizedBox(height: 16),
                if (hosts.isNotEmpty) ...[
                  Text('Host as', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final t in hosts)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.emoji_events_outlined),
                        ),
                        title: Text(t.name),
                        subtitle: Text(t.kind.label),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(
                          Routes.newTournament(t.id, type: viewModel.type.name),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Or start a new host',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  Text(
                    'You don\'t manage a group, school or club yet. Start one '
                    'to host from, for example your league\'s name.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: () => context.go(Routes.createCommunity),
                  icon: const Icon(Icons.apartment_outlined),
                  label: const Text('Start a school or club'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.go(Routes.createGroup),
                  icon: const Icon(Icons.diversity_3_outlined),
                  label: const Text('Start a community group'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
