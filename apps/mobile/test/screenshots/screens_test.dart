// Phone screenshots of the main screens, on fake data, for design review.
// Skipped unless asked for:
//   flutter test test/screenshots --dart-define=SCREENSHOTS=<out dir>
// writes <out dir>/<name>.png at 390x844 (iPhone 14/15) with the app's
// Inter font and Material icons, so the text is real, not test boxes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/calendar/calendar_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/follow/follow_repository.dart';
import 'package:frisbee_app/data/repositories/group_tournament/group_tournament_repository.dart';
import 'package:frisbee_app/data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import 'package:frisbee_app/data/repositories/meeting/meeting_repository.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/personal/personal_repository.dart';
import 'package:frisbee_app/data/repositories/playbook/play_repository.dart';
import 'package:frisbee_app/data/repositories/post_comment/post_comment_repository.dart';
import 'package:frisbee_app/data/repositories/profile/profile_repository.dart';
import 'package:frisbee_app/data/repositories/stats/stats_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/team_post/team_post_repository.dart';
import 'package:frisbee_app/data/repositories/theme/theme_repository.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository.dart';
import 'package:frisbee_app/data/repositories/voice/voice_repository.dart';
import 'package:frisbee_app/data/repositories/people/people_repository.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository.dart';
import 'package:frisbee_app/data/repositories/video/video_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../testing/group_tournament_fakes.dart';
import '../testing/hosted_tournament_fakes.dart';
import '../testing/meeting_fakes.dart';
import '../testing/mock_stats_repository.dart';
import '../testing/social_fakes.dart';
import '../testing/voice_fakes.dart';
import '../testing/video_fakes.dart';
import '../ui/explore_test.dart' show FakeRankingRepository;

const _out = String.fromEnvironment('SCREENSHOTS');

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('Inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      'assets/fonts/Inter-$w.ttf',
  ]);
  // The test runs under <flutter>/bin/cache/...; find the SDK's icon font.
  var dir = File(Platform.resolvedExecutable).parent;
  const icons = 'bin/cache/artifacts/material_fonts/materialicons-regular.otf';
  while (!File('${dir.path}/$icons').existsSync() && dir.parent != dir) {
    dir = dir.parent;
  }
  await family('MaterialIcons', ['${dir.path}/$icons']);
}

