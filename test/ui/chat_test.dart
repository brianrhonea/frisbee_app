import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/voice/voice_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_list_viewmodel.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_room_settings_viewmodel.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_room_viewmodel.dart';
import 'package:frisbee_app/ui/chat/view_models/message_thread_viewmodel.dart';
import 'package:frisbee_app/ui/chat/view_models/voice_channel_viewmodel.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_room_screen.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_tab.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/voice_fakes.dart';

void main() {
  // u1 is signed in (testUser).
  const captains = ChatRoom(
    id: 'caps',
    name: 'Captains',
    readRoles: {'coach', 'captain'},
    writeRoles: {'captain'},
    readUsers: {'p2'},
  );

  group('ChatRoom', () {
    final team = teamWith({
      'o': TeamRole.owner,
      'c': TeamRole.coach,
      'k': TeamRole.captain,
      'p1': TeamRole.player,
      'p2': TeamRole.player,
    });

    test('access by role, by name, and always for the owner', () {
      expect(captains.accessFor(team, 'o'), ChatAccess.write);
      expect(captains.accessFor(team, 'k'), ChatAccess.write);
      expect(captains.accessFor(team, 'c'), ChatAccess.read);
      expect(captains.accessFor(team, 'p2'), ChatAccess.read);
      expect(captains.accessFor(team, 'p1'), ChatAccess.none);
      expect(captains.accessFor(team, 'stranger'), ChatAccess.none);
      final upgraded = captains.withUserAccess('p2', ChatAccess.write);
      expect(upgraded.accessFor(team, 'p2'), ChatAccess.write);
    });

    test('stores writers as readers too', () {
      final map = const ChatRoom(
        id: 'r',
        name: ' Room ',
        writeRoles: {'player'},
        writeUsers: {'x'},
      ).toMap();
      expect(map['name'], 'Room');
      expect(map['readRoles'], ['player']);
      expect(map['readUsers'], ['x']);
      final back = ChatRoom.fromMap('r', map);
      expect(back.roleAccess('player'), ChatAccess.write);
    });

    test('lowering access removes write first', () {
      final r = captains.withRoleAccess('captain', ChatAccess.read);
      expect(r.roleAccess('captain'), ChatAccess.read);
      expect(r.withRoleAccess('captain', ChatAccess.none).readRoles, {'coach'});
    });

    test('describes its audience', () {
      expect(ChatRoom.general().audienceOn(team), 'Everyone');
      expect(captains.audienceOn(team), 'Coaches, Captains + 1 person');
      expect(
        const ChatRoom(id: 'r', name: 'Owner only').audienceOn(team),
        'Owner',
      );
      // Rooms from before "everyone" listed every tier.
      final legacy = ChatRoom.fromMap('r', {
        'name': 'Old',
        'readRoles': ['owner', 'coach', 'captain', 'player'],
        'writeRoles': ['owner'],
      });
      expect(legacy.readRoles, {'coach', 'captain', 'player'});
      expect(legacy.audienceOn(team), 'Everyone');
    });

    test('drops grants for people who left the team', () {
      final r = captains.withUserAccess('gone', ChatAccess.write);
      expect(r.forMembersOf(team).readUsers, {'p2'});
      expect(r.forMembersOf(team).writeUsers, isEmpty);
    });

    group('with custom roles', () {
      final roled = team.copyWith(
        roles: {
          'h': const CustomRole(id: 'h', name: 'Handlers'),
          'm': const CustomRole(
            id: 'm',
            name: 'Mods',
            permissions: {TeamPermission.moderate},
          ),
        },
        memberRoles: {
          'p1': {'h'},
        },
      );
      const handlers = ChatRoom(
        id: 'h',
        name: 'Handlers',
        readRoles: {'h'},
        writeRoles: {'h'},
      );

      test('grant access to their members', () {
        expect(handlers.accessFor(roled, 'p1'), ChatAccess.write);
        expect(handlers.accessFor(roled, 'p2'), ChatAccess.none);
        expect(handlers.accessFor(roled, 'o'), ChatAccess.write);
        expect(handlers.audienceOn(roled), 'Handlers');
      });

      test('"everyone" lets every member in', () {
        const open = ChatRoom(
          id: 'x',
          name: 'Open',
          readRoles: {ChatAudience.everyone},
        );
        expect(open.accessFor(roled, 'p2'), ChatAccess.read);
        expect(open.accessFor(roled, 'stranger'), ChatAccess.none);
      });

      test('are offered after everyone; legacy tiers are not', () {
        expect(ChatAudience.choicesFor(roled), ['everyone', 'h', 'm']);
        expect(ChatAudience.labelOf(roled, 'coach'), 'Coach');
        expect(ChatAudience.labelOf(roled, 'h'), 'Handlers');
        expect(ChatAudience.labelOf(roled, 'gone'), 'Deleted role');
      });

      test('deleted ones are dropped on save', () {
        final r = handlers.withRoleAccess('gone', ChatAccess.read);
        expect(r.forMembersOf(roled).readRoles, {'h'});
      });

      test('groups offer no tiers', () {
        final group = roled.copyWith();
        final community = Team(
          id: group.id,
          name: group.name,
          division: group.division,
          level: group.level,
          ownerId: group.ownerId,
          members: group.members,
          kind: TeamKind.community,
          roles: group.roles,
        );
        expect(ChatAudience.choicesFor(community), ['everyone', 'h', 'm']);
      });
    });

    test('groups rooms by folder, in order', () {
      const folders = [
        ChatFolder(id: 'b', name: 'Beta', position: 1),
        ChatFolder(id: 'a', name: 'Alpha', position: 0),
        ChatFolder(id: 'empty', name: 'Empty', position: 2),
      ];
      final rooms = [
        const ChatRoom(id: 'z', name: 'Zed', position: 0),
        ChatRoom.general(),
        const ChatRoom(id: 'b2', name: 'B two', folderId: 'b', position: 1),
        const ChatRoom(id: 'b1', name: 'B one', folderId: 'b', position: 0),
        const ChatRoom(id: 'a1', name: 'A one', folderId: 'a'),
        const ChatRoom(id: 'lost', name: 'Lost', folderId: 'deleted'),
      ];
      final groups = groupRooms(rooms, folders);
      expect(
        [
          for (final g in groups) [g.folder?.id, for (final r in g.rooms) r.id],
        ],
        [
          [null, 'general', 'lost', 'z'],
          ['a', 'a1'],
          ['b', 'b1', 'b2'],
        ],
      );
      expect(
        groupRooms(rooms, folders, keepEmpty: true).last.folder?.id,
        'empty',
      );
    });

    test('new rooms in a folder start with its access', () {
      const folder = ChatFolder(
        id: 'f',
        name: 'Coaching',
        readRoles: {'coach'},
        writeRoles: {'coach'},
      );
      final room = ChatRoom.newIn(folder);
      expect(room.folderId, 'f');
      expect(room.roleAccess('coach'), ChatAccess.write);
      expect(room.roleAccess(ChatAudience.everyone), ChatAccess.none);
      expect(
        ChatRoom.newIn(null).roleAccess(ChatAudience.everyone),
        ChatAccess.write,
      );
      final map = room.withPosition(3).toMap();
      expect(map['folderId'], 'f');
      expect(map['position'], 3);
    });

    test('guesses content types and formats sizes', () {
      expect(contentTypeFor('Photo.JPG'), 'image/jpeg');
      expect(contentTypeFor('plays.pdf'), 'application/pdf');
      expect(contentTypeFor('noext'), 'application/octet-stream');
      expect(formatFileSize(10 * 1024 * 1024), '10.0 MB');
      expect(formatFileSize(2048), '2 KB');
    });
  });

  late FakeTeamRepository teams;
  late FakeChatRepository chats;
  late FakeAuthRepository auth;
  late FakeFilePickerService picker;
  late FakeNotificationRepository notifications;
  late FakeVoiceRepository voice;

  setUp(() {
    teams = FakeTeamRepository();
    chats = FakeChatRepository()
      ..rooms['general'] = ChatRoom.general()
      ..rooms['caps'] = captains
      // Most tests don't want the default voice channels in the way.
      ..seedVoice = false;
    auth = FakeAuthRepository(user: testUser);
    picker = FakeFilePickerService();
    notifications = FakeNotificationRepository();
    voice = FakeVoiceRepository();
  });

  void joinAs(TeamRole role) => teams.teams['t1'] = teamWith({
    if (role != TeamRole.owner) 'o': TeamRole.owner,
    'u1': role,
    'p2': TeamRole.player,
  });

  group('ChatListViewModel', () {
    ChatListViewModel load() => ChatListViewModel(
      teamId: 't1',
      teamRepository: teams,
      chatRepository: chats,
      authRepository: auth,
      voiceRepository: voice,
    );

    test('players see only rooms they can read', () async {
      joinAs(TeamRole.player);
      final vm = load();
      await pumpEventQueue();
      expect(vm.loaded, isTrue);
      expect(vm.rooms.map((r) => r.id), ['general']);
      expect(vm.canManage, isFalse);
      vm.dispose();
    });

    test('admins see every room and add a missing General', () async {
      joinAs(TeamRole.coach);
      chats.rooms.remove('general');
      final vm = load();
      await pumpEventQueue();
      expect(chats.generalEnsured, 1);
      expect(vm.rooms.map((r) => r.id), containsAll(['caps', 'general']));
      expect(vm.accessTo(captains), ChatAccess.read);
      expect(vm.canManage, isTrue);
      vm.dispose();
    });

    test('a custom role opens its rooms', () async {
      joinAs(TeamRole.player);
      teams.teams['t1'] = teams.teams['t1']!.copyWith(
        roles: {'c': const CustomRole(id: 'c', name: 'Caps club')},
        memberRoles: {
          'u1': {'c'},
        },
      );
      chats.rooms['club'] = const ChatRoom(
        id: 'club',
        name: 'Club',
        readRoles: {'c'},
      );
      final vm = load();
      await pumpEventQueue();
      expect(vm.rooms.map((r) => r.id), ['general', 'club']);
      expect(vm.canManage, isFalse);
      vm.dispose();
    });

    test('Manage chats lets a player see and arrange every room', () async {
      joinAs(TeamRole.player);
      teams.teams['t1'] = teams.teams['t1']!.copyWith(
        roles: {
          'm': const CustomRole(
            id: 'm',
            name: 'Chat mods',
            permissions: {TeamPermission.manageChats},
          ),
        },
        memberRoles: {
          'u1': {'m'},
        },
        memberPerms: {
          'u1': {TeamPermission.manageChats},
        },
      );
      final vm = load();
      await pumpEventQueue();
      expect(vm.canManage, isTrue);
      expect(vm.rooms.map((r) => r.id), containsAll(['caps', 'general']));

      await vm.saveFolder.execute(const ChatFolder(id: '', name: 'Leaders'));
      await pumpEventQueue();
      await vm.saveFolder.execute(const ChatFolder(id: '', name: 'Fun'));
      await pumpEventQueue();
      expect(vm.folders.map((f) => f.name), ['Leaders', 'Fun']);
      final leaders = vm.folders.first;

      await vm.moveRoom.execute((room: captains, folderId: leaders.id));
      await pumpEventQueue();
      expect(
        [
          for (final g in vm.groups)
            [g.folder?.name, for (final r in g.rooms) r.id],
        ],
        [
          [null, 'general'],
          ['Leaders', 'caps'],
          ['Fun'],
        ],
      );

      await vm.shiftFolder.execute((id: leaders.id, by: 1));
      await pumpEventQueue();
      expect(vm.folders.map((f) => f.name), ['Fun', 'Leaders']);

      vm.toggleFolder(leaders.id);
      expect(vm.isCollapsed(leaders.id), isTrue);

      await vm.deleteFolder.execute(leaders.id);
      await pumpEventQueue();
      expect(chats.rooms['caps']!.folderId, isNull);
      expect(vm.folders.map((f) => f.name), ['Fun']);
      vm.dispose();
    });

    test("players don't create General", () async {
      joinAs(TeamRole.player);
      chats.rooms.remove('general');
      final vm = load();
      await pumpEventQueue();
      expect(chats.generalEnsured, 0);
      vm.dispose();
    });
  });

  group('ChatRoomViewModel', () {
    ChatRoomViewModel load(String roomId) => ChatRoomViewModel(
      teamId: 't1',
      roomId: roomId,
      teamRepository: teams,
      chatRepository: chats,
      notificationRepository: notifications,
      authRepository: auth,
      filePicker: picker,
    );

    test("mutes and unmutes the room's notifications", () async {
      joinAs(TeamRole.player);
      final vm = load('general');
      await pumpEventQueue();
      expect(vm.muted, isFalse);
      await vm.toggleMuted.execute();
      await pumpEventQueue();
      expect(vm.muted, isTrue);
      expect(notifications.prefs.isRoomMuted('t1', 'general'), isTrue);
      await vm.toggleMuted.execute();
      await pumpEventQueue();
      expect(vm.muted, isFalse);
      vm.dispose();
    });

    test('sends text with attachments and clears drafts', () async {
      joinAs(TeamRole.player);
      final vm = load('general');
      await pumpEventQueue();
      expect(vm.canWrite, isTrue);
      picker.next = [FakeFilePickerService.file('field.png', 1000)];
      await vm.pickFiles.execute(true);
      expect(vm.drafts.single.isImage, isTrue);
      await vm.send.execute('  See you there ');
      await pumpEventQueue();
      expect(vm.send.completed, isTrue);
      expect(vm.drafts, isEmpty);
      final m = vm.messages.single;
      expect(m.text, 'See you there');
      expect(m.attachments.single.name, 'field.png');
      expect(vm.isMine(m), isTrue);
      final data = await vm.attachmentData(m.attachments.single);
      expect(data, isA<Ok<Uint8List>>());
      vm.dispose();
    });

    test('rejects files over 10 MB and keeps the rest', () async {
      joinAs(TeamRole.player);
      final vm = load('general');
      await pumpEventQueue();
      picker.next = [
        FakeFilePickerService.file('big.jpg', maxAttachmentBytes + 1),
        FakeFilePickerService.file('ok.pdf', maxAttachmentBytes),
      ];
      await vm.pickFiles.execute(false);
      expect(vm.drafts.map((d) => d.name), ['ok.pdf']);
      final error = vm.pickFiles.result as Error;
      expect(error.error, isA<AttachmentTooLargeException>());
      expect(error.error.toString(), contains('big.jpg'));
      vm.dispose();
    });

    test('keeps drafts when sending fails', () async {
      joinAs(TeamRole.player);
      chats.sendError = Exception('offline');
      final vm = load('general');
      await pumpEventQueue();
      picker.next = [FakeFilePickerService.file('a.txt', 3)];
      await vm.pickFiles.execute(false);
      await vm.send.execute('hi');
      expect(vm.send.error, isTrue);
      expect(vm.drafts, hasLength(1));
      vm.dispose();
    });

    test('read-only members cannot post; outsiders cannot read', () async {
      joinAs(TeamRole.coach);
      var vm = load('caps');
      await pumpEventQueue();
      expect(vm.access, ChatAccess.read);
      expect(vm.canWrite, isFalse);
      vm.dispose();
      joinAs(TeamRole.player);
      vm = load('caps');
      await pumpEventQueue();
      expect(vm.access, ChatAccess.none);
      vm.dispose();
    });

    test('authors delete their own messages; moderators delete any', () async {
      chats.messages['general'] = [
        const ChatMessage(id: 'm1', authorId: 'p2', authorName: 'Pat'),
      ];
      joinAs(TeamRole.player);
      var vm = load('general');
      await pumpEventQueue();
      expect(vm.canDelete(vm.messages.single), isFalse);
      vm.dispose();
      teams.teams['t1'] = teams.teams['t1']!.copyWith(
        memberPerms: {
          'u1': {TeamPermission.moderate},
        },
      );
      vm = load('general');
      await pumpEventQueue();
      expect(vm.canDelete(vm.messages.single), isTrue);
      vm.dispose();
      joinAs(TeamRole.captain);
      vm = load('general');
      await pumpEventQueue();
      expect(vm.canDelete(vm.messages.single), isTrue);
      vm.dispose();
      joinAs(TeamRole.owner);
      vm = load('general');
      await pumpEventQueue();
      expect(vm.canDelete(vm.messages.single), isTrue);
      vm.dispose();
    });

    test('pages back through older messages', () async {
      chats.messages['general'] = [
        for (var i = 0; i < 60; i++)
          ChatMessage(id: 'm$i', authorId: 'p2', authorName: 'Pat'),
      ];
      joinAs(TeamRole.player);
      final vm = load('general');
      await pumpEventQueue();
      expect(vm.messages, hasLength(MessageThreadViewModel.pageSize));
      expect(vm.hasMore, isTrue);
      vm.loadMore();
      await pumpEventQueue();
      expect(vm.messages, hasLength(60));
      expect(vm.hasMore, isFalse);
      vm.dispose();
    });
  });

  group('ChatRoomSettingsViewModel', () {
    ChatRoomSettingsViewModel load({String? roomId}) =>
        ChatRoomSettingsViewModel(
          teamId: 't1',
          roomId: roomId,
          teamRepository: teams,
          chatRepository: chats,
          authRepository: auth,
        );

    test('creates a room with role and per-person access', () async {
      joinAs(TeamRole.captain);
      final vm = load();
      await pumpEventQueue();
      expect(vm.canSave, isFalse);
      vm
        ..setName('Handlers')
        ..setRoleAccess(ChatAudience.everyone, ChatAccess.none)
        ..setRoleAccess('captain', ChatAccess.write)
        ..setUserAccess('p2', ChatAccess.write);
      await vm.save.execute();
      final id = (vm.save.result as Ok<String>).value;
      final saved = chats.rooms[id]!;
      expect(saved.name, 'Handlers');
      expect(saved.roleAccess('player'), ChatAccess.none);
      expect(saved.roleAccess('captain'), ChatAccess.write);
      expect(saved.userAccess('p2'), ChatAccess.write);
      expect(vm.members.map((m) => m.uid), isNot(contains('o')));
      vm.dispose();
    });

    test('chat managers delete rooms they can read, never General', () async {
      chats.rooms['owners'] = const ChatRoom(id: 'owners', name: 'Owner');
      joinAs(TeamRole.coach);
      var vm = load(roomId: 'caps');
      await pumpEventQueue();
      expect(vm.canManage, isTrue);
      expect(vm.canDelete, isTrue);
      vm.dispose();
      vm = load(roomId: 'owners');
      await pumpEventQueue();
      expect(vm.canDelete, isFalse);
      vm.dispose();
      joinAs(TeamRole.player);
      vm = load(roomId: 'general');
      await pumpEventQueue();
      expect(vm.canManage, isFalse);
      expect(vm.canDelete, isFalse);
      vm.dispose();
      joinAs(TeamRole.owner);
      vm = load(roomId: 'owners');
      await pumpEventQueue();
      expect(vm.canDelete, isTrue);
      vm.dispose();
      vm = load(roomId: 'general');
      await pumpEventQueue();
      expect(vm.canDelete, isFalse);
      vm.dispose();
    });

    test('a new room in a folder starts with its access', () async {
      chats.folders['f'] = const ChatFolder(
        id: 'f',
        name: 'Coaching',
        readRoles: {'coach'},
        writeRoles: {'coach'},
      );
      joinAs(TeamRole.coach);
      final vm = ChatRoomSettingsViewModel(
        teamId: 't1',
        folderId: 'f',
        teamRepository: teams,
        chatRepository: chats,
        authRepository: auth,
      );
      await pumpEventQueue();
      expect(vm.loaded, isTrue);
      expect(vm.room!.folderId, 'f');
      expect(vm.room!.roleAccess('coach'), ChatAccess.write);
      expect(vm.room!.roleAccess(ChatAudience.everyone), ChatAccess.none);
      expect(vm.folders.map((f) => f.id), ['f']);
      vm.setFolder(null);
      expect(vm.room!.folderId, isNull);
      vm.dispose();
    });
  });

  Widget withRepos(Widget child) => MultiProvider(
    providers: [
      Provider<TeamRepository>.value(value: teams),
      Provider<ChatRepository>.value(value: chats),
      ChangeNotifierProvider<AuthRepository>.value(value: auth),
      Provider<FilePickerService>.value(value: picker),
      Provider<NotificationRepository>.value(value: notifications),
      ChangeNotifierProvider<VoiceRepository>.value(value: voice),
    ],
    child: child,
  );

  testWidgets('wide screens list rooms beside the open one', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    joinAs(TeamRole.captain);
    final vm = ChatListViewModel(
      teamId: 't1',
      teamRepository: teams,
      chatRepository: chats,
      authRepository: auth,
      voiceRepository: voice,
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      withRepos(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: ChatTab(viewModel: vm)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    // General sorts first, so it opens by default.
    expect(vm.selectedId, 'general');
    expect(find.text('Say hello to the team.'), findsOneWidget);
    await tester.tap(find.text('captains'));
    await tester.pump();
    await tester.pump();
    expect(vm.selectedId, 'caps');
    expect(find.text('No messages yet'), findsOneWidget);
  });

  group('ChatRoomScreen', () {
    Future<ChatRoomViewModel> pump(WidgetTester tester, String roomId) async {
      final vm = ChatRoomViewModel(
        teamId: 't1',
        roomId: roomId,
        teamRepository: teams,
        chatRepository: chats,
        notificationRepository: notifications,
        authRepository: auth,
        filePicker: picker,
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        withRepos(
          MaterialApp(
            theme: AppTheme.light,
            home: ChatRoomScreen(viewModel: vm),
          ),
        ),
      );
      await tester.pump();
      return vm;
    }

    testWidgets('on phones the Chats button opens the room panel', (
      tester,
    ) async {
      joinAs(TeamRole.captain);
      await pump(tester, 'general');
      expect(find.text('captains'), findsNothing);
      await tester.tap(find.byTooltip('Chats'));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('captains'), findsOneWidget);
      // Tapping the open room returns to it.
      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('general'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('posts a message', (tester) async {
      joinAs(TeamRole.player);
      await pump(tester, 'general');
      expect(find.text('No messages yet'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Bring both jerseys');
      // Enter sends, as on Discord.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(find.text('Bring both jerseys'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    for (final size in const [
      Size(390, 844),
      Size(1024, 768),
      Size(1600, 900),
    ]) {
      testWidgets('the Send button shows and sends at ${size.width}px wide', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        joinAs(TeamRole.player);
        await pump(tester, 'general');
        final send = find.byTooltip('Send');
        expect(send, findsOneWidget);
        // Nothing to send yet.
        expect(
          tester
              .widget<IconButton>(
                find.ancestor(of: send, matching: find.byType(IconButton)),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(find.byType(TextField), 'Tap to send');
        await tester.pump();
        await tester.tap(send);
        await tester.pump();
        await tester.pump();
        expect(find.text('Tap to send'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
      });
    }

    testWidgets('read-only members see a notice instead of the composer', (
      tester,
    ) async {
      joinAs(TeamRole.coach);
      await pump(tester, 'caps');
      expect(
        find.text('You can read this room but not post in it.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets("members without access can't open the room", (tester) async {
      joinAs(TeamRole.player);
      await pump(tester, 'caps');
      expect(find.text("You're not in this room"), findsOneWidget);
    });
  });

  group('drag and drop', () {
    ChatListViewModel load() => ChatListViewModel(
      teamId: 't1',
      teamRepository: teams,
      chatRepository: chats,
      authRepository: auth,
      voiceRepository: voice,
    );

    List<String> namesIn(ChatListViewModel vm, String? folderId) => [
      for (final g in vm.groups)
        if (g.folder?.id == folderId) ...g.rooms.map((r) => r.id),
    ];

    setUp(() {
      chats.folders['f'] = const ChatFolder(
        id: 'f',
        name: 'Field',
        position: 0,
      );
      chats.folders['g'] = const ChatFolder(id: 'g', name: 'Gym', position: 1);
      for (final (i, id) in ['a', 'b', 'c'].indexed) {
        chats.rooms[id] = ChatRoom(
          id: id,
          name: id,
          folderId: 'f',
          position: i,
          readRoles: const {ChatAudience.everyone},
        );
      }
    });

    test('moving a room down puts it after the one dropped on', () async {
      joinAs(TeamRole.captain);
      final vm = load();
      await pumpEventQueue();
      await vm.placeRoom.execute((roomId: 'a', folderId: 'f', index: 1));
      await pumpEventQueue();
      expect(namesIn(vm, 'f'), ['b', 'a', 'c']);
      vm.dispose();
    });

    test('moving a room up puts it before the one dropped on', () async {
      joinAs(TeamRole.captain);
      final vm = load();
      await pumpEventQueue();
      await vm.placeRoom.execute((roomId: 'c', folderId: 'f', index: 0));
      await pumpEventQueue();
      expect(namesIn(vm, 'f'), ['c', 'a', 'b']);
      vm.dispose();
    });

    test('rooms move between folders and out of them', () async {
      joinAs(TeamRole.captain);
      final vm = load();
      await pumpEventQueue();
      await vm.placeRoom.execute((roomId: 'b', folderId: 'g', index: 0));
      await pumpEventQueue();
      expect(namesIn(vm, 'f'), ['a', 'c']);
      expect(namesIn(vm, 'g'), ['b']);
      await vm.placeRoom.execute((roomId: 'a', folderId: null, index: 0));
      await pumpEventQueue();
      expect(namesIn(vm, null), ['general', 'a', 'caps']);
      expect(chats.rooms['a']!.folderId, isNull);
      vm.dispose();
    });

    test('folders reorder', () async {
      joinAs(TeamRole.captain);
      final vm = load();
      await pumpEventQueue();
      final before = vm.folders.map((f) => f.id).toList();
      await vm.placeFolder.execute((folderId: before.last, index: 0));
      await pumpEventQueue();
      expect(vm.folders.first.id, before.last);
      vm.dispose();
    });
  });

  group('voice channels', () {
    setUp(() => chats.seedVoice = true);

    test('admins of older teams get the default voice channels', () async {
      joinAs(TeamRole.captain);
      final vm = ChatListViewModel(
        teamId: 't1',
        teamRepository: teams,
        chatRepository: chats,
        authRepository: auth,
        voiceRepository: voice,
      );
      await pumpEventQueue();
      expect(chats.voiceEnsured, 1);
      expect(vm.rooms.where((r) => r.isVoice).map((r) => r.name), [
        'Lounge',
        'Sideline',
        'Film Room',
      ]);
      expect(vm.folders.map((f) => f.name), contains('Voice Channels'));
      // Wide screens still open a text room by default.
      expect(vm.selectedId, 'general');
      vm.dispose();
    });

    test('players never add them', () async {
      joinAs(TeamRole.player);
      final vm = ChatListViewModel(
        teamId: 't1',
        teamRepository: teams,
        chatRepository: chats,
        authRepository: auth,
        voiceRepository: voice,
      );
      await pumpEventQueue();
      expect(chats.voiceEnsured, 0);
      vm.dispose();
    });

    test('a team that has voice channels is left alone', () async {
      joinAs(TeamRole.captain);
      chats.rooms['v'] = const ChatRoom(
        id: 'v',
        name: 'Huddle',
        kind: ChatRoomKind.voice,
        readRoles: {ChatAudience.everyone},
      );
      final vm = ChatListViewModel(
        teamId: 't1',
        teamRepository: teams,
        chatRepository: chats,
        authRepository: auth,
        voiceRepository: voice,
      );
      await pumpEventQueue();
      expect(chats.voiceEnsured, 0);
      vm.dispose();
    });

    test('joining, muting and leaving', () async {
      joinAs(TeamRole.player);
      final lounge = ChatRoom.defaultVoiceRooms().first;
      chats.rooms[lounge.id] = lounge;
      final vm = VoiceChannelViewModel(
        teamId: 't1',
        roomId: lounge.id,
        teamRepository: teams,
        chatRepository: chats,
        voiceRepository: voice,
        authRepository: auth,
      );
      final list = ChatListViewModel(
        teamId: 't1',
        teamRepository: teams,
        chatRepository: chats,
        authRepository: auth,
        voiceRepository: voice,
      );
      await pumpEventQueue();
      expect(vm.canSpeak, isTrue);
      expect(vm.connected, isFalse);
      await vm.join.execute();
      expect(vm.connected, isTrue);
      expect(voice.joins.single.name, 'Lounge');
      expect(vm.participants.single.isLocal, isTrue);
      expect(list.voiceChannel?.roomId, lounge.id);
      expect(list.voiceParticipants(lounge), hasLength(1));
      expect(vm.micOn, isTrue);
      await list.toggleMic.execute();
      expect(vm.micOn, isFalse);
      await list.leaveVoice.execute();
      expect(vm.connected, isFalse);
      expect(list.voiceChannel, isNull);
      vm.dispose();
      list.dispose();
    });

    test('members without access are not let in', () async {
      joinAs(TeamRole.player);
      chats.rooms['coaches'] = const ChatRoom(
        id: 'coaches',
        name: 'Coaches',
        kind: ChatRoomKind.voice,
        readRoles: {'coach'},
      );
      final vm = VoiceChannelViewModel(
        teamId: 't1',
        roomId: 'coaches',
        teamRepository: teams,
        chatRepository: chats,
        voiceRepository: voice,
        authRepository: auth,
      );
      await pumpEventQueue();
      await vm.join.execute();
      expect(vm.join.error, isTrue);
      expect(voice.joins, isEmpty);
      vm.dispose();
    });

    test('rooms keep their kind', () {
      final room = ChatRoom.fromMap('v', {'name': 'Lounge', 'kind': 'voice'});
      expect(room.isVoice, isTrue);
      expect(room.withKind(ChatRoomKind.text).isVoice, isTrue);
      expect(ChatRoom.fromMap('t', {'name': 'x'}).isVoice, isFalse);
      expect(ChatRoom.newIn(null).withKind(ChatRoomKind.voice).isVoice, isTrue);
      expect(const ChatRoom(id: 'x', name: 'Game Day').handle, 'game-day');
    });
  });
}
