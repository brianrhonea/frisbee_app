import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/posts/view_models/home_feed.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/domain/models/feed_item.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/domain/models/tournament.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/home/view_models/home_viewmodel.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_editor_screen.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

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
  late FakeFollowRepository follows;
  late FakeUserPostRepository userPosts;

  Future<HomeViewModel> load({
    bool withTeam = true,
    bool withPersonal = false,
  }) async {
    teams = FakeTeamRepository();
    events = FakeEventRepository();
    posts = FakeTeamPostRepository();
    follows = FakeFollowRepository();
    userPosts = FakeUserPostRepository();
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
      followRepository: follows,
      userPostRepository: userPosts,
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
      expect(vm.posts.map((p) => p.id), ['team/t2/q1', 'team/t1/p1']);
      expect((vm.posts.first as TeamPostItem).teamName, 'Sunday pickup');
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
      expect(
        vm.posts.map((p) => (p as TeamPostItem).post.body),
        contains('Bring cleats'),
      );
    });

    UserPost userPost(String id, String author, DateTime at) => UserPost(
      id: id,
      authorId: author,
      authorName: author == testUser.uid ? 'Alex' : 'Sam',
      body: 'Post $id',
      createdAt: at,
    );

    test('the feed adds my posts and those of people I follow', () async {
      final vm = await load();
      userPosts.posts.addAll([
        userPost('mine', testUser.uid, DateTime(2026, 10, 27)),
        userPost('sam', 'sam', DateTime(2026, 10, 28)),
        userPost('stranger', 'zed', DateTime(2026, 10, 28, 1)),
      ]);
      await follows.follow(testUser.uid, const FollowTarget.user('sam', 'Sam'));
      await pumpEventQueue();
      expect(vm.posts.map((i) => i.id), [
        'team/t1/p1',
        'user/sam',
        'user/mine',
      ]);
      expect(vm.followsAnything, isTrue);

      await follows.unfollow(testUser.uid, FollowTarget.userKey('sam'));
      await pumpEventQueue();
      expect(vm.posts.map((i) => i.id), ['team/t1/p1', 'user/mine']);
    });

    test('older posts load a page at a time, with no gaps', () async {
      final vm = await load();
      // Newer than the team post, so my posts fill the first pages.
      userPosts.posts.addAll([
        for (var i = 0; i < 45; i++)
          userPost(
            'm$i',
            testUser.uid,
            DateTime(2026, 11, 1).add(Duration(hours: i)),
          ),
      ]);
      userPosts.changed();
      await pumpEventQueue();
      expect(vm.posts, hasLength(HomeFeed.pageSize));
      expect(vm.posts.first.id, 'user/m44');
      expect(vm.hasMorePosts, isTrue);

      vm.loadMorePosts();
      await pumpEventQueue();
      expect(userPosts.fetches, 1, reason: 'one page read, not a re-read');
      expect(vm.posts, hasLength(40));
      expect(vm.posts.last.id, 'user/m5');

      vm.loadMorePosts();
      await pumpEventQueue();
      // All 45 and then the older team post, in order.
      expect(vm.posts.map((i) => i.id).take(46).last, 'team/t1/p1');
      expect(vm.posts.map((i) => i.id).toSet(), hasLength(vm.posts.length));
      expect(vm.hasMorePosts, isFalse);
    });

    test("teammates see events shared from the team's schedule", () async {
      final vm = await load();
      SharedEvent shared(String teamId) => SharedEvent(
        eventId: 'e-$teamId',
        title: 'Showcase',
        startsAt: DateTime(2026, 11, 7, 18),
        teamId: teamId,
      );
      userPosts.posts.addAll([
        // By a coach I don't follow, from my team's schedule.
        userPost(
          'coach',
          'coach',
          DateTime(2026, 10, 28),
        ).copyWith(event: () => shared('t1')),
        // From a team I'm not on.
        userPost(
          'other',
          'zed',
          DateTime(2026, 10, 28, 1),
        ).copyWith(event: () => shared('other')),
      ]);
      userPosts.changed();
      await pumpEventQueue();
      expect(vm.posts.map((i) => i.id), contains('user/coach'));
      expect(vm.posts.map((i) => i.id), isNot(contains('user/other')));

      // Following the coach as well doesn't show it twice.
      await follows.follow(
        testUser.uid,
        const FollowTarget.user('coach', 'Coach'),
      );
      await pumpEventQueue();
      expect(vm.posts.where((i) => i.id == 'user/coach'), hasLength(1));
    });

    test("teammates don't get reposts of the team's events", () async {
      final vm = await load();
      final shared = SharedEvent(
        eventId: 'e1',
        title: 'Showcase',
        startsAt: DateTime(2026, 11, 7, 18),
        teamId: 't1',
      );
      userPosts.posts.addAll([
        userPost(
          'coach',
          'coach',
          DateTime(2026, 10, 28),
        ).copyWith(event: () => shared),
        UserPost(
          id: 'echo',
          authorId: 'zed',
          event: shared,
          repostOf: const RepostOf(postId: 'coach', authorId: 'coach'),
          createdAt: DateTime(2026, 10, 28, 2),
        ),
      ]);
      userPosts.changed();
      await pumpEventQueue();
      expect(vm.posts.map((i) => i.id), contains('user/coach'));
      expect(vm.posts.map((i) => i.id), isNot(contains('user/echo')));
    });

    test('followed teams I am not on show only their public posts', () async {
      final vm = await load();
      posts.posts['other'] = [
        TeamPost(id: 'pub', body: 'Open tryouts', isPublic: true),
        const TeamPost(id: 'priv', body: 'Members only'),
      ];
      await follows.follow(
        testUser.uid,
        const FollowTarget.team('other', 'Other'),
      );
      await pumpEventQueue();
      expect(vm.posts.map((i) => i.id), contains('team/other/pub'));
      expect(vm.posts.map((i) => i.id), isNot(contains('team/other/priv')));
      // Not on that team, so no editing its posts.
      final pub = vm.posts.whereType<TeamPostItem>().firstWhere(
        (p) => p.teamId == 'other',
      );
      expect(vm.canEditPost(pub), isFalse);
    });

    test('names the next tournament', () async {
      final vm = await load();
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

      // No page header; the composer is the way to post.
      expect(find.text('Good things fly together.'), findsNothing);
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

      await tester.ensureVisible(find.text('Your teams'));
      await tester.pump();
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
    // One way to post: the composer, not a second header button.
    expect(find.text('Create post'), findsNothing);
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

  testWidgets('Add event in Coming up asks where; closing adds nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = await tester.runAsync(() => load());
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => HomeScreen(viewModel: vm!),
        ),
      ],
      // Every other page: say where we went.
      errorBuilder: (_, state) => Text('Went to ${state.uri.path}'),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(
            value: FakeAuthRepository(user: testUser),
          ),
          Provider<TeamRepository>.value(value: teams),
          Provider<EventRepository>.value(value: events),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pump();

    // Events are added from Coming up, not the post composer.
    expect(find.widgetWithText(TextButton, 'Event'), findsNothing);
    expect(find.text('Coming up'), findsOneWidget);

    Future<void> openPicker() async {
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Add event'));
      await tester.tap(find.widgetWithText(TextButton, 'Add event'));
      await tester.pumpAndSettle();
      expect(find.text('Add an event to'), findsOneWidget);
    }

    // Clicking outside closes it and stays put.
    await openPicker();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Add an event to'), findsNothing);
    expect(find.textContaining('Went to'), findsNothing);

    // Picking My schedule opens a new personal event over home.
    await openPicker();
    await tester.tap(find.text('My schedule'));
    await tester.pumpAndSettle();
    expect(find.byType(EventEditorScreen), findsOneWidget);
    expect(find.textContaining('Went to'), findsNothing);
  });
}
