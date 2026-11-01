import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/meeting/meeting_repository.dart';
import 'package:frisbee_app/data/repositories/playbook/play_repository.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/data/repositories/stats/mock_stats_repository.dart';
import 'package:frisbee_app/data/repositories/stats/stats_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/team_post/team_post_repository.dart';
import 'package:frisbee_app/data/repositories/follow/follow_repository.dart';
import 'package:frisbee_app/data/repositories/group_tournament/group_tournament_repository.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository.dart';
import 'package:frisbee_app/data/repositories/theme/theme_repository.dart';
import 'package:frisbee_app/data/repositories/tournament/tournament_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/routing/open_link.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/data/repositories/usau_schedule/usau_schedule_repository.dart';
import 'package:frisbee_app/data/repositories/usau_team/usau_team_repository.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/tournament.dart';
import 'package:frisbee_app/domain/models/usau_team.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/events/widgets/events_screen.dart';
import 'package:frisbee_app/ui/rankings/widgets/rankings_screen.dart';
import 'package:frisbee_app/ui/rankings/widgets/usau_team_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/tournament_detail_screen.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_detail_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_editor_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/my_event_detail_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_section_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../testing/group_tournament_fakes.dart';
import '../testing/social_fakes.dart';
import '../testing/meeting_fakes.dart';

/// USA Ultimate team pages fail to load; these tests only navigate.
class _NoUsauTeams implements UsauTeamRepository {
  @override
  Future<Result<UsauTeam>> getTeam(String url) async =>
      Result.error(Exception('offline'));
}

