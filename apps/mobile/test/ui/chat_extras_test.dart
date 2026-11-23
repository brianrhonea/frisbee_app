// Pinned messages and event cards in team rooms (redesign F2, F3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/ui/chat/widgets/pinned_messages_screen.dart';
import 'package:frisbee_app/ui/chat/view_models/message_thread_viewmodel.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository.dart';
import 'package:frisbee_app/data/repositories/event/event_repository.dart';
import 'package:frisbee_app/data/repositories/notification/notification_repository.dart';
import 'package:frisbee_app/data/repositories/team/team_repository.dart';
import 'package:frisbee_app/data/repositories/voice/voice_repository.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_event_card_viewmodel.dart';
import 'package:frisbee_app/ui/chat/view_models/chat_room_viewmodel.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_room_screen.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/utils/result.dart';

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

  final soon = DateTime.now().add(const Duration(days: 2));

  ChatMessage msg(String id, String text, {ChatEventRef? event}) => ChatMessage(
    id: id,
    authorId: 'p2',
    authorName: 'Riley',
    text: text,
    createdAt: DateTime(2026, 11, 1, 9, int.parse(id.substring(1))),
    event: event,
  );

  setUp(() {
    teams = FakeTeamRepository();
    chats = FakeChatRepository()
      ..rooms['general'] = ChatRoom.general()
      ..seedVoice = false
      ..messages['general'] = [
        for (var i = 0; i < 12; i++) msg('m$i', 'Message $i'),
      ];
    auth = FakeAuthRepository(user: testUser);
    picker = FakeFilePickerService();
    notifications = FakeNotificationRepository();
    voice = FakeVoiceRepository();
    events = FakeEventRepository()
      ..events['e1'] = TeamEvent(
        id: 'e1',
        title: 'Practice: zone O',
        startsAt: soon,
        location: "Sloan's Lake",
        rsvps: const {'p2': RsvpStatus.going},
      );
  });

  void joinAs(TeamRole role, {Set<TeamPermission> perms = const {}}) =>
      teams.teams['t1'] = teamWith({
        'o': TeamRole.owner,
        'u1': role,
        'p2': TeamRole.player,
      }).copyWith(memberPerms: {if (perms.isNotEmpty) 'u1': perms});

  ChatRoomViewModel load() => ChatRoomViewModel(
    teamId: 't1',
    roomId: 'general',
    teamRepository: teams,
    chatRepository: chats,
    notificationRepository: notifications,
    authRepository: auth,
    filePicker: picker,
  );

  group('pins', () {
    test('chat managers pin and unpin; players and builds without the API '
        "can't", () async {
      joinAs(TeamRole.captain);
      final vm = load();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.canPin, isTrue);
      final m1 = chats.messages['general']![1];
      await vm.togglePin.execute(m1);
      await pumpEventQueue();
      expect(vm.pins.map((m) => m.id), ['m1']);
      expect(vm.latestPin?.id, 'm1');
      expect(vm.isPinned(m1), isTrue);
      await vm.togglePin.execute(m1);
      await pumpEventQueue();
      expect(vm.pins, isEmpty);

      for (final (role, perms, can) in [
        (TeamRole.player, <TeamPermission>{}, false),
        (TeamRole.player, {TeamPermission.manageChats}, true),
      ]) {
        joinAs(role, perms: perms);
        final other = load();
        addTearDown(other.dispose);
        await pumpEventQueue();
        expect(other.canPin, can, reason: '$role $perms');
      }
      chats.hasApi = false;
      expect(vm.canPin, isFalse);
    });

    test('a full room asks which pin to take down', () async {
      joinAs(TeamRole.owner);
      final vm = load();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      final all = chats.messages['general']!;
      for (var i = 0; i < chatPinsMax; i++) {
        await vm.togglePin.execute(all[i]);
      }
      await pumpEventQueue();
      expect(vm.pins, hasLength(chatPinsMax));
      await vm.togglePin.execute(all[10]);
      expect(
        (vm.togglePin.result as Error).error,
        isA<PinsFullException>().having((e) => e.message.id, 'id', 'm10'),
      );
      await vm.replacePin.execute((all[10], 'm0'));
      await pumpEventQueue();
      expect(vm.pins.first.id, 'm10');
      expect(vm.pins.map((m) => m.id), isNot(contains('m0')));
    });
  });

  group('event shares', () {
    test('need someone who adds events and can post here', () async {
      joinAs(TeamRole.player);
      final player = load();
      addTearDown(player.dispose);
      await pumpEventQueue();
      expect(player.canShareEvents, isFalse);
      joinAs(TeamRole.player, perms: {TeamPermission.manageEvents});
      final vm = load();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.canShareEvents, isTrue);
      await vm.shareEvent.execute('e1');
      expect(chats.shared, [('general', 'e1')]);
    });

    test('the card answers through the RSVP path and degrades', () async {
      final card = ChatEventCardViewModel(
        teamId: 't1',
        eventId: 'e1',
        eventRepository: events,
        authRepository: auth,
      );
      addTearDown(card.dispose);
      await pumpEventQueue();
      expect(card.event?.title, 'Practice: zone O');
      expect(card.goingCount, 1);
      expect(card.needsAnswer, isTrue);
      card.answer(RsvpStatus.going);
      await pumpEventQueue();
      expect(events.events['e1']!.rsvpOf('u1'), RsvpStatus.going);
      expect(card.goingCount, 2);
      expect(card.needsAnswer, isFalse);
      // Picking the same answer takes it back.
      card.answer(RsvpStatus.going);
      await pumpEventQueue();
      expect(events.events['e1']!.rsvpOf('u1'), isNull);
      events.events.remove('e1');
      events.emit();
      await pumpEventQueue();
      expect(card.unavailable, isTrue);
    });

    test('the picker lists upcoming events, a community only its events '
        'for everyone', () async {
      events.events
        ..['old'] = TeamEvent(
          id: 'old',
          title: 'Earlier today',
          startsAt: DateTime.now().subtract(const Duration(hours: 5)),
        )
        ..['coaches'] = TeamEvent(
          id: 'coaches',
          title: 'Coaches meeting',
          startsAt: soon,
          audience: const {'coach'},
        )
        ..['all'] = TeamEvent(
          id: 'all',
          title: 'Open practice',
          startsAt: soon,
          audience: const {'everyone'},
        );
      final team = teamWith({'o': TeamRole.owner, 'u1': TeamRole.coach});
      final picker = ChatEventPickerViewModel(
        team: team,
        eventRepository: events,
      );
      addTearDown(picker.dispose);
      await pumpEventQueue();
      expect(picker.events.map((e) => e.id), ['e1', 'coaches', 'all']);
      final org = ChatEventPickerViewModel(
        team: Team(
          id: 't1',
          name: 'Community',
          division: Division.mixed,
          level: CompetitionLevel.club,
          ownerId: 'o',
          members: const {'o': TeamRole.owner, 'u1': TeamRole.coach},
          kind: TeamKind.organization,
        ),
        eventRepository: events,
      );
      addTearDown(org.dispose);
      await pumpEventQueue();
      expect(org.events.map((e) => e.id), ['all']);
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

    Future<ChatRoomViewModel> pump(WidgetTester tester) async {
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
      return vm;
    }

    Future<void> openPins(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Room options'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room-pinned')));
      await tester.pumpAndSettle();
    }

    testWidgets("pinned messages are their own page, from the room's ⋯", (
      tester,
    ) async {
      joinAs(TeamRole.player);
      chats.pinned['general'] = ['m11', 'm3'];
      await pump(tester);
      await openPins(tester);
      expect(find.byType(PinnedMessagesScreen), findsOneWidget);
      expect(find.text('Pinned messages'), findsOneWidget);
      expect(find.byKey(const Key('pin-m11')), findsOneWidget);
      expect(find.byKey(const Key('pin-m3')), findsOneWidget);
      // Players can't unpin.
      expect(find.byTooltip('Pin options'), findsNothing);
    });

    testWidgets('a room with no pins says how to pin', (tester) async {
      joinAs(TeamRole.captain);
      await pump(tester);
      await openPins(tester);
      expect(find.text('Nothing pinned yet'), findsOneWidget);
    });

    testWidgets('tapping a pin jumps to it in the chat, loading older '
        'messages, and highlights it', (tester) async {
      joinAs(TeamRole.player);
      chats.messages['general'] = [
        for (var i = 0; i < 160; i++) msg('m$i', 'Message $i'),
      ];
      chats.pinned['general'] = ['m2'];
      final vm = await pump(tester);
      expect(find.text('Message 2'), findsNothing);
      await openPins(tester);
      await tester.tap(find.byKey(const Key('pin-m2')));
      await tester.pumpAndSettle();
      expect(find.byType(PinnedMessagesScreen), findsNothing);
      expect(find.text('Message 2').hitTestable(), findsOneWidget);
      expect(vm.highlightedId, 'm2');
      await tester.pump(MessageThreadViewModel.highlightFor);
      await tester.pumpAndSettle();
      expect(vm.highlightedId, isNull);
    });

    testWidgets('chat managers pin from the long-press sheet, and unpin '
        'from the pinned page', (tester) async {
      joinAs(TeamRole.captain);
      await pump(tester);
      await tester.longPress(find.text('Message 11'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin message'));
      await tester.pumpAndSettle();
      expect(chats.pinned['general'], ['m11']);
      await openPins(tester);
      await tester.tap(find.byTooltip('Pin options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpin'));
      await tester.pumpAndSettle();
      expect(chats.pinned['general'], isEmpty);
      expect(find.text('Nothing pinned yet'), findsOneWidget);
    });

    testWidgets('players get no Pin in the long-press sheet', (tester) async {
      joinAs(TeamRole.player);
      await pump(tester);
      await tester.longPress(find.text('Message 11'));
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Pin message'), findsNothing);
    });

    testWidgets('a shared event shows as a card that RSVPs', (tester) async {
      joinAs(TeamRole.player);
      chats.messages['general']!.add(
        msg(
          'm50',
          '',
          event: const ChatEventRef(id: 'e1', title: 'Practice'),
        ),
      );
      await pump(tester);
      await tester.pump();
      expect(find.text('Practice: zone O'), findsOneWidget);
      expect(find.text('1 going'), findsOneWidget);
      expect(find.text('RSVP needed'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Going'));
      await tester.pump();
      await tester.pump();
      expect(events.events['e1']!.rsvpOf('u1'), RsvpStatus.going);
      expect(find.text('2 going'), findsOneWidget);
    });

    testWidgets('a deleted event says so', (tester) async {
      joinAs(TeamRole.player);
      chats.messages['general']!.add(
        msg(
          'm50',
          '',
          event: const ChatEventRef(id: 'gone', title: 'Old'),
        ),
      );
      await pump(tester);
      await tester.pump();
      expect(find.text('Event no longer available'), findsOneWidget);
    });

    testWidgets('event managers share an event from the attach menu', (
      tester,
    ) async {
      joinAs(TeamRole.captain);
      await pump(tester);
      await tester.tap(find.byTooltip('Upload a photo, video or file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share an event'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Practice: zone O'));
      await tester.pumpAndSettle();
      expect(chats.shared, [('general', 'e1')]);
    });

    testWidgets('players get no Share an event', (tester) async {
      joinAs(TeamRole.player);
      await pump(tester);
      await tester.tap(find.byTooltip('Upload a photo, video or file'));
      await tester.pumpAndSettle();
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Share an event'), findsNothing);
    });
  });
}
