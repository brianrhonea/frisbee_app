import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/calendar/calendar_repository.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/routing/push_team_route.dart';
import 'package:frisbee_app/ui/people/widgets/following_screen.dart';
import 'package:frisbee_app/ui/settings/widgets/settings_screen.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/personal/personal_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/meeting/meeting_repository.dart';
import 'package:frisbee_app/data/repositories/playbook/play_repository.dart';
import '../testing/mock_stats_repository.dart';
import 'package:frisbee_app/data/repositories/profile/profile_repository.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/data/repositories/stats/stats_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/team_post/team_post_repository.dart';
import 'package:frisbee_app/data/repositories/theme/theme_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/routing/open_link.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:frisbee_app/ui/learn/widgets/learn_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_detail_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_editor_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/my_event_detail_screen.dart';
import 'package:frisbee_app/ui/meetings/widgets/meetings_list_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/team_events_tab.dart';
import 'package:frisbee_app/ui/teams/widgets/members_tab.dart';
import 'package:frisbee_app/ui/teams/widgets/roster_tab.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_section_screen.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/data/repositories/follow/follow_repository.dart';
import 'package:frisbee_app/data/repositories/group_tournament/group_tournament_repository.dart';
import 'package:frisbee_app/data/repositories/post_comment/post_comment_repository.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository.dart';

import 'package:frisbee_app/data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/schedule_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournament_screen.dart';
import 'package:frisbee_app/utils/pending_removals.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';
import '../testing/group_tournament_fakes.dart';
import '../testing/social_fakes.dart';
import '../testing/meeting_fakes.dart';
import 'explore_test.dart' show FakeRankingRepository;

