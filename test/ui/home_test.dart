import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/domain/models/tournament.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/home/view_models/home_viewmodel.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';

import '../testing/fakes.dart';

TeamEvent event(String id, String title, EventType type, DateTime at) =>
    TeamEvent(id: id, title: title, type: type, startsAt: at);

void main() {
  // A Wednesday.
  final now = DateTime(2026, 10, 28, 9);
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

  Team team(
    String id,
    String name, {
    String? owner,
    TeamRole role = TeamRole.owner,
    String city = 'Denver',
  }) => Team(
    id: id,
    name: name,
    division: Division.mixed,
    level: CompetitionLevel.club,
    city: city,
    ownerId: owner ?? testUser.uid,
    members: {
      owner ?? testUser.uid: TeamRole.owner,
      if (owner != null) testUser.uid: role,
    },
  );

  late FakeTeamRepository teams;
  late FakeEventRepository events;
  late FakeTeamPostRepository posts;

  Future<HomeViewModel> load({
    bool withTeam = true,
    bool withPersonal = false,
  }) async {
    teams = FakeTeamRepository();
    events = FakeEventRepository();
    posts = FakeTeamPostRepository();
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
    if (withTeam) {
      teams.teams['t1'] = team('t1', 'Northside Flyers');
      posts.posts['t1'] = [
        TeamPost(
          id: 'p1',
          title: 'Next stop: the postseason',
          body: 'A 15–11 win.',
          authorName: 'Theo Brooks',
          createdAt: now.subtract(const Duration(hours: 4)),
        ),
      ];
    }
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
      teamRepository: teams,
      eventRepository: events,
      teamPostRepository: posts,
      tournamentRepository: FakeTournamentRepository(tournaments),
      filePicker: FakeFilePickerService(),
      clock: () => now,
    );
    await pumpEventQueue();
    return vm;
  }

  group('HomeViewModel', () {
    test('features the next team event and lists the rest', () async {
      final vm = await load(withPersonal: true);
      expect(vm.firstName, 'Alex');
      expect(vm.nextTeamEvent?.event.id, 'prac');
      expect(vm.nextTeamEvent?.team?.id, 't1');
      // Team events lead each day; personal ones follow.
      expect(vm.upcomingEvents.map((e) => e.event.id), [
        'run',
        'regs',
        'lift',
        'far',
      ]);
      expect(vm.nextEventFor(vm.teams.single)?.event.id, 'prac');
    });

    test('personal events show without a team', () async {
      final vm = await load(withTeam: false, withPersonal: true);
      expect(vm.teamsLoaded, isTrue);
      expect(vm.nextTeamEvent, isNull);
      expect(vm.upcomingEvents.map((e) => e.event.id), ['run']);
      expect(vm.upcomingEvents.single.isPersonal, isTrue);
      expect(vm.postsLoaded, isTrue);
      expect(vm.posts, isEmpty);
    });

    test('the feed merges every team\'s posts, newest first', () async {
      final vm = await load();
      expect(vm.postsLoaded, isTrue);
      teams.teams['t2'] = team(
        't2',
        'Sunday pickup',
        owner: 'u9',
        role: TeamRole.player,
      );
      posts.posts['t2'] = [
        TeamPost(
          id: 'q1',
          body: 'Field 5 is booked.',
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
      ];
      await teams.updateTeam(teams.teams['t2']!);
      await pumpEventQueue();
      expect(vm.posts.map((p) => p.post.id), ['q1', 'p1']);
      expect(vm.posts.first.team.name, 'Sunday pickup');
      // Only teams the user runs take posts.
      expect(vm.postableTeams.map((t) => t.id), ['t1']);
    });

    test('posts go to the chosen team', () async {
      final vm = await load();
      await vm.savePost.execute((
        teamId: 't1',
        draft: const PostDraft(
          post: TeamPost(id: '', body: 'Bring cleats'),
        ),
      ));
      await pumpEventQueue();
      expect(vm.savePost.completed, isTrue);
      expect(vm.posts.map((p) => p.post.body), contains('Bring cleats'));
    });

    test('names the home city and the next tournament', () async {
      final vm = await load();
      expect(vm.homeCity, 'Denver');
      expect(vm.nextTournament?.id, 'next');
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
    testWidgets('community feed lays out at phone width ($name)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final vm = await tester.runAsync(() => load(withPersonal: true));
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: HomeScreen(viewModel: vm!),
        ),
      );
      await tester.pump();

      expect(find.text('Good things fly together.'), findsOneWidget);
      expect(find.text('DENVER / YOUR ULTIMATE COMMUNITY'), findsOneWidget);
      // The next event sits above the feed in place of the side column.
      expect(find.text('Thursday practice'), findsOneWidget);
      expect(find.text('Coming up'), findsOneWidget);
      expect(find.text("What's happening on your sideline?"), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Next stop: the postseason'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Theo Brooks'), findsOneWidget);
      expect(find.textContaining('Northside Flyers ·'), findsOneWidget);

      await tester.tap(find.text('Your teams'));
      await tester.pump();
      expect(find.text('Northside Flyers'), findsOneWidget);
      expect(
        find.text('Next: Thursday practice · Thu, Oct 29'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('community feed shows a side column at desktop width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = await tester.runAsync(() => load(withPersonal: true));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(viewModel: vm!),
      ),
    );
    await tester.pump();

    // What's up next sits in a right-hand column beside the feed.
    final feed = tester.getTopLeft(
      find.text("What's happening on your sideline?"),
    );
    final upNext = tester.getTopLeft(find.text('UP NEXT · NORTHSIDE FLYERS'));
    expect(upNext.dx, greaterThan(feed.dx + 400));
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.text('Fall Classic'), findsOneWidget);
    expect(find.text('Create post'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('community feed offers to join a team', (tester) async {
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
    expect(find.text('Join your team.'), findsOneWidget);
    await tester.tap(find.text('Join with code'));
    await tester.pumpAndSettle();
    expect(find.text('Invite code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
