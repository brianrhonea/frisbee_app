import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/ranking.dart';
import '../../../domain/models/team_elo.dart';
import '../../../routing/routes.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/usau_attribution.dart';
import '../view_models/rankings_viewmodel.dart';

class RankingsScreen extends StatelessWidget {
  const RankingsScreen({super.key, required this.viewModel});

  final RankingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Scaffold(
      appBar: AppBar(title: const Text('Rankings')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (vm.loading) return const LoadingView();
          if (vm.error != null) {
            return ErrorView(error: vm.error, onRetry: vm.retry);
          }
          final selected = vm.selected;
          if (selected == null) {
            return const EmptyView(
              icon: Icons.leaderboard_outlined,
              title: 'No rankings yet',
              message:
                  'Rankings from USA Ultimate sync daily. Check back soon.',
            );
          }
          final entries = vm.entries;
          final theme = Theme.of(context);
          return ConstrainedContent(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: selected.key,
                          decoration: const InputDecoration(
                            labelText: 'Division',
                          ),
                          items: [
                            for (final d in vm.divisions)
                              DropdownMenuItem(
                                value: d.key,
                                child: Text(d.label),
                              ),
                          ],
                          onChanged: (k) => vm.select(k!),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Find a team',
                          ),
                          onChanged: vm.setQuery,
                        ),
                        if (vm.hasElo) ...[
                          const SizedBox(height: 12),
                          SegmentedButton<RankingSort>(
                            segments: const [
                              ButtonSegment(
                                value: RankingSort.usau,
                                label: Text('USAU rank'),
                                icon: Icon(Icons.leaderboard_outlined),
                              ),
                              ButtonSegment(
                                value: RankingSort.elo,
                                label: Text('Elo'),
                                icon: Icon(Icons.trending_up),
                              ),
                            ],
                            selected: {vm.sort},
                            onSelectionChanged: (s) => vm.setSort(s.single),
                          ),
                        ],
                        if (vm.sort == RankingSort.elo &&
                            vm.eloUpdatedAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Elo from game results, updated '
                            '${DateFormat.yMMMd().format(vm.eloUpdatedAt!.toLocal())}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ] else if (selected.updatedAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Updated ${DateFormat.yMMMd().add_jm().format(selected.updatedAt!.toLocal())}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _RankingRow(
                    entry: entries[i],
                    elo: vm.eloFor(entries[i]),
                    byElo: vm.hasElo && vm.sort == RankingSort.elo,
                  ),
                ),
                const SliverToBoxAdapter(child: UsauAttribution()),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.entry, this.elo, this.byElo = false});

  final RankingEntry entry;
  final TeamEloEntry? elo;

  /// Lead with the Elo rank and rating instead of USAU's.
  final bool byElo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elo = this.elo;
    final details = [
      if (byElo) 'USAU #${entry.rank}',
      if (entry.region.isNotEmpty) entry.region,
      'Record ${entry.record}',
      if (!byElo && elo != null) 'Elo ${elo.elo.toStringAsFixed(0)}',
    ].join(' · ');
    final rank = byElo ? (elo == null ? '–' : '${elo.rank}') : '${entry.rank}';
    final value = byElo ? elo?.elo : entry.rating;
    return ListTile(
      leading: SizedBox(
        width: 40,
        child: Text(
          rank,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(entry.teamName),
      subtitle: Text(details),
      trailing: value == null
          ? null
          : Text(value.toStringAsFixed(0), style: theme.textTheme.titleSmall),
      onTap: entry.teamUrl.isEmpty
          ? null
          : () => context.push(
              Routes.usauTeam(entry.teamUrl, name: entry.teamName),
            ),
    );
  }
}
