import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository_firebase.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/data/services/firestore_utils.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/api_fakes.dart';

/// Team chat unread dots: the server stamps the room's lastAt (never the
/// text) and the sender's own read when a message is sent (the API route,
/// contracts/phase1-writes.md §3.3); members' reads are private docs.
void main() {
  late FakeFirebaseFirestore db;
  late ChatRepositoryFirebase repo;
  late FakeApi api;

  setUp(() async {
    db = FakeFirebaseFirestore();
    api = FakeApi();
    repo = ChatRepositoryFirebase(
      attachments: AttachmentStorage(),
      firestore: db,
      api: api.client(),
    );
    await db.doc('teams/t1/chats/general').set({
      'name': 'General',
      'readRoles': ['everyone'],
      'writeRoles': ['everyone'],
    });
  });

  test('sending goes to the API, which stamps the room and the read', () async {
    final sent = await repo.sendMessage(
      't1',
      'general',
      author: const AppUser(uid: 'u1', displayName: 'Ana'),
      text: ' hi ',
    );
    expect(sent, isA<Ok<void>>());
    expect(
      api.bodyOf('POST /v1/teams/t1/chats/general/messages')['text'],
      'hi',
    );
    // The app no longer writes the room or the read itself.
    var room = (await db.doc('teams/t1/chats/general').get()).data()!;
    expect(room['lastAt'], isNull);
    expect(await repo.watchReads('u1').first, isEmpty);
    // What the server writes (hub/service.ts sendMessage): lastAt, and the
    // sender's own read.
    await db.doc('teams/t1/chats/general').update({
      'lastAt': DateTime(2026, 11, 27, 12),
    });
    await db.doc('users/u1/chatReads/t1').set({
      'rooms': {'general': DateTime(2026, 11, 27, 12)},
    });
    room = (await db.doc('teams/t1/chats/general').get()).data()!;
    expect(room.containsKey('lastMessage'), isFalse);
    final reads = await repo.watchReads('u1').first;
    final mine = reads['t1']!['general']!;
    final r = ChatRoom.fromMap('general', plainData(room));
    expect(r.unreadSince(mine), isFalse);
    // Someone who never opened it has it unread.
    expect(r.unreadSince(null), isTrue);
  });

  test('markRead keeps the other rooms read times', () async {
    await repo.markRead('t1', 'general', 'u2');
    await repo.markRead('t1', 'lines', 'u2');
    await repo.markRead('t2', 'general', 'u2');
    final reads = await repo.watchReads('u2').first;
    expect(reads['t1']!.keys, unorderedEquals(['general', 'lines']));
    expect(reads['t2']!.keys, ['general']);
  });

  test('voice channels and rooms without a stamp are never unread', () {
    final at = DateTime(2026, 11, 1);
    expect(const ChatRoom(id: 'x', name: 'x').unreadSince(null), isFalse);
    expect(
      ChatRoom(
        id: 'v',
        name: 'Lounge',
        kind: ChatRoomKind.voice,
        lastAt: at,
      ).unreadSince(null),
      isFalse,
    );
    final room = ChatRoom(id: 'r', name: 'r', lastAt: at);
    expect(room.unreadSince(at), isFalse);
    expect(room.unreadSince(at.subtract(const Duration(seconds: 1))), isTrue);
  });
}
