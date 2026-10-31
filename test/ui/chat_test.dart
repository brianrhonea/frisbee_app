import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_list_viewmodel.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_room_settings_viewmodel.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_room_viewmodel.dart';
import 'package:frisbee_app/ui/chat/view_models/message_thread_viewmodel.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_room_screen.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_tab.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  // u1 is signed in (testUser).
  const captains = ChatRoom(
    id: 'caps',
    name: 'Captains',
    readRoles: {TeamRole.coach, TeamRole.captain},
    writeRoles: {TeamRole.captain},
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
        writeRoles: {TeamRole.player},
        writeUsers: {'x'},
      ).toMap();
      expect(map['name'], 'Room');
      expect(map['readRoles'], ['player']);
      expect(map['readUsers'], ['x']);
      final back = ChatRoom.fromMap('r', map);
      expect(back.roleAccess(TeamRole.player), ChatAccess.write);
    });

    test('lowering access removes write first', () {
      final r = captains.withRoleAccess(TeamRole.captain, ChatAccess.read);
      expect(r.roleAccess(TeamRole.captain), ChatAccess.read);
      expect(r.withRoleAccess(TeamRole.captain, ChatAccess.none).readRoles, {
        TeamRole.coach,
      });
    });

    test('describes its audience', () {
      expect(ChatRoom.general().audience, 'Everyone');
      expect(captains.audience, 'Coaches, Captains + 1 person');
      expect(const ChatRoom(id: 'r', name: 'Owner only').audience, 'Owner');
    });

    test('drops grants for people who left the team', () {
      final r = captains.withUserAccess('gone', ChatAccess.write);
      expect(r.forMembersOf(team).readUsers, {'p2'});
      expect(r.forMembersOf(team).writeUsers, isEmpty);
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

  setUp(() {
    teams = FakeTeamRepository();
    chats = FakeChatRepository()
      ..rooms['general'] = ChatRoom.general()
      ..rooms['caps'] = captains;
    auth = FakeAuthRepository(user: testUser);
    picker = FakeFilePickerService();
    notifications = FakeNotificationRepository();
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

    test('authors delete their own messages; the owner deletes any', () async {
      chats.messages['general'] = [
        const ChatMessage(id: 'm1', authorId: 'p2', authorName: 'Pat'),
      ];
      joinAs(TeamRole.captain);
      var vm = load('general');
      await pumpEventQueue();
      expect(vm.canDelete(vm.messages.single), isFalse);
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
        ..setRoleAccess(TeamRole.player, ChatAccess.none)
        ..setUserAccess('p2', ChatAccess.write);
      await vm.save.execute();
      final id = (vm.save.result as Ok<String>).value;
      final saved = chats.rooms[id]!;
      expect(saved.name, 'Handlers');
      expect(saved.roleAccess(TeamRole.player), ChatAccess.none);
      expect(saved.userAccess('p2'), ChatAccess.write);
      expect(vm.members.map((m) => m.uid), isNot(contains('o')));
      vm.dispose();
    });

    test('only the owner deletes rooms, never General', () async {
      joinAs(TeamRole.coach);
      var vm = load(roomId: 'caps');
      await pumpEventQueue();
      expect(vm.canManage, isTrue);
      expect(vm.canDelete, isFalse);
      vm.dispose();
      joinAs(TeamRole.owner);
      vm = load(roomId: 'caps');
      await pumpEventQueue();
      expect(vm.canDelete, isTrue);
      vm.dispose();
      vm = load(roomId: 'general');
      await pumpEventQueue();
      expect(vm.canDelete, isFalse);
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
    // Captains sorts first in the fake, so it opens by default.
    expect(vm.selectedId, 'caps');
    expect(find.text('No messages yet'), findsOneWidget);
    await tester.tap(find.text('General'));
    await tester.pump();
    await tester.pump();
    expect(vm.selectedId, 'general');
    expect(find.text('Say hello to the team.'), findsOneWidget);
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
      expect(find.text('Captains'), findsNothing);
      await tester.tap(find.byTooltip('Chats'));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('Captains'), findsOneWidget);
      // Tapping the open room returns to it.
      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('General'),
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
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Bring both jerseys'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

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
}
