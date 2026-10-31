import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/tournament.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/home/view_models/home_viewmodel.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';

import '../testing/fakes.dart';

RankingDivision division(String key, String label, List<String> teams) =>
    RankingDivision(
      key: key,
      label: label,
      entries: [
        for (var i = 0; i < teams.length; i++)
          RankingEntry(
            rank: i + 1,
            teamName: teams[i],
            rating: 2000.0 - i * 50,
          ),
      ],
    );

TeamEvent event(String id, String title, EventType type, DateTime at) =>
    TeamEvent(id: id, title: title, type: type, startsAt: at);

void main() {
  // A Wednesday.
  final now = DateTime(2026, 10, 28, 9);
  final rankings = [
    division('College-Women', 'College Women', ['Ws A', 'Ws B', 'Ws C']),
    division('Club-Mixed', 'Club Mixed', [
      'Alpha',
      'Beta',
      'Gamma',
      'Northside Flyers',
      for (var i = 5; i <= 12; i++) 'Team $i',
    ]),
  ];
  final tournaments = [
    Tournament(
      id: 'past',
      name: 'Past Cup',
      url: '',
      startDate: DateTime.utc(2026, 10, 1, 12),
      endDate: DateTime.utc(2026, 10, 2, 12),
    ),
    Tournament(
      id: 'next',
      name: 'Fall Classic',
      url: '',
      startDate: DateTime.utc(2026, 10, 31, 12),
      endDate: DateTime.utc(2026, 11, 1, 12),
      city: 'Portland',
      state: 'OR',
      competitionLevel: 'Club',
      divisions: const ['Mixed'],
    ),
  ];

  Team team(String id, String name, {String? owner}) => Team(
    id: id,
    name: name,
    division: Division.mixed,
    level: CompetitionLevel.club,
    ownerId: owner ?? testUser.uid,
    members: {owner ?? testUser.uid: TeamRole.owner},
  );

  late FakeTeamRepository teams;
  late FakeDirectMessageRepository dms;
  late FakePlayRepository plays;
  late FakeEventRepository events;

  Future<HomeViewModel> load({
    bool withTeam = true,
    String teamName = 'Northside Flyers',
    Map<String, List<Play>> teamPlays = const {},
    bool withPersonal = false,
  }) async {
    teams = FakeTeamRepository();
    dms = FakeDirectMessageRepository();
    plays = FakePlayRepository()..byTeam.addAll(teamPlays);
    events = FakeEventRepository();
    if (withPersonal) {
      events.mine[testUser.uid] = {
        'run': event(
          'run',
          'Tempo run',
          EventType.workout,
          DateTime(2026, 10, 30, 7),
        ),
      };
    }
    if (withTeam) teams.teams['t1'] = team('t1', teamName);
    events.events.addAll({
      for (final e in [
        event(
          'old',
          'Old practice',
          EventType.practice,
          DateTime(2026, 10, 20, 18),
        ),
        event(
          'prac',
          'Thursday practice',
          EventType.practice,
          DateTime(2026, 10, 29, 18),
        ),
        event('lift', 'Lift', EventType.workout, DateTime(2026, 10, 31, 7)),
        event(
          'regs',
          'Regionals',
          EventType.tournament,
          DateTime(2026, 10, 31, 10),
        ),
        event(
          'far',
          'Far scrimmage',
          EventType.scrimmage,
          DateTime(2026, 11, 8, 10),
        ),
      ])
        e.id: e,
    });
    final vm = HomeViewModel(
      authRepository: FakeAuthRepository(user: testUser),
      directMessageRepository: dms,
      teamRepository: teams,
      playRepository: plays,
      eventRepository: events,
      tournamentRepository: FakeTournamentRepository(tournaments),
      rankingRepository: FakeRankingRepository(rankings),
      clock: () => now,
    );
    await pumpEventQueue();
    return vm;
  }

  group('HomeViewModel', () {
    test(
      'greets by first name and counts down to the next team event',
      () async {
        final vm = await load();
        expect(vm.firstName, 'Alex');
        expect(vm.initials, 'A');
        expect(vm.daysUntilNext, 1);
      },
    );

    test('without a team, counts down to the next tournament', () async {
      final vm = await load(withTeam: false);
      expect(vm.teamsLoaded, isTrue);
      expect(vm.selectedTeam, isNull);
      expect(vm.weekEvents, isEmpty);
      expect(vm.daysUntilNext, 3);
    });

    test('weekly outlook covers today and the next six days', () async {
      final vm = await load();
      expect(vm.weekDays.first, DateTime(2026, 10, 28));
      expect(vm.weekDays.last, DateTime(2026, 11, 3));
      expect(vm.weekEvents.map((e) => e.event.id), ['prac', 'lift', 'regs']);
      expect(vm.eventsOn(DateTime(2026, 10, 31)).length, 2);
      expect(vm.weekEvents.first.team?.id, 't1');
    });

    test(
      'this week mixes personal events in; team events leave them out',
      () async {
        final vm = await load(withPersonal: true);
        expect(vm.weekEvents.map((e) => e.event.id), [
          'prac',
          'run',
          'lift',
          'regs',
        ]);
        expect(vm.weekEvents[1].isPersonal, isTrue);
        // Team events lead each day; personal ones follow.
        expect(vm.upcomingEvents.map((e) => e.event.id), [
          'prac',
          'run',
          'regs',
          'lift',
        ]);
      },
    );

    test('personal events show without a team', () async {
      final vm = await load(withTeam: false, withPersonal: true);
      expect(vm.weekEvents.map((e) => e.event.id), ['run']);
      expect(vm.upcomingEvents.map((e) => e.event.id), ['run']);
      expect(vm.daysUntilNext, 2);
      expect(vm.weekEvents.single.isPersonal, isTrue);
    });

    test('team events put tournaments ahead of workouts on a day', () async {
      final vm = await load();
      expect(vm.upcomingEvents.map((e) => e.event.id), [
        'prac',
        'regs',
        'lift',
        'far',
      ]);
      expect(vm.nextEventFor(vm.selectedTeam!)?.event.id, 'prac');
    });

    test('other events are behind a toggle', () async {
      final vm = await load();
      expect(vm.showOtherEvents, isFalse);
      vm.setShowOtherEvents(true);
      expect(vm.showOtherEvents, isTrue);
      expect(vm.otherEvents.map((t) => t.id), ['next']);
    });

    test('podium and top ten come from the team\'s division', () async {
      final vm = await load();
      expect(vm.featuredDivision?.key, 'Club-Mixed');
      expect(vm.podium.map((e) => e.teamName), ['Alpha', 'Beta', 'Gamma']);
      expect(vm.topTen.map((e) => e.rank), [4, 5, 6, 7, 8, 9, 10]);
      expect(vm.myRanking?.rank, 4);
      expect(vm.isMine(vm.topTen.first), isTrue);
      expect(vm.myRankingBelowTopTen, isNull);
    });

    test('quick filter switches divisions', () async {
      final vm = await load();
      vm.selectDivision('College-Women');
      expect(vm.podium.map((e) => e.teamName), ['Ws A', 'Ws B', 'Ws C']);
      expect(vm.topTen, isEmpty);
      expect(vm.myRanking, isNull);
    });

    test('shows the user\'s team when it is below the top ten', () async {
      final vm = await load(teamName: 'Team 12');
      expect(vm.myRankingBelowTopTen?.rank, 12);
    });

    test('falls back to the first list without a team', () async {
      final vm = await load(withTeam: false);
      expect(vm.featuredDivision?.key, 'College-Women');
      expect(vm.myRanking, isNull);
    });

    test('previews the selected team\'s plays', () async {
      final vm = await load(
        teamPlays: const {
          't1': [Play(id: 'p1', name: 'Ho stack')],
          't2': [Play(id: 'p2', name: 'Zone'), Play(id: 'p3', name: 'Cup')],
        },
      );
      await teams.updateTeam(team('t2', 'Second'));
      await pumpEventQueue();
      expect(vm.plays.map((p) => p.id), ['p1']);
      vm.selectTeam('t2');
      await pumpEventQueue();
      expect(vm.selectedTeam?.id, 't2');
      expect(vm.playCount, 2);
      expect(vm.canEdit(vm.selectedTeam!), isTrue);
    });

    test('joins a team by invite code', () async {
      final vm = await load(withTeam: false);
      teams.teams['t9'] = team('t9', 'Other', owner: 'u9');
      await vm.joinTeam.execute('CODEt9');
      await pumpEventQueue();
      expect(vm.joinTeam.completed, isTrue);
      expect(vm.teams.map((t) => t.id), ['t9']);
    });
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('home screen lays out at phone width ($name)', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final page = find.byType(Scrollable).first;
      final vm = await tester.runAsync(
        () => load(
          withPersonal: true,
          teamPlays: const {
            't1': [Play(id: 'p1', name: 'Ho stack')],
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: HomeScreen(viewModel: vm!),
        ),
      );
      await tester.pump();

      expect(find.text("LET'S GO, ALEX."), findsOneWidget);
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('Thursday practice'), findsWidgets);
      expect(find.text('Tempo run'), findsOneWidget);
      expect(find.textContaining('Personal'), findsOneWidget);
      expect(find.text('1 days out'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Ho stack'),
        300,
        scrollable: page,
      );
      expect(find.text('New play'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Show other events'),
        300,
        scrollable: page,
      );
      await tester.tap(find.text('Show other events'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Fall Classic'),
        300,
        scrollable: page,
      );
      expect(find.text('Fall Classic'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('YOU: #4'),
        300,
        scrollable: page,
      );
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Northside Flyers'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('home screen lays out as a dashboard at desktop width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = await tester.runAsync(
      () => load(
        withPersonal: true,
        teamPlays: const {
          't1': [Play(id: 'p1', name: 'Ho stack')],
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(viewModel: vm!),
      ),
    );
    await tester.pump();

    // Team and rankings sit in a right-hand column beside the schedule.
    final week = tester.getTopLeft(find.text('THIS WEEK'));
    final team = tester.getTopLeft(find.text('MY TEAM'));
    expect(team.dx, greaterThan(week.dx + 400));
    expect(team.dy, week.dy);
    expect(tester.getTopLeft(find.text('RANKINGS')).dx, team.dx);
    expect(find.text('Ho stack'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('counts unread direct messages', () async {
    final vm = await load();
    expect(vm.unreadMessages, 0);
    dms.conversations['a_u1'] = Conversation(
      id: 'a_u1',
      participants: const ['a', 'u1'],
      lastMessage: 'hey',
      lastMessageAt: DateTime(2026, 10, 30),
      lastSenderId: 'a',
    );
    dms.conversations['b_u1'] = Conversation(
      id: 'b_u1',
      participants: const ['b', 'u1'],
      lastMessage: 'mine',
      lastMessageAt: DateTime(2026, 10, 30),
      lastSenderId: 'u1',
    );
    dms.emit();
    await pumpEventQueue();
    expect(vm.unreadMessages, 1);
  });

  testWidgets('home screen offers to join a team', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final vm = await tester.runAsync(() => load(withTeam: false));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(viewModel: vm!),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Join with code'));
    await tester.pumpAndSettle();
    expect(find.text('JOIN YOUR TEAM.'), findsOneWidget);
    await tester.tap(find.text('Join with code'));
    await tester.pumpAndSettle();
    expect(find.text('Invite code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
