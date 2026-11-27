import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/discover.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/tone.dart';
import '../view_models/hosted_tournaments_viewmodel.dart';
import 'hosted_status_badge.dart';
import 'hosted_tournament_screen.dart';
import 'spots_left.dart';

import 'tournament_parts.dart';

/// "All" and each status the list has, when it has more than one.
class HostedStatusFilterBar extends StatelessWidget {
  const HostedStatusFilterBar({super.key, required this.viewModel});

  final HostedTournamentsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final counts = vm.statusCounts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ToneFilterBar<HostedStatus>(
        filters: [
          (
            value: null,
            label: 'All',
            tone: null,
            count: counts.values.fold(0, (a, b) => a + b),
          ),
          for (final MapEntry(key: s, value: n) in counts.entries)
            (value: s, label: s.label, tone: s.tone, count: n),
        ],
        selected: vm.statusFilter,
        onSelected: vm.setStatusFilter,
      ),
    );
  }
}

/// One tournament in a list.
class HostedTournamentCard extends StatelessWidget {
  const HostedTournamentCard({
    super.key,
    required this.tournament,
    this.showHost = true,
    this.spots,
  });

  final HostedTournament tournament;
  final bool showHost;

  /// Team spots left; shown only while registration is open.
  final TournamentSpots? spots;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final divisions = t.divisions.map((d) => d.label).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _EventRow(
        startsOn: t.startsOn,
        endsOn: t.isLeague ? null : t.endsOn,
        title: t.name,
        official: t.hostOfficial,
        lines: [
          [hostedDates(t), if (t.location.isNotEmpty) t.location].join(' · '),
          [
            if (t.type != HostedType.tournament) t.type.label,
            if (showHost) t.hostName,
            if (divisions.isNotEmpty) divisions,
            if (t.visibility == TournamentVisibility.inviteOnly) 'Invite only',
            if (t.bidFee case final f?)
              '${f.label} ${t.takesPlayers ? 'to play' : 'bid'}',
          ].join(' · '),
        ],
        trailing: HostedStatusBadge(status: t.status),
        below: spots == null || t.status != HostedStatus.registration
            ? null
            : SpotsLeft(spots: spots!),
        onTap: () => context.push(Routes.tournament(t.id)),
      ),
    );
  }
}

/// A host's tournaments, as a section of its page. Managers host new
/// ones here and see drafts.
class HostedTournamentsSection extends StatelessWidget {
  const HostedTournamentsSection({
    super.key,
    required this.viewModel,
    this.footer = const [],
  });

  final HostedTournamentsViewModel viewModel;

  /// More below the list (a group's hat tournaments).
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final fab = vm.canHost
            ? FloatingActionButton.extended(
                heroTag: 'host-tournament',
                onPressed: () => context.push(Routes.newTournament(vm.hostId!)),
                icon: const Icon(Icons.add),
                label: const Text('Host an event'),
              )
            : null;
        final Widget body;
        if (!vm.loaded) {
          body = const LoadingState();
        } else if (vm.error != null) {
          body = ErrorState(error: vm.error);
        } else {
          body = ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (vm.playingIn.isNotEmpty) ...[
                  const _Heading('Playing in'),
                  for (final e in vm.playingIn) _EnteredCard(entry: e),
                  if (vm.tournaments.isNotEmpty || vm.canHost)
                    const _Heading('Hosted here'),
                ],
                if (vm.filtersByStatus) HostedStatusFilterBar(viewModel: vm),
                if (vm.tournaments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      vm.canHost
                          ? 'Host a tournament, a hat tournament or a league. '
                                'Pick divisions, set a fee, take applications '
                                'or player signups, then publish the schedule.'
                          : 'No tournaments or leagues hosted here yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final t in vm.tournaments)
                  HostedTournamentCard(
                    tournament: t,
                    showHost: false,
                    spots: vm.spotsOf(t.id),
                  ),
                ...footer,
              ],
            ),
          );
        }
        return Scaffold(floatingActionButton: fab, body: body);
      },
    );
  }
}

