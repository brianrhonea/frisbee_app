// TEMPORARY (redesign 3e): Home, Discover, profiles, posts and
// notifications screenshots, on fake data, for design review.
// Skipped unless asked for:
//   flutter test test/screenshots --dart-define=SCREENSHOTS=<out dir>
// (add --dart-define=SHOT_THEME=dark for the dark theme)
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
import 'package:frisbee_app/data/services/location_service.dart';
import 'package:frisbee_app/data/repositories/workout_recorder/workout_recorder.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/workout_recorder_test.dart' show FakeLocationService;
import 'shot_env.dart';
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
const _dark = String.fromEnvironment('SHOT_THEME') == 'dark';

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
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'])
      'assets/fonts/Inter-$w.ttf',
  ]);
  await family('Barlow Condensed', [
    for (final w in ['Bold', 'ExtraBold', 'ExtraBoldItalic'])
      'assets/fonts/BarlowCondensed-$w.ttf',
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
    tester.view.physicalSize = const Size(shotWidth * 3.0, shotHeight * 3.0);
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

    // Northside Flyers are playing the Mile High Open today, and the user
    // captains them: Home and the team page show the tournament-day card.
    final hosted = FakeHostedTournamentRepository();
    seedLiveTournament(hosted, now: now, captains: [testUser.uid]);

    // Seeds for the redesign screenshots.
    teams.teams['g2'] = Team(
      id: 'g2',
      name: 'Lake Pickup',
      kind: TeamKind.community,
      division: Division.mixed,
      level: CompetitionLevel.pickup,
      ownerId: testUser.uid,
      members: {testUser.uid: TeamRole.owner},
      requiresApproval: true,
    );
    teams.joinRequests['g2'] = [
      const GroupJoinRequest(uid: 'u2', name: 'Kai'),
      const GroupJoinRequest(uid: 'u3', name: 'Rae'),
    ];
    final teamPosts = FakeTeamPostRepository();
    teamPosts.posts['t1'] = [
      TeamPost(
        id: 'tp1',
        title: 'Saturday: bring both jerseys',
        body:
            '2-0 in pool play. Lunch is at the tent behind Field 2, back on '
            'the line by 1:15 for Mesa.',
        authorId: 'coach',
        authorName: 'Coach Rivera',
        createdAt: at(0, 7),
      ),
    ];
    final profiles = FakeProfileRepository();
    const season = StatTotals(
      games: 18,
      points: 214,
      goals: 23,
      assists: 41,
      blocks: 12,
      completions: 310,
      throwaways: 19,
      catches: 140,
      drops: 4,
    );
    profiles.profiles['jo'] = PlayerProfile(
      uid: 'jo',
      name: 'Jo Park',
      username: 'jopark',
      details: const ProfileDetails(
        hometown: 'Denver',
        bio: 'Handler. Will throw for snacks.',
      ),
      summary: ProfileSummary(
        teams: const [
          ProfileTeam(
            id: 't1',
            name: 'Northside Flyers',
            subtitle: 'Club · Mixed',
            number: 7,
            position: 'Handler',
          ),
          ProfileTeam(
            id: 'g1',
            name: 'Denver Thursday Pickup',
            kind: TeamKind.community,
          ),
        ],
        seasons: {'${now.year}': season},
      ),
    );
    final follows = FakeFollowRepository();
    await follows.follow(
      testUser.uid,
      const FollowTarget.user('jo', 'Jo Park'),
    );
    await follows.follow(
      testUser.uid,
      const FollowTarget.user('sam', 'Sam Lee'),
      notify: true,
    );
    await follows.follow(
      testUser.uid,
      const FollowTarget.team('t2', 'State Ultimate'),
    );
    final rankings = FakeRankingRepository()
      ..initialRankings = [
        DivisionRanking(
          level: CompetitionLevel.club,
          division: Division.mixed,
          teams: [
            for (final (i, (id, name)) in [
              ('m1', 'Mesa Mavericks'),
              ('b1', 'Boulder Gold'),
              ('t1', 'Northside Flyers'),
              ('f1', 'Front Range Mixed'),
              ('s1', 'Springs Cyclones'),
            ].indexed)
              RankedTeam(
                rank: i + 1,
                teamId: id,
                name: name,
                rating: 1842 - i * 46,
                wins: 14 - i,
                losses: 2 + i,
              ),
          ],
        ),
      ];

    final location = FakeLocationService();
    final auth = FakeAuthRepository(user: testUser);
    appRouter = router(
      auth,
      FakePersonalDetailsRepository(),
      FakeAgreementRepository(),
    );
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
              value: FakeNotificationRepository(
                feed: [
                  AppNotification(
                    id: 'n1',
                    category: NotificationCategory.social,
                    title: 'Sam Lee liked your post',
                    body: 'Track session done. 6x400 at 1:20',
                    createdAt: at(0, 9),
                  ),
                  AppNotification(
                    id: 'n2',
                    category: NotificationCategory.chat,
                    title: 'Northside Flyers · #lines',
                    body: '5 new messages',
                    count: 5,
                    createdAt: at(0, 8),
                  ),
                  AppNotification(
                    id: 'n3',
                    category: NotificationCategory.eventChanges,
                    title: 'Practice moved to 6:30 PM',
                    body: 'State Ultimate · City Park, field 3',
                    createdAt: at(-1, 18),
                    read: true,
                  ),
                  AppNotification(
                    id: 'n4',
                    category: NotificationCategory.social,
                    title: 'Maya Kim started following you',
                    createdAt: at(-3, 12),
                    followBack: (uid: 'maya', name: 'Maya Kim', photoUrl: null),
                  ),
                ],
              ),
            ),
            Provider<DirectMessageRepository>.value(value: dms),
            Provider<ChatRepository>.value(value: chat),
            Provider<FilePickerService>.value(value: FakeFilePickerService()),
            Provider<EventRepository>.value(value: events),
            Provider<MeetingRepository>.value(value: FakeMeetingRepository()),
            Provider<CalendarRepository>.value(value: FakeCalendarRepository()),
            Provider<TeamPostRepository>.value(value: teamPosts),
            Provider<ProfileRepository>.value(value: profiles),
            Provider<StatsRepository>.value(
              value: MockStatsRepository(teamRepository: teams),
            ),
            Provider<FollowRepository>.value(value: follows),
            Provider<UserPostRepository>.value(value: posts),
            Provider<PostCommentRepository>.value(
              value: FakePostCommentRepository(posts: posts),
            ),
            Provider<GroupTournamentRepository>.value(
              value: FakeGroupTournamentRepository(),
            ),
            Provider<HostedTournamentRepository>.value(value: hosted),
            ChangeNotifierProvider<PeopleRepository>(
              create: (_) => FakePeopleRepository([
                const UserProfile(uid: 'jo', name: 'Jo Park'),
                const UserProfile(uid: 'sam', name: 'Sam Lee'),
              ]),
            ),
            Provider<RankingRepository>.value(value: rankings),
            Provider<LocationService>.value(value: location),
            ChangeNotifierProvider<WorkoutRecorder>(
              create: (_) => WorkoutRecorder(location: location),
            ),
            Provider<VideoRepository>.value(value: FakeVideoRepository()),
            ChangeNotifierProvider<VoiceRepository>.value(
              value: FakeVoiceRepository(me: testUser.uid),
            ),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: _dark ? AppTheme.dark : AppTheme.light,
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

  testWidgets('home area screens', skip: skip != null, (tester) async {
    await pumpApp(tester);
    await capture(tester, '01-home');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await capture(tester, '01b-home-feed');
    await go(tester, Routes.explorePath);
    await capture(tester, '02-discover');
    await go(tester, Routes.explore(query: 'mile'));
    await capture(tester, '03-discover-search');
    await go(tester, Routes.rankings());
    await capture(tester, '04-rankings');
    await go(tester, Routes.learn);
    await capture(tester, '05-learn');
    await go(tester, Routes.profile);
    await capture(tester, '06-my-profile');
    await go(tester, Routes.player('jo'));
    await capture(tester, '07-player');
    await go(tester, Routes.following);
    await capture(tester, '08-following');
    await go(tester, Routes.post('p1'));
    await capture(tester, '09-post');
    await go(tester, Routes.profile);
    await tester.tap(find.text('Posts').first);
    await tester.pumpAndSettle();
    await capture(tester, '06b-my-posts');
    await tester.tap(find.text('New post'));
    await capture(tester, '12-compose');
    await tester.tap(find.byTooltip('Close').first);
    await go(tester, Routes.notifications);
    await capture(tester, '11-notifications');
    // Last: leaving it releases the recorder while the tree is locked.
    await go(tester, Routes.recordWorkout);
    await capture(tester, '10-record-workout');
  });
}
