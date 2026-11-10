import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/skeleton.dart';
import '../../core/ui/status_views.dart';
import '../view_models/explore_viewmodel.dart';
import 'explore_cards.dart';

/// Every division's full team ranking, one at a time, or the player
/// ranking.
class RankingsScreen extends StatelessWidget {
  const RankingsScreen({super.key, required this.viewModel});

  final ExploreViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final mobile = ScreenSize.of(context).isMobile;
    return Scaffold(
      appBar: mobile ? AppBar(title: const Text('Rankings')) : null,
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final vm = viewModel;
          // Keep the link in step, so it can be shared.
          void relink() {
            if (vm.rankingLink case final link?) {
              GoRouter.maybeOf(context)?.replace(Routes.rankings(link));
            }
          }

          return PageScroll(
            children: [
              if (!mobile)
                const PageHeader(
                  eyebrow: 'Explore',
                  title: 'Rankings',
                  subtitle:
                      'Teams from public tournaments, players from logged '
                      'stats.',
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: RankingKindToggle(
                  viewModel: vm,
                  onPick: (_) => relink(),
                ),
              ),
              const SizedBox(height: 12),
              if (vm.kind == RankingKind.players)
                ..._players(context, vm)
              else
                ..._teams(context, vm, relink),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _teams(
    BuildContext context,
    ExploreViewModel vm,
    VoidCallback relink,
  ) {
    final c = AppColors.of(context);
    final ranking = vm.ranking;
    if (!vm.rankingsLoaded) {
      return const [SkeletonList(count: 8, padding: EdgeInsets.zero)];
    }
    if (vm.error != null && ranking == null) {
      return [ErrorView(error: vm.error)];
    }
    if (ranking == null) {
      return const [
        EmptyView(
          icon: Icons.leaderboard_outlined,
          title: 'No team rankings yet',
          message:
              'Teams get ranked once they play 5 games in public '
              'tournaments hosted on Stall 10.',
        ),
      ];
    }
    return [
      RankingPicker(viewModel: vm, onPick: (_) => relink()),
      const SizedBox(height: 12),
      SectionCard(
        title: ranking.label,
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Header(columns: ['TEAM', 'W–L', 'RATING'], last: 52),
            for (final t in ranking.teams)
              RankingRow(team: t, mine: vm.isMine(t.teamId)),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(
        [
          'Ratings come from the score of every game in public '
              'tournaments over the last 12 months: bigger wins and newer '
              'games count more, and beating strong teams counts more than '
              'beating weak ones. Teams need ${ranking.minGames} games to be '
              'ranked.',
          if (ranking.updatedAt case final at?)
            'Updated ${DateFormat.yMMMd().add_jm().format(at)}.',
        ].join(' '),
        style: TextStyle(fontSize: 12, color: c.muted),
      ),
    ];
  }

  List<Widget> _players(BuildContext context, ExploreViewModel vm) {
    final c = AppColors.of(context);
    final ranking = vm.playerRanking;
    if (!vm.playersLoaded) {
      return const [SkeletonList(count: 8, padding: EdgeInsets.zero)];
    }
    if (ranking.players.isEmpty) {
      return const [
        EmptyView(
          icon: Icons.person_search_outlined,
          title: 'No player ratings yet',
          message:
              'Players get rated once their team logs 10 of their games '
              'with the stat tracker. Only public profiles that show stats '
              'are rated.',
        ),
      ];
    }
    return [
      SectionCard(
        title: 'Players',
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Header(columns: ['PLAYER', 'GAMES', 'RATING'], last: 36),
            for (final p in ranking.players)
              PlayerRankingRow(player: p, me: vm.isMe(p.uid), details: true),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(
        [
          'Ratings come from stats logged with the game tracker this season '
              'and last (last season counts half): goals, assists, blocks '
              'and touches per point played, less throwaways and drops. '
              'More points played means a steadier rating. 50 is average. '
              'Players need ${ranking.minGames} games, and a public profile '
              'that shows stats.',
          if (ranking.updatedAt case final at?)
            'Updated ${DateFormat.yMMMd().add_jm().format(at)}.',
        ].join(' '),
        style: TextStyle(fontSize: 12, color: c.muted),
      ),
    ];
  }
}

/// Column labels over a ranking: rank, then [columns]; the last one is
/// [last] wide and right-aligned.
class _Header extends StatelessWidget {
  const _Header({required this.columns, required this.last});

  final List<String> columns;
  final double last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
    child: DefaultTextStyle.merge(
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.of(context).muted,
      ),
      child: Row(
        children: [
          const SizedBox(width: 30, child: Text('#')),
          Expanded(child: Text(columns[0])),
          Text(columns[1]),
          SizedBox(
            width: last,
            child: Text(columns[2], textAlign: TextAlign.right),
          ),
        ],
      ),
    ),
  );
}
