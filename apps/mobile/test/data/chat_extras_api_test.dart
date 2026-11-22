import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository_firebase.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Pins and event cards (redesign F2, F3) go through the API only; pins
/// are read back from the room's messages.
void main() {
  late FakeFirebaseFirestore db;
  late List<Map<String, Object?>> sent;
  late http.Response Function() answer;

  ChatRepositoryFirebase repo({bool api = true}) => ChatRepositoryFirebase(
    attachments: AttachmentStorage(),
    firestore: db,
    api: api
        ? ApiClient(
            baseUrl: Uri.parse('https://api.test'),
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'u1'),
            ),
            client: MockClient((req) async {
              sent.add({
                'method': req.method,
                'path': req.url.path,
                if (req.body.isNotEmpty) 'body': jsonDecode(req.body),
              });
              return answer();
            }),
          )
        : null,
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    sent = [];
    answer = () => http.Response('', 204);
  });

  test('pin, unpin and share call the API', () async {
    final r = repo();
    expect(r.canUseChatExtras, isTrue);
    expect(await r.pinMessage('t1', 'general', 'm1'), isA<Ok<void>>());
    expect(
      await r.pinMessage('t1', 'general', 'm2', unpin: 'm1'),
      isA<Ok<void>>(),
    );
    expect(await r.unpinMessage('t1', 'general', 'm2'), isA<Ok<void>>());
    answer = () => http.Response(jsonEncode({'id': 'x'}), 201);
    expect(await r.shareEvent('t1', 'general', 'e1'), isA<Ok<void>>());
    expect(sent, [
      {
        'method': 'PUT',
        'path': '/v1/teams/t1/chats/general/messages/m1/pin',
        'body': <String, Object?>{},
      },
      {
        'method': 'PUT',
        'path': '/v1/teams/t1/chats/general/messages/m2/pin',
        'body': {'unpin': 'm1'},
      },
      {
        'method': 'DELETE',
        'path': '/v1/teams/t1/chats/general/messages/m2/pin',
      },
      {
        'method': 'POST',
        'path': '/v1/teams/t1/chats/general/event-shares',
        'body': {'eventId': 'e1'},
      },
    ]);
  });

  test('a full room comes back as failed_precondition', () async {
    answer = () => http.Response(
      jsonEncode({
        'error': {'code': 'failed_precondition', 'message': 'Unpin one first.'},
      }),
      412,
    );
    final result = await repo().pinMessage('t1', 'general', 'm1');
    expect(
      (result as Error).error,
      isA<ApiException>().having((e) => e.code, 'code', 'failed_precondition'),
    );
  });

  test('without the API nothing is offered and nothing is sent', () async {
    final r = repo(api: false);
    expect(r.canUseChatExtras, isFalse);
    expect(await r.pinMessage('t1', 'general', 'm1'), isA<Error<void>>());
    expect(sent, isEmpty);
  });

  test('pins are the pinned messages, newest pin first', () async {
    final messages = db.collection('teams/t1/chats/general/messages');
    await messages.doc('a').set({
      'authorId': 'p',
      'text': 'older pin',
      'pinnedAt': DateTime(2026, 11, 1),
    });
    await messages.doc('b').set({'authorId': 'p', 'text': 'not pinned'});
    await messages.doc('c').set({
      'authorId': 'p',
      'text': 'newer pin',
      'pinnedAt': DateTime(2026, 11, 2),
    });
    final pins = await repo().watchPins('t1', 'general').first;
    expect(pins.map((m) => m.id), ['c', 'a']);
    expect(pins.first.isPinned, isTrue);
  });

  test('polls (F33) post, vote and close through the API', () async {
    final r = repo();
    answer = () => http.Response(jsonEncode({'id': 'q1'}), 201);
    final closes = DateTime.utc(2026, 11, 21, 18);
    expect(
      await r.createPoll('t1', 'general', (
        question: 'Which day?',
        options: ['Sat', 'Sun'],
        multiple: true,
        closesAt: closes,
      )),
      isA<Ok<void>>(),
    );
    answer = () => http.Response('', 204);
    expect(await r.votePoll('t1', 'general', 'q1', [0, 1]), isA<Ok<void>>());
    expect(await r.closePoll('t1', 'general', 'q1'), isA<Ok<void>>());
    expect(sent, [
      {
        'method': 'POST',
        'path': '/v1/teams/t1/chats/general/polls',
        'body': {
          'question': 'Which day?',
          'options': ['Sat', 'Sun'],
          'multiple': true,
          'closesAt': '2026-11-21T18:00:00.000Z',
        },
      },
      {
        'method': 'PUT',
        'path': '/v1/teams/t1/chats/general/messages/q1/vote',
        'body': {
          'options': [0, 1],
        },
      },
      {
        'method': 'POST',
        'path': '/v1/teams/t1/chats/general/messages/q1/close-poll',
        'body': <String, Object?>{},
      },
    ]);
  });

  test('a poll card reads its own message, live', () async {
    final doc = db.doc('teams/t1/chats/general/messages/q1');
    await doc.set({
      'authorId': 'p',
      'text': '',
      'poll': {
        'question': 'Which day?',
        'options': ['Sat', 'Sun'],
        'multiple': false,
        'votes': {
          'p': [1],
        },
        'voterIds': ['p'],
      },
    });
    final m = await repo().watchMessage('t1', 'general', 'q1').first;
    expect(m?.poll?.counts, [0, 1]);
    expect(await repo().watchMessage('t1', 'general', 'gone').first, isNull);
  });
}
