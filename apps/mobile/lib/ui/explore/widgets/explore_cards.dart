import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/discover.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/ranking.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';
import '../../core/ui/skeleton.dart';
import '../../tournaments/widgets/hosted_status_badge.dart';
import '../../tournaments/widgets/spots_left.dart';

import '../../tournaments/widgets/hosted_tournament_screen.dart'
    show hostedDates;
import '../view_models/explore_viewmodel.dart';
import '../../core/ui/app_segmented_button.dart';

/// The next few published tournaments, with a link to all of them.
class UpcomingTournamentsCard extends StatelessWidget {
  const UpcomingTournamentsCard({super.key, required this.viewModel});

  final ExploreViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final list = viewModel.upcoming
            .take(ExploreViewModel.previewCount)
            .toList();
        return SectionCard(
          title: 'Tournaments & leagues',
          action: CardLink(
            label: 'See all',
            onTap: () => context.push(Routes.tournaments),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!viewModel.tournamentsLoaded)
                const SkeletonList(count: 3, padding: EdgeInsets.zero)
              else if (list.isEmpty)
                Text(
                  'Nothing coming up yet. Communities and clubs host tournaments '
                  'and leagues from their Tournaments tab.',
                  style: AppText.secondary.copyWith(color: c.muted),
                )
              else
                for (final t in list)
                  TournamentTile(tournament: t, spots: viewModel.spotsOf(t.id)),
            ],
          ),
        );
      },
    );
  }
}

/// A tournament or league in Discover: dates, place, host, divisions,
/// whether it's invite only and its fee, with its status.
class TournamentTile extends StatelessWidget {
  const TournamentTile({super.key, required this.tournament, this.spots});

  final HostedTournament tournament;

  /// Team spots left; shown only while registration is open.
  final TournamentSpots? spots;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final c = AppColors.of(context);
    final details = [
      hostedDates(t),
      if (t.location.isNotEmpty) t.location,
    ].join(' · ');
    final divisions = t.divisions.map((d) => d.label).join(', ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      // When it starts, as on the schedule's rows.
      leading: DateBadge(date: t.startsOn, size: 40),
      title: Row(
        children: [
          Flexible(
            child: Text(
              t.name,
              style: AppText.label.copyWith(color: c.ink),
            ),
          ),
          if (t.hostOfficial) ...[
            const SizedBox(width: 6),
            const OfficialBadge(label: null),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subtitle(t, details, divisions),
          if (spots case final s? when t.status == HostedStatus.registration)
            SpotsLeft(spots: s),
        ],
      ),
      trailing: HostedStatusBadge(status: t.status),
      onTap: () => context.push(Routes.tournament(t.id)),
    );
  }

  Widget _subtitle(HostedTournament t, String details, String divisions) =>
      Text(
        [
          details,
          [
            if (t.type != HostedType.tournament) t.type.label,
            t.hostName,
            if (divisions.isNotEmpty) divisions,
            if (t.visibility == TournamentVisibility.inviteOnly) 'Invite only',
            if (t.bidFee case final f?)
              '${f.label} ${t.takesPlayers ? 'to play' : 'bid'}',
          ].join(' · '),
        ].join('\n'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
}

/// Champions of recently finished public tournaments.
class RecentResultsCard extends StatelessWidget {
  const RecentResultsCard({super.key, required this.viewModel});

  final ExploreViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final list = viewModel.results
            .take(ExploreViewModel.previewCount)
            .toList();
        // Nothing to show until a tournament has finished.
        if (list.isEmpty) return const SizedBox.shrink();
        return SectionCard(
          title: 'Recent results',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, r) in list.indexed) ...[
                if (i > 0) const Divider(height: 20),
                _ResultBlock(result: r),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.result});

  final TournamentResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final c = AppColors.of(context);
    final ended = r.endsOn ?? r.startsOn;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push(Routes.tournament(r.tournamentId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            [
              if (ended != null) DateFormat.yMMMd().format(ended),
              if (r.hostName.isNotEmpty) r.hostName,
              if (r.location.isNotEmpty) r.location,
            ].join(' · '),
            style: AppText.caption.copyWith(color: c.muted),
          ),
          const SizedBox(height: 6),
          for (final d in r.divisions)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.emoji_events, size: 16, color: c.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: d.champion?.name ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: [
                              '  ${d.label}',
                              if (d.runnerUp case final ru?) 'over ${ru.name}',
                            ].join(' · '),
                            style: TextStyle(color: c.muted),
                          ),
                        ],
                      ),
                      style: AppText.secondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The top of one division's ranking, or of the player ranking, linking
