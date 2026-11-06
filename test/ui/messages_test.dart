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
import 'package:frisbee_app/ui/chat/view_models/message_thread_viewmodel.dart';
import 'package:frisbee_app/ui/chat/widgets/message_thread_view.dart';
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
      expect(messagePreview('', 1, video: true), '🎬 Video');
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

  test('opening a chat clears its notification, and again for new '
      'messages from the other person', () async {
    await dms.openConversation(
      testUser,
      const UserProfile(uid: 'a', name: 'Avery'),
    );
    await dms.sendMessage(
      'a_u1',
      author: const AppUser(uid: 'a', displayName: 'Avery'),
      text: 'Hi',
    );
    final notices = FakeNotificationRepository();
    final vm = DirectChatViewModel(
      conversationId: 'a_u1',
      directMessageRepository: dms,
      authRepository: auth,
      filePicker: FakeFilePickerService(),
      notificationRepository: notices,
    );
    addTearDown(vm.dispose);
    await pumpEventQueue();
    expect(notices.seen, ['dm_a_u1']);
    // My own message doesn't need clearing.
    await vm.send.execute('Hey');
    await pumpEventQueue();
    expect(notices.seen, ['dm_a_u1']);
    await dms.sendMessage(
      'a_u1',
      author: const AppUser(uid: 'a', displayName: 'Avery'),
      text: 'Practice at 6',
    );
    await pumpEventQueue();
    expect(notices.seen, ['dm_a_u1', 'dm_a_u1']);
  });

  test('shows who is typing until they go quiet, and sends my typing '
      'at most every few seconds', () async {
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
    var clock = DateTime(2026, 11, 6, 9);
    vm.now = () => clock;
    await pumpEventQueue();
    expect(vm.typingLabel, isNull);

    dms.typed('a_u1', 'a', DateTime(2026, 11, 6, 8));
    await pumpEventQueue();
    expect(vm.typingLabel, 'Avery is typing…');
    // My own entry is never shown.
    dms.typed('a_u1', 'u1', DateTime(2026, 11, 6, 8));
    await pumpEventQueue();
    expect(vm.typingNames, ['Avery']);

    clock = clock.add(MessageThreadViewModel.typingFor);
    expect(vm.typingLabel, isNull, reason: 'quiet for too long');
    dms.typed('a_u1', 'a', DateTime(2026, 11, 6, 8, 1));
    await pumpEventQueue();
    expect(vm.typingLabel, 'Avery is typing…');
    dms.stoppedTyping('a_u1', 'a');
    await pumpEventQueue();
    expect(vm.typingLabel, isNull);

    vm.composerChanged('H');
    vm.composerChanged('He');
    clock = clock.add(MessageThreadViewModel.typingEvery);
    vm.composerChanged('Hey');
    vm.composerChanged('');
    expect(dms.typingSent, [('u1', true), ('u1', true), ('u1', false)]);
  });

  test('a photo from the camera joins the next message', () async {
    dms.follows.add(('a', testUser.uid));
    await dms.openConversation(
      testUser,
      const UserProfile(uid: 'a', name: 'Avery'),
    );
    final picker = FakeFilePickerService()
      ..canUseCamera = true
      ..nextPhoto = FakeFilePickerService.file('image_123.jpg', 2000);
    final vm = DirectChatViewModel(
      conversationId: 'a_u1',
      directMessageRepository: dms,
      authRepository: auth,
      filePicker: picker,
    );
    addTearDown(vm.dispose);
    await pumpEventQueue();
    expect(vm.canUseCamera, isTrue);
    await vm.takePhoto.execute();
    expect(vm.drafts.single.isImage, isTrue);
    // Cancelling the camera adds nothing.
    picker.nextPhoto = null;
    await vm.takePhoto.execute();
    expect(vm.drafts, hasLength(1));
    expect(vm.takePhoto.error, isFalse);
  });

  group('videos', () {
    Future<DirectChatViewModel> chat(
      FakeFilePickerService picker, {
      bool settle = true,
    }) async {
      dms.follows.add(('a', testUser.uid));
      await dms.openConversation(
        testUser,
        const UserProfile(uid: 'a', name: 'Avery'),
      );
      final vm = DirectChatViewModel(
        conversationId: 'a_u1',
        directMessageRepository: dms,
        authRepository: auth,
        filePicker: picker,
      );
      addTearDown(vm.dispose);
      if (settle) await pumpEventQueue();
      return vm;
    }

    test('a recorded video joins the next message, up to 100 MB', () async {
      final picker = FakeFilePickerService()
        ..canUseCamera = true
        ..nextRecording = FakeFilePickerService.file(
          'clip.mp4',
          40 * 1024 * 1024,
        );
      final vm = await chat(picker);
      await vm.recordVideo.execute();
      expect(vm.drafts.single.isVideo, isTrue);
      await vm.send.execute('');
      final sent = dms.messages['a_u1']!.single.attachments.single;
      expect(sent.isVideo, isTrue);
      expect(
        await vm.videoUrl(sent),
        isA<Ok<String>>().having(
          (r) => r.value,
          'url',
          'https://files.test/${sent.path}',
        ),
      );

      picker.nextRecording = FakeFilePickerService.file(
        'long.mp4',
        maxVideoBytes + 1,
      );
      await vm.recordVideo.execute();
      expect(vm.recordVideo.error, isTrue);
      expect(vm.recordVideo.result.toString(), contains('100.0 MB'));
      expect(vm.drafts, isEmpty);
    });

    test('other files stay capped at 10 MB', () async {
      final picker = FakeFilePickerService()
        ..next = [FakeFilePickerService.file('notes.pdf', 11 * 1024 * 1024)];
      final vm = await chat(picker);
      await vm.pickFiles.execute(false);
      expect(vm.pickFiles.result.toString(), contains('10.0 MB'));
      expect(vm.drafts, isEmpty);
    });

    testWidgets('a video plays from the conversation', (tester) async {
      final picker = FakeFilePickerService()
        ..canUseCamera = true
        ..nextRecording = FakeFilePickerService.file('clip.mp4', 5000);
      final vm = await chat(picker, settle: false);
      await tester.pumpWidget(
        withRepos(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: MessageThreadView(
                viewModel: vm,
                videoPlayer: (url) => Text('playing $url'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Upload a photo, video or file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record video'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Huck!');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.textContaining('Video ·'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_circle_fill));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'playing https://files.test/conversations/a_u1/u1/m1/0-clip.mp4',
        ),
        findsOneWidget,
      );
    });
  });

  group('message requests', () {
    const avery = AppUser(uid: 'a', displayName: 'Avery');
    const me = UserProfile(uid: 'u1', name: 'Alex');

    /// Avery messages the user, who doesn't follow them.
    Future<DirectChatViewModel> request() async {
      await dms.openConversation(avery, me);
      await dms.sendMessage('a_u1', author: avery, text: 'Want to pick up?');
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

    test(
      'starting one depends on who follows whom and their setting',
      () async {
        Future<Result<String>> open() async {
          dms.conversations.clear();
          return dms.openConversation(
            testUser,
            const UserProfile(uid: 'a', name: 'Avery'),
          );
        }

        Future<ConversationStatus?> statusFor(MessagePolicy p) async {
          dms.policies['a'] = p;
          final r = await open();
          return r is Ok ? dms.conversations['a_u1']!.status : null;
        }

        expect(
          await statusFor(MessagePolicy.everyone),
          ConversationStatus.request,
        );
        expect(await statusFor(MessagePolicy.followers), isNull);
        expect(await statusFor(MessagePolicy.following), isNull);
        dms.follows.add((testUser.uid, 'a'));
        expect(
          await statusFor(MessagePolicy.followers),
          ConversationStatus.request,
        );
        dms.follows.add(('a', testUser.uid));
        expect(
          await statusFor(MessagePolicy.following),
          ConversationStatus.accepted,
        );
        expect(await statusFor(MessagePolicy.nobody), isNull);
        final r = await open();
        expect(
          (r as Error).error,
          isA<MessagingNotAllowedException>().having(
            (e) => '$e',
            'message',
            "Avery isn't accepting messages from you.",
          ),
        );
      },
    );

    test(
      'a request waits in Requests, read without a receipt or reply',
      () async {
        final vm = await request();
        final inbox = InboxViewModel(
          directMessageRepository: dms,
          authRepository: auth,
        );
        addTearDown(inbox.dispose);
        await pumpEventQueue();
        expect(inbox.allItems, isEmpty);
        expect(inbox.requestItems.single.title, 'Avery');
        expect(inbox.requestCount, 1);
        expect(inbox.unreadCount, 0, reason: 'requests count apart');

        expect(vm.isRequest, isTrue);
        expect(vm.canWrite, isFalse);
        expect(dms.reads, ['a_u1']);
        expect(
          dms.conversations['a_u1']!.readAt.containsKey('u1'),
          isFalse,
          reason: "Avery can't tell it was read",
        );

        await vm.accept.execute();
        await pumpEventQueue();
        expect(vm.isRequest, isFalse);
        expect(vm.canWrite, isTrue);
        expect(inbox.allItems.single.title, 'Avery');
        expect(inbox.requestItems, isEmpty);
      },
    );

    test('deleting a request hides it for good, quietly', () async {
      final vm = await request();
      await vm.decline.execute();
      await pumpEventQueue();
      final inbox = InboxViewModel(
        directMessageRepository: dms,
        authRepository: auth,
      );
      addTearDown(inbox.dispose);
      await pumpEventQueue();
      expect(inbox.allItems, isEmpty);
      expect(inbox.requestItems, isEmpty);
      // More from Avery doesn't bring it back.
      dms.clock = DateTime(2026, 11, 2);
      await dms.sendMessage('a_u1', author: avery, text: 'Hello?');
      await pumpEventQueue();
      expect(inbox.allItems, isEmpty);
      expect(inbox.archivedItems, isEmpty);
      // From Avery's side it still looks pending.
      expect(dms.conversations['a_u1']!.isPendingFrom('a'), isTrue);
    });

    test('the request sender sees "Request sent", never "Seen"', () async {
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
      expect(vm.isPending, isTrue);
      expect(vm.canWrite, isTrue);
      await vm.send.execute('Hi');
      await pumpEventQueue();
      expect(vm.receiptFor(vm.messages.single), isNull);
    });
  });

  group('archive and delete', () {
    Future<(DirectChatViewModel, InboxViewModel)> chat() async {
      dms.follows.add(('a', testUser.uid));
      await dms.openConversation(
        testUser,
        const UserProfile(uid: 'a', name: 'Avery'),
      );
      await dms.sendMessage(
        'a_u1',
        author: const AppUser(uid: 'a', displayName: 'Avery'),
        text: 'Old news',
      );
      final vm = DirectChatViewModel(
        conversationId: 'a_u1',
        directMessageRepository: dms,
        authRepository: auth,
        filePicker: FakeFilePickerService(),
      );
      addTearDown(vm.dispose);
      final inbox = InboxViewModel(
        directMessageRepository: dms,
        authRepository: auth,
      );
      addTearDown(inbox.dispose);
      await pumpEventQueue();
      return (vm, inbox);
    }

    test('archiving moves it out of the inbox until a new message', () async {
      final (vm, inbox) = await chat();
      dms.clock = DateTime(2026, 11, 2, 12);
      await vm.toggleArchived.execute();
      await pumpEventQueue();
      expect(vm.isArchived, isTrue);
      expect(inbox.allItems, isEmpty);
      expect(inbox.archivedItems.single.title, 'Avery');

      // Unarchive from the inbox, archive again, then a new message.
      await inbox.archive.execute(inbox.archivedItems.single);
      await pumpEventQueue();
      expect(inbox.allItems, hasLength(1));
      await inbox.archive.execute(inbox.allItems.single);
      await pumpEventQueue();
      expect(inbox.allItems, isEmpty);
      dms.messages['a_u1']!.clear();
      await dms.sendMessage(
        'a_u1',
        author: const AppUser(uid: 'a', displayName: 'Avery'),
        text: 'Practice moved',
      );
      // The fake stamps messages in 2026-10-30; push this one past.
      dms.conversations['a_u1'] = dms.conversations['a_u1']!.copyWith(
        lastMessageAt: DateTime(2026, 11, 3),
      );
      dms.emit();
      await pumpEventQueue();
      expect(inbox.allItems.single.title, 'Avery');
      expect(inbox.archivedItems, isEmpty);
    });

    test('deleting it hides its messages from me only', () async {
      final (vm, inbox) = await chat();
      expect(vm.messages, hasLength(1));
      dms.clock = DateTime(2026, 11, 2, 12);
      await vm.clear.execute();
      await pumpEventQueue();
      expect(vm.messages, isEmpty);
      expect(vm.hasMore, isFalse);
      expect(inbox.allItems, isEmpty);
      expect(inbox.archivedItems, isEmpty);
      expect(dms.messages['a_u1'], hasLength(1), reason: 'Avery keeps them');
    });
  });

  group('read receipts', () {
    Future<DirectChatViewModel> chat() async {
      // Avery follows the user, so it's an ordinary conversation.
      dms.follows.add(('a', testUser.uid));
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

  testWidgets('a request shows Accept and Delete instead of the composer, '
      'and sits under Requests', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const avery = AppUser(uid: 'a', displayName: 'Avery');
    await dms.openConversation(avery, const UserProfile(uid: 'u1', name: 'A'));
    await dms.sendMessage('a_u1', author: avery, text: 'Want to pick up?');
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
    expect(find.text('Message request'), findsOneWidget);
    expect(find.text('Avery wants to message you'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Avery wants to message you'), findsNothing);

    final list = inbox();
    addTearDown(list.dispose);
    dms.conversations['a_u1'] = dms.conversations['a_u1']!.copyWith(
      status: ConversationStatus.request,
    );
    dms.emit();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: InboxScreen(viewModel: list),
      ),
    );
    await tester.pump();
    expect(find.text('Avery'), findsNothing);
    await tester.tap(find.text('Requests (1)'));
    await tester.pump();
    expect(find.text('Avery'), findsOneWidget);
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
