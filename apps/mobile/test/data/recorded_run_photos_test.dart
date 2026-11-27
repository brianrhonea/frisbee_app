import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository_firebase.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/domain/models/workout.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/api_fakes.dart';
import '../testing/fakes.dart';
import '../testing/outbox_harness.dart';

class _Storage extends AttachmentStorage {
  final folders = <String>[];

  @override
  Future<List<ChatAttachment>> upload(
    String folder,
    List<NewAttachment> attachments,
  ) async {
    folders.add(folder);
    return [
      for (final (i, a) in attachments.indexed)
        ChatAttachment(
          path: '$folder/$i-${a.name}',
          name: a.name,
          contentType: 'image/jpeg',
          size: a.size,
        ),
    ];
  }
}

/// M1: a recorded run saved directly keeps its photos (17-B regression).
void main() {
  late FakeApi api;
  late FakeFirebaseFirestore db;
  late _Storage storage;

  setUp(() async {
    api = FakeApi();
    db = FakeFirebaseFirestore();
    storage = _Storage();
    await db.collection('profiles').doc('u1').set({'private': false});
  });

  UserPostRepositoryFirebase repo(OutboxHarness? h) =>
      UserPostRepositoryFirebase(
        attachments: storage,
        firestore: db,
        api: api.client(),
        uploads: api.uploadClient(),
        outbox: h?.outbox,
      );

  UserPostDraft draft() => UserPostDraft(
    post: const UserPost(
      id: '',
      workout: Workout(durationMinutes: 20, durationSeconds: 1230),
    ),
    newImages: [NewAttachment(name: 'a.jpg', bytes: Uint8List(4))],
  );

  Future<List<Object?>> imagesOf(String id) async =>
      (await db.collection('posts').doc(id).get()).data()!['images']
          as List<Object?>;

  test('saved directly: the photo is uploaded and on the post', () async {
    final r = await repo(null).savePost(draft(), testUser);
    final id = (r as Ok<String>).value;
    final images = await imagesOf(id);
    expect(images, hasLength(1));
    expect((images.single as Map)['path'], startsWith('users/u1/posts/$id/'));
    expect(storage.folders, hasLength(1));
    expect(api.sent, isEmpty);
  });

  test('through the outbox: photos kept, uploaded once', () async {
    final h = OutboxHarness();
    addTearDown(h.dispose);
    final r = await repo(h).savePost(draft(), testUser);
    final id = (r as Ok<String>).value;
    await h.outbox.drain();
    expect(await imagesOf(id), hasLength(1));
    expect(storage.folders, hasLength(1));
  });
}
