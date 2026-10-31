import 'package:flutter/material.dart';

import '../../core/ui/status_views.dart';
import '../../core/ui/usau_attribution.dart';
import '../../tournaments/view_models/tournaments_viewmodel.dart';
import '../../tournaments/widgets/tournament_widgets.dart';

/// Events tab: USA Ultimate tournaments. Team and personal events live on
/// the Schedule tab.
class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key, required this.viewModel});

  final TournamentsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (vm.loading) return const LoadingView();
          if (vm.error != null) {
            return ErrorView(error: vm.error, onRetry: vm.retry);
          }
          if (vm.isEmpty) {
            return const EmptyView(
              icon: Icons.emoji_events_outlined,
              title: 'No tournaments yet',
              message:
                  'Tournament data from USA Ultimate syncs daily. '
                  'Check back soon.',
            );
          }
          final list = vm.tournaments;
          return ConstrainedContent(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: TournamentFilters(viewModel: vm)),
                if (list.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyView(
                      icon: Icons.search_off,
                      title: 'No matching tournaments',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverList.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          TournamentCard(tournament: list[i]),
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
