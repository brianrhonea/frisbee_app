import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/playbook/play_repository.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/data/repositories/stats/mock_stats_repository.dart';
import 'package:frisbee_app/data/repositories/stats/stats_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/team_post/team_post_repository.dart';
import 'package:frisbee_app/data/repositories/theme/theme_repository.dart';
import 'package:frisbee_app/data/repositories/tournament/tournament_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_detail_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/event_editor_screen.dart';
import 'package:frisbee_app/ui/schedule/widgets/my_event_detail_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_section_screen.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';

/// Event pages open over the current tab and back returns to it.
void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;

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
          Provider<TeamPostRepository>.value(value: FakeTeamPostRepository()),
          Provider<StatsRepository>.value(
            value: MockStatsRepository(teamRepository: teams),
          ),
          Provider<TournamentRepository>.value(
            value: FakeTournamentRepository(const []),
          ),
          Provider<RankingRepository>.value(
            value: FakeRankingRepository(const []),
          ),
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
    await tapText(tester, 'Teams');
    await tapText(tester, 'Northside Flyers');
    await tapText(tester, 'Roster');
    expect(find.byType(TeamSectionScreen), findsOneWidget);

    await tapText(tester, 'Home');
    await tapText(tester, 'Team practice');
    expect(find.byType(EventDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    // The Teams tab kept its place, and back returns to the team home.
    await tapText(tester, 'Teams');
    expect(find.byType(TeamSectionScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TeamHomeScreen), findsOneWidget);
  });

  testWidgets('events from the team home page return to it', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Teams');
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
    await tapText(tester, 'Teams');
    await tapText(tester, 'Northside Flyers');
    await tapText(tester, 'Team Events');
    expect(find.byType(TeamSectionScreen), findsOneWidget);
    await tapText(tester, 'Team practice');
    expect(find.byType(EventDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TeamSectionScreen), findsOneWidget);
  });

  testWidgets('old ?tab= team links open the matching section', (tester) async {
    await pumpApp(tester);
    GoRouter.of(
      tester.element(find.byType(HomeScreen)),
    ).go('/teams/t1?tab=schedule');
    await tester.pumpAndSettle();
    final section = tester.widget<TeamSectionScreen>(
      find.byType(TeamSectionScreen),
    );
    expect(section.section, TeamSection.events);
    expect(find.text('Team Events'), findsOneWidget);
  });
}
