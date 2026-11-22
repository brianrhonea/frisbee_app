// Polls posted into team rooms (redesign F33).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/voice/voice_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_poll_viewmodel.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_room_viewmodel.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_room_screen.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';

import '../testing/fakes.dart';
import '../testing/voice_fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeChatRepository chats;
  late FakeAuthRepository auth;
  late FakeFilePickerService picker;
  late FakeNotificationRepository notifications;
  late FakeVoiceRepository voice;
  late FakeEventRepository events;

  ChatMessage poll(
    String id, {
    String author = 'p2',
    bool multiple = false,
    Map<String, List<int>> votes = const {},
    DateTime? closesAt,
    DateTime? closedAt,
  }) => ChatMessage(
    id: id,
    authorId: author,
    authorName: 'Riley',
    createdAt: DateTime(2026, 11, 1, 10),
    poll: ChatPoll(
      question: 'Which day?',
      options: const ['Saturday', 'Sunday', 'Both'],
      multiple: multiple,
      votes: votes,
      closesAt: closesAt,
      closedAt: closedAt,
    ),
  );

  setUp(() {
    teams = FakeTeamRepository();
    chats = FakeChatRepository()
      ..rooms['general'] = ChatRoom.general()
      ..seedVoice = false
      ..messages['general'] = [
        ChatMessage(
          id: 'm0',
          authorId: 'p2',
          authorName: 'Riley',
          text: 'Hello',
          createdAt: DateTime(2026, 11, 1, 9),
        ),
      ];
    auth = FakeAuthRepository(user: testUser);
    picker = FakeFilePickerService();
    notifications = FakeNotificationRepository();
    voice = FakeVoiceRepository();
    events = FakeEventRepository();
  });

  void joinAs(TeamRole role, {Set<TeamPermission> perms = const {}}) =>
      teams.teams['t1'] =
          teamWith({
            'o': TeamRole.owner,
            'u1': role,
            'p2': TeamRole.player,
          }).copyWith(
            memberPerms: {if (perms.isNotEmpty) 'u1': perms},
            memberNames: const {'u1': 'Alex', 'p2': 'Riley'},
          );

  ChatRoomViewModel load() => ChatRoomViewModel(
    teamId: 't1',
    roomId: 'general',
    teamRepository: teams,
    chatRepository: chats,
    notificationRepository: notifications,
    authRepository: auth,
    filePicker: picker,
  );

  ChatPollCardViewModel card(ChatMessage m, {bool canManage = false}) {
    chats.messages['general']!.add(m);
    final vm = ChatPollCardViewModel(
      teamId: 't1',
      roomId: 'general',
      message: m,
      chatRepository: chats,
      authRepository: auth,
      canManage: () => canManage,
      nameOf: (uid) => {'u1': 'Alex', 'p2': 'Riley'}[uid] ?? 'Member',
    );
    addTearDown(vm.dispose);
    return vm;
  }

  group('ChatPoll', () {
    test('counts, toggles and closes as packages/shared does', () {
      const p = ChatPoll(
        question: 'Q',
        options: ['a', 'b', 'c'],
        votes: {
          'x': [0],
          'y': [0, 2],
          'z': [],
        },
      );
      expect(p.counts, [2, 0, 1]);
      expect(p.voterCount, 2);
      expect(p.votersFor(0), ['x', 'y']);
      expect(p.toggle([], 1), [1]);
      expect(p.toggle([1], 1), isEmpty);
      expect(p.toggle([1], 2), [2]);
      const multi = ChatPoll(
        question: 'Q',
        options: ['a', 'b'],
        multiple: true,
      );
      expect(multi.toggle([1], 0), [0, 1]);
      final now = DateTime(2026, 11, 20);
      expect(p.isClosed(now), isFalse);
      expect(
        ChatPoll(question: 'Q', options: const [], closesAt: now).isClosed(now),
        isTrue,
      );
    });

    test('reads from the message, previews and survives a reaction', () {
      final m = ChatMessage.fromMap('m1', {
        'authorId': 'p2',
        'text': '',
        'poll': {
          'question': 'Which day?',
          'options': ['Sat', 'Sun'],
          'multiple': true,
          'votes': {
            'p2': [1],
          },
        },
      });
      expect(m.poll?.multiple, isTrue);
      expect(m.poll?.picksOf('p2'), [1]);
      expect(m.preview, '📊 Which day?');
      expect(m.withReaction('u1', '👍').poll?.question, 'Which day?');
    });
  });

  group('ChatRoomViewModel', () {
    test('anyone who can post asks a poll, through the API', () async {
      joinAs(TeamRole.player);
      final vm = load();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.canPoll, isTrue);
      expect(vm.canManagePolls, isFalse);
      chats.hasApi = false;
      expect(vm.canPoll, isFalse);
    });

    test('chat managers manage polls', () async {
      joinAs(TeamRole.player, perms: {TeamPermission.manageChats});
      final vm = load();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.canManagePolls, isTrue);
      expect(vm.nameOf('p2'), 'Riley');
    });
  });

  group('ChatPollFormViewModel', () {
    test('needs a question and 2–6 different options; then posts', () async {
      final now = DateTime(2026, 11, 20, 12);
      final form = ChatPollFormViewModel(
        teamId: 't1',
        roomId: 'general',
        chatRepository: chats,
        now: () => now,
      );
      addTearDown(form.dispose);
      expect(form.problem, 'Ask a question.');
      form.setQuestion(' Which day? ');
      expect(form.problem, 'Fill in every option, or remove it.');
      final [a, b] = form.options;
      form
        ..setOption(a.id, 'Sat')
        ..setOption(b.id, 'sat');
      expect(form.problem, 'Each option must be different.');
      form.setOption(b.id, 'Sun ');
      expect(form.problem, isNull);
      expect(form.canRemoveOption, isFalse);
      for (var i = 0; i < 10; i++) {
        form.addOption();
      }
      expect(form.options, hasLength(chatPollOptionsMax));
      expect(form.canAddOption, isFalse);
      for (final o in form.options.skip(2).toList()) {
        form.removeOption(o.id);
      }
      expect(form.options.map((o) => o.text), ['Sat', 'Sun ']);
      form.setClosesAt(now.subtract(const Duration(minutes: 1)));
      expect(form.problem, 'Pick a closing time in the future.');
      final closes = now.add(const Duration(days: 1));
      form
        ..setClosesAt(closes)
        ..setMultiple(true);
      await form.submit.execute();
      expect(chats.polls, hasLength(1));
      final (room, sent) = chats.polls.single;
      expect(room, 'general');
      expect(sent.question, 'Which day?');
      expect(sent.options, ['Sat', 'Sun']);
      expect(sent.multiple, isTrue);
      expect(sent.closesAt, closes);
    });
  });

  group('ChatPollCardViewModel', () {
    test('votes, takes it back, and a single choice replaces', () async {
      final vm = card(
        poll(
          'q1',
          votes: const {
            'p2': [0],
          },
        ),
      );
      await pumpEventQueue();
      expect(vm.needsVote, isTrue);
      expect(vm.counts, [1, 0, 0]);
      vm.tap(1);
      await pumpEventQueue();
      expect(chats.votes.last.$2, [1]);
      expect(vm.mine, [1]);
      expect(vm.counts, [1, 1, 0]);
      expect(vm.voterCount, 2);
      expect(vm.needsVote, isFalse);
      vm.tap(0);
      await pumpEventQueue();
      expect(vm.mine, [0]);
      expect(vm.counts, [2, 0, 0]);
      vm.tap(0);
      await pumpEventQueue();
      expect(vm.mine, isEmpty);
      expect(vm.voterCount, 1);
      expect(vm.votersFor(0), ['Riley']);
    });

    test('a multiple-choice poll keeps several picks', () async {
      final vm = card(poll('q1', multiple: true));
      await pumpEventQueue();
      vm.tap(2);
      await pumpEventQueue();
      vm.tap(0);
      await pumpEventQueue();
      expect(vm.mine, [0, 2]);
      expect(vm.voterCount, 1);
    });

    test(
      'closes for its author or chat managers; closed takes no votes',
      () async {
        final theirs = card(poll('q1'));
        await pumpEventQueue();
        expect(theirs.canClose, isFalse);
        final managed = card(poll('q2'), canManage: true);
        await pumpEventQueue();
        expect(managed.canClose, isTrue);
        final mine = card(poll('q3', author: 'u1'));
        await pumpEventQueue();
        expect(mine.canClose, isTrue);
        await mine.close.execute();
        await pumpEventQueue();
        expect(mine.isClosed, isTrue);
        expect(mine.canVote, isFalse);
        expect(mine.needsVote, isFalse);
        mine.tap(0);
        expect(chats.votes, isEmpty);
        final past = card(
          poll(
            'q4',
            closesAt: DateTime.now().subtract(const Duration(hours: 1)),
          ),
        );
        await pumpEventQueue();
        expect(past.isClosed, isTrue);
      },
    );

    test('says so when the message is deleted', () async {
      final vm = card(poll('q1'));
      await pumpEventQueue();
      chats.messages['general']!.removeWhere((m) => m.id == 'q1');
      chats.emit();
      await pumpEventQueue();
      expect(vm.deleted, isTrue);
      expect(vm.poll, isNull);
    });
  });

  group('ChatRoomScreen', () {
    Widget withRepos(Widget child) => MultiProvider(
      providers: [
        Provider<TeamRepository>.value(value: teams),
        Provider<ChatRepository>.value(value: chats),
        Provider<EventRepository>.value(value: events),
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
        Provider<FilePickerService>.value(value: picker),
        Provider<NotificationRepository>.value(value: notifications),
        ChangeNotifierProvider<VoiceRepository>.value(value: voice),
      ],
      child: child,
    );

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = load();
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
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a poll shows as a card that votes and lists voters', (
      tester,
    ) async {
      joinAs(TeamRole.player);
      chats.messages['general']!.add(
        poll(
          'q1',
          votes: const {
            'p2': [1],
          },
        ),
      );
      await pump(tester);
      expect(find.text('Which day?'), findsOneWidget);
      expect(find.text('POLL · PICK ONE'), findsOneWidget);
      expect(find.text('1 vote'), findsOneWidget);
      expect(find.text('Vote'), findsOneWidget);
      // Not theirs, and they don't manage chats.
      expect(find.text('Close poll'), findsNothing);
      await tester.tap(find.text('Saturday'));
      await tester.pump();
      await tester.pump();
      expect(chats.votes.single.$1, 'q1');
      expect(chats.votes.single.$2, [0]);
      expect(find.text('2 votes'), findsOneWidget);
      expect(find.text('Vote'), findsNothing);
      await tester.tap(find.text('See votes'));
      await tester.pumpAndSettle();
      expect(find.text('Saturday · 1'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Riley'), findsWidgets);
    });

    testWidgets('a closed poll says so and takes no votes', (tester) async {
      joinAs(TeamRole.player);
      chats.messages['general']!.add(
        poll('q1', closedAt: DateTime(2026, 11, 2)),
      );
      await pump(tester);
      expect(find.text('0 votes · Poll closed'), findsOneWidget);
      expect(find.text('Vote'), findsNothing);
      await tester.tap(find.text('Saturday'));
      await tester.pump();
      expect(chats.votes, isEmpty);
    });

    testWidgets('its author closes it early', (tester) async {
      joinAs(TeamRole.player);
      chats.messages['general']!.add(poll('q1', author: 'u1'));
      await pump(tester);
      await tester.tap(find.text('Close poll'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Close poll'));
      await tester.pumpAndSettle();
      expect(find.text('0 votes · Poll closed'), findsOneWidget);
    });

    testWidgets("chat managers close anyone's poll", (tester) async {
      joinAs(TeamRole.player, perms: {TeamPermission.manageChats});
      chats.messages['general']!.add(poll('q1'));
      await pump(tester);
      await tester.tap(find.text('Close poll'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Close poll'));
      await tester.pumpAndSettle();
      expect(find.text('0 votes · Poll closed'), findsOneWidget);
    });

    testWidgets('anyone who can post asks one from the attach menu', (
      tester,
    ) async {
      joinAs(TeamRole.player);
      await pump(tester);
      await tester.tap(find.byTooltip('Upload a photo, video or file'));
      await tester.pumpAndSettle();
      expect(find.text('Share an event'), findsNothing);
      await tester.tap(find.text('Poll'));
      await tester.pumpAndSettle();
      expect(find.text('New poll'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('poll-question')),
        'Which day?',
      );
      await tester.enterText(
        find.byKey(const ValueKey('poll-option-0')),
        'Sat',
      );
      await tester.enterText(
        find.byKey(const ValueKey('poll-option-1')),
        'Sun',
      );
      await tester.tap(find.text('Allow multiple answers'));
      await tester.pump();
      await tester.tap(find.text('Post poll'));
      await tester.pumpAndSettle();
      expect(find.text('New poll'), findsNothing);
      final (_, sent) = chats.polls.single;
      expect(sent.question, 'Which day?');
      expect(sent.options, ['Sat', 'Sun']);
      expect(sent.multiple, isTrue);
      expect(find.text('POLL · PICK ANY'), findsOneWidget);
    });

    testWidgets('no Poll without the API', (tester) async {
      joinAs(TeamRole.player);
      chats.hasApi = false;
      await pump(tester);
      await tester.tap(find.byTooltip('Upload a photo, video or file'));
      await tester.pumpAndSettle();
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Poll'), findsNothing);
    });
  });
}
