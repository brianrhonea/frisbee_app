// TEMPORARY (redesign subtask 3d): phone screenshots of the inbox and
// team chat screens on fake data. Skipped unless asked for:
//   flutter test test/screenshots/chat_test.dart \
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
import 'package:frisbee_app/data/services/meeting_call.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/data/repositories/draft/message_draft_repository.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_list_viewmodel.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_room_settings_viewmodel.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_room_viewmodel.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_room_screen.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_room_settings_screen.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_tab.dart';
import 'package:frisbee_app/ui/core/ui/view_model_host.dart';
import 'package:frisbee_app/ui/messages/view_models/direct_chat_viewmodel.dart';
import 'package:frisbee_app/ui/messages/view_models/group_members_viewmodel.dart';
import 'package:frisbee_app/ui/messages/view_models/inbox_viewmodel.dart';
import 'package:frisbee_app/ui/messages/widgets/direct_chat_screen.dart';
import 'package:frisbee_app/ui/messages/widgets/group_members_screen.dart';
import 'package:frisbee_app/ui/messages/widgets/inbox_screen.dart';
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
    );
    teams.teams['g1'] = Team(
      id: 'g1',
      name: 'Denver Thursday Pickup',
      kind: TeamKind.community,
      division: Division.mixed,
      level: CompetitionLevel.pickup,
      city: 'Denver',
      ownerId: 'sam',
      members: {'sam': TeamRole.owner, me: TeamRole.player},
      memberNames: {me: 'Test User', 'sam': 'Sam Ortiz'},
    );
    final events = FakeEventRepository();

    final chat = FakeChatRepository()..seedVoice = false;
    const everyone = {ChatAudience.everyone};
    chat
      ..folders['field'] = const ChatFolder(id: 'field', name: 'On field')
      ..folders['lead'] = const ChatFolder(
        id: 'lead',
        name: 'Leadership',
        position: 1,
      )
      ..rooms['general'] = ChatRoom.general()
      ..rooms['news'] = const ChatRoom(
        id: 'news',
        name: 'Announcements',
        position: 1,
        readRoles: everyone,
        writeRoles: {'coach'},
      )
      ..rooms['lines'] = const ChatRoom(
        id: 'lines',
        name: 'Lines',
        folderId: 'field',
        readRoles: everyone,
        writeRoles: everyone,
      )
      ..rooms['oline'] = const ChatRoom(
        id: 'oline',
        name: 'O-line',
        folderId: 'field',
        position: 1,
        readRoles: everyone,
        writeRoles: everyone,
      )
      ..rooms['film'] = const ChatRoom(
        id: 'film',
        name: 'Film room',
        kind: ChatRoomKind.voice,
        folderId: 'field',
        position: 2,
        readRoles: everyone,
        writeRoles: everyone,
      )
      ..rooms['captains'] = const ChatRoom(
        id: 'captains',
        name: 'Captains',
        folderId: 'lead',
        readRoles: {'coach'},
        writeRoles: {'coach'},
      );
    for (final id in [
      'general',
      'news',
      'lines',
      'oline',
      'film',
      'captains',
    ]) {
      chat.teamOf['r:$id'] = 't1';
    }
    chat.teamOf['f:field'] = 't1';
    chat.teamOf['f:lead'] = 't1';
    chat.rooms['lobby'] = ChatRoom.general().withName('Lobby');
    chat.teamOf['r:lobby'] = 'g1';
    chat.messages['lines'] = [
      ChatMessage(
        id: 'm1',
        authorId: 'coach',
        authorName: 'Riley Chen',
        text:
            'Practice Thursday is all zone O. Handlers, come 15 min early '
            'for the swing drill.',
        createdAt: at(0, 9),
        reactions: const {'sam': '👍', 'jo': '👍', 'ava': '🔥'},
      ),
      ChatMessage(
        id: 'm2',
        authorId: 'sam',
        authorName: 'Sam Ortiz',
        text: "I'll bring the cones. Who's on D-line Saturday?",
        createdAt: at(0, 9).add(const Duration(minutes: 11)),
        replyTo: const MessageReply(
          id: 'm1',
          authorId: 'coach',
          authorName: 'Riley Chen',
          text: 'Handlers, come 15 min early',
        ),
      ),
      ChatMessage(
        id: 'm3',
        authorId: 'jo',
        authorName: 'Jo Park',
        text: "It's in the doc: https://stall10.app/lines",
        createdAt: at(0, 9).add(const Duration(minutes: 12)),
      ),
      ChatMessage(
        id: 'm4',
        authorId: me,
        authorName: 'Test User',
        text: 'Thanks, see you all there.',
        createdAt: at(0, 9).add(const Duration(minutes: 14)),
      ),
    ];
    chat
      ..stampRoom('general', at(0, 8))
      ..stampRoom('lines', at(0, 9).add(const Duration(minutes: 14)))
      ..stampRoom('captains', at(0, 7))
      ..stampRoom('lobby', at(-1, 19));
    await chat.markRead('g1', 'lobby', me);

    final dms = FakeDirectMessageRepository();
    dms.profiles.addAll(const [
      UserProfile(uid: 'coach', name: 'Riley Chen', username: 'riley'),
      UserProfile(uid: 'rio', name: 'Rio Martinez'),
    ]);
    dms.conversations['jo_$me'] = Conversation(
      id: 'jo_$me',
      participants: ['jo', me],
      names: {'jo': 'Jo Park', me: 'Test User'},
      lastMessage: 'Can you grab the cones Thursday?',
      lastMessageAt: at(0, 10),
      lastSenderId: 'jo',
    );
    dms.conversations['sam_$me'] = Conversation(
      id: 'sam_$me',
      participants: ['sam', me],
      names: {'sam': 'Sam Ortiz', me: 'Test User'},
      lastMessage: 'See you at practice',
      lastMessageAt: at(-2, 18),
      lastSenderId: me,
      readAt: {me: at(-2, 19)},
    );
    dms.conversations['grp'] = Conversation(
      id: 'grp',
      participants: ['sam', 'jo', me],
      isGroup: true,
      name: 'Carpool to Mile High',
      names: {'sam': 'Sam Ortiz', 'jo': 'Jo Park', me: 'Test User'},
      lastMessage: 'I can take 3 from Highlands',
      lastMessageAt: at(-3, 12),
      lastSenderId: 'sam',
      readAt: {me: at(-3, 13)},
    );
    dms.messages['jo_$me'] = [
      ChatMessage(
        id: 'd1',
        authorId: 'jo',
        authorName: 'Jo Park',
        text: 'Good games Saturday! Your hucks were on point.',
        createdAt: at(-1, 20),
      ),
      ChatMessage(
        id: 'd2',
        authorId: me,
        authorName: 'Test User',
        text: 'Thanks! Film is up at https://stall10.app/film',
        createdAt: at(-1, 20).add(const Duration(minutes: 12)),
      ),
      ChatMessage(
        id: 'd3',
        authorId: 'jo',
        authorName: 'Jo Park',
        text: 'Riley wants extra cones for the new zone drill',
        createdAt: at(0, 10),
      ),
      ChatMessage(
        id: 'd4',
        authorId: 'jo',
        authorName: 'Jo Park',
        text: "Can you grab the cones Thursday? I'll bring the discs.",
        createdAt: at(0, 10).add(const Duration(minutes: 1)),
        reactions: {me: '👍'},
      ),
      ChatMessage(
        id: 'd5',
        authorId: me,
        authorName: 'Test User',
        text: 'Yep, I have 20 in the car. See you at 6:30',
        createdAt: at(0, 10).add(const Duration(minutes: 3)),
        replyTo: const MessageReply(
          id: 'd4',
          authorId: 'jo',
          authorName: 'Jo Park',
          text: 'Can you grab the cones Thursday?',
        ),
      ),
    ];
    final voice = FakeVoiceRepository(me: me)
      ..others = const [
        CallParticipant(uid: 'coach', name: 'Riley Chen', isSpeaking: true),
        CallParticipant(uid: 'jo', name: 'Jo Park'),
      ];
    final teamPosts = FakeTeamPostRepository();
    final posts = FakeUserPostRepository();
    final auth = FakeAuthRepository(user: testUser);
    // The chat routes only (the app's router pulls in every screen, which
    // other work may have mid-edit); the team page's Chat tab is shown
    // under a plain bar.
    Widget settings(GoRouterState s, String? roomId) => ViewModelHost(
      key: ValueKey('settings-$roomId'),
      create: (c) => ChatRoomSettingsViewModel(
        teamId: s.pathParameters['t']!,
        roomId: roomId,
        teamRepository: c.read(),
        chatRepository: c.read(),
        authRepository: c.read(),
      ),
      builder: (_, vm) => ChatRoomSettingsScreen(viewModel: vm),
    );
    appRouter = GoRouter(
      initialLocation: Routes.messages,
      routes: [
        GoRoute(
          path: Routes.messages,
          builder: (_, _) => ViewModelHost(
            create: (c) => InboxViewModel(
              directMessageRepository: c.read(),
              authRepository: c.read(),
              teamRepository: c.read<TeamRepository?>(),
              chatRepository: c.read<ChatRepository?>(),
            ),
            builder: (_, vm) => InboxScreen(viewModel: vm),
          ),
          routes: [
            GoRoute(
              path: 'new',
              builder: (_, _) => ViewModelHost(
                create: (c) => GroupMembersViewModel(
                  directMessageRepository: c.read(),
                  authRepository: c.read(),
                ),
                builder: (_, vm) => GroupMembersScreen(viewModel: vm),
              ),
            ),
            GoRoute(
              path: ':id',
              builder: (_, s) => ViewModelHost(
                key: ValueKey('dm-${s.pathParameters['id']}'),
                create: (c) => DirectChatViewModel(
                  conversationId: s.pathParameters['id']!,
                  directMessageRepository: c.read(),
                  authRepository: c.read(),
                  filePicker: c.read(),
                  peopleRepository: c.read<PeopleRepository?>(),
                  draftRepository: c.read<MessageDraftRepository?>(),
                ),
                builder: (_, vm) => DirectChatScreen(viewModel: vm),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/teams/:t',
          builder: (_, s) => ViewModelHost(
            key: ValueKey('rooms-${s.uri}'),
            create: (c) => ChatListViewModel(
              teamId: s.pathParameters['t']!,
              teamRepository: c.read(),
              chatRepository: c.read(),
              authRepository: c.read(),
              voiceRepository: c.read(),
            ),
            builder: (_, vm) => Scaffold(
              appBar: AppBar(title: const Text('Northside Flyers · Chat')),
              body: ChatTab(viewModel: vm),
            ),
          ),
        ),
        GoRoute(
          path: '/teams/:t/chats/new',
          builder: (_, s) => settings(s, null),
        ),
        GoRoute(
          path: '/teams/:t/chats/:r',
          builder: (_, s) => ViewModelHost(
            key: ValueKey('room-${s.pathParameters['r']}'),
            create: (c) => ChatRoomViewModel(
              teamId: s.pathParameters['t']!,
              roomId: s.pathParameters['r']!,
              teamRepository: c.read(),
              chatRepository: c.read(),
              notificationRepository: c.read(),
              authRepository: c.read(),
              filePicker: c.read(),
              peopleRepository: c.read<PeopleRepository?>(),
            ),
            builder: (_, vm) => ChatRoomScreen(viewModel: vm),
          ),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (_, s) => settings(s, s.pathParameters['r']),
            ),
          ],
        ),
      ],
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
            Provider<DirectMessageRepository>.value(value: dms),
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
            ChangeNotifierProvider<VoiceRepository>.value(value: voice),
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

  testWidgets('chat screens', skip: skip != null, (tester) async {
    await pumpApp(tester);
    await go(tester, Routes.messages);
    await capture(tester, '01-inbox');
    await go(tester, Routes.conversation('jo_$me'));
    await capture(tester, '02-conversation');
    await go(tester, Routes.newMessage);
    await tester.enterText(find.byType(TextField).last, 'ri');
    await tester.pump(const Duration(milliseconds: 400));
    await capture(tester, '03-new-message');
    await go(tester, Routes.teamChat('t1'));
    await capture(tester, '04-team-rooms');
    await go(tester, Routes.chatRoom('t1', 'lines'));
    await capture(tester, '05-room');
    await go(tester, Routes.chatRoomSettings('t1', 'lines'));
    await capture(tester, '06-room-settings');
    await go(tester, Routes.newChatRoom('t1'));
    await capture(tester, '07-new-room');
    await go(tester, Routes.chatRoom('t1', 'film'));
    await capture(tester, '08-voice-join');
    await tester.tap(find.text('Join voice'));
    await capture(tester, '09-voice-in');
    await go(tester, Routes.teamChat('t1'));
    await capture(tester, '10-team-rooms-voice');
    await go(tester, Routes.chatRoom('t1', 'lines'));
    await tester.longPress(
      find.text("I'll bring the cones. Who's on D-line Saturday?"),
    );
    await capture(tester, '11-message-actions');
  });
}