/// to the full Rankings page.
class RankingsPreviewCard extends StatelessWidget {
  const RankingsPreviewCard({super.key, required this.viewModel});

  final ExploreViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final vm = viewModel;
        final link = vm.rankingLink;
        final players = vm.kind == RankingKind.players;
        return SectionCard(
          title: 'Rankings',
          action: link == null
              ? null
              : CardLink(
                  label: 'Full rankings',
                  onTap: () => context.go(Routes.rankings(link)),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RankingKindToggle(viewModel: vm),
              const SizedBox(height: 10),
              if (players) ..._players(context, vm) else ..._teams(context, vm),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _teams(BuildContext context, ExploreViewModel vm) {
    final ranking = vm.ranking;
    if (!vm.rankingsLoaded) {
      return const [SkeletonList(count: 3, padding: EdgeInsets.zero)];
    }
    if (ranking == null) return const [RankingsEmptyNote.teams()];
    return [
      if (vm.rankings.length > 1)
        RankingPicker(viewModel: vm)
      else
        Eyebrow(ranking.label),
      const SizedBox(height: 6),
      for (final t in ranking.teams.take(ExploreViewModel.previewTeams))
        RankingRow(team: t, mine: vm.isMine(t.teamId)),
    ];
  }

  List<Widget> _players(BuildContext context, ExploreViewModel vm) {
    if (!vm.playersLoaded) {
      return const [SkeletonList(count: 3, padding: EdgeInsets.zero)];
    }
    final list = vm.playerRanking.players;
    if (list.isEmpty) return const [RankingsEmptyNote.players()];
    return [
      for (final p in list.take(ExploreViewModel.previewTeams))
        PlayerRankingRow(player: p, me: vm.isMe(p.uid)),
    ];
  }
}

/// Teams or players.
class RankingKindToggle extends StatelessWidget {
  const RankingKindToggle({super.key, required this.viewModel, this.onPick});

  final ExploreViewModel viewModel;

  /// Called after the view model switches.
  final ValueChanged<RankingKind>? onPick;

  @override
  Widget build(BuildContext context) => AppSegmentedButton<RankingKind>(
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(
        value: RankingKind.teams,
        label: Text('Teams'),
        icon: Icon(Icons.groups_outlined, size: 18),
      ),
      ButtonSegment(
        value: RankingKind.players,
        label: Text('Players'),
        icon: Icon(Icons.person_outline, size: 18),
      ),
    ],
    selected: {viewModel.kind},
    onSelectionChanged: (s) {
      viewModel.setKind(s.first);
      onPick?.call(s.first);
    },
  );
}

/// Why a ranking is empty.
class RankingsEmptyNote extends StatelessWidget {
  const RankingsEmptyNote.teams({super.key})
    : text =
          'Teams get ranked once they play 5 games in public '
          'tournaments hosted on Stall 10.';

  const RankingsEmptyNote.players({super.key})
    : text =
          'Players get rated once their team logs 10 of their games '
          'with the stat tracker. Only public profiles that show stats '
          'are rated.';

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppText.secondary.copyWith(color: AppColors.of(context).muted),
  );
}

/// A rated player: rank, name, games and rating; opens their profile.
class PlayerRankingRow extends StatelessWidget {
  const PlayerRankingRow({
    super.key,
    required this.player,
    this.me = false,
    this.details = false,
  });

  final RankedPlayer player;

  /// The user: highlighted.
  final bool me;