/// Event pages open over the current tab and back returns to it.
void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size * 3;
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
          Provider<TeamRepository>.value(value: teams),
          ChangeNotifierProvider<ThemeRepository>.value(
            value: FakeThemeRepository(),
          ),
          Provider<PlayRepository>.value(value: FakePlayRepository()),
          Provider<NotificationRepository>.value(
            value: FakeNotificationRepository(),
          ),
          Provider<DirectMessageRepository>.value(
            value: FakeDirectMessageRepository(),
          ),
          Provider<ChatRepository>.value(value: FakeChatRepository()),
          Provider<FilePickerService>.value(value: FakeFilePickerService()),
          Provider<EventRepository>.value(value: events),
          Provider<MeetingRepository>.value(value: FakeMeetingRepository()),
          Provider<TeamPostRepository>.value(value: FakeTeamPostRepository()),
          Provider<FollowRepository>.value(value: FakeFollowRepository()),
          Provider<UserPostRepository>.value(value: FakeUserPostRepository()),
          Provider<GroupTournamentRepository>.value(
            value: FakeGroupTournamentRepository(),
          ),
          Provider<StatsRepository>.value(
            value: MockStatsRepository(teamRepository: teams),
          ),
          Provider<TournamentRepository>.value(
            value: FakeTournamentRepository([
              Tournament(
                id: 'fc',
                name: 'Fall Classic',
                url: '',
                startDate: DateTime.now().add(const Duration(days: 10)),
              ),
            ]),
          ),
          Provider<UsauScheduleRepository>.value(
            value: FakeUsauScheduleRepository(),
          ),
          Provider<RankingRepository>.value(
            value: FakeRankingRepository(const [
              RankingDivision(
                key: 'Club-Mixed',
                label: 'Club Mixed',
                entries: [
                  RankingEntry(
                    rank: 1,
                    teamName: 'Alpha',
                    rating: 2000,
                    teamUrl: 'https://example.com/alpha',
                  ),
                ],
              ),
            ]),
          ),
          Provider<UsauTeamRepository>.value(value: _NoUsauTeams()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router(auth),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text).first;
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  /// Taps a bottom navigation tab (the team page has a Home tab too).
  Future<void> tapNav(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps one of the team page's tabs.
  Future<void> tapTeamTab(WidgetTester tester, String label) async {
    final tab = find.descendant(
      of: find.byType(TabBar),
      matching: find.text(label),
    );
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  TeamSection? selectedSection(WidgetTester tester) =>
      tester.widget<TeamHomeScreen>(find.byType(TeamHomeScreen)).section;

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

  testWidgets('new event has a way back', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Add event');
    expect(find.byType(EventEditorScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('saving a new event shows it; back returns home', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Add event');
    await tester.enterText(find.byType(TextFormField).first, 'Pickup');
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
    expect(find.byType(MyEventDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a team left on its roster does not hijack event links', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapNav(tester, 'Teams');
    await tapText(tester, 'Northside Flyers');
    await tapTeamTab(tester, 'Roster');
    expect(find.byType(TeamSectionView), findsOneWidget);

    await tapNav(tester, 'Home');
    await tapText(tester, 'Team practice');
    expect(find.byType(EventDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    // The Teams tab kept its place, and back leaves the team.
    await tapNav(tester, 'Teams');
    expect(selectedSection(tester), TeamSection.roster);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TeamHomeScreen), findsNothing);
    expect(find.byType(TeamsScreen), findsOneWidget);
  });

  testWidgets('team tabs swap content in place; back leaves the team', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapNav(tester, 'Teams');
    await tapText(tester, 'Northside Flyers');
    final home = tester.state(find.byType(TeamHomeScreen));

    for (final tab in ['Roster', 'Chat', 'Members', 'Home', 'Team Events']) {
      await tapTeamTab(tester, tab);
      // Same page and header throughout; only the content changes.
      expect(tester.state(find.byType(TeamHomeScreen)), same(home));
      expect(find.byType(TabBar), findsOneWidget);
    }
    expect(selectedSection(tester), TeamSection.events);
    expect(find.byType(TeamSectionView), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TeamHomeScreen), findsNothing);
    expect(find.byType(TeamsScreen), findsOneWidget);
  });

  testWidgets('events from the team home page return to it', (tester) async {
    await pumpApp(tester);
    await tapNav(tester, 'Teams');
    await tapText(tester, 'Northside Flyers');
    expect(find.byType(TeamHomeScreen), findsOneWidget);
    await tapText(tester, 'Team practice');
    expect(find.byType(EventDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TeamHomeScreen), findsOneWidget);
  });

  testWidgets('events from Team Events return to it', (tester) async {
    await pumpApp(tester);
    await tapNav(tester, 'Teams');
    await tapText(tester, 'Northside Flyers');
    await tapTeamTab(tester, 'Team Events');
    expect(find.byType(TeamSectionView), findsOneWidget);
    await tapText(tester, 'Team practice');
    expect(find.byType(EventDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(selectedSection(tester), TeamSection.events);
    expect(find.byType(TeamSectionView), findsOneWidget);
  });

  group('USA Ultimate pages open over the tab they came from', () {
    Finder inNavBar(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

    testWidgets('a tournament from Events returns to Events', (tester) async {
      await pumpApp(tester);
      await tapNav(tester, 'Events');
      await tapText(tester, 'Fall Classic');
      expect(find.byType(TournamentDetailScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(EventsScreen), findsOneWidget);
      expect(find.byType(TournamentDetailScreen), findsNothing);
    });

    testWidgets('a ranked team from Home returns Home, not to Rankings', (
      tester,
    ) async {
      // Home shows rankings in the wide (dashboard) layout.
      await pumpApp(tester, size: const Size(1400, 1000));
      await tapText(tester, 'Alpha');
      expect(find.byType(UsauTeamScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(RankingsScreen), findsNothing);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        0,
      );
    });

    testWidgets('a team from Rankings returns to Rankings', (tester) async {
      await pumpApp(tester);
      await tapNav(tester, 'Rankings');
      await tapText(tester, 'Alpha');
      expect(find.byType(UsauTeamScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(RankingsScreen), findsOneWidget);
      expect(inNavBar('Rankings'), findsOneWidget);
    });

    testWidgets('a tournament link has a way back to Events', (tester) async {
      await pumpApp(tester);
      GoRouter.of(
        tester.element(find.byType(HomeScreen)),
      ).go(Routes.tournament('fc'));
      await tester.pumpAndSettle();
      expect(find.byType(TournamentDetailScreen), findsOneWidget);
      await tester.tap(find.byType(BackButtonIcon));
      await tester.pumpAndSettle();
      expect(find.byType(EventsScreen), findsOneWidget);
    });
  });

  testWidgets('old ?tab= team links open the matching section', (tester) async {
    await pumpApp(tester);
    GoRouter.of(
      tester.element(find.byType(HomeScreen)),
    ).go('/teams/t1?tab=schedule');
    await tester.pumpAndSettle();
    expect(selectedSection(tester), TeamSection.events);
    expect(find.byType(TeamSectionView), findsOneWidget);
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
    expect(selectedSection(tester), TeamSection.events);
    expect(find.byType(TeamSectionView), findsOneWidget);
  });
}
