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
import '../../core/ui/app_search_field.dart';
import '../../core/ui/skeleton.dart';
import '../../shell/widgets/app_shell.dart' show SearchField;

/// Explore: search players, teams and groups in one box, and jump to
/// starting a team or group.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.viewModel,
    required this.players,
    this.initialQuery = '',
    this.initialFilter,
  });

  final TeamSearchViewModel viewModel;
  final PlayerSearchViewModel players;

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
  late final _text = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;

  /// The picked chip; null for All.
  ExploreFilter? _only;

  void _search(String text) {
    vm.search.execute(text);
    players.search.execute(text);
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
              subtitle: 'Players, teams and pickup groups.',
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
            listenable: Listenable.merge([vm, vm.search, players.search]),
            builder: (context, _) {
              final only = _only;
              final all = only == null;
              final teamsShown =
                  all ||
                  only == ExploreFilter.teams ||
                  only == ExploreFilter.groups;
              final playersShown = all || only == ExploreFilter.players;

              final results = teamsShown ? vm.results : const <TeamListing>[];
              final people = playersShown
                  ? players.results
                  : const <PlayerProfile>[];

              final running =
                  (teamsShown && vm.search.running) ||
                  (playersShown && players.search.running);
              final failed = (teamsShown && vm.search.error)
                  ? vm.search.result
                  : (playersShown && players.search.error)
                  ? players.search.result
                  : null;
              final nothing = results.isEmpty && people.isEmpty;
              final noMatches =
                  nothing &&
                  !running &&
                  (!teamsShown || vm.noMatches) &&
                  (!playersShown || players.noMatches);
              final sections = [
                results.isNotEmpty,
                people.isNotEmpty,
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
                          'school or team.',
                    )
                  else if (nothing)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Type at least ${TeamSearchViewModel.minQueryLength} '
                        'letters to search players, teams and groups.',
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
        'Find a tournament',
        'Apply with your team, or follow results',
        () => context.push(Routes.tournaments),
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
