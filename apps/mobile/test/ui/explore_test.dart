import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/explore/view_models/explore_viewmodel.dart';
import 'package:frisbee_app/ui/explore/view_models/player_search_viewmodel.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/explore/widgets/rankings_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/team_search_viewmodel.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';

class FakeRankingRepository implements RankingRepository {
  final rankings = StreamController<List<DivisionRanking>>.broadcast();
  final results = StreamController<List<TournamentResult>>.broadcast();
  List<DivisionRanking> initialRankings = const [];
  List<TournamentResult> initialResults = const [];
  PlayerRanking initialPlayers = const PlayerRanking();

  @override
  Stream<List<DivisionRanking>> watchRankings() async* {
    yield initialRankings;
    yield* rankings.stream;
  }

  @override
  Stream<List<TournamentResult>> watchRecentResults() async* {
    yield initialResults;
    yield* results.stream;
  }

  @override
  Stream<PlayerRanking> watchPlayerRankings() async* {
    yield initialPlayers;
  }
}

DivisionRanking ranking(
  CompetitionLevel level,
  Division division,
  List<(String, String)> teams,
) => DivisionRanking(
  level: level,
  division: division,
  teams: [
    for (final (i, (id, name)) in teams.indexed)
      RankedTeam(
        rank: i + 1,
        teamId: id,
        name: name,
        rating: 1500 - i * 50,
        wins: 6 - i,
        losses: i,
      ),
  ],
);

