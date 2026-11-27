import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository_firebase.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository_firebase.dart';
import 'package:frisbee_app/data/repositories/outbox/outbox_repository.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/outbox.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/api_fakes.dart';
import '../testing/fakes.dart';
import '../testing/outbox_harness.dart';

/// Team chat and direct messages through the API (contracts/phase1-writes.md
/// §3.3, §3.4): sends with ids and uploads, reactions, deletes, and the
/// conversation writes. Read markers, typing, archive and clear stay direct.
void main() {
  late FakeApi api;
  late FakeFirebaseFirestore db;

  setUp(() {
    api = FakeApi();
    db = FakeFirebaseFirestore();
  });

  Object errorOf(Result<Object?> r) => (r as Error).error;
  NewAttachment file(String name, [int n = 5]) =>
      NewAttachment(name: name, bytes: Uint8List(n));

  const reply = MessageReply(
    id: 'm0',
    authorId: 'u9',
    authorName: 'Sam',
    text: 'quoted',
  );

  group('team chat', () {
    ChatRepositoryFirebase repo({OutboxRepository? outbox}) =>
        ChatRepositoryFirebase(
          attachments: AttachmentStorage(),
          firestore: db,
          api: api.client(),
          uploads: api.uploadClient(),
          outbox: outbox,
        );
    const route = 'POST /v1/teams/t1/chats/r1/messages';

    test('send: POST with its id; a reply is just the message id', () async {
      final r = await repo().sendMessage(
        't1',
        'r1',
        author: testUser,
        text: ' hi ',
        replyTo: reply,
      );
      expect(r, isA<Ok<void>>());
      final b = api.bodyOf(route);
      expect(b, {
        'id': b['id'],
        'text': 'hi',
        'replyTo': 'm0',
        'uploadIds': <String>[],
      });
      expect(b['id'], matches(RegExp(r'^[A-Za-z0-9]{1,40}$')));
    });

    test('files go up as chat uploads for the room and the message', () async {
      uploadsWork(api);
      await repo().sendMessage(
        't1',
        'r1',
        author: testUser,
        text: '',
        attachments: [file('plan.pdf'), file('a.jpg')],
      );
      final id = api.bodyOf(route)['id'];
      final creates = api.to('POST /v1/uploads');
      expect(
        [for (final c in creates) c.body],
        [
          {
            'purpose': 'chat',
            'contentType': 'application/pdf',
            'size': 5,
            'itemId': id,
            'targetId': 'teams/t1/chats/r1',
            'name': 'plan.pdf',
          },
          {
            'purpose': 'chat',
            'contentType': 'image/jpeg',
            'size': 5,
            'itemId': id,
            'targetId': 'teams/t1/chats/r1',
            'name': 'a.jpg',
          },
        ],
      );
      expect(api.bodyOf(route)['uploadIds'], ['up1', 'up2']);
    });

    test('a file over the limit is refused before anything is sent', () async {
      final big = NewAttachment(
        name: 'x.pdf',
        bytes: Uint8List(11 * 1024 * 1024),
      );
      final r = await repo().sendMessage(
        't1',
        'r1',
        author: testUser,
        text: 'x',
        attachments: [big],
      );
      expect(errorOf(r), isA<AttachmentTooLargeException>());
      expect(api.sent, isEmpty);
    });

    test('react, clear a reaction and delete use their routes', () async {
      final c = repo();
      await c.setReaction('t1', 'r1', 'm1', 'u1', '👍');
      await c.setReaction('t1', 'r1', 'm1', 'u1', null);
      await c.deleteMessage(
        't1',
        'r1',
        const ChatMessage(id: 'm1', authorId: 'u1', authorName: 'A', text: 'x'),
      );
      expect(
        [for (final s in api.sent) '${s.method} ${s.path}'],
        [
          'PUT /v1/teams/t1/chats/r1/messages/m1/reaction',
          'PUT /v1/teams/t1/chats/r1/messages/m1/reaction',
          'DELETE /v1/teams/t1/chats/r1/messages/m1',
        ],
      );
      expect(
        [for (final s in api.sent.take(2)) s.body],
        [
          {'emoji': '👍'},
          {'emoji': null},
        ],
      );
    });

    test('muted: the server message comes back', () async {
      api.on(
        route,
        apiError(429, 'resource_exhausted', "You're muted for 5 minutes."),
      );
      final r = await repo().sendMessage(
        't1',
        'r1',
        author: testUser,
        text: 'x',
      );
      expect(errorOf(r).toString(), "You're muted for 5 minutes.");
      expect(outboxFailureFor(errorOf(r)), OutboxFailure.retry);
    });

    test('read only: permission_denied is permanent for the queue', () async {
      api.on(
        route,
        apiError(
          403,
          'permission_denied',
          'You can read this room but not post in it.',
        ),
      );
      final r = await repo().sendMessage(
        't1',
        'r1',
        author: testUser,
        text: 'x',
      );
      expect(outboxFailureFor(errorOf(r)), OutboxFailure.permanent);
    });

    test('offline with the queue: waits, then goes out with one id', () async {
      final h = OutboxHarness();
      addTearDown(h.dispose);
      api.offline = true;
      final r = await repo(
        outbox: h.outbox,
      ).sendMessage('t1', 'r1', author: testUser, text: 'later');
      expect(r, isA<Ok<void>>());
      final job = h.outbox.jobs.single;
      api.offline = false;
      await h.connectivity.check();
      await h.outbox.drain();
      expect(h.outbox.jobs, isEmpty);
      expect(api.bodyOf(route)['id'], job.id);
    });

    test('upload done, send failed, replay: no second upload', () async {
      final h = OutboxHarness();
      addTearDown(h.dispose);
      uploadsWork(api);
      api.on(route, [
        apiError(500, 'internal', 'Boom'),
        apiError(409, 'already_exists', 'That message was already sent.'),
      ]);
      await repo(outbox: h.outbox).sendMessage(
        't1',
        'r1',
        author: testUser,
        text: 'pic',
        attachments: [file('a.jpg')],
      );
      expect(h.outbox.jobs.single.uploads.keys, [0]);
      h.passTime();
      await h.outbox.drain();
      // The 409 means it went through: done.
      expect(h.outbox.jobs, isEmpty);
      expect(api.to('POST /v1/uploads'), hasLength(1));
      final sent = [for (final s in api.to(route)) s.body as Map];
      expect(sent, hasLength(2));
      expect(sent[0]['id'], sent[1]['id']);
      expect(sent[0]['uploadIds'], sent[1]['uploadIds']);
    });

    test(
      'a message queued by an older build: replyTo object is its id',
      () async {
        final h = OutboxHarness(
          saved: [
            {
              'id': 'oldm',
              'uid': 'u1',
              'kind': 'teamChat',
              'createdAt': '2026-11-20T10:00:00.000Z',
              'target': 't1/r1',
              'label': 'Team chat message',
              'payload': {
                'teamId': 't1',
                'roomId': 'r1',
                'text': 'old hello',
                'replyTo': reply.toMap(),
              },
              'state': 'waiting',
              'attempts': 0,
            },
          ],
        );
        addTearDown(h.dispose);
        repo(outbox: h.outbox);
        await h.outbox.drain();
        expect(api.bodyOf(route), {
          'id': 'oldm',
          'text': 'old hello',
          'replyTo': 'm0',
          'uploadIds': <String>[],
        });
      },
    );
  });

  group('direct messages', () {
    DirectMessageRepositoryFirebase repo({OutboxRepository? outbox}) =>
        DirectMessageRepositoryFirebase(
          attachments: AttachmentStorage(),
          firestore: db,
          api: api.client(),
          uploads: api.uploadClient(),
          outbox: outbox,
        );
    const route = 'POST /v1/conversations/c1/messages';
    const sam = UserProfile(uid: 'u9', name: 'Sam');

    test('open: POST with the other person; the id comes back', () async {
      api.on('POST /v1/conversations', {'id': 'u1_u9', 'status': 'request'});
      final r = await repo().openConversation(testUser, sam);
      expect((r as Ok<String>).value, 'u1_u9');
      expect(api.bodyOf('POST /v1/conversations'), {'with': 'u9'});
    });

    test('open: not allowed shows the server message', () async {
      api.on(
        'POST /v1/conversations',
        apiError(
          403,
          'permission_denied',
          "Sam doesn't take messages from you.",
        ),
      );
      final r = await repo().openConversation(testUser, sam);
      expect(errorOf(r).toString(), "Sam doesn't take messages from you.");
    });

    test('group: POST with a g- id, the name and the member uids', () async {
      api.on('POST /v1/conversations/groups', (Object? b) {
        return {
          'id': (b as Map)['id'],
          'notAdded': ['Pat'],
        };
      });
      final r = await repo().createGroup(testUser, ' Crew ', [
        sam,
        const UserProfile(uid: 'u8', name: 'Pat'),
      ]);
      final added = (r as Ok<GroupAdded>).value;
      final b = api.bodyOf('POST /v1/conversations/groups');
      expect(b['id'], matches(RegExp(r'^g-[A-Za-z0-9]{1,40}$')));
      expect(b['name'], 'Crew');
      expect(b['members'], ['u9', 'u8']);
      expect(b.keys.toSet(), {'id', 'name', 'members'});
      expect(added.id, b['id']);
      expect(added.notAdded, ['Pat']);
    });

    test('members: add, remove, leave and rename', () async {
      api.on('POST /v1/conversations/g-1/members', {
        'id': 'g-1',
        'notAdded': <String>[],
      });
      final d = repo();
      await d.addToGroup('g-1', testUser, [sam]);
      // Nobody to add: nothing sent.
      await d.addToGroup('g-1', testUser, const []);
      await d.removeFromGroup('g-1', 'u9');
      await d.removeFromGroup('g-1', 'u1');
      await d.renameGroup('g-1', ' New name ');
      expect(
        [for (final s in api.sent) '${s.method} ${s.path}'],
        [
          'POST /v1/conversations/g-1/members',
          'DELETE /v1/conversations/g-1/members/u9',
          'DELETE /v1/conversations/g-1/members/u1',
          'PATCH /v1/conversations/g-1',
        ],
      );
      expect(api.bodyOf('POST /v1/conversations/g-1/members'), {
        'members': ['u9'],
      });
      expect(api.bodyOf('PATCH /v1/conversations/g-1'), {'name': 'New name'});
    });

    test(
      'send: id, text, a reply id and the uploads for the conversation',
      () async {
        uploadsWork(api);
        await repo().sendMessage(
          'c1',
          author: testUser,
          text: 'look',
          attachments: [file('a.jpg')],
          replyTo: reply,
        );
        final b = api.bodyOf(route);
        expect(b, {
          'id': b['id'],
          'text': 'look',
          'replyTo': 'm0',
          'uploadIds': ['up1'],
        });
        expect(api.bodyOf('POST /v1/uploads'), {
          'purpose': 'chat',
          'contentType': 'image/jpeg',
          'size': 5,
          'itemId': b['id'],
          'targetId': 'conversations/c1',
          'name': 'a.jpg',
        });
      },
    );

    test('react, delete and answer a request use their routes', () async {
      final d = repo();
      await d.setReaction('c1', 'm1', 'u1', '❤️');
      await d.setReaction('c1', 'm1', 'u1', null);
      await d.deleteMessage(
        'c1',
        const ChatMessage(id: 'm1', authorId: 'u1', authorName: 'A', text: 'x'),
      );
      await d.answerRequest('c1', 'u1', accept: true);
      await d.answerRequest('c1', 'u1', accept: false);
      expect(
        [for (final s in api.sent) '${s.method} ${s.path} ${s.body}'],
        [
          'PUT /v1/conversations/c1/messages/m1/reaction {emoji: ❤️}',
          'PUT /v1/conversations/c1/messages/m1/reaction {emoji: null}',
          'DELETE /v1/conversations/c1/messages/m1 null',
          'PUT /v1/conversations/c1/request {accept: true}',
          'PUT /v1/conversations/c1/request {accept: false}',
        ],
      );
    });

    test(
      'a read receipt is shared through the API; a private mark is not',
      () async {
        final d = repo();
        await d.markRead('c1', 'u1', shareReceipt: true);
        expect(api.to('POST /v1/conversations/c1/read'), hasLength(1));
        await d.markRead('c2', 'u1', shareReceipt: false);
        // Direct, as D6 says: your own read time, nothing for the other person.
        expect(api.to('POST /v1/conversations/c2/read'), isEmpty);
        final doc = await db.collection('users/u1/dmReads').doc('c2').get();
        expect(doc.data()?['readAt'], isNotNull);
      },
    );

    test('archive and clear stay direct (D6)', () async {
      final d = repo();
      await d.setArchived('c1', 'u1', archived: true);
      await d.clearConversation('c1', 'u1');
      expect(api.sent, isEmpty);
      final doc = await db.collection('users/u1/dmReads').doc('c1').get();
      expect(doc.data()?['clearedAt'], isNotNull);
    });

    test('blocked: the server message, and permanent for the queue', () async {
      api.on(
        route,
        apiError(
          403,
          'permission_denied',
          "You can't do that: one of you blocked the other.",
        ),
      );
      final r = await repo().sendMessage('c1', author: testUser, text: 'x');
      expect(
        errorOf(r).toString(),
        "You can't do that: one of you blocked the other.",
      );
      expect(outboxFailureFor(errorOf(r)), OutboxFailure.permanent);
    });

    test(
      'a request not yet answered: failed_precondition shows its words',
      () async {
        api.on(
          route,
          apiError(412, 'failed_precondition', 'Accept the request to reply.'),
        );
        final r = await repo().sendMessage('c1', author: testUser, text: 'x');
        expect(errorOf(r).toString(), 'Accept the request to reply.');
      },
    );

    test('offline: writes that are not queued fail with a retry', () async {
      api.offline = true;
      final d = repo();
      for (final r in [
        await d.setReaction('c1', 'm1', 'u1', '👍'),
        await d.renameGroup('g-1', 'x'),
        await d.answerRequest('c1', 'u1', accept: true),
        await d.openConversation(testUser, sam),
      ]) {
        expect(
          errorOf(r),
          isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
        );
      }
    });

    test('offline with the queue, then a 409 replay: sent once', () async {
      final h = OutboxHarness();
      addTearDown(h.dispose);
      api.on(route, [
        apiError(500, 'internal', 'Boom'),
        apiError(409, 'already_exists', 'That message was already sent.'),
      ]);
      uploadsWork(api);
      await repo(outbox: h.outbox).sendMessage(
        'c1',
        author: testUser,
        text: 'x',
        attachments: [file('a.jpg')],
      );
      expect(h.outbox.jobs.single.kind, OutboxKind.directMessage);
      h.passTime();
      await h.outbox.drain();
      expect(h.outbox.jobs, isEmpty);
      expect(api.to('POST /v1/uploads'), hasLength(1));
      expect(api.to(route), hasLength(2));
    });

    test('a message queued by an older build still goes out', () async {
      final h = OutboxHarness(
        saved: [
          {
            'id': 'olddm',
            'uid': 'u1',
            'kind': 'directMessage',
            'createdAt': '2026-11-20T10:00:00.000Z',
            'target': 'c1',
            'label': 'Message',
            'payload': {'text': 'hello', 'replyTo': null},
            'state': 'waiting',
            'attempts': 0,
          },
        ],
      );
      addTearDown(h.dispose);
      repo(outbox: h.outbox);
      await h.outbox.drain();
      expect(api.bodyOf(route), {
        'id': 'olddm',
        'text': 'hello',
        'uploadIds': <String>[],
      });
    });
  });
}
