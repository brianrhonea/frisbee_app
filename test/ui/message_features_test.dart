import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/draft/message_draft_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/ui/chat/view_models/message_thread_viewmodel.dart';
import 'package:frisbee_app/ui/messages/view_models/direct_chat_viewmodel.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/messages/view_models/inbox_viewmodel.dart';
import 'package:frisbee_app/ui/messages/widgets/inbox_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  late FakeDirectMessageRepository dms;
  late FakeAuthRepository auth;
  late MessageDraftRepositoryMemory drafts;

  const avery = UserProfile(uid: 'a', name: 'Avery Jones');
  const blake = UserProfile(uid: 'b', name: 'Blake Jordan');

  setUp(() async {
    dms = FakeDirectMessageRepository()..profiles.addAll(const [avery, blake]);
    auth = FakeAuthRepository(user: testUser);
    drafts = MessageDraftRepositoryMemory();
    await dms.openConversation(testUser, avery);
    await dms.sendMessage(
      'a_u1',
      author: const AppUser(uid: 'a', displayName: 'Avery'),
      text: 'Need a ride?',
    );
  });

  DirectChatViewModel chat() {
    final vm = DirectChatViewModel(
      conversationId: 'a_u1',
      directMessageRepository: dms,
      authRepository: auth,
      filePicker: FakeFilePickerService(),
      draftRepository: drafts,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  group('a conversation', () {
    test('looks like a text thread one-to-one', () async {
      final vm = chat();
      await pumpEventQueue();
      expect(vm.style, ThreadStyle.bubbles);
      expect(vm.canReact, isTrue);
    });

    test('reacting adds one reaction per person; the same again takes it '
        'back, another replaces it', () async {
      final vm = chat();
      await pumpEventQueue();
      final m = vm.messages.single;
      await vm.react.execute((m, '❤️'));
      await pumpEventQueue();
      expect(vm.messages.single.reactionOf(testUser.uid), '❤️');
      expect(vm.messages.single.reactionCounts(testUser.uid), [
        (emoji: '❤️', count: 1, mine: true),
      ]);
      await vm.react.execute((vm.messages.single, '😂'));
      await pumpEventQueue();
      expect(vm.messages.single.reactions, {testUser.uid: '😂'});
      await vm.react.execute((vm.messages.single, '😂'));
      await pumpEventQueue();
      expect(vm.messages.single.reactions, isEmpty);
    });

    test('a reply quotes the message it answers, then clears', () async {
      final vm = chat();
      await pumpEventQueue();
      final original = vm.messages.single;
      vm.replyTo(original);
      expect(vm.replyingTo, same(original));
      await vm.send.execute('Yes please');
      await pumpEventQueue();
      final reply = vm.messages.last;
      expect(reply.text, 'Yes please');
      expect(reply.replyTo?.id, original.id);
      expect(reply.replyTo?.text, 'Need a ride?');
      expect(vm.replyingTo, isNull);
    });

    test('cancelling a reply sends a plain message', () async {
      final vm = chat();
      await pumpEventQueue();
      vm
        ..replyTo(vm.messages.single)
        ..cancelReply();
      await vm.send.execute('Plain');
      await pumpEventQueue();
      expect(vm.messages.last.replyTo, isNull);
    });

    test('unsent text is kept for next time, and cleared once sent', () async {
      final first = chat();
      await pumpEventQueue();
      first.composerChanged('Half a tho');
      expect(chat().draft, 'Half a tho');
      await first.send.execute('Half a thought');
      await pumpEventQueue();
      expect(chat().draft, isEmpty);
    });
  });

  test('a reply is stored with a short quote', () {
    final long = ChatMessage(
      id: 'm1',
      authorId: 'a',
      authorName: 'Avery',
      text: 'x' * 500,
    );
    final map = MessageReply.of(long).toMap();
    expect(
      (map['text'] as String).length,
      lessThanOrEqualTo(MessageReply.maxText),
    );
    expect(MessageReply.fromMap(map)?.authorName, 'Avery');
  });

  group('the inbox', () {
    InboxViewModel inbox({FakeNotificationRepository? notices}) {
      final vm = InboxViewModel(
        directMessageRepository: dms,
        authRepository: auth,
        notificationRepository: notices,
      );
      addTearDown(vm.dispose);
      return vm;
    }

    test('mutes and unmutes a conversation', () async {
      final notices = FakeNotificationRepository();
      final vm = inbox(notices: notices);
      await pumpEventQueue();
      expect(vm.canMute, isTrue);
      expect(vm.allItems.single.muted, isFalse);
      await vm.toggleMute.execute(vm.allItems.single);
      await pumpEventQueue();
      expect(
        notices.prefs.mutedRooms,
        contains(NotificationPreferences.conversationKey('a_u1')),
      );
      expect(vm.allItems.single.muted, isTrue);
      await vm.toggleMute.execute(vm.allItems.single);
      await pumpEventQueue();
      expect(vm.allItems.single.muted, isFalse);
    });

    test("can't mute without notifications", () async {
      final vm = inbox();
      await pumpEventQueue();
      expect(vm.canMute, isFalse);
    });

    test('shows who is typing, and stops after a while', () async {
      var now = DateTime(2026, 11, 6, 12);
      final vm = inbox()..now = () => now;
      await pumpEventQueue();
      expect(vm.allItems.single.typing, isNull);
      dms.typed('a_u1', 'a', now);
      await pumpEventQueue();
      expect(vm.allItems.single.typing, 'typing…');
      // The user's own typing never shows.
      dms.typed('a_u1', testUser.uid, now);
      await pumpEventQueue();
      expect(vm.allItems.single.typing, 'typing…');
      now = now.add(InboxViewModel.typingFor + const Duration(seconds: 1));
      expect(vm.allItems.single.typing, isNull);
    });

    test(
      'a direct chat shows the other person; a group, two members',
      () async {
        dms.follows.addAll({('a', testUser.uid), ('b', testUser.uid)});
        final group = await dms.createGroup(testUser, '', const [avery, blake]);
        final groupId = (group as Ok<GroupAdded>).value.id;
        final vm = inbox();
        await pumpEventQueue();
        final direct = vm.allItems.firstWhere((i) => !i.isGroup);
        expect(direct.otherId, 'a');
        final g = vm.allItems.firstWhere((i) => i.conversation.id == groupId);
        expect(g.faces.map((f) => f.uid), unorderedEquals(['a', 'b']));
      },
    );
  });

  testWidgets('on a small phone the filters sit on one line, and swiping an '
      'entry left offers Mute and Delete', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notices = FakeNotificationRepository();
    final vm = InboxViewModel(
      directMessageRepository: dms,
      authRepository: auth,
      notificationRepository: notices,
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: InboxScreen(viewModel: vm),
      ),
    );
    await tester.pump();
    expect(find.text('New group'), findsNothing);
    final all = tester.getCenter(find.text('All'));
    final archived = tester.getCenter(find.text('Archived'));
    expect((all.dy - archived.dy).abs(), lessThan(1));
    expect(tester.takeException(), isNull);

    expect(find.text('Mute'), findsNothing);
    await tester.drag(find.text('Avery Jones'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();
    expect(
      notices.prefs.mutedRooms,
      contains(NotificationPreferences.conversationKey('a_u1')),
    );
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

    var now = DateTime(2026, 11, 6, 12);
    vm.now = () => now;
    dms.typed('a_u1', 'a', now);
    await tester.pump();
    await tester.pump();
    expect(find.text('typing…'), findsOneWidget);
    now = now.add(InboxViewModel.typingFor);
    await tester.pump(InboxViewModel.typingFor + const Duration(seconds: 1));
    expect(find.text('typing…'), findsNothing);
  });
}
