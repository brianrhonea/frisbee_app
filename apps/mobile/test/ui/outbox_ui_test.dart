import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/outbox/outbox_repository.dart';
import 'package:frisbee_app/data/services/connectivity_service.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/outbox.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/domain/models/workout.dart';
import 'package:frisbee_app/ui/messages/view_models/direct_chat_viewmodel.dart';
import 'package:frisbee_app/ui/outbox/view_models/outbox_viewmodel.dart';
import 'package:frisbee_app/ui/outbox/widgets/offline_banner.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/outbox_fakes.dart';

/// What a saved job's payload comes back as after the app restarts.
Map<String, Object?> _reloaded(Map<String, Object?> payload) {
  final job = OutboxJob(
    id: 'j',
    uid: 'me',
    kind: OutboxKind.userPost,
    createdAt: DateTime.utc(2026, 11, 16),
    target: 't',
    label: 'Post',
    payload: Map<String, Object?>.from(jsonSafe(payload) as Map),
  );
  final back = OutboxJob.fromJson(
    Map<String, Object?>.from(jsonDecode(jsonEncode(job.toJson())) as Map),
  );
  return back!.payload;
}

void main() {
  group('queued payloads survive being saved', () {
    test('a post with a workout and a tournament tag', () {
      const post = UserPost(
        id: '',
        body: 'Track day',
        links: ['https://example.com'],
        workout: Workout(
          activity: WorkoutActivity.run,
          durationMinutes: 45,
          distanceKm: 8.5,
          exercises: [WorkoutExercise(name: 'Strides', sets: 4, reps: 6)],
        ),
        tournamentKey: 'spring-classic',
        tournamentName: 'Spring Classic',
      );
      final back = _reloaded({'post': post.toEditableMap()});
      final rebuilt = UserPost.fromMap(
        '',
        Map<String, dynamic>.from(back['post']! as Map),
      );
      expect(jsonSafe(rebuilt.toEditableMap()), jsonSafe(post.toEditableMap()));
    });

    test('a team post', () {
      const post = TeamPost(
        id: '',
        title: 'Practice moved',
        body: 'Field 3 tonight',
        location: 'Riverside',
        links: ['https://example.com/map'],
        isPublic: true,
      );
      final back = _reloaded({'post': post.toEditableMap()});
      final rebuilt = TeamPost.fromMap(
        '',
        Map<String, dynamic>.from(back['post']! as Map),
      );
      expect(jsonSafe(rebuilt.toEditableMap()), jsonSafe(post.toEditableMap()));
    });

    test("a message's reply", () {
      const reply = MessageReply(
        id: 'm0',
        authorId: 'a',
        authorName: 'Avery',
        text: 'Need a ride?',
      );
      final back = _reloaded({'text': 'Yes', 'replyTo': reply.toMap()});
      final rebuilt = MessageReply.fromMap(back['replyTo'])!;
      expect(rebuilt.toMap(), reply.toMap());
      expect(back['text'], 'Yes');
    });
  });

  group('in the app', () {
    late MemoryOutboxStore store;
    late StreamController<bool> network;
    late ConnectivityService connectivity;
    late FakeAuthRepository auth;
    late OutboxRepository outbox;

    setUp(() {
      store = MemoryOutboxStore();
      network = StreamController<bool>();
      connectivity = ConnectivityService(
        networkChanges: network.stream,
        probe: () async => false,
        probeEvery: const Duration(hours: 1),
        grace: Duration.zero,
      );
      auth = FakeAuthRepository(user: testUser);
      outbox = OutboxRepository(
        store: store,
        connectivity: connectivity,
        auth: auth,
      );
    });

    tearDown(() async {
      outbox.dispose();
      connectivity.dispose();
      await network.close();
    });

    Future<void> queueMessage(String id, {String target = 'a_u1'}) async {
      network.add(false);
      await pumpEventQueue();
      await outbox.submit(
        kind: OutboxKind.directMessage,
        id: id,
        target: target,
        label: 'Message',
        payload: {'text': 'Sent offline'},
        sendNow: () async => const Result.ok(null),
      );
    }

    test('a queued message shows at the end of its thread until the real '
        'one arrives', () async {
      final dms = FakeDirectMessageRepository();
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
        outbox: outbox,
      );
      addTearDown(vm.dispose);
      await queueMessage('q1');
      await queueMessage('other', target: 'b_u1');
      await pumpEventQueue();

      expect(vm.messages.map((m) => m.text), ['Need a ride?', 'Sent offline']);
      final pending = vm.messages.last;
      expect(pending.id, 'q1');
      expect(vm.isQueued(pending), isTrue);
      expect(vm.statusFor(pending), 'Waiting to send');
      expect(vm.isFailed(pending), isFalse);
      expect(vm.canDelete(pending), isFalse);

      // The real one (same id) arrives: shown once, not twice.
      dms.messages['a_u1']!.add(
        ChatMessage(
          id: 'q1',
          authorId: testUser.uid,
          authorName: 'Me',
          text: 'Sent offline',
          createdAt: DateTime.now(),
        ),
      );
      dms.emit();
      await pumpEventQueue();
      expect(vm.messages.where((m) => m.id == 'q1'), hasLength(1));
    });

    test(
      'the banner copy tells no network from an unreachable server',
      () async {
        final vm = OutboxViewModel(outbox: outbox);
        addTearDown(vm.dispose);
        expect(vm.showBanner, isFalse, reason: 'online: no banner');

        network.add(false);
        await pumpEventQueue();
        expect(
          vm.bannerText,
          "You're offline. What you send will go out when you're back.",
        );
        expect(vm.serverUnreachable, isFalse);

        // The network is back but the server doesn't answer.
        network.add(true);
        await pumpEventQueue();
        expect(vm.online, isFalse);
        expect(vm.serverUnreachable, isTrue);
        expect(
          vm.bannerText,
          "Can't reach Stall 10 right now. What you send will go out when "
          "you're back.",
        );
      },
    );

    test('queued items use the same wording in both states', () async {
      await queueMessage('q1');
      final vm = OutboxViewModel(outbox: outbox);
      addTearDown(vm.dispose);
      expect(
        vm.bannerText,
        "You're offline. 1 item will send when you're back.",
      );
      network.add(true);
      await pumpEventQueue();
      expect(
        vm.bannerText,
        "Can't reach Stall 10 right now. 1 item will send when you're back.",
      );
    });

    testWidgets('the banner says offline, lists what waits and discards', (
      tester,
    ) async {
      await tester.runAsync(() => queueMessage('q1'));
      final vm = OutboxViewModel(outbox: outbox);
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineBanner(
            viewModel: vm,
            child: const Scaffold(body: Text('Page')),
          ),
        ),
      );
      expect(
        find.text("You're offline. 1 item will send when you're back."),
        findsOneWidget,
      );
      expect(find.text('Page'), findsOneWidget);

      await tester.tap(find.textContaining("You're offline"));
      await tester.pumpAndSettle();
      expect(find.text('Waiting to send'), findsWidgets);
      expect(find.text('Message: Sent offline'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Discard'));
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();
      expect(find.text('Everything has been sent.'), findsOneWidget);
      expect(outbox.jobs, isEmpty);
    });
  });
}
