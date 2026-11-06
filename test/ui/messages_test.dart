import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/model_utils.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/messages/view_models/direct_chat_viewmodel.dart';
import 'package:frisbee_app/ui/messages/view_models/inbox_viewmodel.dart';
import 'package:frisbee_app/ui/messages/view_models/people_search_viewmodel.dart';
import 'package:frisbee_app/ui/messages/widgets/direct_chat_screen.dart';
import 'package:frisbee_app/ui/messages/widgets/inbox_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

void main() {
  group('UserProfile', () {
    test('indexes every word prefix, lowercased', () {
      final k = searchKeywords('Jo Smith-Lee');
      expect(k, containsAll(['j', 'jo', 's', 'smi', 'smith', 'l', 'lee']));
      expect(k, isNot(contains('Jo')));
    });

    test('matches when every query word starts a name word', () {
      const p = UserProfile(uid: 'x', name: 'Jordan Smith');
      expect(p.matches('jor'), isTrue);
      expect(p.matches('smi jo'), isTrue);
      expect(p.matches('jordan x'), isFalse);
    });
  });

  group('Conversation', () {
    test('ids are the sorted uid pair', () {
      expect(Conversation.idFor('b', 'a'), 'a_b');
      expect(Conversation.idFor('a', 'b'), 'a_b');
    });

    test('unread only when the other person posted after you read', () {
      final at = DateTime(2026, 10, 30, 12);
      Conversation c({String sender = 'a', DateTime? read}) => Conversation(
        id: 'a_u1',
        participants: const ['a', 'u1'],
        names: const {'a': 'Avery'},
        lastMessageAt: at,
        lastSenderId: sender,
        readAt: {'u1': ?read},
      );
      expect(c().isUnread('u1'), isTrue);
      expect(
        c(read: at.add(const Duration(seconds: 1))).isUnread('u1'),
        isFalse,
      );
      expect(c(sender: 'u1').isUnread('u1'), isFalse);
      expect(c().otherName('u1'), 'Avery');
    });

    test('previews text or attachments', () {
      expect(messagePreview('  hi\n there ', 0), 'hi there');
      expect(messagePreview('', 2, image: true), '📷 2 photos');
      expect(messagePreview('', 1), '📎 File');
      expect(messagePreview('x' * 200, 0).length, 118);
    });
  });

  late FakeDirectMessageRepository dms;
  late FakeAuthRepository auth;
  late FakeTeamRepository teams;
  late FakeChatRepository chats;

  setUp(() {
    dms = FakeDirectMessageRepository()
      ..profiles.addAll(const [
        UserProfile(uid: 'a', name: 'Avery Jones'),
        UserProfile(uid: 'b', name: 'Blake Jordan'),
        UserProfile(uid: 'u1', name: 'Alex'),
      ]);
    auth = FakeAuthRepository(user: testUser);
    teams = FakeTeamRepository();
    chats = FakeChatRepository();
  });

  Widget withRepos(Widget child) => MultiProvider(
    providers: [
      Provider<DirectMessageRepository>.value(value: dms),
      Provider<TeamRepository>.value(value: teams),
      Provider<ChatRepository>.value(value: chats),
      ChangeNotifierProvider<AuthRepository>.value(value: auth),
      Provider<FilePickerService>.value(value: FakeFilePickerService()),
    ],
    child: child,
  );

  InboxViewModel inbox() =>
      InboxViewModel(directMessageRepository: dms, authRepository: auth);

  test('search finds people by name, not yourself, and opens a chat', () async {
    final vm = PeopleSearchViewModel(
      directMessageRepository: dms,
      authRepository: auth,
    );
    await vm.search.execute('j');
    expect(vm.results, isEmpty, reason: 'too short');
    await vm.search.execute('jo');
    expect(vm.results.map((p) => p.uid), ['a', 'b']);
    await vm.search.execute('alex');
    expect(vm.noMatches, isTrue);
    await vm.open.execute(dms.profiles.first);
    expect((vm.open.result as Ok<String>).value, 'a_u1');
    expect(dms.conversations['a_u1']!.names['a'], 'Avery Jones');
  });

  test('a chat posts messages and marks incoming ones read', () async {
    await dms.openConversation(
      testUser,
      const UserProfile(uid: 'a', name: 'Avery'),
    );
    await dms.sendMessage(
      'a_u1',
      author: const AppUser(uid: 'a', displayName: 'Avery'),
      text: 'Need a ride?',
    );
    final vm = DirectChatViewModel(
      conversationId: 'a_u1',
      directMessageRepository: dms,
      authRepository: auth,
      filePicker: FakeFilePickerService(),
    );
    addTearDown(vm.dispose);
    await pumpEventQueue();
    expect(vm.otherName, 'Avery');
    expect(vm.canWrite, isTrue);
    expect(dms.reads, ['a_u1']);
    expect(vm.messages.single.text, 'Need a ride?');
    await vm.send.execute('Yes please');
    await pumpEventQueue();
    expect(vm.messages.map((m) => m.text), ['Need a ride?', 'Yes please']);
    expect(vm.canDelete(vm.messages.first), isFalse);
    expect(vm.canDelete(vm.messages.last), isTrue);
  });

  test('messages and the header show usernames once looked up', () async {
    await dms.openConversation(
      testUser,
      const UserProfile(uid: 'a', name: 'Avery'),
    );
    await dms.sendMessage(
      'a_u1',
      author: const AppUser(uid: 'a', displayName: 'Avery'),
      text: 'Hi',
    );
    final people = FakePeopleRepository(const [
      UserProfile(uid: 'a', name: 'Avery', username: 'avery7'),
    ]);
    final vm = DirectChatViewModel(
      conversationId: 'a_u1',
      directMessageRepository: dms,
      authRepository: auth,
      filePicker: FakeFilePickerService(),
      peopleRepository: people,
    );
    addTearDown(vm.dispose);
    await pumpEventQueue();
    expect(vm.usernameOf('a'), 'avery7');
    expect(vm.otherUsername, 'avery7');
    expect(vm.usernameOf(testUser.uid), isNull);
  });

  group('read receipts', () {
    Future<DirectChatViewModel> chat() async {
      await dms.openConversation(
        testUser,
        const UserProfile(uid: 'a', name: 'Avery'),
      );
      final vm = DirectChatViewModel(
        conversationId: 'a_u1',
        directMessageRepository: dms,
        authRepository: auth,
        filePicker: FakeFilePickerService(),
      );
      addTearDown(vm.dispose);
      await pumpEventQueue();
      return vm;
    }

    test('show Seen under my newest message once they read it', () async {
      final vm = await chat();
      await vm.send.execute('Ride at 6?');
      await pumpEventQueue();
      expect(vm.receiptFor(vm.messages.last), isNull);

      await dms.markRead('a_u1', 'a', shareReceipt: true);
      await pumpEventQueue();
      expect(vm.receiptFor(vm.messages.last), 'Seen');
    });

    test('turned off: reads stay private and theirs are hidden', () async {
      await dms.setReadReceipts(testUser.uid, on: false);
      await dms.openConversation(
        testUser,
        const UserProfile(uid: 'a', name: 'Avery'),
      );
      await dms.sendMessage(
        'a_u1',
        author: const AppUser(uid: 'a', displayName: 'Avery'),
        text: 'Need a ride?',
      );
      final vm = await chat();
      // Read privately: no longer unread, but no receipt for Avery.
      expect(dms.reads, ['a_u1']);
      expect(dms.conversations['a_u1']!.readAt[testUser.uid], isNull);
      expect(vm.conversation!.isUnread(testUser.uid), isFalse);

      await vm.send.execute('Yes please');
      await dms.markRead('a_u1', 'a', shareReceipt: true);
      await pumpEventQueue();
      expect(vm.receiptFor(vm.messages.last), isNull);
    });
  });

  testWidgets('inbox lists conversations with unread marks', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dms.conversations['a_u1'] = Conversation(
      id: 'a_u1',
      participants: const ['a', 'u1'],
      names: const {'a': 'Avery Jones'},
      lastMessage: 'See you at practice',
      lastMessageAt: DateTime(2026, 10, 1),
      lastSenderId: 'a',
    );
    final vm = inbox();
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: InboxScreen(viewModel: vm),
      ),
    );
    await tester.pump();
    expect(find.text('Avery Jones'), findsOneWidget);
    expect(find.text('See you at practice'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsOneWidget);
  });

  testWidgets('direct chat screen sends a message', (tester) async {
    await dms.openConversation(
      testUser,
      const UserProfile(uid: 'a', name: 'Avery'),
    );
    final vm = DirectChatViewModel(
      conversationId: 'a_u1',
      directMessageRepository: dms,
      authRepository: auth,
      filePicker: FakeFilePickerService(),
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      withRepos(
        MaterialApp(
          theme: AppTheme.light,
          home: DirectChatScreen(viewModel: vm),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Avery'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Hey!');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(find.text('Hey!'), findsOneWidget);
    // On a phone, back goes to Messages; no conversation panel on top.
    expect(find.byTooltip('Chats'), findsNothing);
  });

  testWidgets('on a phone, back from a conversation goes to Messages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await dms.openConversation(
      testUser,
      const UserProfile(uid: 'a', name: 'Avery'),
    );
    final router = GoRouter(
      initialLocation: '/messages',
      routes: [
        GoRoute(
          path: '/messages',
          builder: (_, _) => const Scaffold(body: Text('Messages list')),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, state) => DirectChatScreen(
                viewModel: DirectChatViewModel(
                  conversationId: state.pathParameters['id']!,
                  directMessageRepository: dms,
                  authRepository: auth,
                  filePicker: FakeFilePickerService(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      withRepos(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    router.push('/messages/a_u1');
    await tester.pumpAndSettle();
    expect(find.text('Avery'), findsOneWidget);
    expect(find.byTooltip('Chats'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Messages list'), findsOneWidget);
    expect(find.byType(DirectChatScreen), findsNothing);
  });

  testWidgets('wide inbox opens the newest conversation beside the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await dms.openConversation(
      testUser,
      const UserProfile(uid: 'a', name: 'Avery'),
    );
    await dms.sendMessage(
      'a_u1',
      author: const AppUser(uid: 'a', displayName: 'Avery'),
      text: 'Ride at 6?',
    );
    final vm = inbox();
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      withRepos(
        MaterialApp(
          theme: AppTheme.light,
          home: InboxScreen(viewModel: vm),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(vm.selectedId, 'a_u1');
    // The preview in the list and the message in the open pane.
    expect(find.text('Ride at 6?'), findsNWidgets(2));
    // One New message button, in the page header; none on the list.
    expect(find.text('New message'), findsOneWidget);
    expect(find.byTooltip('New message'), findsNothing);
  });

  test('the inbox lists only private messages, not team chats', () async {
    teams.teams['t1'] = teamWith({
      'owner': TeamRole.owner,
      testUser.uid: TeamRole.player,
    });
    chats.rooms['general'] = ChatRoom.general();
    chats.messages['general'] = [
      ChatMessage(
        id: 'm1',
        authorId: 'a',
        authorName: 'Avery Jones',
        text: 'Field 3 at noon',
        createdAt: DateTime(2026, 10, 2),
      ),
    ];
    for (final (uid, name) in [('a', 'Avery'), ('b', 'Blake')]) {
      await dms.openConversation(testUser, UserProfile(uid: uid, name: name));
    }
    await dms.sendMessage(
      'a_u1',
      author: const AppUser(uid: 'a', displayName: 'Avery'),
      text: 'Ride at 6?',
    );
    await dms.sendMessage('b_u1', author: testUser, text: 'Hi');
    final vm = inbox();
    addTearDown(vm.dispose);
    await pumpEventQueue();
    expect(
      vm.allItems.map((i) => i.title),
      unorderedEquals(['Avery', 'Blake']),
    );
    expect(
      vm.allItems.map((i) => i.preview),
      isNot(contains(contains('Field'))),
    );
    vm.setFilter(InboxFilter.unread);
    expect(vm.items.single.title, 'Avery');
    vm.setFilter(InboxFilter.all);
    vm.setQuery('bla');
    expect(vm.items.single.title, 'Blake');
  });
}
