import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:go_router/go_router.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/player_profile.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';
import '../../core/ui/status_views.dart';
import '../../teams/view_models/team_search_viewmodel.dart';
import '../../tournaments/view_models/hosted_tournaments_viewmodel.dart';
import '../../tournaments/widgets/hosted_tournament_screen.dart'
    show hostedDates;
import '../../tournaments/widgets/hosted_tournaments_list.dart'
    show HostedStatusFilterBar;
import '../view_models/explore_viewmodel.dart';
import '../view_models/player_search_viewmodel.dart';
import 'explore_cards.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/skeleton.dart';
import '../../shell/widgets/app_shell.dart' show ProfileButton, SearchField;

/// Discover: one place to find things. Search players, teams, communities,
/// tournaments and leagues in one box, narrowed by the filter chips; with
/// no search, what's live now, the tournaments and leagues coming up (the
/// old Events tab's "Find events", with its status filter and Host), recent
/// results, a rankings preview and ways to jump in (Learn to play, start a
/// team or community).
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.viewModel,
    required this.players,
    this.explore,
    this.events,
    this.initialQuery = '',
    this.initialFilter,
  });

  final TeamSearchViewModel viewModel;
  final PlayerSearchViewModel players;

  /// Tournaments, results and rankings; null shows search alone.
  final ExploreViewModel? explore;

  /// Every upcoming tournament and league, to filter by status and search
  /// (what "Find events" listed); null shows Explore's preview instead.
  final HostedTournamentsViewModel? events;

  /// Search text from the top bar's search field.
  final String initialQuery;

  /// Filter to start with; null for All.
  final ExploreFilter? initialFilter;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

/// The kinds of hosted event each event filter keeps.
const _eventKinds = {
  ExploreFilter.tournaments: {HostedType.tournament, HostedType.hat},
  ExploreFilter.leagues: {HostedType.league},
};

class _ExploreScreenState extends State<ExploreScreen> {
  TeamSearchViewModel get vm => widget.viewModel;
  PlayerSearchViewModel get players => widget.players;
  late final _text = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;

  /// The picked chip; null for All.
  ExploreFilter? _only;

  bool get _hasEvents => widget.explore != null || widget.events != null;

  void _search(String text) {
    vm.search.execute(text);
    players.search.execute(text);
    widget.events?.setQuery(_ready(text) ? text.trim() : '');
  }

