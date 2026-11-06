import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/player_profile.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../view_models/browse_search_viewmodel.dart';

/// Explore for signed-out visitors: find players, teams and groups by
/// name, and open their public pages.
class BrowseSearchScreen extends StatefulWidget {
  const BrowseSearchScreen({
    super.key,
    required this.viewModel,
    this.initialQuery = '',
  });

  final BrowseSearchViewModel viewModel;

  /// Search text from `?q=`.
  final String initialQuery;

  @override
  State<BrowseSearchScreen> createState() => _BrowseSearchScreenState();
}

class _BrowseSearchScreenState extends State<BrowseSearchScreen> {
  BrowseSearchViewModel get vm => widget.viewModel;
  late final _text = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) vm.search.execute(widget.initialQuery);
  }

  @override
  void didUpdateWidget(BrowseSearchScreen old) {
    super.didUpdateWidget(old);
    final q = widget.initialQuery;
    if (q != old.initialQuery && q.isNotEmpty) {
      _text.text = q;
      vm.search.execute(q);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => vm.search.execute(text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ScreenSize.of(context).isMobile;
    return Scaffold(
      appBar: mobile ? AppBar(title: const Text('Explore')) : null,
      body: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.search]),
        builder: (context, _) => PageScroll(
          children: [
            if (!mobile)
              const PageHeader(
                eyebrow: 'Explore',
                title: 'Find your next point.',
                subtitle: 'Players, teams and pickup groups on $appName.',
              ),
            AppSearchField(
              controller: _text,
              hint: 'Search players, teams and groups',
              onChanged: _onChanged,
              onSubmitted: vm.search.execute,
              autofocus: widget.initialQuery.isEmpty,
            ),
            const SizedBox(height: 16),
            if (vm.search.running && vm.players.isEmpty && vm.teams.isEmpty)
              const LoadingView()
            else if (vm.search.error)
              ErrorView(
                error: "Search isn't working right now.",
                onRetry: () => vm.search.execute(_text.text),
              )
            else if (vm.noMatches)
              EmptyView(
                icon: Icons.search_off,
                title: 'No matches for "${vm.query}"',
              )
            else if (vm.query.length < BrowseSearchViewModel.minQueryLength)
              const EmptyView(
                icon: Icons.search,
                title: 'Search by name',
                message: 'Try a player, a team, or a city.',
              )
            else ...[
              if (vm.teams.isNotEmpty)
                SectionCard(
                  title: 'Teams and groups',
                  child: Column(
                    children: [for (final t in vm.teams) _TeamRow(team: t)],
                  ),
                ),
              if (vm.players.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Players',
                  child: Column(
                    children: [
                      for (final p in vm.players) _PlayerRow(player: p),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// "Women · College · Boulder".
String teamSubtitle(TeamListing t) => [
  t.kind == TeamKind.team
      ? '${t.division.label} · ${t.level.label}'
      : t.kind.label,
  if (t.city.isNotEmpty) t.city,
].join(' · ');

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team});

  final TeamListing team;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: TeamBadge(community: team.kind != TeamKind.team),
    title: Text(team.name, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(
      teamSubtitle(team),
      style: TextStyle(color: AppColors.of(context).muted),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.go(Routes.team(team.id)),
  );
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player});

  final PlayerProfile player;

  @override
  Widget build(BuildContext context) {
    final p = player;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: PersonAvatar(name: p.name, photoUrl: p.photoUrl),
      title: Row(
        children: [
          Flexible(
            child: Text(
              p.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (p.isPrivate) ...[
            const SizedBox(width: 6),
            const Icon(Icons.lock_outline, size: 15),
          ],
        ],
      ),
      subtitle: p.username == null
          ? null
          : Text(
              '@${p.username}',
              style: TextStyle(color: AppColors.of(context).muted),
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(Routes.player(p.uid)),
    );
  }
}
