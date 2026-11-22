import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/chat/chat_repository_firebase.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/data/services/firestore_utils.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/utils/result.dart';

/// Team chat unread dots: senders stamp the room's lastAt (never the text)
/// and their own read in one batch; members' reads are private docs.
void main() {
  late FakeFirebaseFirestore db;
  late ChatRepositoryFirebase repo;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = ChatRepositoryFirebase(
      attachments: AttachmentStorage(),
      firestore: db,
    );
    await db.doc('teams/t1/chats/general').set({
      'name': 'General',
      'readRoles': ['everyone'],
      'writeRoles': ['everyone'],
    });
  });

  test('sending stamps the room and marks it read for the sender', () async {
    final sent = await repo.sendMessage(
      't1',
      'general',
      author: const AppUser(uid: 'u1', displayName: 'Ana'),
      text: ' hi ',
    );
    expect(sent, isA<Ok<void>>());
    final room = (await db.doc('teams/t1/chats/general').get()).data()!;
    expect(room['lastAt'], isNotNull);
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