/// Upcoming tournaments anyone can find, apply to or follow.
class FindTournamentsScreen extends StatelessWidget {
  const FindTournamentsScreen({
    super.key,
    required this.viewModel,
    this.title = 'Tournaments & leagues',
    this.leading,
    this.bottom,
  });

  final HostedTournamentsViewModel viewModel;

  /// The app bar's title, leading widget and bottom (the Events tabs).
  final String title;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Scaffold(
      appBar: AppBar(
        leading: leading,
        title: Text(title),
        bottom: bottom,
        actions: [
          TextButton.icon(
            onPressed: () => context.push(Routes.hostEvent),
            icon: const Icon(Icons.add),
            label: const Text('Host'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (!vm.loaded) return const LoadingState();
          if (vm.error != null) return ErrorState(error: vm.error);
          return ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name, host or place',
                  ),
                  onChanged: vm.setQuery,
                ),
                const SizedBox(height: 12),
                if (vm.filtersByType)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: vm.typeFilter == null,
                          onSelected: (_) => vm.setTypeFilter(null),
                        ),
                        for (final e in vm.typeCounts.entries)
                          ChoiceChip(
                            label: Text('${e.key.label} (${e.value})'),
                            selected: vm.typeFilter == e.key,
                            onSelected: (_) => vm.setTypeFilter(e.key),
                          ),
                      ],
                    ),
                  ),
                if (vm.filtersByStatus) HostedStatusFilterBar(viewModel: vm),
                if (vm.tournaments.isEmpty)
                  EmptyState(
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
                for (final t in vm.tournaments)
                  HostedTournamentCard(tournament: t, spots: vm.spotsOf(t.id)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: SectionHeader(text),
  );
}

/// An event in a list: its date badge, name, a line or two about it, and
/// [trailing] (its status).
class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.title,
    required this.lines,
    required this.onTap,
    this.startsOn,
    this.endsOn,
    this.official = false,
    this.trailing,
    this.below,
  });

  final DateTime? startsOn;
  final DateTime? endsOn;
  final String title;
  final bool official;
  final List<String> lines;
  final Widget? trailing;

  /// Under the lines (spots left).
  final Widget? below;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final start = startsOn;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              if (start != null)
                EventDateBadge(startsOn: start, endsOn: endsOn, size: 48)
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Icon(Icons.emoji_events_outlined, color: c.accentInk),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                        ),
                        if (official) ...[
                          const SizedBox(width: 6),
                          const OfficialBadge(label: null),
                        ],
                      ],
                    ),
                    for (final line in lines)
                      if (line.isNotEmpty)
                        Text(
                          line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                    ?below,
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A tournament the team entered: its dates, where, and where the entry
/// stands (Accepted, Applied, Invited, Waitlist).
class _EnteredCard extends StatelessWidget {
  const _EnteredCard({required this.entry});

  final EnteredTournament entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final when = switch ((e.startsOn, e.endsOn)) {
      (final s?, final end?) when !DateUtils.isSameDay(s, end) =>
        '${DateFormat.MMMd().format(s)} – ${DateFormat.MMMd().format(end)}',
      (final s?, _) => DateFormat.yMMMd().format(s),
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _EventRow(
        startsOn: e.startsOn,
        endsOn: e.endsOn,
        title: e.name,
        lines: [
          [
            when,
            if (e.location.isNotEmpty) e.location,
          ].where((x) => x.isNotEmpty).join(' · '),
          if (e.hostName.isNotEmpty) 'Hosted by ${e.hostName}',
        ],
        trailing: Pill(
          e.status.label,
          // An invite is the team's to answer.
          tone: switch (e.status) {
            EntryStatus.accepted => PillTone.turf,
            EntryStatus.invited => PillTone.needsYou,
            _ => PillTone.neutral,
          },
        ),
        onTap: () => context.push(Routes.tournament(e.tournamentId)),
      ),
    );
  }
}
