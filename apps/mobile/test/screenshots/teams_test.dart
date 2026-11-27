// TEMPORARY (redesign subtask 3b): phone screenshots of the team and
// community screens on fake data. Skipped unless asked for:
//   flutter test test/screenshots/teams_test.dart \
//     --dart-define=SCREENSHOTS=<out dir> [--dart-define=SHOT_THEME=dark]
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
import 'package:frisbee_app/data/repositories/discord/discord_import_repository.dart';
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
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'shot_env.dart';
import '../testing/fakes.dart';
import '../testing/group_tournament_fakes.dart';
import '../testing/hosted_tournament_fakes.dart';
import '../testing/meeting_fakes.dart';
import '../testing/mock_stats_repository.dart';
import '../testing/social_fakes.dart';
import '../testing/voice_fakes.dart';
import '../testing/video_fakes.dart';
import '../ui/discord_import_test.dart' show FakeDiscordImportRepository;
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
  var dir = File(Platform.resolvedExecutable).parent;
  const icons = 'bin/cache/artifacts/material_fonts/materialicons-regular.otf';
  while (!File('${dir.path}/$icons').existsSync() && dir.parent != dir) {
    dir = dir.parent;
  }
  await family('MaterialIcons', ['${dir.path}/$icons']);
}

void main() {
  final skip = _out.isEmpty ? 'pass --dart-define=SCREENSHOTS=<dir>' : null;

  late GoRouter appRouter;
  final shot = GlobalKey();
  final me = testUser.uid;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(shotWidth * 3.0, shotHeight * 3.0);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    DateTime at(int days, int hour) =>
        DateTime(now.year, now.month, now.day + days, hour);

    final teams = FakeTeamRepository();
    teams.teams['t1'] = Team(
      id: 't1',
      name: 'Northside Flyers',
      division: Division.mixed,
      level: CompetitionLevel.club,
      city: 'Denver',
      ownerId: me,
      createdAt: DateTime(2019),
      description:
          'Competitive mixed club team in north Denver. We practice '
          'Tuesdays at Sloan\'s Lake.',
      members: {
        me: TeamRole.owner,
        'coach': TeamRole.coach,
        'sam': TeamRole.player,
        'jo': TeamRole.player,
        'ava': TeamRole.player,
      },
      memberNames: {
        me: 'Test User',
        'coach': 'Riley Chen',
        'sam': 'Sam Ortiz',
        'jo': 'Jo Park',
        'ava': 'Ava Brooks',
      },
      statKeepers: const {'sam'},
      roles: const {
        'carpool': CustomRole(
          id: 'carpool',
          name: 'Carpool',
          color: 0xFF2C6FB7,
        ),
        'org': CustomRole(
          id: 'org',
          name: 'Organizers',
          color: 0xFFA8407A,
          position: 1,
          permissions: {
            TeamPermission.manageEvents,
            TeamPermission.manageChats,
          },
        ),
      },
      memberRoles: const {
        'sam': {'carpool'},
        'jo': {'org'},
      },
    );
    teams.roster['t1'] = const [
      RosterPlayer(
        id: 'r1',
        name: 'Ava Brooks',
        number: 7,
        position: PlayerPosition.handler,
        userId: 'ava',
      ),
      RosterPlayer(
        id: 'r2',
        name: 'Sam Ortiz',
        number: 12,
        position: PlayerPosition.cutter,
        userId: 'sam',
        paid: true,
      ),
      RosterPlayer(
        id: 'r3',
        name: 'Jo Park',
        number: 23,
        position: PlayerPosition.handler,
      ),
    ];
    // Outsider's view of a team the user isn't on.
    teams.teams['t3'] = Team(
      id: 't3',
      name: 'Boulder Gold',
      division: Division.open,
      level: CompetitionLevel.club,
      city: 'Boulder',
      ownerId: 'bg',
      description: 'Open club team in Boulder. Tryouts every December.',
      members: const {'bg': TeamRole.owner, 'x': TeamRole.player},
      memberNames: const {'bg': 'Pat Lee', 'x': 'Kim'},
    );
    teams.listings['t3'] = TeamListing.of(teams.teams['t3']!);
    teams.teams['g1'] = Team(
      id: 'g1',
      name: 'Denver Thursday Pickup',
      kind: TeamKind.community,
      division: Division.mixed,
      level: CompetitionLevel.pickup,
      city: 'Denver',
      requiresApproval: true,
      ownerId: me,
      members: {me: TeamRole.owner, 'sam': TeamRole.player},
      memberNames: {me: 'Test User', 'sam': 'Sam Ortiz'},
    );
    teams.joinRequests['g1'] = const [
      GroupJoinRequest(uid: 'maya', name: 'Maya Kim'),
    ];
    teams.teams['o1'] = Team(
      id: 'o1',
      name: 'Front Range Ultimate',
      kind: TeamKind.organization,
      division: Division.mixed,
      level: CompetitionLevel.club,
      city: 'Denver',
      ownerId: me,
      members: {me: TeamRole.owner, 'sam': TeamRole.player},
      memberNames: {me: 'Test User', 'sam': 'Sam Ortiz'},
      linkedTeams: const {
        't1': LinkedTeam(id: 't1', name: 'Northside Flyers'),
        'ff': LinkedTeam(
          id: 'ff',
          name: 'Front Range Fury',
          division: Division.women,
        ),
      },
    );
    teams.linkRequests['o1'] = {
      'mm': const TeamLinkRequest(
        teamId: 'mm',
        teamName: 'Mile High Masters',
        requestedByName: 'Pat Lee',
      ),
    };

    final events = FakeEventRepository()
      ..events['e1'] = TeamEvent(
        id: 'e1',
        title: 'Practice: zone offense',
        startsAt: at(1, 18),
        location: 'City Park, field 3',
      )
      ..events['e2'] = TeamEvent(
        id: 'e2',
        title: 'Open tryouts',
        type: EventType.tournament,
        startsAt: at(4, 8),
        location: 'Sloan\'s Lake Park',
      );

    final chat = FakeChatRepository()..rooms['general'] = ChatRoom.general();
    final teamPosts = FakeTeamPostRepository();
    teamPosts.posts['t1'] = [
      TeamPost(
        id: 'p1',
        body:
            "Lines for Sunday's bracket are up in the Playbook. O-line "
            'warm-up 7:45 at Field 3.',
        authorId: 'coach',
        authorName: 'Riley Chen',
        createdAt: at(0, 8),
      ),
    ];
    final posts = FakeUserPostRepository();
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
              value: FakeNotificationRepository(),
            ),
            Provider<DirectMessageRepository>.value(
              value: FakeDirectMessageRepository(),
            ),
            Provider<ChatRepository>.value(value: chat),
            Provider<DiscordImportRepository>.value(
              value: FakeDiscordImportRepository(teams, chat),
            ),
            Provider<FilePickerService>.value(value: FakeFilePickerService()),
            Provider<EventRepository>.value(value: events),
            Provider<MeetingRepository>.value(value: FakeMeetingRepository()),
            Provider<CalendarRepository>.value(value: FakeCalendarRepository()),
            Provider<TeamPostRepository>.value(value: teamPosts),
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
            Provider<HostedTournamentRepository>.value(
              value: FakeHostedTournamentRepository(),
            ),
            ChangeNotifierProvider<PeopleRepository>(
              create: (_) => FakePeopleRepository(),
            ),
            Provider<RankingRepository>.value(value: FakeRankingRepository()),
            Provider<VideoRepository>.value(value: FakeVideoRepository()),
            ChangeNotifierProvider<VoiceRepository>.value(
              value: FakeVoiceRepository(me: me),
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
    // Let the logo image finish decoding, so every picture shows it.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
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

  Future<void> back(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
    nav.maybePop();
    await tester.pumpAndSettle();
  }

  testWidgets('team screens', skip: skip != null, (tester) async {
    await pumpApp(tester);
    await go(tester, Routes.team('t1'));
    await capture(tester, '01-team-feed');
    await go(tester, Routes.teamRoster('t1'));
    await capture(tester, '02-team-roster');
    await go(tester, Routes.teamMembers('t1'));
    await capture(tester, '03-team-members');
    await go(tester, Routes.teamSection('t1', 'more'));
    await capture(tester, '04-team-more');
    await go(tester, Routes.team('t1'));
    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit team'));
    await capture(tester, '05-team-settings');
    await back(tester);
    await go(tester, Routes.teamRoles('t1'));
    await capture(tester, '06-roles');
    await go(tester, Routes.team('t1'));
    await tester.tap(find.text('Invite players').first);
    await capture(tester, '07-invite');
    await back(tester);
    await go(tester, Routes.team('t3'));
    await capture(tester, '08-team-public');
    await go(tester, Routes.team('g1'));
    await capture(tester, '09-community');
    await tester.tap(find.text('Invite members').first);
    await capture(tester, '09b-community-invite');
    await back(tester);
    await go(tester, Routes.teamMembers('g1'));
    await capture(tester, '10-community-members');
    await go(tester, Routes.team('o1'));
    await capture(tester, '11-organization');
    await go(tester, Routes.teamSection('o1', 'teams'));
    await capture(tester, '12-organization-teams');
    await go(tester, Routes.createTeam);
    await capture(tester, '13-create-team');
    await go(tester, Routes.discordImport('t1'));
    await capture(tester, '14-discord-import');
  });
}
