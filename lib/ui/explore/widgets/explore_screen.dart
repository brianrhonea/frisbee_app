import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/player_profile.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/tournament.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../teams/view_models/team_search_viewmodel.dart';
import '../../tournaments/view_models/tournaments_viewmodel.dart';
import '../../tournaments/widgets/tournament_widgets.dart' show formatDateRange;
import '../view_models/player_search_viewmodel.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/skeleton.dart';
import '../../shell/widgets/app_shell.dart' show SearchField;

/// Explore: search players, teams, groups and events in one box, and
/// jump to rankings, USA Ultimate teams, or starting a team.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.viewModel,
    required this.players,
    required this.events,
    this.initialQuery = '',
    this.initialFilter,
  });

  final TeamSearchViewModel viewModel;
  final PlayerSearchViewModel players;

  /// USA Ultimate events, filtered by the same search.
  final TournamentsViewModel events;

  /// Search text from the top bar's search field.
  final String initialQuery;

  /// Filter to start with; null for All.
  final ExploreFilter? initialFilter;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  TeamSearchViewModel get vm => widget.viewModel;
  PlayerSearchViewModel get players => widget.players;
  TournamentsViewModel get events => widget.events;
  late final _text = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;

  /// The picked chip; null for All.
  ExploreFilter? _only;

  /// Events in All, before "See all".
  static const _eventsInAll = 3;

  void _search(String text) {
    vm.search.execute(text);
    players.search.execute(text);
    final q = text.trim();
    events.setQuery(q.length < TeamSearchViewModel.minQueryLength ? '' : q);
  }

  @override
  void initState() {
    super.initState();
    _applyFilter(widget.initialFilter);
    if (widget.initialQuery.isNotEmpty) _search(widget.initialQuery);
  }

  @override
  void didUpdateWidget(ExploreScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialFilter != old.initialFilter) {
      _applyFilter(widget.initialFilter);
    }
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

  void _applyFilter(ExploreFilter? only) {
    _only = only;
    vm.setKind(switch (only) {
      ExploreFilter.teams => TeamKind.team,
      ExploreFilter.groups => TeamKind.community,
      _ => null,
    });
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
              subtitle: 'Players, teams, pickup groups, events and rankings.',
            ),
          SideColumnLayout(
            main: [_searchCard(context)],
            side: [_Shortcuts()],
            narrow: [_searchCard(context), _Shortcuts()],
          ),
        ],
      ),
    );
  }

  Widget _searchCard(BuildContext context) {
    final c = AppColors.of(context);
    return SectionCard(
      title: 'Search',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _text,
            hint: SearchField.hint,
            onChanged: _onChanged,
            onSubmitted: _search,
          ),
          const SizedBox(height: 10),
          ListenableBuilder(
            listenable: Listenable.merge([
              vm,
              vm.search,
              players.search,
              events,
            ]),
            builder: (context, _) {
              final only = _only;
              final all = only == null;
              final teamsShown =
                  all ||
                  only == ExploreFilter.teams ||
                  only == ExploreFilter.groups;
              final playersShown = all || only == ExploreFilter.players;
              final eventsShown = all || only == ExploreFilter.events;

              final results = teamsShown ? vm.results : const <TeamListing>[];
              final people = playersShown
                  ? players.results
                  : const <PlayerProfile>[];
              final searched = events.query.isNotEmpty;
              final allEvents = eventsShown && searched
                  ? events.tournaments
                  : const <Tournament>[];
              final shownEvents = all
                  ? allEvents.take(_eventsInAll).toList()
                  : allEvents;

              final running =
                  (teamsShown && vm.search.running) ||
                  (playersShown && players.search.running) ||
                  (eventsShown && searched && events.loading);
              final failed = (teamsShown && vm.search.error)
                  ? vm.search.result
                  : (playersShown && players.search.error)
                  ? players.search.result
                  : null;
              final nothing =
                  results.isEmpty && people.isEmpty && shownEvents.isEmpty;
              final noMatches =
                  nothing &&
                  !running &&
                  (!teamsShown || vm.noMatches) &&
                  (!playersShown || players.noMatches) &&
                  (!eventsShown || searched);
              final sections = [
                results.isNotEmpty,
                people.isNotEmpty,
                shownEvents.isNotEmpty,
              ].where((x) => x).length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final (label, filter) in const [
                        ('All', null),
                        ('Players', ExploreFilter.players),
                        ('Teams', ExploreFilter.teams),
                        ('Groups', ExploreFilter.groups),
                        ('Events', ExploreFilter.events),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          showCheckmark: false,
                          selected: _only == filter,
                          onSelected: (_) =>
                              setState(() => _applyFilter(filter)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (running && nothing)
                    const SkeletonList(count: 4, padding: EdgeInsets.zero)
                  else if (failed != null && nothing)
                    ErrorView(error: failed)
                  else if (noMatches)
                    const EmptyView(
                      icon: Icons.search_off,
                      title: 'Nothing found',
                      message:
                          'Try another word from a name, username, city, '
                          'school, team or event.',
                    )
                  else if (nothing)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Type at least ${TeamSearchViewModel.minQueryLength} '
                        'letters to search players, teams, groups and '
                        'events.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted),
                      ),
                    ),
                  if (people.isNotEmpty) ...[
                    if (sections > 1) const _ResultsHeading('Players'),
                    for (final p in people) PlayerTile(profile: p),
                  ],
                  if (results.isNotEmpty) ...[
                    if (sections > 1) const _ResultsHeading('Teams and groups'),
                    for (final t in results) _ResultTile(listing: t, vm: vm),
                  ],
                  if (shownEvents.isNotEmpty) ...[
                    if (sections > 1) const _ResultsHeading('Events'),
                    for (final t in shownEvents) _EventTile(tournament: t),
                    if (allEvents.length > shownEvents.length)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(
                            () => _applyFilter(ExploreFilter.events),
                          ),
                          child: Text('See all ${allEvents.length} events'),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// An upcoming USA Ultimate event in search results.
class _EventTile extends StatelessWidget {
  const _EventTile({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.emoji_events_outlined)),
      title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          formatDateRange(t.startDate, t.endDate),
          if (t.location.isNotEmpty) t.location,
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.tournament(t.id)),
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
      if (p.username case final u?) '@$u',
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
