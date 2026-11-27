import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository_firebase.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/domain/models/workout.dart';
import 'package:frisbee_app/domain/models/workout_route.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/api_fakes.dart';
import '../testing/fakes.dart';
import '../testing/outbox_harness.dart';

/// A recorded run with photos goes through the API like any post (it was a
/// direct Firestore write before API 0.54.0).
void main() {
  late FakeApi api;
  late FakeFirebaseFirestore db;

  setUp(() async {
    api = FakeApi();
    db = FakeFirebaseFirestore();
    uploadsWork(api);
  });

  UserPostRepositoryFirebase repo(OutboxHarness? h) =>
      UserPostRepositoryFirebase(
        attachments: AttachmentStorage(),
        firestore: db,
        api: api.client(),
        uploads: api.uploadClient(),
        outbox: h?.outbox,
      );

  UserPostDraft draft() => UserPostDraft(
    post: UserPost(
      id: '',
      workout: Workout(
        durationMinutes: 20,
        durationSeconds: 1230,
        route: WorkoutRoute(
          path: const [RoutePoint(40, -105), RoutePoint(40.01, -105.01)],
        ),
      ),
    ),
    newImages: [NewAttachment(name: 'a.jpg', bytes: Uint8List(4))],
  );

  test('sent through the API with the photo as an upload id', () async {
    final r = await repo(null).savePost(draft(), testUser);
    final id = (r as Ok<String>).value;
    expect(api.bodyOf('POST /v1/uploads')['itemId'], id);
    final b = api.bodyOf('POST /v1/posts');
    expect(b['id'], id);
    expect(b['uploadIds'], ['up1']);
    expect((await db.collection('posts').get()).docs, isEmpty);
  });

  test('through the outbox: a retry reuses the id and uploads once; '
      'a 409 replay is sent', () async {
    final h = OutboxHarness();
    addTearDown(h.dispose);
    api.on('POST /v1/posts', [
      apiError(500, 'internal', 'Boom'),
      apiError(409, 'already_exists', 'That post already exists.'),
    ]);
    final r = await repo(h).savePost(draft(), testUser);
    final id = (r as Ok<String>).value;
    expect(h.outbox.jobs, hasLength(1));
    h.passTime();
    await h.outbox.drain();
    expect(h.outbox.jobs, isEmpty);
    expect(api.to('POST /v1/uploads'), hasLength(1));
    expect(
      {for (final s in api.to('POST /v1/posts')) (s.body as Map)['id']},
      {id},
    );
  });
}
