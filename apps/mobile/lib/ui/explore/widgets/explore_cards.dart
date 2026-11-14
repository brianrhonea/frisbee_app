import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/ranking.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/skeleton.dart';
import '../../tournaments/widgets/hosted_status_badge.dart';
import '../../tournaments/widgets/hosted_tournament_screen.dart'
    show hostedDates;
import '../view_models/explore_viewmodel.dart';

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
                  'Nothing coming up yet. Groups and clubs host tournaments '
                  'and leagues from their Tournaments tab.',
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                )
              else
                for (final t in list) TournamentTile(tournament: t),
            ],
          ),
        );
      },
    );
  }
}

/// A tournament in Explore: dates, place and divisions, with its status.
class TournamentTile extends StatelessWidget {
  const TournamentTile({super.key, required this.tournament});

  final HostedTournament tournament;

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
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        child: Icon(Icons.emoji_events_outlined, size: 20, color: c.ink),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              t.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (t.hostOfficial) ...[
            const SizedBox(width: 6),
            const OfficialBadge(label: null),
          ],
        ],
      ),
      subtitle: Text(
        [
          details,
          [
            if (t.type != HostedType.tournament) t.type.label,
            t.hostName,
            if (divisions.isNotEmpty) divisions,
          ].join(' · '),
        ].join('\n'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: HostedStatusBadge(status: t.status),
      onTap: () => context.push(Routes.tournament(t.id)),
    );
  }
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
            style: TextStyle(fontSize: 12, color: c.muted),
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
                      style: const TextStyle(fontSize: 13),
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
  Widget build(BuildContext context) => SegmentedButton<RankingKind>(
    showSelectedIcon: false,
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
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
    style: TextStyle(fontSize: 12.5, color: AppColors.of(context).muted),
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
    const figures = [FontFeature.tabularFigures()];
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
                child: Text(
                  '${p.rank}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontFeatures: figures,
                    color: p.rank <= 3 ? c.ink : c.muted,
                  ),
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
                        style: TextStyle(
                          fontSize: 11.5,
                          color: c.muted,
                          fontFeatures: figures,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${p.games} gp',
                style: TextStyle(
                  fontSize: 12.5,
                  color: c.muted,
                  fontFeatures: figures,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                child: Text(
                  '${p.rating}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: figures,
                  ),
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
              SizedBox(
                width: 30,
                child: Text(
                  '${t.rank}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: t.rank <= 3 ? c.ink : c.muted,
                  ),
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
                style: TextStyle(
                  fontSize: 12.5,
                  color: c.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  '${t.rating}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
