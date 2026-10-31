import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/usau_attribution.dart';
import '../view_models/usau_team_search_viewmodel.dart';

/// Search USA Ultimate teams by name; each result opens its team page.
class UsauTeamSearchScreen extends StatefulWidget {
  const UsauTeamSearchScreen({super.key, required this.viewModel});

  final UsauTeamSearchViewModel viewModel;

  @override
  State<UsauTeamSearchScreen> createState() => _UsauTeamSearchScreenState();
}

class _UsauTeamSearchScreenState extends State<UsauTeamSearchScreen> {
  late final _search = TextEditingController(text: widget.viewModel.query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(
        leading: backOr(context, Routes.teams),
        title: const Text('Search USA Ultimate'),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          final theme = Theme.of(context);
          final results = vm.results;
          return ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _search,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: 'Team name',
                    suffixIcon: vm.query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              vm.setQuery('');
                            },
                          ),
                  ),
                  onChanged: vm.setQuery,
                ),
                if (vm.divisions.length > 1) ...[
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final label in [null, ...vm.divisions])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label ?? 'All'),
                              selected: vm.division == label,
                              onSelected: (_) => vm.setDivision(label),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (vm.searching)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (vm.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      errorMessage(vm.error),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 8),
                if (vm.query.trim().isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Look up any ranked USA Ultimate team to see its '
                      'roster and results.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                else if (results.isEmpty && !vm.searching)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No ranked teams match.'),
                  ),
                for (final c in results)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text('${c.entry.rank}')),
                    title: Text(c.entry.teamName),
                    subtitle: Text(
                      [
                        c.division,
                        if (c.entry.region.isNotEmpty) c.entry.region,
                        c.entry.record,
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(
                      Routes.searchedUsauTeam(
                        c.entry.teamUrl,
                        name: c.entry.teamName,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const UsauAttribution(),
              ],
            ),
          );
        },
      ),
    );
  }
}
