import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/status_views.dart';
import '../view_models/team_search_viewmodel.dart';

/// Search the app's teams by name or city; each result opens the team's
/// home page (its public page for non-members). USA Ultimate's rankings
/// have their own search.
class TeamSearchScreen extends StatefulWidget {
  const TeamSearchScreen({super.key, required this.viewModel});

  final TeamSearchViewModel viewModel;

  @override
  State<TeamSearchScreen> createState() => _TeamSearchScreenState();
}

class _TeamSearchScreenState extends State<TeamSearchScreen> {
  TeamSearchViewModel get vm => widget.viewModel;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => vm.search.execute(text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: backOr(context, Routes.teams),
        title: const Text('Find a team'),
      ),
      body: ConstrainedContent(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Team name or city',
                ),
                onChanged: _onChanged,
                onSubmitted: vm.search.execute,
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([vm, vm.search]),
                builder: (context, _) {
                  final usau = ListTile(
                    leading: const Icon(Icons.leaderboard_outlined),
                    title: const Text('Search USA Ultimate rankings'),
                    subtitle: const Text(
                      'Look up any ranked team, its roster and results',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.searchUsauTeams),
                  );
                  if (vm.search.running) return const LoadingView();
                  if (vm.search.error) {
                    return ErrorView(error: vm.search.result);
                  }
                  final results = vm.results;
                  return ListView(
                    children: [
                      if (vm.noMatches)
                        const EmptyView(
                          icon: Icons.search_off,
                          title: 'No teams found',
                          message:
                              'Try another word from the team name or '
                              'its city.',
                        )
                      else if (results.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Type at least '
                            '${TeamSearchViewModel.minQueryLength} letters '
                            'of a team name or city.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.muted),
                          ),
                        ),
                      for (final t in results)
                        ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              t.name.isEmpty ? '?' : t.name[0].toUpperCase(),
                            ),
                          ),
                          title: Text(t.name),
                          subtitle: Text(t.subtitle),
                          trailing: vm.isMine(t.id)
                              ? const Chip(label: Text('Your team'))
                              : const Icon(Icons.chevron_right),
                          onTap: () => context.push(Routes.team(t.id)),
                        ),
                      const Divider(height: 32),
                      usau,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