/// Event pages open over the current tab and back returns to it.
void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;
  late FakeUserPostRepository userPosts;
  late FakePostCommentRepository comments;
  late FakeDirectMessageRepository dms;
  late FakeFollowRepository follows;
  late FakeHostedTournamentRepository hosted;

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    teams = FakeTeamRepository();
    teams.teams['t1'] = Team(
      id: 't1',
      name: 'Northside Flyers',
      division: Division.mixed,
      level: CompetitionLevel.club,
      ownerId: testUser.uid,
      members: {testUser.uid: TeamRole.owner},
    );
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final day = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18);
    events = FakeEventRepository()
      ..events['e1'] = TeamEvent(
        id: 'e1',
        title: 'Team practice',
        startsAt: day,
      )
      ..mine[testUser.uid] = {
        'm1': TeamEvent(
          id: 'm1',
          title: 'Tempo run',
          type: EventType.workout,
          startsAt: day.add(const Duration(hours: 1)),
        ),
      };
    final auth = FakeAuthRepository(user: testUser);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
          ChangeNotifierProvider<PersonalDetailsRepository>(
            create: (_) => FakePersonalDetailsRepository(),
          ),
          Provider<TeamRepository>.value(value: teams),
          ChangeNotifierProvider<ThemeRepository>.value(
            value: FakeThemeRepository(),
          ),
          Provider<PlayRepository>.value(value: FakePlayRepository()),
          Provider<NotificationRepository>.value(
            value: FakeNotificationRepository(),
          ),
          Provider<DirectMessageRepository>.value(
            value: dms = FakeDirectMessageRepository(),
          ),
          Provider<ChatRepository>.value(value: FakeChatRepository()),
          Provider<FilePickerService>.value(value: FakeFilePickerService()),
          Provider<EventRepository>.value(value: events),
          Provider<MeetingRepository>.value(value: FakeMeetingRepository()),
          Provider<CalendarRepository>.value(value: FakeCalendarRepository()),
          Provider<TeamPostRepository>.value(value: FakeTeamPostRepository()),
          Provider<ProfileRepository>.value(value: FakeProfileRepository()),
          Provider<StatsRepository>.value(
            value: MockStatsRepository(teamRepository: teams),
          ),
          Provider<FollowRepository>.value(
            value: follows = FakeFollowRepository(),
          ),
          Provider<UserPostRepository>.value(
            value: userPosts = FakeUserPostRepository(),
          ),
          Provider<PostCommentRepository>.value(
            value: comments = FakePostCommentRepository(posts: userPosts),
          ),
          Provider<GroupTournamentRepository>.value(
            value: FakeGroupTournamentRepository(),
          ),
          Provider<HostedTournamentRepository>.value(
            value: hosted = FakeHostedTournamentRepository(),
          ),
          Provider<RankingRepository>.value(value: FakeRankingRepository()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router(
            auth,
            FakePersonalDetailsRepository(),
            FakeAgreementRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text).first;
    // Scrolling something already in view can tuck it under the team
    // page's pinned header.
    if (f.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
    }
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('a tournament the team was accepted into opens its page', (
    tester,
  ) async {
    await pumpApp(tester);
    final router = GoRouter.of(tester.element(find.byType(HomeScreen)));
    events.events['e2'] = TeamEvent(
      id: 'e2',
      title: 'Lone Star Classic',
      type: EventType.tournament,
      startsAt: DateTime.now().add(const Duration(days: 3)),
      tournamentId: 'x9',
    );
    unawaited(router.push(Routes.event('t1', 'e2')));
    await tester.pumpAndSettle();
    expect(find.byType(EventDetailScreen), findsOneWidget);
    await tapText(tester, 'Open tournament page');
    expect(find.byType(HostedTournamentScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(EventDetailScreen), findsOneWidget);
  });

  testWidgets("a tournament's host slides in over it; its tabs stay "
      'there and back returns to the tournament', (tester) async {
    await pumpApp(tester);
    final router = GoRouter.of(tester.element(find.byType(HomeScreen)));
    hosted.tournaments['x9'] = HostedTournament(
      id: 'x9',
      hostId: 't1',
      hostName: 'Northside Flyers',
      name: 'Lone Star Classic',
      startsOn: DateTime.now().add(const Duration(days: 3)),
    );
    unawaited(router.push(Routes.tournament('x9')));
    await tester.pumpAndSettle();
    await tapText(tester, 'Hosted by Northside Flyers');
    expect(find.byType(TeamHomeScreen), findsOneWidget);
    // Pushed over the tournament, not swapped for the Teams tab.
    expect(
      find.byType(HostedTournamentScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      GoRouterState.of(tester.element(find.byType(TeamHomeScreen))).uri.path,
      Routes.teamOver('t1'),
    );

    await tapText(tester, 'All events');
    final uri = GoRouterState.of(
      tester.element(find.byType(TeamHomeScreen)),
    ).uri;
    expect(uri.path, Routes.teamOver('t1'));
    expect(uri.queryParameters['section'], 'events');
    expect(
      find.byType(HostedTournamentScreen, skipOffstage: false),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HostedTournamentScreen), findsOneWidget);
    expect(find.byType(TeamHomeScreen), findsNothing);
  });

  testWidgets('team and personal events return to home', (tester) async {
    await pumpApp(tester);

    await tapText(tester, 'Team practice');
    expect(find.byType(EventDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(TeamHomeScreen), findsNothing);

    await tapText(tester, 'Tempo run');
    expect(find.byType(MyEventDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('new event opens over home; closing asks before discarding', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapText(tester, 'Add event');
    // They run a team, so Add event asks where it goes.
    await tapText(tester, 'My schedule');
    // A panel over home, not a page of its own.
    expect(find.byType(EventEditorScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    final close = find.descendant(
      of: find.byType(EventEditorScreen),
      matching: find.byTooltip('Close'),
    );

    // Nothing typed: closes straight away.
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(EventEditorScreen), findsNothing);

    // Something typed: asks first.
    await tapText(tester, 'Add event');
    await tapText(tester, 'My schedule');
    await tester.enterText(find.byType(TextFormField).first, 'Pickup');
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text('Discard this event?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(EventEditorScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(events.mine[testUser.uid]!.values.map((e) => e.title), [
      'Tempo run',
    ]);
  });

  testWidgets('saving a new event offers to view it; back returns home', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapText(tester, 'Add event');
    // They run a team, so Add event asks where it goes.
    await tapText(tester, 'My schedule');
    await tester.enterText(find.byType(TextFormField).first, 'Pickup');
    // Done typing: otherwise the focused field keeps scrolling back into view.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create event'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(EventEditorScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tapText(tester, 'Create event');
    // The panel closes and says so, with a way to open it.
    expect(find.byType(EventEditorScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Event created'), findsOneWidget);
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byType(MyEventDetailScreen), findsOneWidget);
    expect(find.text('Pickup'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a new event can be shared with followers', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Add event');
    await tapText(tester, 'My schedule');
    await tester.enterText(find.byType(TextFormField).first, 'Pickup');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final form = find
        .descendant(
          of: find.byType(EventEditorScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Share with followers'),
      300,
      scrollable: form,
    );
    await tapText(tester, 'Share with followers');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Say something (optional)'),
      'Bring a light and a dark',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create event'),
      300,
      scrollable: form,
    );
    await tapText(tester, 'Create event');

    expect(find.byType(EventEditorScreen), findsNothing);
    expect(
      find.text('Event created and shared with your followers'),
      findsOneWidget,
    );
    final post = userPosts.posts.single;
    expect(post.body, 'Bring a light and a dark');
    expect(post.event!.title, 'Pickup');
    expect(post.event!.teamId, isNull);
  });

  testWidgets('from a post page, the author opens their profile', (
    tester,
  ) async {
    await pumpApp(tester);
    userPosts.posts.add(
      UserPost(
        id: 'p1',
        authorId: 'sam',
        authorName: 'Sam Lee',
        body: 'Hello there',
        createdAt: DateTime(2026, 11, 1),
      ),
    );
    userPosts.changed();
    GoRouter.of(tester.element(find.byType(HomeScreen))).push('/posts/p1');
    await tester.pumpAndSettle();
    expect(find.text('Hello there'), findsOneWidget);
    // The post page sits over the tabs; the profile lives in one.
    await tester.tap(find.text('Sam Lee').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PlayerProfileScreen), findsOneWidget);
  });

  testWidgets('comment on a post from its page, and delete the comment', (
    tester,
  ) async {
    await pumpApp(tester);
    userPosts.posts.add(
      UserPost(
        id: 'p1',
        authorId: 'sam',
        authorName: 'Sam Lee',
        body: 'Hello there',
        createdAt: DateTime(2026, 11, 1),
      ),
    );
    userPosts.changed();
    // A post link (as sent in a message) opens the post at the comment box.
    GoRouter.of(
      tester.element(find.byType(HomeScreen)),
    ).push('/posts/p1?comment=1');
    await tester.pumpAndSettle();
    expect(find.text('No comments yet. Be the first.'), findsOneWidget);
    final box = find.widgetWithText(TextField, 'Add a comment…');
    expect(tester.widget<TextField>(box).focusNode!.hasFocus, isTrue);

    await tester.enterText(box, '  See you there!  ');
    await tester.pump();
    await tester.tap(find.byTooltip('Post comment'));
    await tester.pumpAndSettle();
    expect(find.text('See you there!'), findsOneWidget);
    expect(find.text('Comments (1)'), findsOneWidget);
    expect(comments.comments.single.authorId, testUser.uid);
    expect(userPosts.posts.single.commentCount, 1);
    // The footer counts it, and the box is empty for the next one.
    expect(find.text('1'), findsWidgets);
    expect(tester.widget<TextField>(box).controller!.text, isEmpty);

    // Someone else's comment can't be deleted by the user; their own can.
    await comments.addComment(
      'p1',
      'Me too',
      const AppUser(uid: 'zed', email: 'z@z.com', displayName: 'Zed'),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Delete comment'), findsOneWidget);
    // Gone at once, with Undo instead of "Are you sure?".
    await tester.tap(find.byTooltip('Delete comment'));
    await tester.pump();
    expect(find.text('See you there!'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(find.text('See you there!'), findsOneWidget);
    expect(userPosts.posts.single.commentCount, 2);

    await tester.tap(find.byTooltip('Delete comment'));
    await tester.pump();
    await tester.pump(PendingRemovals.undoWindow);
    await tester.pumpAndSettle();
    expect(find.text('See you there!'), findsNothing);
    expect(find.text('Me too'), findsOneWidget);
    expect(userPosts.posts.single.commentCount, 1);
  });

  testWidgets('send a post to someone in a message', (tester) async {
    await pumpApp(tester);
    dms.profiles.add(const UserProfile(uid: 'jo', name: 'Jo Park'));
    userPosts.posts.add(
      UserPost(
        id: 'p1',
        authorId: 'sam',
        authorName: 'Sam Lee',
        body: 'Pickup tonight at 6',
        createdAt: DateTime(2026, 11, 1),
      ),
    );
    userPosts.changed();
    GoRouter.of(tester.element(find.byType(HomeScreen))).push('/p/p1');
    await tester.pumpAndSettle();
    expect(find.text('Pickup tonight at 6'), findsOneWidget);

    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Search for someone to send this post to.'), findsOne);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search people by name'),
      'jo',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(find.text('Sent'), findsOneWidget);

    final sent = dms.messages[Conversation.idFor(testUser.uid, 'jo')]!.single;
    expect(sent.text, contains("Sam Lee's post"));
    expect(sent.text, contains('Pickup tonight at 6'));
    expect(sent.text, contains('/p/p1'));
  });

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Schedule is the calendar; events to find are on Discover', (
    tester,
  ) async {
    await pumpApp(tester);
    hosted.tournaments['x1'] = HostedTournament(
      id: 'x1',
      hostId: 'h',
      hostName: 'Austin Ultimate',
      name: 'Lone Star Classic',
      startsOn: DateTime.now().add(const Duration(days: 10)),
      status: HostedStatus.registration,
    );
    hosted.tournaments['x2'] = HostedTournament(
      id: 'x2',
      hostId: 'h',
      hostName: 'Austin Ultimate',
      name: 'Winter League',
      kind: HostedKind.league,
      startsOn: DateTime.now().add(const Duration(days: 12)),
      status: HostedStatus.registration,
    );
    await tapTab(tester, 'Schedule');
    expect(find.byType(ScheduleScreen), findsOneWidget);
    expect(find.byTooltip('New event'), findsOneWidget);
    // No switch to a second view any more.
    expect(find.text('My schedule'), findsNothing);
    expect(find.text('Find events'), findsNothing);

    // Discover lists them, with Host, and its filters narrow them.
    await tapTab(tester, 'Discover');
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.text('Lone Star Classic'), findsOneWidget);
    expect(find.text('Winter League'), findsOneWidget);
    await tapText(tester, 'Leagues');
    expect(find.text('Lone Star Classic'), findsNothing);
    expect(find.text('Winter League'), findsOneWidget);

    // The old link to events to find opens Discover.
    final router = GoRouter.of(tester.element(find.byType(ExploreScreen)));
    router.go(Routes.schedule);
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleScreen), findsOneWidget);
    router.go('/schedule?view=find');
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleScreen), findsNothing);
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect(router.state.uri.path, Routes.explorePath);

    // Old Explore links keep their search and filter; /discover works too.
    router.go('/explore?only=leagues&q=winter');
    await tester.pumpAndSettle();
    final screen = tester.widget<ExploreScreen>(find.byType(ExploreScreen));
    expect(screen.initialFilter, ExploreFilter.leagues);
    expect(screen.initialQuery, 'winter');
    router.go('/discover?only=teams');
    await tester.pumpAndSettle();
    expect(router.state.uri.path, Routes.explorePath);
    expect(
      tester.widget<ExploreScreen>(find.byType(ExploreScreen)).initialFilter,
      ExploreFilter.teams,
    );
  });

  testWidgets('with one team, the Teams tab shows the list', (tester) async {
    await pumpApp(tester);
    await tapTab(tester, 'Teams');
    // Never opens the only team by itself (F34): the list, with the team.
    expect(find.byType(TeamsScreen), findsOneWidget);
    expect(find.byType(TeamHomeScreen), findsNothing);
    expect(find.text('Northside Flyers'), findsWidgets);
    final router = GoRouter.of(tester.element(find.byType(TeamsScreen)));
    await tester.pump(const Duration(seconds: 1));
    expect(router.state.uri.path, Routes.teams);

    // Opening the team; back (All teams) is the list again.
    await tapText(tester, 'Northside Flyers');
    expect(find.byType(TeamHomeScreen), findsOneWidget);
    await tester.tap(find.byTooltip('All teams'));
    await tester.pumpAndSettle();
    expect(find.byType(TeamsScreen), findsOneWidget);
    expect(find.byType(TeamHomeScreen), findsNothing);

    // Away and back by the tab: still the list.
    await tapTab(tester, 'Home');
    await tapTab(tester, 'Teams');
    expect(find.byType(TeamsScreen), findsOneWidget);
    expect(find.byType(TeamHomeScreen), findsNothing);
  });

  testWidgets(
    'after a link to Discover (or an old Find teams link), the Teams tab is still the list',
    (tester) async {
      await pumpApp(tester);
      await tapTab(tester, 'Teams');
      final router = GoRouter.of(tester.element(find.byType(TeamsScreen)));
      router.go(Routes.explore(only: ExploreFilter.teams));
      await tester.pumpAndSettle();
      expect(find.byType(ExploreScreen), findsOneWidget);
      await tapTab(tester, 'Teams');
      expect(router.state.uri.path, Routes.teams);
      expect(find.byType(TeamsScreen), findsOneWidget);
      await tapTab(tester, 'Teams');
      expect(router.state.uri.path, Routes.teams);
      router.go(Routes.searchTeams);
      await tester.pumpAndSettle();
      await tapTab(tester, 'Home');
      await tapTab(tester, 'Teams');
      expect(router.state.uri.path, Routes.teams);
    },
  );

  testWidgets('a team page from a tournament opened in Discover slides in '
      'over it, and the Teams tab still opens the list', (tester) async {
    await pumpApp(tester);
    hosted.tournaments['x9'] = HostedTournament(
      id: 'x9',
      hostId: 't1',
      hostName: 'Northside Flyers',
      name: 'Lone Star Classic',
      startsOn: DateTime.now().add(const Duration(days: 3)),
    );
    await tapTab(tester, 'Discover');
    final router = GoRouter.of(tester.element(find.byType(ExploreScreen)));
    unawaited(router.push(Routes.tournament('x9')));
    await tester.pumpAndSettle();
    // As the tournament's Invite players does: pushing /teams/... over a
    // full-screen page stacked a second copy of the tabs.
    pushTeamRoute(
      tester.element(find.byType(HostedTournamentScreen)),
      Routes.teamMembers('t1'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(router.state.uri.path, Routes.teamOver('t1'));
    expect(router.state.uri.queryParameters['section'], 'members');
    expect(find.byType(TeamHomeScreen), findsOneWidget);

    // Deeper team pages switch to the Teams tab instead.
    pushTeamRoute(
      tester.element(find.byType(TeamHomeScreen)),
      Routes.teamRoles('t1'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(router.state.uri.path, Routes.teamRoles('t1'));

    router.go(Routes.explore());
    await tester.pumpAndSettle();
    await tapTab(tester, 'Teams');
    await tapTab(tester, 'Teams');
    expect(router.state.uri.path, Routes.teams);
    expect(find.byType(TeamsScreen), findsOneWidget);
    expect(find.byType(ExploreScreen).hitTestable(), findsNothing);
  });

  testWidgets('with one team and an invitation, the Teams tab shows both', (
    tester,
  ) async {
    await pumpApp(tester);
    teams.invites[testUser.uid] = [
      const TeamInvite(teamId: 't9', teamName: 'Mile High Masters'),
    ];
    await tapTab(tester, 'Teams');
    expect(find.byType(TeamsScreen), findsOneWidget);
    expect(find.byType(TeamHomeScreen), findsNothing);
    expect(find.textContaining('Mile High Masters'), findsWidgets);
  });

  testWidgets('with two teams, the Teams tab shows the list', (tester) async {
    await pumpApp(tester);
    teams.teams['t2'] = Team(
      id: 't2',
      name: 'Southside Sliders',
      division: Division.open,
      level: CompetitionLevel.club,
      ownerId: testUser.uid,
      members: {testUser.uid: TeamRole.owner},
    );
    await tapTab(tester, 'Teams');
    expect(find.byType(TeamsScreen), findsOneWidget);
    expect(find.byType(TeamHomeScreen), findsNothing);
    expect(find.text('Southside Sliders'), findsOneWidget);
  });

  testWidgets('the avatar opens the profile, which has no tab', (tester) async {
    await pumpApp(tester);
    expect(find.text('Profile'), findsNothing);
    await tester.tap(find.byTooltip('My profile'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerProfileScreen), findsOneWidget);
    // The tabs are still there to leave by.
    await tapText(tester, 'Home');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Learn to play opens from Settings and goes back there', (
    tester,
  ) async {
    await pumpApp(tester);
    final router = GoRouter.of(tester.element(find.byType(HomeScreen)));
    router.go(Routes.profile);
    await tester.pumpAndSettle();
    unawaited(router.push(Routes.settings));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Learn to play'));
    await tapText(tester, 'Learn to play');
    expect(find.byType(LearnScreen), findsOneWidget);
    expect(find.text('Ultimate in five minutes'), findsOneWidget);

    // The contents jump to a section.
    await tapText(tester, 'Turnovers');
    expect(find.text('the thrower is stalled out.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LearnScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('a team left on its roster does not hijack event links', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapText(tester, 'Teams');
    await tapText(tester, 'Northside Flyers');
    // Roster opens on the members, with the players beside them.
    await tapText(tester, 'Roster');
    expect(find.byType(MembersTab), findsOneWidget);
    await tapText(tester, 'Players');
    expect(find.byType(RosterTab), findsOneWidget);

    await tapText(tester, 'Home');
    await tapText(tester, 'Team practice');
    expect(find.byType(EventDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    // The Teams tab kept its place on the roster tab; Feed returns to the
    // team summary on the same page.
    await tapText(tester, 'Teams');
    expect(find.byType(RosterTab), findsOneWidget);
    await tapText(tester, 'Feed');
    expect(find.byType(RosterTab), findsNothing);
    expect(find.byType(TeamHomeScreen), findsOneWidget);
  });

  testWidgets('events from the team home page return to it', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Teams');
    await tapText(tester, 'Northside Flyers');
    expect(find.byType(TeamHomeScreen), findsOneWidget);
    await tapText(tester, 'Team practice');
    expect(find.byType(EventDetailScreen), findsOneWidget);
    // A popup over the team page (whose back is now "All teams").
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(EventDetailScreen), findsNothing);
    expect(find.byType(TeamHomeScreen), findsOneWidget);
  });

  testWidgets('events from the team schedule return to it', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Teams');
    await tapText(tester, 'Northside Flyers');
    await tapText(tester, 'Schedule');
    // The tab shows in place on the team page, as a list with no calendar.
    expect(find.byType(TeamHomeScreen), findsOneWidget);
    expect(find.byType(TeamEventsTab), findsOneWidget);
    expect(find.byTooltip('Next month'), findsNothing);
    await tapText(tester, 'Team practice');
    // The details and RSVP open in a popup over the tab.
    expect(find.byType(EventDetailScreen), findsOneWidget);
    expect(find.text('Going'), findsWidgets);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(EventDetailScreen), findsNothing);
    expect(find.byType(TeamEventsTab), findsOneWidget);
  });

  testWidgets('More lists the other sections and opens them', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Teams');
    await tapText(tester, 'Northside Flyers');
    await tapText(tester, 'More');
    for (final label in ['Playbook', 'Videos', 'Stats', 'Tournaments']) {
      expect(find.text(label), findsOneWidget);
    }
    await tapText(tester, 'Playbook');
    final home = tester.widget<TeamHomeScreen>(find.byType(TeamHomeScreen));
    expect(home.section, TeamSection.playbook);
    // Still under More.
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('More opens the team\'s Meetings list', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Teams');
    await tapText(tester, 'Northside Flyers');
    await tapText(tester, 'More');
    await tapText(tester, 'Meetings');
    expect(find.byType(MeetingsListScreen), findsOneWidget);
    expect(find.text('Coming up'.toUpperCase()), findsOneWidget);
  });

  testWidgets('old ?tab= team links open the matching section', (tester) async {
    await pumpApp(tester);
    GoRouter.of(
      tester.element(find.byType(HomeScreen)),
    ).go('/teams/t1?tab=schedule');
    await tester.pumpAndSettle();
    final home = tester.widget<TeamHomeScreen>(find.byType(TeamHomeScreen));
    expect(home.section, TeamSection.events);
    expect(find.byType(TeamEventsTab), findsOneWidget);
  });

  testWidgets('notification links open one after another', (tester) async {
    await pumpApp(tester);
    final router = GoRouter.of(tester.element(find.byType(HomeScreen)));
    // A play (over the tabs) loads the team into the Teams tab; a team
    // page opened after it must not stack a second copy of that team.
    unawaited(router.push('/notifications'));
    await tester.pumpAndSettle();
    router.openLink('/teams/t1/plays/p1');
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    unawaited(router.push('/notifications'));
    await tester.pumpAndSettle();
    router.openLink('/teams/t1/events');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TeamEventsTab), findsOneWidget);
  });

  testWidgets('People you follow returns to Settings', (tester) async {
    await pumpApp(tester);
    // Wide, where Settings is a side panel.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();
    // Home's top bar is a little tight at this size in the test font.
    tester.takeException();
    final router = GoRouter.of(tester.element(find.byType(HomeScreen)));
    router.go(Routes.profile);
    await tester.pumpAndSettle();
    unawaited(router.push(Routes.settings));
    await tester.pumpAndSettle();
    await tapText(tester, 'People you follow');
    expect(find.byType(FollowingScreen), findsOneWidget);

    // Its own back arrow, not one on the page behind.
    final back = find.descendant(
      of: find.byType(FollowingScreen),
      matching: find.byType(BackButton),
    );
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byType(FollowingScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Opening someone from there goes to their profile, without the
    // duplicate-page crash pushing a tab page over Settings caused.
    await follows.follow(testUser.uid, const FollowTarget.user('p2', 'Pat'));
    await tapText(tester, 'People you follow');
    await tapText(tester, 'Pat');
    expect(tester.takeException(), isNull);
    expect(find.byType(PlayerProfileScreen), findsOneWidget);
  });
}
