import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/player_profile.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../teams/view_models/team_search_viewmodel.dart';
import '../view_models/player_search_viewmodel.dart';

/// Explore: search the app's teams, groups and players, and jump to events,
/// rankings, USA Ultimate teams, or starting a team.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.viewModel,
    required this.players,
    this.initialQuery = '',
  });

  final TeamSearchViewModel viewModel;
  final PlayerSearchViewModel players;

  /// Search text from the top bar's search field.
  final String initialQuery;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  TeamSearchViewModel get vm => widget.viewModel;
  PlayerSearchViewModel get players => widget.players;
  late final _text = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;

  /// Whether the Players chip is picked, rather than a team kind.
  var _playersOnly = false;

  void _search(String text) {
    vm.search.execute(text);
    players.search.execute(text);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) _search(widget.initialQuery);
  }

  @override
  void didUpdateWidget(ExploreScreen old) {
    super.didUpdateWidget(old);
    final q = widget.initialQuery;
    if (q != old.initialQuery && q.isNotEmpty) {
      _text.text = q;
      _search(q);
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
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text));
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ScreenSize.of(context).isMobile;
    return Scaffold(
      appBar: mobile ? AppBar(title: const Text('Explore')) : null,
      body: PageScroll(
        children: [
          if (!mobile)
            const PageHeader(
              eyebrow: 'Explore',
              title: 'Find your next point.',
              subtitle: 'Teams, pickup groups, tournaments and rankings.',
            ),
          SideColumnLayout(
            main: [_searchCard(context)],
            side: [_Shortcuts()],
            narrow: [_Shortcuts(), _searchCard(context)],
          ),
        ],
      ),
    );
  }

  Widget _searchCard(BuildContext context) {
    final c = AppColors.of(context);
    return SectionCard(
      title: 'Teams, groups and players',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Name, city, school or team',
            ),
            onChanged: _onChanged,
            onSubmitted: _search,
          ),
          const SizedBox(height: 10),
          ListenableBuilder(
            listenable: Listenable.merge([vm, vm.search, players.search]),
            builder: (context, _) {
              final results = _playersOnly ? const <TeamListing>[] : vm.results;
              final people = _playersOnly || vm.kind == null
                  ? players.results
                  : const <PlayerProfile>[];
              final running = _playersOnly
                  ? players.search.running
                  : vm.search.running ||
                        (vm.kind == null && players.search.running);
              final failed = _playersOnly
                  ? players.search.error
                  : vm.search.error;
              final noMatches = _playersOnly
                  ? players.noMatches
                  : vm.noMatches && (vm.kind != null || players.noMatches);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (label, kind) in const [
                        ('All', null),
                        ('Teams', TeamKind.team),
                        ('Groups', TeamKind.community),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          showCheckmark: false,
                          selected: !_playersOnly && vm.kind == kind,
                          onSelected: (_) {
                            setState(() => _playersOnly = false);
                            vm.setKind(kind);
                          },
                        ),
                      ChoiceChip(
                        label: const Text('Players'),
                        showCheckmark: false,
                        selected: _playersOnly,
                        onSelected: (_) => setState(() => _playersOnly = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (running && results.isEmpty && people.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (failed)
                    ErrorView(
                      error: _playersOnly
                          ? players.search.result
                          : vm.search.result,
                    )
                  else if (noMatches)
                    const EmptyView(
                      icon: Icons.search_off,
                      title: 'Nothing found',
                      message:
                          'Try another word from the name, a city, '
                          'school or team.',
                    )
                  else if (results.isEmpty && people.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Type at least ${TeamSearchViewModel.minQueryLength} '
                        'letters of a name, city, school or team.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted),
                      ),
                    ),
                  if (people.isNotEmpty && results.isNotEmpty)
                    const _ResultsHeading('Teams and groups'),
                  for (final t in results) _ResultTile(listing: t, vm: vm),
                  if (people.isNotEmpty && results.isNotEmpty)
                    const _ResultsHeading('Players'),
                  for (final p in people) PlayerTile(profile: p),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.listing, required this.vm});

  final TeamListing listing;
  final TeamSearchViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = listing;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: TeamBadge(community: t.isCommunity),
      title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        t.isCommunity
            ? '${t.subtitle} · '
                  '${t.requiresApproval ? 'Approval required' : 'Open to join'}'
            : t.subtitle,
      ),
      trailing: vm.isMine(t.id)
          ? Tag(t.isCommunity ? 'Your group' : 'Your team')
          : const Icon(Icons.chevron_right),
      onTap: () => context.go(Routes.team(t.id)),
    );
  }
}

class _ResultsHeading extends StatelessWidget {
  const _ResultsHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 2),
    child: Eyebrow(text),
  );
}

/// A player in search results; opens their profile.
class PlayerTile extends StatelessWidget {
  const PlayerTile({super.key, required this.profile});

  final PlayerProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final team = p.summary.teams
        .where((t) => t.kind == TeamKind.team)
        .firstOrNull;
    final subtitle = [
      if (team != null)
        [team.name, if (team.number != null) '#${team.number}'].join(' '),
      if (p.details.school.isNotEmpty) p.details.school,
      if (p.details.hometown.isNotEmpty) p.details.hometown,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: PersonAvatar(name: p.name, photoUrl: p.photoUrl),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.player(p.uid)),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      (
        Icons.emoji_events_outlined,
        'Events',
        'USA Ultimate tournaments near you',
        () => context.go(Routes.tournaments),
      ),
      (
        Icons.leaderboard_outlined,
        'Rankings',
        'Every division, top to bottom',
        () => context.go(Routes.rankings),
      ),
      (
        Icons.travel_explore_outlined,
        'USA Ultimate teams',
        'Rosters and results for any ranked team',
        () => context.go(Routes.searchUsauTeams),
      ),
      (
        Icons.add_circle_outline,
        'Start a team',
        'Roster, playbook, stats and chat',
        () => context.go(Routes.createTeam),
      ),
      (
        Icons.diversity_3_outlined,
        'Start a pickup group',
        'Open sign-ups, pickup and tournaments',
        () => context.go(Routes.createGroup),
      ),
    ];
    final c = AppColors.of(context);
    return SectionCard(
      title: 'Jump in',
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        children: [
          for (final (icon, title, subtitle, onTap) in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minLeadingWidth: 0,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(controlRadius),
                ),
                child: Icon(icon, size: 19, color: c.ink),
              ),
              title: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}
