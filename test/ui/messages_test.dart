import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/messages/view_models/direct_chat_viewmodel.dart';
import 'package:frisbee_app/ui/messages/view_models/inbox_viewmodel.dart';
import 'package:frisbee_app/ui/messages/view_models/people_search_viewmodel.dart';
import 'package:frisbee_app/ui/messages/widgets/direct_chat_screen.dart';
import 'package:frisbee_app/ui/messages/widgets/inbox_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  group('UserProfile', () {
    test('indexes every word prefix, lowercased', () {
      final k = UserProfile.searchKeywords('Jo Smith-Lee');
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

  setUp(() {
    dms = FakeDirectMessageRepository()
      ..profiles.addAll(const [
        UserProfile(uid: 'a', name: 'Avery Jones'),
        UserProfile(uid: 'b', name: 'Blake Jordan'),
        UserProfile(uid: 'u1', name: 'Alex'),
      ]);
    auth = FakeAuthRepository(user: testUser);
  });

  Widget withRepos(Widget child) => MultiProvider(
    providers: [
      Provider<DirectMessageRepository>.value(value: dms),
      ChangeNotifierProvider<AuthRepository>.value(value: auth),
      Provider<FilePickerService>.value(value: FakeFilePickerService()),
    ],
    child: child,
  );

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

  testWidgets('inbox lists conversations with unread marks', (tester) async {
    dms.conversations['a_u1'] = Conversation(
      id: 'a_u1',
      participants: const ['a', 'u1'],
      names: const {'a': 'Avery Jones'},
      lastMessage: 'See you at practice',
      lastMessageAt: DateTime(2026, 10, 1),
      lastSenderId: 'a',
    );
    final vm = InboxViewModel(
      directMessageRepository: dms,
      authRepository: auth,
    );
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
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Hey!'), findsOneWidget);
    // The Chats button opens the conversation panel.
    await tester.tap(find.byTooltip('Chats'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Drawer), matching: find.text('Avery')),
      findsOneWidget,
    );
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
    final vm = InboxViewModel(
      directMessageRepository: dms,
      authRepository: auth,
    );
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
  });
}