  static bool _ready(String text) =>
      text.trim().length >= TeamSearchViewModel.minQueryLength;

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
      ExploreFilter.groups || ExploreFilter.pickup => TeamKind.community,
      _ => null,
    });
    widget.events?.setKindsFilter(_eventKinds[only]);
  }

  void _onChanged(String text) {
    // Events are filtered here, so they follow the box at once; the
    // searches wait for a pause in typing.
    widget.events?.setQuery(_ready(text) ? text.trim() : '');
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text));
  }

  /// Whether the chip picked shows [f]'s results (All shows every kind).
  bool _shows(ExploreFilter f) => _only == null || _only == f;

  bool _showsKind(HostedType type) =>
      _only == null || (_eventKinds[_only]?.contains(type) ?? false);

  @override
  Widget build(BuildContext context) {
    final mobile = ScreenSize.of(context).isMobile;
    final host = TextButton.icon(
      onPressed: () => context.push(Routes.hostEvent),
      icon: const Icon(Icons.add),
      label: const Text('Host'),
    );
    return Scaffold(
      appBar: mobile
          ? AppBar(
              leading: ProfileButton.leading(context),
              title: const Text('Discover'),
              actions: [if (_hasEvents) host],
            )
          : null,
      body: ListenableBuilder(
        listenable: Listenable.merge([
          vm,
          vm.search,
          players.search,
          _text,
          ?widget.explore,
          ?widget.events,
        ]),
        builder: (context, _) {
          final searching = _ready(_text.text);
          final top = [
            _searchBox(),
            if (searching) ..._results() else ..._browse(context),
          ];
          final side = [
            if (widget.explore case final x? when !searching)
              RankingsPreviewCard(viewModel: x),
            _Shortcuts(),
          ];
          return PageScroll(
            children: [
              if (!mobile)
                PageHeader(
                  eyebrow: 'Discover',
                  title: 'Find your next point.',
                  subtitle:
                      'Tournaments, leagues, pickup, teams, communities '
                      'and players.',
                  action: _hasEvents ? host : null,
                ),
              SideColumnLayout(
                main: top,
                side: side,
                narrow: [...top, ...side],
              ),
            ],
          );
        },
      ),
    );
  }

  /// The search box and the filter chips under it.
  Widget _searchBox() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppSearchField(
        controller: _text,
        hint: SearchField.hint,
        onChanged: _onChanged,
        onSubmitted: _search,
      ),
      const SizedBox(height: 10),
      _FilterChips(
        filters: [
          ('All', null),
          if (_hasEvents) ...[
            ('Tournaments', ExploreFilter.tournaments),
            ('Leagues', ExploreFilter.leagues),
          ],
          ('Pickup', ExploreFilter.pickup),
          ('Teams', ExploreFilter.teams),
          ('Communities', ExploreFilter.groups),
          ('Players', ExploreFilter.players),
        ],
        selected: _only,
        onSelect: (f) => setState(() => _applyFilter(f)),
      ),
    ],
  );

  /// With no search: what's live, what's coming up and recent results; for
  /// a filter that needs a search, how to search it.
  List<Widget> _browse(BuildContext context) {
    final c = AppColors.of(context);
    final x = widget.explore;
    final events = widget.events;
    final eventsShown =
        _only == null ||
        _only == ExploreFilter.tournaments ||
        _only == ExploreFilter.leagues;
    if (!_hasEvents || !eventsShown) {
      final what = switch (_only) {
        ExploreFilter.pickup => 'pickup communities',
        ExploreFilter.teams => 'teams',
        ExploreFilter.groups => 'communities, schools and clubs',
        ExploreFilter.players => 'players by name or username',
        _ => 'players, teams, communities and tournaments',
      };
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Type at least ${TeamSearchViewModel.minQueryLength} letters '
            'to search $what.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted),
          ),
        ),
      ];
    }
    final live = [
      for (final t in x?.upcoming ?? const <HostedTournament>[])
        if (t.status == HostedStatus.live && _showsKind(t.type)) t,
    ];
    return [
      if (live.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Live now', leading: LiveDot()),
            ...spaced([
              for (final t in live) _LiveCard(tournament: t),
            ], gap: 10),
          ],
        ),
      if (events != null)
        _ComingUp(viewModel: events)
      else if (x != null)
        UpcomingTournamentsCard(viewModel: x),
      if (x != null && _only != ExploreFilter.leagues)
        RecentResultsCard(viewModel: x),
    ];
  }

  /// Search results, grouped by kind: tournaments, leagues, teams,
  /// communities and players, as the chip picked allows.
  List<Widget> _results() {
    final events = widget.events;
    final hosted = events != null
        ? events.matches
        : widget.explore?.matching(_text.text) ?? const <HostedTournament>[];
    final tournaments = [
      if (_hasEvents && _shows(ExploreFilter.tournaments))
        for (final t in hosted)
          if (t.type != HostedType.league) t,
    ];
    final leagues = [
      if (_hasEvents && _shows(ExploreFilter.leagues))
        for (final t in hosted)
          if (t.type == HostedType.league) t,
    ];
    final teamsShown = _shows(ExploreFilter.teams);
    final pickup = _only == ExploreFilter.pickup;
    final groupsShown = _shows(ExploreFilter.groups) || pickup;
    final teams = [
      if (teamsShown)
        for (final t in vm.results)
          if (t.kind == TeamKind.team) t,
    ];
    final groups = [
      if (groupsShown)
        for (final t in vm.results)
          if (pickup ? t.kind == TeamKind.community : t.kind.isGroupLike) t,
    ];
    final playersShown = _shows(ExploreFilter.players);
    final people = playersShown ? players.results : const <PlayerProfile>[];

    final searchesTeams = teamsShown || groupsShown;
    final running =
        (searchesTeams && vm.search.running) ||
        (playersShown && players.search.running) ||
        (events != null && !events.loaded);
    final failed = (searchesTeams && vm.search.error)
        ? vm.search.result
        : (playersShown && players.search.error)
        ? players.search.result
        : null;
    final nothing =
        tournaments.isEmpty &&
        leagues.isEmpty &&
        teams.isEmpty &&
        groups.isEmpty &&
        people.isEmpty;
    // From the lists shown, not the searches' own: a search can match only
    // what the chip hides (schools and clubs under Pickup).
    final noMatches =
        nothing &&
        !running &&
        (!searchesTeams || vm.search.completed) &&
        (!playersShown || players.search.completed);

    Widget group(String title, List<Widget> rows) => SectionCard(
      title: title,
      child: Column(children: rows),
    );

    return [
      if (running && nothing)
        const SkeletonList(count: 4, padding: EdgeInsets.zero)
      else if (failed != null && nothing)
        ErrorView(error: failed)
      else if (noMatches)
        const EmptyView(
          icon: Icons.search_off,
          title: 'Nothing found',
          message:
              'Try another word from a name, username, city, school, team, '
              'tournament or league.',
        ),
      if (tournaments.isNotEmpty)
        group('Tournaments', [
          for (final t in tournaments) TournamentTile(tournament: t),
        ]),
      if (leagues.isNotEmpty)
        group('Leagues', [
          for (final t in leagues) TournamentTile(tournament: t),
        ]),
      if (teams.isNotEmpty)
        group('Teams', [
          for (final t in teams) _ResultTile(listing: t, vm: vm),
        ]),
      if (groups.isNotEmpty)
        group(pickup ? 'Pickup' : 'Communities', [
          for (final t in groups) _ResultTile(listing: t, vm: vm),
        ]),
      if (people.isNotEmpty)
        group('Players', [for (final p in people) PlayerTile(profile: p)]),
    ];
  }
}

