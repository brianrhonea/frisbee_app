import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/routing/routes.dart' show ExploreFilter;
import 'package:frisbee_app/ui/explore/view_models/explore_viewmodel.dart';
import 'package:frisbee_app/ui/explore/view_models/player_search_viewmodel.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/explore/widgets/rankings_screen.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart' show SectionCard;
import 'package:frisbee_app/ui/teams/view_models/team_search_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournaments_viewmodel.dart';

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
  final collegeOpen = ranking(CompetitionLevel.college, Division.open, [
    ('co1', 'Pleasure'),
  ]);
  final youthMixed = ranking(CompetitionLevel.youth, Division.mixed, [
    for (var i = 0; i < 12; i++) ('y$i', 'Youth $i'),
  ]);

  ExploreViewModel build({
    FakeRankingRepository? rankings,
    FakeHostedTournamentRepository? tournaments,
    FakeTeamRepository? teams,
    bool rankingsPage = false,
    RankingKind kind = RankingKind.teams,
    String? level,
    String? division,
  }) {
    final vm = ExploreViewModel(
      tournamentRepository: tournaments ?? FakeHostedTournamentRepository(),
      rankingRepository: rankings ?? FakeRankingRepository(),
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
      rankingsPage: rankingsPage,
      kind: kind,
      level: level,
      division: division,
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
      final vm = build(rankings: repo, level: 'club', division: 'mixed');
      await pumpEventQueue();
      expect(vm.ranking?.key, 'club-mixed');
      expect(vm.rankingLink, {'level': 'club', 'division': 'mixed'});
    });

    test('never shows a youth ranking, even the biggest or linked', () async {
      final repo = FakeRankingRepository()
        ..initialRankings = [youthMixed, clubOpen];
      final preview = build(rankings: repo);
      final page = build(
        rankings: repo,
        rankingsPage: true,
        level: 'youth',
        division: 'mixed',
      );
      await pumpEventQueue();
      expect(preview.rankings.map((r) => r.key), ['club-open']);
      expect(preview.ranking?.key, 'club-open');
      expect(page.ranking?.key, 'club-open');
      expect(page.rankingChoice?.levels, [CompetitionLevel.club]);

      final onlyYouth = FakeRankingRepository()..initialRankings = [youthMixed];
      final none = build(rankings: onlyYouth, rankingsPage: true);
      await pumpEventQueue();
      expect(none.ranking, isNull);
    });
  });

  group('Rankings page filters', () {
    test('opens on Club Mixed, as the website does, else the first', () async {
      final repo = FakeRankingRepository()
        ..initialRankings = [collegeWomen, clubOpen, clubMixed];
      final teams = FakeTeamRepository()
        ..teams['w1'] = Team(
          id: 'w1',
          name: 'Fury',
          division: Division.women,
          level: CompetitionLevel.college,
          ownerId: testUser.uid,
          members: {testUser.uid: TeamRole.owner},
        );
      final vm = build(rankings: repo, teams: teams, rankingsPage: true);
      await pumpEventQueue();
      expect(vm.ranking?.key, 'club-mixed', reason: 'not the biggest or mine');

      final noMixed = FakeRankingRepository()
        ..initialRankings = [collegeWomen, clubOpen];
      final other = build(rankings: noMixed, rankingsPage: true);
      await pumpEventQueue();
      expect(other.ranking?.key, 'club-open');
    });

    test('offer only levels and divisions with rankings', () async {
      final repo = FakeRankingRepository()
        ..initialRankings = [collegeWomen, collegeOpen, clubOpen, clubMixed];
      final vm = build(rankings: repo, rankingsPage: true);
      await pumpEventQueue();
      final choice = vm.rankingChoice!;
      expect(choice.levels, [CompetitionLevel.club, CompetitionLevel.college]);
      expect(choice.divisions, [Division.mixed, Division.open]);
      expect(
        (choice.level, choice.division),
        (CompetitionLevel.club, Division.mixed),
      );
    });

    test('a level keeps the division if it has one, else its first', () async {
      final repo = FakeRankingRepository()
        ..initialRankings = [collegeWomen, collegeOpen, clubOpen, clubMixed];
      final vm = build(rankings: repo, rankingsPage: true);
      await pumpEventQueue();
      vm.pickDivision(Division.open);
      expect(vm.ranking?.key, 'club-open');
      vm.pickLevel(CompetitionLevel.college);
      expect(vm.ranking?.key, 'college-open', reason: 'kept Open');
      expect(vm.rankingChoice?.divisions, [Division.open, Division.women]);
      vm.pickDivision(Division.women);
      expect(vm.ranking?.key, 'college-women');
      vm.pickLevel(CompetitionLevel.club);
      expect(vm.ranking?.key, 'club-mixed', reason: 'no Club Women');
      expect(vm.rankingLink, {'level': 'club', 'division': 'mixed'});
    });

    test('reads the old ?d= and ?division= keys', () {
      expect(RankingChoice.wantFromQuery(d: 'college-women'), (
        level: 'college',
        division: 'women',
      ));
      expect(RankingChoice.wantFromQuery(division: 'club-open'), (
        level: 'club',
        division: 'open',
      ));
      expect(RankingChoice.wantFromQuery(d: 'youth-mixed'), (
        level: null,
        division: null,
      ));
      expect(RankingChoice.wantFromQuery(level: 'pickup', division: 'open'), (
        level: 'pickup',
        division: 'open',
      ));
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

  testWidgets('the Rankings page filters by Level and Division, never Youth', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rankings = FakeRankingRepository()
      ..initialRankings = [clubMixed, clubOpen, collegeWomen, youthMixed];
    final vm = build(rankings: rankings, rankingsPage: true);
    await tester.pumpWidget(MaterialApp(home: RankingsScreen(viewModel: vm)));
    await tester.pumpAndSettle();

    expect(find.text('Level'), findsOneWidget);
    expect(find.text('Division'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Club'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'College'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Youth'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Mixed'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Open'), findsOneWidget);
    expect(find.text('Club Mixed'), findsOneWidget);
    expect(find.text('Seattle Mixtape'), findsOneWidget);
    expect(find.textContaining('Youth'), findsOneWidget);
    expect(find.textContaining("Youth teams aren't ranked."), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Open'));
    await tester.pumpAndSettle();
    expect(find.text('Club Open'), findsOneWidget);
    expect(find.text('Open 0'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'College'));
    await tester.pumpAndSettle();
    expect(find.text('College Women'), findsOneWidget);
    expect(find.text('Fury'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Women'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Open'), findsNothing);
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

  testWidgets(
    'the filter chips sit in one row that scrolls, selected chip in view',
    (tester) async {
      // A narrow phone: seven chips are wider than the screen.
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final explore = build();
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
            initialFilter: ExploreFilter.tournaments,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chips = find.byType(ChoiceChip);
      expect(chips, findsNWidgets(7));
      expect(
        [
          for (final e in chips.evaluate())
            ((e.widget as ChoiceChip).label as Text).data,
        ],
        [
          'All',
          'Tournaments',
          'Leagues',
          'Pickup',
          'Teams',
          'Communities',
          'Players',
        ],
      );
      final rows = {
        for (final e in chips.evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy,
      };
      expect(rows, hasLength(1), reason: 'every chip on the same line');

      // The selected chip, last in the row, was scrolled into view.
      final selected = tester.getRect(
        find.widgetWithText(ChoiceChip, 'Tournaments'),
      );
      expect(selected.left, greaterThanOrEqualTo(0));
      expect(selected.right, lessThanOrEqualTo(320));

      // A chip scrolled out of view comes back when it's picked.
      await tester.drag(find.byType(ChoiceChip).last, const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.widgetWithText(ChoiceChip, 'All')).left,
        greaterThanOrEqualTo(0),
      );
      // (Picked by its callback: it's partly off the screen to tap.)
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Communities'))
          .onSelected!(true);
      await tester.pumpAndSettle();
      final groups = tester.getRect(
        find.widgetWithText(ChoiceChip, 'Communities'),
      );
      expect(groups.left, greaterThanOrEqualTo(0));
      expect(groups.right, lessThanOrEqualTo(320));
    },
  );

  group('Discover', () {
    HostedTournament event(
      String id,
      String name, {
      HostedType type = HostedType.tournament,
      HostedStatus status = HostedStatus.registration,
      int inDays = 10,
    }) => HostedTournament(
      id: id,
      hostId: 'h',
      hostName: 'Austin Ultimate',
      name: name,
      kind: type == HostedType.league
          ? HostedKind.league
          : HostedKind.tournament,
      entryType: type == HostedType.hat
          ? TournamentEntryType.players
          : TournamentEntryType.teams,
      location: 'Austin',
      startsOn: DateTime.now().add(Duration(days: inDays)),
      status: status,
    );

    /// Picks the chip [label] (by its callback: the row scrolls, so it
    /// may be off the screen to tap).
    Future<void> pick(WidgetTester tester, String label) async {
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
          .onSelected!(true);
      await tester.pump();
    }

    Future<void> pumpDiscover(
      WidgetTester tester, {
      required FakeHostedTournamentRepository tournaments,
      FakeTeamRepository? teams,
    }) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final teamSearch = TeamSearchViewModel(
        teamRepository: teams ?? FakeTeamRepository(),
        authRepository: FakeAuthRepository(user: testUser),
      );
      final players = PlayerSearchViewModel(
        profileRepository: FakeProfileRepository(),
      );
      final events = HostedTournamentsViewModel(
        tournamentRepository: tournaments,
        authRepository: FakeAuthRepository(user: testUser),
      );
      addTearDown(teamSearch.dispose);
      addTearDown(players.dispose);
      addTearDown(events.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ExploreScreen(
            viewModel: teamSearch,
            players: players,
            explore: build(tournaments: tournaments),
            events: events,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('has what Find events had: live now, coming up and Host', (
      tester,
    ) async {
      final tournaments = FakeHostedTournamentRepository()
        ..tournaments.addAll({
          'live': event(
            'live',
            'Mile High Open',
            status: HostedStatus.live,
            inDays: 0,
          ),
          'a': event('a', 'Lone Star Classic'),
          'hat': event('hat', 'Snowmelt Hat', type: HostedType.hat),
          'l': event('l', 'Winter League', type: HostedType.league),
        });
      await pumpDiscover(tester, tournaments: tournaments);

      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);
      // Live ones on a scoreboard card, not again under Coming up.
      expect(find.text('Live now'), findsOneWidget);
      expect(find.text('Mile High Open'), findsOneWidget);
      expect(find.text('Coming up'), findsOneWidget);
      for (final name in [
        'Lone Star Classic',
        'Snowmelt Hat',
        'Winter League',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      // The status filter Find events had.
      expect(find.textContaining('Registration open'), findsWidgets);

      // Tournaments: tournaments and hats; Leagues: leagues.
      await pick(tester, 'Tournaments');
      await tester.pumpAndSettle();
      expect(find.text('Snowmelt Hat'), findsOneWidget);
      expect(find.text('Winter League'), findsNothing);
      await pick(tester, 'Leagues');
      await tester.pumpAndSettle();
      expect(find.text('Winter League'), findsOneWidget);
      expect(find.text('Lone Star Classic'), findsNothing);
      expect(find.text('Mile High Open'), findsNothing);

      // Teams need a search: a hint, no events.
      await pick(tester, 'Teams');
      await tester.pumpAndSettle();
      expect(find.text('Coming up'), findsNothing);
      expect(find.textContaining('letters to search teams'), findsOneWidget);
    });

    testWidgets("Live now shows the games being played, with their scores", (
      tester,
    ) async {
      final now = DateTime.now();
      final tournaments = FakeHostedTournamentRepository();
      seedLiveTournament(tournaments, now: now);
      // g3 (Boulder Gold v Northside Flyers) is being played; g4's running
      // score is hours old, so it isn't live any more.
      LiveScore live(int a, int b, DateTime at) =>
          LiveScore(scoreA: a, scoreB: b, startedAt: at, updatedAt: at);
      tournaments.games['x9/d1'] = [
        for (final g in tournaments.games['x9/d1']!)
          switch (g.id) {
            'g3' => g.copyWith(live: () => live(9, 7, now)),
            'g4' => g.copyWith(
              live: () => live(2, 2, now.subtract(const Duration(hours: 5))),
            ),
            _ => g,
          },
      ];
      await pumpDiscover(tester, tournaments: tournaments);
      expect(find.text('Live now'), findsOneWidget);
      expect(find.text('Mile High Open'), findsOneWidget);
      expect(find.text('Boulder Gold'), findsOneWidget);
      expect(find.text('Northside Flyers'), findsOneWidget);
      expect(find.text('9–7'), findsOneWidget);
      expect(find.text('2–2'), findsNothing);
      expect(find.text('Field 3'), findsOneWidget);
    });

    testWidgets('search results are grouped by kind', (tester) async {
      final tournaments = FakeHostedTournamentRepository()
        ..tournaments.addAll({
          'a': event('a', 'Austin Classic'),
          'l': event('l', 'Austin League', type: HostedType.league),
        });
      final teams = FakeTeamRepository()
        ..listings['t'] = const TeamListing(
          id: 't',
          name: 'Austin Flyers',
          division: Division.mixed,
          level: CompetitionLevel.club,
        )
        ..listings['p'] = const TeamListing(
          id: 'p',
          name: 'Austin Pickup',
          division: Division.mixed,
          level: CompetitionLevel.club,
          kind: TeamKind.community,
        )
        ..listings['s'] = const TeamListing(
          id: 's',
          name: 'Austin School',
          division: Division.mixed,
          level: CompetitionLevel.club,
          kind: TeamKind.organization,
        );
      await pumpDiscover(tester, tournaments: tournaments, teams: teams);
      await tester.enterText(find.byType(TextField), 'austin');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      for (final heading in [
        'Tournaments',
        'Leagues',
        'Teams',
        'Communities',
      ]) {
        expect(
          find.descendant(
            of: find.byType(SectionCard),
            matching: find.text(heading),
          ),
          findsOneWidget,
          reason: heading,
        );
      }
      expect(find.text('Austin Classic'), findsOneWidget);
      expect(find.text('Austin League'), findsOneWidget);
      expect(find.text('Austin Flyers'), findsOneWidget);
      expect(find.text('Austin Pickup'), findsOneWidget);
      expect(find.text('Austin School'), findsOneWidget);
      // Not while searching.
      expect(find.text('Coming up'), findsNothing);

      // Pickup: pickup communities only; Communities: schools and clubs too.
      await pick(tester, 'Pickup');
      await tester.pumpAndSettle();
      expect(find.text('Austin Pickup'), findsOneWidget);
      expect(find.text('Austin School'), findsNothing);
      expect(find.text('Austin Flyers'), findsNothing);
      expect(find.text('Austin Classic'), findsNothing);
      await pick(tester, 'Communities');
      await tester.pumpAndSettle();
      expect(find.text('Austin Pickup'), findsOneWidget);
      expect(find.text('Austin School'), findsOneWidget);
      expect(find.text('Austin League'), findsNothing);

      // Under Pickup, a search that only finds a school says so.
      await pick(tester, 'Pickup');
      await tester.enterText(find.byType(TextField), 'school');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Austin School'), findsNothing);
      expect(find.text('Nothing found'), findsOneWidget);
    });
  });

  test('a players link opens on players', () async {
    final vm = build(kind: RankingKind.players, rankingsPage: true);
    await pumpEventQueue();
    expect(vm.kind, RankingKind.players);
    expect(vm.rankingLink, {'kind': 'players'});
    expect(vm.playersLoaded, isTrue);
  });
}
