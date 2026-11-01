import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/usau_team.dart';
import '../../../routing/routes.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/usau_attribution.dart';
import '../../core/ui/win_colors.dart';
import '../view_models/usau_team_viewmodel.dart';

class UsauTeamScreen extends StatelessWidget {
  const UsauTeamScreen({super.key, required this.viewModel});

  final UsauTeamViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final team = vm.team;
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              leading: backOr(context, Routes.rankings),
              title: Text(vm.name),
              actions: [
                IconButton(
                  tooltip: 'View on USA Ultimate',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () async {
                    final ok = await launchUrl(Uri.parse(vm.url));
                    if (!ok && context.mounted) {
                      showSnackBar(context, 'Could not open link');
                    }
                  },
                ),
              ],
              bottom: team == null
                  ? null
                  : TabBar(
                      tabs: [
                        Tab(text: 'Roster (${team.roster.length})'),
                        const Tab(text: 'Events & Schedule'),
                        const Tab(text: 'Info'),
                      ],
                    ),
            ),
            body: switch ((vm.load.running, team)) {
              (true, _) => const LoadingView(),
              (_, null) => ErrorView(error: vm.error, onRetry: vm.load.execute),
              (_, final team?) => TabBarView(
                children: [
                  _RosterTab(team: team),
                  _ScheduleTab(viewModel: vm, team: team),
                  _InfoTab(team: team),
                ],
              ),
            },
          ),
        );
      },
    );
  }
}

class _RosterTab extends StatelessWidget {
  const _RosterTab({required this.team});

  final UsauTeam team;

  @override
  Widget build(BuildContext context) {
    if (team.roster.isEmpty) {
      return const EmptyView(
        icon: Icons.people_outline,
        title: 'No roster posted',
      );
    }
    final theme = Theme.of(context);
    return ConstrainedContent(
      maxWidth: 640,
      child: ListView(
        children: [
          for (final p in team.roster)
            ListTile(
              leading: SizedBox(
                width: 40,
                child: Text(
                  p.number,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(p.name),
              subtitle: _joinedOrNull([p.pronouns, p.position, p.height]),
            ),
          const UsauAttribution(),
        ],
      ),
    );
  }
}

/// The team's events and games. Won games (and won past events) are filled
/// green; losses and anything upcoming keep the default theme colors.
class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({required this.viewModel, required this.team});

  final UsauTeamViewModel viewModel;
  final UsauTeam team;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final events = vm.events;
    if (events.isEmpty && team.games.isEmpty) {
      return const EmptyView(
        icon: Icons.sports_outlined,
        title: 'No events or games posted',
      );
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final win = winColors(context);

    Widget sectionHeader(String text, {String? detail}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(color: colors.primary),
          ),
          if (detail != null && detail.isNotEmpty)
            Text(detail, style: theme.textTheme.bodySmall),
        ],
      ),
    );

    final children = <Widget>[
      if (team.wins + team.losses > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Record ${team.wins}-${team.losses}',
            style: theme.textTheme.titleMedium,
          ),
        ),
    ];

    if (events.isNotEmpty) {
      children.add(sectionHeader('Events'));
      for (final e in events) {
        final upcoming = vm.isUpcoming(e);
        final highlight = vm.highlightEvent(e);
        children.add(
          ListTile(
            tileColor: highlight ? win.fill : null,
            textColor: highlight ? win.onFill : null,
            iconColor: highlight ? win.onFill : null,
            leading: Icon(
              highlight
                  ? Icons.emoji_events
                  : upcoming
                  ? Icons.event_outlined
                  : Icons.event_available_outlined,
            ),
            title: Text(e.name),
            subtitle: _joinedOrNull([e.dates, e.location]),
            trailing: upcoming
                ? const Chip(label: Text('Upcoming'))
                : e.placement.isEmpty
                ? null
                : Text(e.placement, style: theme.textTheme.titleSmall),
          ),
        );
      }
    }

    String? tournament;
    var gamesHeaderShown = false;
    for (final g in team.games) {
      if (!gamesHeaderShown && g.tournament.isEmpty) {
        children.add(sectionHeader('Games'));
        gamesHeaderShown = true;
      }
      if (g.tournament.isNotEmpty && g.tournament != tournament) {
        tournament = g.tournament;
        gamesHeaderShown = true;
        children.add(
          sectionHeader(
            g.tournament,
            detail: team.eventNamed(g.tournament)?.dates,
          ),
        );
      }
      final highlight = vm.highlightGame(g);
      final Widget badge = switch (g.result) {
        GameResult.win => CircleAvatar(
          backgroundColor: win.onFill,
          foregroundColor: win.fill,
          child: const Text('W'),
        ),
        GameResult.loss => CircleAvatar(
          backgroundColor: colors.errorContainer,
          foregroundColor: colors.onErrorContainer,
          child: const Text('L'),
        ),
        GameResult.upcoming => const CircleAvatar(
          child: Icon(Icons.schedule, size: 20),
        ),
        GameResult.unknown => const CircleAvatar(child: Text('–')),
      };
      children.add(
        ListTile(
          tileColor: highlight ? win.fill : null,
          textColor: highlight ? win.onFill : null,
          leading: badge,
          title: Text('vs ${g.opponent}'),
          subtitle: _joinedOrNull([
            g.date,
            if (g.result == GameResult.upcoming) 'Upcoming',
          ]),
          trailing: g.score.isEmpty
              ? null
              : Text(
                  g.score,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: highlight ? win.onFill : null,
                  ),
                ),
        ),
      );
    }
    children.add(const UsauAttribution());
    return ConstrainedContent(
      maxWidth: 640,
      child: ListView(children: children),
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.team});

  final UsauTeam team;

  @override
  Widget build(BuildContext context) {
    if (team.info.isEmpty) {
      return const EmptyView(
        icon: Icons.info_outline,
        title: 'No team details posted',
      );
    }
    return ConstrainedContent(
      maxWidth: 640,
      child: ListView(
        children: [
          for (final i in team.info)
            ListTile(title: Text(i.value), subtitle: Text(i.label)),
          const UsauAttribution(),
        ],
      ),
    );
  }
}

Widget? _joinedOrNull(List<String> parts) {
  final text = parts.where((p) => p.isNotEmpty).join(' · ');
  return text.isEmpty ? null : Text(text);
}