void main() {
  final skip = _out.isEmpty ? 'pass --dart-define=SCREENSHOTS=<dir>' : null;

  late FakeTeamRepository teams;
  late GoRouter appRouter;
  final shot = GlobalKey();

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    DateTime at(int days, int hour) =>
        DateTime(now.year, now.month, now.day + days, hour);

    teams = FakeTeamRepository();
    teams.teams['t1'] = Team(
      id: 't1',
      name: 'Northside Flyers',
      division: Division.mixed,
      level: CompetitionLevel.club,
      city: 'Denver',
      ownerId: 'coach',
      members: {
        'coach': TeamRole.owner,
        testUser.uid: TeamRole.player,
        'sam': TeamRole.player,
        'jo': TeamRole.player,
      },
    );
    teams.teams['t2'] = Team(
      id: 't2',
      name: 'State Ultimate',
      division: Division.open,
      level: CompetitionLevel.college,
      city: 'Boulder',
      ownerId: 'cap',
      members: {'cap': TeamRole.owner, testUser.uid: TeamRole.player},
    );
    teams.teams['g1'] = Team(
      id: 'g1',
      name: 'Denver Thursday Pickup',
      kind: TeamKind.community,
      division: Division.mixed,
      level: CompetitionLevel.pickup,
      ownerId: 'org',
      members: {'org': TeamRole.owner, testUser.uid: TeamRole.player},
    );

    final events = FakeEventRepository()
      ..events['e1'] = TeamEvent(
        id: 'e1',
        title: 'Practice: zone offense',
        startsAt: at(1, 18),
        location: 'City Park, field 3',
      )
      ..events['e2'] = TeamEvent(
        id: 'e2',
        title: 'Mile High Open',
        type: EventType.tournament,
        startsAt: at(4, 8),
        location: 'Aurora Sports Park',
      )
      ..mine[testUser.uid] = {
        'm1': TeamEvent(
          id: 'm1',
          title: 'Tempo run',
          type: EventType.workout,
          startsAt: at(2, 7),
        ),
      };

    final chat = FakeChatRepository()
      ..rooms['general'] = ChatRoom.general()
      ..rooms['lines'] = const ChatRoom(id: 'lines', name: 'Lines & strategy')
      ..rooms['rides'] = const ChatRoom(id: 'rides', name: 'Carpool');
    chat.messages['general'] = [
      ChatMessage(
        id: 'c1',
        authorId: 'coach',
        authorName: 'Coach Rivera',
        text: 'Field 3 tomorrow, bring both jerseys. Cones by 5:45.',
        createdAt: at(0, 9),
      ),
      ChatMessage(
        id: 'c2',
        authorId: 'sam',
        authorName: 'Sam Lee',
        text: "I'll bring the pull timer",
        createdAt: at(0, 10),
      ),
    ];

    final dms = FakeDirectMessageRepository();
    final me = testUser;
    for (final (uid, name, text) in [
      ('sam', 'Sam Lee', 'Want to throw before practice?'),
      ('jo', 'Jo Park', 'Sending the hotel info for Mile High tonight'),
    ]) {
      final other = UserProfile(uid: uid, name: name);
      dms.profiles.add(other);
      await dms.openConversation(me, other);
      await dms.sendMessage(
        Conversation.idFor(me.uid, uid),
        author: AppUser(uid: uid, displayName: name),
        text: text,
      );
    }

    final posts = FakeUserPostRepository();
    posts.posts.addAll([
      UserPost(
        id: 'p1',
        authorId: 'jo',
        authorName: 'Jo Park',
        body:
            'Huge layout D in the semis today. This team is going places. '
            'Thanks everyone who came out to cheer!',
        likedBy: const ['sam', 'coach'],
        commentCount: 3,
        createdAt: at(0, 8),
      ),
      UserPost(
        id: 'p2',
        authorId: 'sam',
        authorName: 'Sam Lee',
        body: 'Track session done. 6x400 at 1:20, legs are toast.',
        createdAt: at(-1, 19),
      ),
    ]);

    final hosted = FakeHostedTournamentRepository()
      ..tournaments['x9'] = HostedTournament(
        id: 'x9',
        hostId: 'g1',
        hostName: 'Denver Thursday Pickup',
        name: 'Mile High Open',
        startsOn: at(4, 8),
        endsOn: at(5, 8),
        location: 'Aurora Sports Park',
        status: HostedStatus.scheduled,
      );

    final auth = FakeAuthRepository(user: testUser);
    appRouter = router(auth, FakePersonalDetailsRepository());
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MultiProvider(
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
            Provider<DirectMessageRepository>.value(value: dms),
            Provider<ChatRepository>.value(value: chat),
            Provider<FilePickerService>.value(value: FakeFilePickerService()),
            Provider<EventRepository>.value(value: events),
            Provider<MeetingRepository>.value(value: FakeMeetingRepository()),
            Provider<CalendarRepository>.value(value: FakeCalendarRepository()),
            Provider<TeamPostRepository>.value(value: FakeTeamPostRepository()),
            Provider<ProfileRepository>.value(value: FakeProfileRepository()),
            Provider<StatsRepository>.value(
              value: MockStatsRepository(teamRepository: teams),
            ),
            Provider<FollowRepository>.value(value: FakeFollowRepository()),
            Provider<UserPostRepository>.value(value: posts),
            Provider<PostCommentRepository>.value(
              value: FakePostCommentRepository(posts: posts),
            ),
            Provider<GroupTournamentRepository>.value(
              value: FakeGroupTournamentRepository(),
            ),
            Provider<HostedTournamentRepository>.value(value: hosted),
            ChangeNotifierProvider<PeopleRepository>(
              create: (_) => FakePeopleRepository(),
            ),
            Provider<RankingRepository>.value(value: FakeRankingRepository()),
            Provider<VideoRepository>.value(value: FakeVideoRepository()),
            ChangeNotifierProvider<VoiceRepository>.value(
              value: FakeVoiceRepository(me: testUser.uid),
            ),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            routerConfig: appRouter,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> go(WidgetTester tester, String location) async {
    appRouter.go(location);
    await tester.pumpAndSettle();
  }

  testWidgets('main screens', skip: skip != null, (tester) async {
    await pumpApp(tester);
    await capture(tester, '01-home');
    await go(tester, Routes.explorePath);
    await capture(tester, '02-explore');
    await go(tester, Routes.schedule);
    await capture(tester, '03-events');
    await go(tester, Routes.teams);
    await capture(tester, '04-teams');
    await go(tester, Routes.team('t1'));
    await capture(tester, '05-team-feed');
    await go(tester, Routes.teamChat('t1'));
    await capture(tester, '06-team-chat');
    await go(tester, Routes.teamSection('t1', 'more'));
    await capture(tester, '07-team-more');
    await go(tester, Routes.messages);
    await capture(tester, '08-messages');
    await go(tester, Routes.tournament('x9'));
    await capture(tester, '09-tournament');
  });
}