/// A tournament or league being played now, on a navy scoreboard card.
/// No running scores yet: its name, host, place and divisions.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.tournament});

  final HostedTournament tournament;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = tournament;
    final divisions = t.divisions.map((d) => d.label).join(', ');
    return FeatureCard(
      padding: const EdgeInsets.all(16),
      onTap: () => context.push(Routes.tournament(t.id, tab: 'schedule')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BoardLabel(
            [
              if (t.type != HostedType.tournament) t.type.label,
              t.hostName,
              if (t.location.isNotEmpty) t.location,
            ].join(' · ').toUpperCase(),
            live: true,
          ),
          const SizedBox(height: 8),
          Text(
            t.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.onFeature,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [hostedDates(t), if (divisions.isNotEmpty) divisions].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.onFeatureMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Every upcoming tournament and league (what "Find events" listed), with
/// its status filter, and a way to host one when there are none. Live ones
/// are under "Live now" unless the Live status is picked.
class _ComingUp extends StatelessWidget {
  const _ComingUp({required this.viewModel});

  final HostedTournamentsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final list = [
      for (final t in vm.tournaments)
        if (vm.statusFilter == HostedStatus.live ||
            t.status != HostedStatus.live)
          t,
    ];
    return SectionCard(
      title: 'Coming up',
      action: CardLink(
        label: 'See all',
        onTap: () => context.push(Routes.tournaments),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!vm.loaded)
            const SkeletonList(count: 3, padding: EdgeInsets.zero)
          else if (vm.error != null)
            ErrorView(error: vm.error)
          else ...[
            if (vm.filtersByStatus) HostedStatusFilterBar(viewModel: vm),
            if (list.isEmpty && list.length < vm.tournaments.length)
              Text(
                'Nothing else coming up yet.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.of(context).muted,
                ),
              )
            else if (list.isEmpty)
              EmptyView(
                icon: Icons.emoji_events_outlined,
                title: 'No upcoming events',
                message:
                    'Teams and communities host tournaments, hat '
                    'tournaments and leagues. Start one with Host.',
                action: FilledButton(
                  onPressed: () => context.push(Routes.hostEvent),
                  child: const Text('Host an event'),
                ),
              ),
            for (final t in list) TournamentTile(tournament: t),
          ],
        ],
      ),
    );
  }
}

/// The filter chips in one row that scrolls sideways when it's wider than
/// the screen (rather than wrapping onto a second line), keeping the
/// selected chip in view.
class _FilterChips extends StatefulWidget {
  const _FilterChips({
    required this.filters,
    required this.selected,
    required this.onSelect,
  });

  final List<(String, ExploreFilter?)> filters;
  final ExploreFilter? selected;
  final ValueChanged<ExploreFilter?> onSelect;

  @override
  State<_FilterChips> createState() => _FilterChipsState();
}

class _FilterChipsState extends State<_FilterChips> {
  final _keys = <ExploreFilter?, GlobalKey>{};
  final _scroll = ScrollController();

  GlobalKey _keyOf(ExploreFilter? f) => _keys[f] ??= GlobalKey();

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(_FilterChips old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected) _reveal();
  }

  /// Scrolls the row (only the row, not the page) so the selected chip is
  /// fully in view, once it's laid out.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _keys[widget.selected]?.currentContext?.findRenderObject();
      if (!mounted || chip == null || !_scroll.hasClients) return;
      final viewport = RenderAbstractViewport.maybeOf(chip);
      if (viewport == null) return;
      final pos = _scroll.position;
      final start = viewport.getOffsetToReveal(chip, 0).offset;
      final end = viewport.getOffsetToReveal(chip, 1).offset;
      final target = pos.pixels > start
          ? start
          : pos.pixels < end
          ? end
          : pos.pixels;
      final clamped = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (clamped != pos.pixels) {
        _scroll.animateTo(
          clamped,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _scroll,
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (i, (label, filter)) in widget.filters.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          ChoiceChip(
            key: _keyOf(filter),
            label: Text(label),
            showCheckmark: false,
            selected: widget.selected == filter,
            onSelected: (_) => widget.onSelect(filter),
          ),
        ],
      ],
    ),
  );
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
          ? Tag(t.isCommunity ? 'Your community' : 'Your team')
          : const Icon(Icons.chevron_right),
      onTap: () => context.go(Routes.team(t.id)),
    );
  }
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
        Icons.menu_book_outlined,
        'Learn to play',
        'The rules of ultimate in five minutes',
        () => context.push(Routes.learn),
      ),
      (
        Icons.emoji_events_outlined,
        'Find a tournament or league',
        'Apply with your team, sign up to play, or follow results',
        () => context.push(Routes.tournaments),
      ),
      (
        Icons.sports_score_outlined,
        'Host a league or tournament',
        'Run it from your team or community',
        () => context.push(Routes.hostEvent),
      ),
      (
        Icons.add_circle_outline,
        'Start a team',
        'Roster, playbook, stats and chat',
        () => context.go(Routes.createTeam),
      ),
      (
        Icons.diversity_3_outlined,
        'Start a pickup community',
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