void main() {
  final clubMixed = ranking(CompetitionLevel.club, Division.mixed, [
    ('m1', 'Seattle Mixtape'),
    ('t1', 'Team'),
  ]);
  final clubOpen = ranking(CompetitionLevel.club, Division.open, [
    for (var i = 0; i < 8; i++) ('o$i', 'Open $i'),
  ]);
  final collegeWomen = ranking(CompetitionLevel.college, Division.women, [
    ('w1', 'Fury'),
  ]);

  ExploreViewModel build({
    FakeRankingRepository? rankings,
    FakeHostedTournamentRepository? tournaments,
    FakeTeamRepository? teams,
    String? initialRanking,
  }) {
    final vm = ExploreViewModel(
      tournamentRepository: tournaments ?? FakeHostedTournamentRepository(),
      rankingRepository: rankings ?? FakeRankingRepository(),
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
      initialRanking: initialRanking,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  group('ExploreViewModel rankings', () {
    test('sorts divisions by level and opens on the biggest', () async {
      final repo = FakeRankingRepository()
        ..initialRankings = [collegeWomen, clubOpen, clubMixed];
      final vm = build(rankings: repo);
      await pumpEventQueue();
      expect(vm.rankings.map((r) => r.key), [
        'club-mixed',
        'club-open',
        'college-women',
      ]);
      expect(vm.ranking?.key, 'club-open', reason: 'most teams');

      vm.pickRanking('college-women');
      expect(vm.ranking?.key, 'college-women');
    });

    test("opens on the user's team's division and marks the team", () async {
      final repo = FakeRankingRepository()
        ..initialRankings = [clubOpen, clubMixed];
      final teams = FakeTeamRepository()
        ..teams['t1'] = teamWith({testUser.uid: TeamRole.owner});
      final vm = build(rankings: repo, teams: teams);
      await pumpEventQueue();
      expect(vm.ranking?.key, 'club-mixed');
      expect(vm.isMine('t1'), isTrue);
      expect(vm.isMine('m1'), isFalse);
    });

    test('a linked division wins over the default', () async {
      final repo = FakeRankingRepository()
        ..initialRankings = [clubOpen, clubMixed];
      final vm = build(rankings: repo, initialRanking: 'club-mixed');
      await pumpEventQueue();
      expect(vm.ranking?.key, 'club-mixed');
    });

    test('has no ranking until one exists', () async {
      final vm = build();
      await pumpEventQueue();
      expect(vm.rankingsLoaded, isTrue);
      expect(vm.ranking, isNull);
    });
  });

  test('matches upcoming tournaments on every word', () async {
    final tournaments = FakeHostedTournamentRepository()
      ..tournaments['a'] = HostedTournament(
        id: 'a',
        hostId: 'h',
        hostName: 'Austin Ultimate',
        name: 'Lone Star Classic',
        location: 'Zilker Park',
        startsOn: DateTime.now().add(const Duration(days: 10)),
        status: HostedStatus.registration,
      )
      ..tournaments['b'] = HostedTournament(
        id: 'b',
        hostId: 'h',
        hostName: 'Seattle',
        name: 'Emerald City',
        startsOn: DateTime.now().add(const Duration(days: 20)),
        status: HostedStatus.draft,
      );
    final vm = build(tournaments: tournaments);
    await pumpEventQueue();
    expect(vm.upcoming.map((t) => t.id), ['a'], reason: 'drafts are hidden');
    expect(vm.matching('lone zilker').map((t) => t.id), ['a']);
    expect(vm.matching('austin'), hasLength(1));
    expect(vm.matching('emerald'), isEmpty);
    expect(vm.matching('  '), isEmpty);
  });

  testWidgets('Explore shows tournaments, results and a rankings preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tournaments = FakeHostedTournamentRepository()
      ..tournaments['a'] = HostedTournament(
        id: 'a',
        hostId: 'h',
        hostName: 'Austin Ultimate',
        name: 'Lone Star Classic',
        startsOn: DateTime.now().add(const Duration(days: 10)),
        status: HostedStatus.registration,
      );
    final rankings = FakeRankingRepository()
      ..initialRankings = [clubOpen]
      ..initialResults = [
        TournamentResult(
          tournamentId: 'f',
          name: 'Fall Classic',
          endsOn: DateTime(2026, 11, 1),
          divisions: const [
            DivisionResult(
              label: 'Club Open',
              champion: (teamId: 'o0', name: 'Open 0'),
              runnerUp: (teamId: 'o1', name: 'Open 1'),
            ),
          ],
        ),
      ];
    final explore = build(tournaments: tournaments, rankings: rankings);
    final teamSearch = TeamSearchViewModel(
      teamRepository: FakeTeamRepository(),
      authRepository: FakeAuthRepository(user: testUser),
    );
    final players = PlayerSearchViewModel(
      profileRepository: FakeProfileRepository(),
    );
    addTearDown(teamSearch.dispose);
    addTearDown(players.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ExploreScreen(
          viewModel: teamSearch,
          players: players,
          explore: explore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tournaments & leagues'), findsOneWidget);
    expect(find.text('Lone Star Classic'), findsOneWidget);
    expect(find.text('Recent results'), findsOneWidget);
    expect(find.text('Fall Classic'), findsOneWidget);
    expect(find.text('Rankings'), findsOneWidget);
    // The preview shows the top five of eight.
    expect(find.text('Open 4'), findsOneWidget);
    expect(find.text('Open 5'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Tournaments'), findsOneWidget);
    // The rules are a tap away.
    expect(find.text('Learn to play'), findsOneWidget);
  });

  testWidgets('the Rankings page lists every ranked team', (tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rankings = FakeRankingRepository()..initialRankings = [clubOpen];
    final vm = build(rankings: rankings);
    await tester.pumpWidget(MaterialApp(home: RankingsScreen(viewModel: vm)));
    await tester.pumpAndSettle();
    expect(find.text('Club Open'), findsWidgets);
    expect(find.text('Open 7'), findsOneWidget);
    expect(find.text('1500'), findsOneWidget);
  });

  testWidgets('Rankings switches to players and marks the user', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rankings = FakeRankingRepository()
      ..initialRankings = [clubOpen]
      ..initialPlayers = PlayerRanking(
        players: [
          const RankedPlayer(rank: 1, uid: 'p9', name: 'Jo Star', rating: 81),
          RankedPlayer(
            rank: 2,
            uid: testUser.uid,
            name: 'Alex',
            rating: 64,
            games: 12,
            goals: 7,
          ),
        ],
      );
    final vm = build(rankings: rankings);
    await tester.pumpWidget(MaterialApp(home: RankingsScreen(viewModel: vm)));
    await tester.pumpAndSettle();
    expect(find.text('Jo Star'), findsNothing);

    await tester.tap(find.text('Players'));
    await tester.pumpAndSettle();
    expect(vm.kind, RankingKind.players);
    expect(find.text('Jo Star'), findsOneWidget);
    expect(find.text('81'), findsOneWidget);
    expect(find.text('12 gp'), findsOneWidget);
    expect(vm.isMe(testUser.uid), isTrue);
  });

  test('a players link opens on players', () async {
    final vm = build(initialRanking: ExploreViewModel.playersKey);
    await pumpEventQueue();
    expect(vm.kind, RankingKind.players);
    expect(vm.rankingLink, 'players');
    expect(vm.playersLoaded, isTrue);
  });
}