  /// Goals, assists and blocks under the name, for the full page.
  final bool details;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final p = player;
    return Material(
      color: me ? c.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push(Routes.player(p.uid)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: ScoreText(
                  '${p.rank}',
                  size: 20,
                  color: p.rank <= 3 ? c.ink : c.muted,
                ),
              ),
              PersonAvatar(name: p.name, photoUrl: p.photoUrl, radius: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (details)
                      Text(
                        '${p.goals} G · ${p.assists} A · ${p.blocks} D · '
                        '${p.turnovers} TO',
                        style: AppText.caption.copyWith(color: c.muted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${p.games} gp',
                style: AppText.secondary.copyWith(color: c.muted),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ScoreText('${p.rating}', size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chips for each division with a ranking.
class RankingPicker extends StatelessWidget {
  const RankingPicker({super.key, required this.viewModel, this.onPick});

  final ExploreViewModel viewModel;

  /// Called with the picked ranking's key, after the view model has it.
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    final current = viewModel.ranking?.key;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final r in viewModel.rankings)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(r.label),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                selected: r.key == current,
                onSelected: (_) {
                  viewModel.pickRanking(r.key);
                  onPick?.call(r.key);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// A ranked team: rank, name, record and rating; opens the team.
class RankingRow extends StatelessWidget {
  const RankingRow({super.key, required this.team, this.mine = false});

  final RankedTeam team;

  /// One of the user's teams: highlighted.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = team;
    return Material(
      color: mine ? c.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push(Routes.teamOver(t.teamId)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              // Rank and rating in the score face.
              SizedBox(
                width: 30,
                child: ScoreText(
                  '${t.rank}',
                  size: 20,
                  color: mine ? c.accentInk : (t.rank <= 3 ? c.ink : c.muted),
                ),
              ),
              Expanded(
                child: Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                t.record,
                style: AppText.secondary.copyWith(color: c.muted),
              ),
              SizedBox(
                width: 56,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ScoreText('${t.rating}', size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Public team events coming up (pickup games, practices open to all),
/// from `GET /v1/public/events` as the website's Discover lists them:
/// every one under All, pickup games under Pickup.
class PublicEventsCard extends StatelessWidget {
  const PublicEventsCard({super.key, required this.viewModel, this.only});

  final ExploreViewModel viewModel;

  /// The chip picked; null for All.
  final ExploreFilter? only;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final list = vm.publicEventsFor(only);
    final pickup = only == ExploreFilter.pickup;
    return SectionCard(
      title: pickup ? 'Pickup games' : 'Team events',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!vm.publicEventsLoaded)
            const SkeletonList(count: 2, padding: EdgeInsets.zero)
          else if (vm.loadPublic.error && list.isEmpty)
            Text(
              "Couldn't load events. Try again.",
              style: AppText.secondary.copyWith(color: c.muted),
            )
          else if (list.isEmpty)
            Text(
              pickup
                  ? 'No pickup games coming up yet. Pickup communities post '
                        'theirs here when they open them to everyone.'
                  : 'Nothing coming up.',
              style: AppText.secondary.copyWith(color: c.muted),
            )
          else
            for (final e in list) PublicEventRow(event: e, viewModel: vm),
        ],
      ),
    );
  }
}

/// A public team event: its date, title, who runs it (with a team or
/// community dot), when and where, and its type. Opens the event for the
/// team's members, else the team or community's page (only members read
/// its events).
class PublicEventRow extends StatelessWidget {
  const PublicEventRow({
    super.key,
    required this.event,
    required this.viewModel,
  });

  final PublicTeamEvent event;
  final ExploreViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final e = event;
    final start = e.startsAt;
    final when = start == null
        ? ''
        : DateFormat('EEE, MMM d · h:mm a').format(start);
    // Only communities run pickup games; anything else reads as a team's.
    final dot = e.isPickup ? c.accent : c.team;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: start == null
          ? const SizedBox(width: 40)
          : DateBadge(date: start, size: 40),
      title: Text(
        e.title.isEmpty ? 'Event' : e.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.label.copyWith(color: c.ink),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  e.teamName.isEmpty ? 'A team on Stall 10' : e.teamName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            [when, if (e.location.isNotEmpty) e.location].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: e.type == null
          ? null
          : Text(
              e.type!.label,
              style: AppText.caption.copyWith(fontWeight: FontWeight.w600, color: c.muted),
            ),
      onTap: () => context.push(
        viewModel.isMine(e.teamId)
            ? Routes.event(e.teamId, e.id)
            : Routes.teamOver(e.teamId),
      ),
    );
  }
}
