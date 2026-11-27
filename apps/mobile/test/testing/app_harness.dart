// Pumps the real router and shell over fakes, for navigation tests.
// ignore_for_file: unused_local_variable
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/calendar/calendar_repository.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/personal/personal_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/meeting/meeting_repository.dart';
import 'package:frisbee_app/data/repositories/playbook/play_repository.dart';
import 'mock_stats_repository.dart';
import 'package:frisbee_app/data/repositories/profile/profile_repository.dart';
import 'package:frisbee_app/data/repositories/stats/stats_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/team_post/team_post_repository.dart';
import 'package:frisbee_app/data/repositories/theme/theme_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/home/widgets/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/data/repositories/follow/follow_repository.dart';
import 'package:frisbee_app/data/repositories/group_tournament/group_tournament_repository.dart';
import 'package:frisbee_app/data/repositories/post_comment/post_comment_repository.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository.dart';
import 'package:frisbee_app/data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/data/repositories/video/video_repository.dart';
import 'package:frisbee_app/data/repositories/voice/voice_repository.dart';
import 'package:frisbee_app/data/repositories/workout_recorder/workout_recorder.dart';
import 'package:frisbee_app/data/services/location_service.dart';
import '../data/workout_recorder_test.dart' show FakeLocationService;
import 'package:frisbee_app/data/services/youtube_info_service.dart';
import 'video_fakes.dart';
import 'voice_fakes.dart';
import 'fakes.dart';
import 'hosted_tournament_fakes.dart';
import 'group_tournament_fakes.dart';
import 'social_fakes.dart';
import 'meeting_fakes.dart';
import '../ui/explore_test.dart' show FakeRankingRepository;

class AppFakes {
  AppFakes(this.teams, this.events, this.auth);
  final FakeTeamRepository teams;
  final FakeEventRepository events;
  final FakeAuthRepository auth;
}

Future<AppFakes> pumpFullApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  bool signedIn = true,
}) async {
  final location = FakeLocationService();
  late FakeUserPostRepository userPosts;
  late FakePostCommentRepository comments;
  late FakeDirectMessageRepository dms;
  late FakeFollowRepository follows;
  late FakeHostedTournamentRepository hosted;
  late FakeTeamRepository teams;
  late FakeEventRepository events;
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
    ..events['e1'] = TeamEvent(id: 'e1', title: 'Team practice', startsAt: day)
    ..mine[testUser.uid] = {
      'm1': TeamEvent(
        id: 'm1',
        title: 'Tempo run',
        type: EventType.workout,
        startsAt: day.add(const Duration(hours: 1)),
      ),
    };
  final auth = FakeAuthRepository(user: signedIn ? testUser : null);
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
        Provider<VideoRepository>.value(value: FakeVideoRepository()),
        ChangeNotifierProvider<VoiceRepository>.value(
          value: FakeVoiceRepository(),
        ),
        Provider<YouTubeInfoService>.value(value: FakeYouTubeInfoService()),
        Provider<LocationService>.value(value: location),
        ChangeNotifierProvider<WorkoutRecorder>(
          create: (_) => WorkoutRecorder(location: location),
        ),
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
  if (signedIn) expect(find.byType(HomeScreen), findsOneWidget);
  return AppFakes(teams, events, auth);
}
