import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/outbox/outbox_repository.dart';
import 'package:frisbee_app/data/repositories/team_post/team_post_repository_firebase.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/outbox.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/api_fakes.dart';
import '../testing/fakes.dart';
import '../testing/outbox_harness.dart';

/// Team posts through the API (contracts/phase1-writes.md §3.7, D1).
void main() {
  late FakeApi api;
  late FakeFirebaseFirestore db;

  setUp(() {
    api = FakeApi();
    db = FakeFirebaseFirestore();
  });

  TeamPostRepositoryFirebase repo({OutboxHarness? h}) =>
      TeamPostRepositoryFirebase(
        attachments: AttachmentStorage(),
        firestore: db,
        api: api.client(),
        uploads: api.uploadClient(),
        outbox: h?.outbox,
      );

  Object errorOf(Result<Object?> r) => (r as Error).error;
  const route = 'POST /v1/teams/t1/posts';

  test('create: POST with a client id and the fields', () async {
    final r = await repo().savePost(
      't1',
      const PostDraft(
        post: TeamPost(
          id: '',
          title: ' Roster ',
          body: 'Tryouts Saturday',
          location: 'Field 3',
          links: ['https://a.b'],
          isPublic: true,
          tournamentKey: 'tournament_t1_x9',
        ),
      ),
      testUser,
    );
    expect(r, isA<Ok<void>>());
    final b = api.bodyOf(route);
    expect(b, {
      'id': b['id'],
      'title': 'Roster',
      'body': 'Tryouts Saturday',
      'location': 'Field 3',
      'links': ['https://a.b'],
      'public': true,
      'tournamentKey': 'tournament_t1_x9',
      'uploadIds': <String>[],
    });
    expect(b['id'], matches(RegExp(r'^[A-Za-z0-9]{1,40}$')));
  });

  test('a photo goes up as a teamImage for the team and the post', () async {
    uploadsWork(api);
    await repo().savePost(
      't1',
      PostDraft(
        post: const TeamPost(id: '', body: 'pic'),
        newImages: [NewAttachment(name: 'a.jpg', bytes: Uint8List(4))],
      ),
      testUser,
    );
    final id = api.bodyOf(route)['id'];
    expect(api.bodyOf('POST /v1/uploads'), {
      'purpose': 'teamImage',
      'contentType': 'image/jpeg',
      'size': 4,
      'itemId': id,
      'targetId': 't1',
    });
    expect(api.bodyOf(route)['uploadIds'], ['up1']);
  });

  test('edit: PATCH with keepImages and new uploads', () async {
    uploadsWork(api);
    await repo().savePost(
      't1',
      PostDraft(
        post: const TeamPost(
          id: 'p1',
          body: 'Edited',
          images: [
            ChatAttachment(
              path: 'teams/t1/posts/p1/k.jpg',
              name: 'k.jpg',
              contentType: 'image/jpeg',
              size: 1,
            ),
          ],
        ),
        newImages: [NewAttachment(name: 'n.png', bytes: Uint8List(2))],
      ),
      testUser,
    );
    expect(api.bodyOf('PATCH /v1/teams/t1/posts/p1'), {
      'title': '',
      'body': 'Edited',
      'location': '',
      'links': <String>[],
      'public': false,
      'keepImages': ['teams/t1/posts/p1/k.jpg'],
      'uploadIds': ['up1'],
    });
    expect(api.bodyOf('POST /v1/uploads')['itemId'], 'p1');
  });

  test('delete uses its route and writes nothing directly', () async {
    final r = await repo().deletePost('t1', 'p1');
    expect(r, isA<Ok<void>>());
    expect(api.sent.single.method, 'DELETE');
    expect(api.sent.single.path, '/v1/teams/t1/posts/p1');
  });

  test('only admins post: the server message comes back', () async {
    api.on(
      route,
      apiError(403, 'permission_denied', "Only the team's admins post for it."),
    );
    final r = await repo().savePost(
      't1',
      const PostDraft(
        post: TeamPost(id: '', body: 'x'),
      ),
      testUser,
    );
    expect(errorOf(r).toString(), "Only the team's admins post for it.");
    expect(outboxFailureFor(errorOf(r)), OutboxFailure.permanent);
  });

  test('offline: an edit fails with a retry; a new post waits', () async {
    final h = OutboxHarness();
    addTearDown(h.dispose);
    api.offline = true;
    final edit = await repo(h: h).savePost(
      't1',
      const PostDraft(
        post: TeamPost(id: 'p1', body: 'x'),
      ),
      testUser,
    );
    expect(
      errorOf(edit),
      isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
    );
    expect(h.outbox.jobs, isEmpty);
    final fresh = await repo(h: h).savePost(
      't1',
      const PostDraft(
        post: TeamPost(id: '', body: 'later'),
      ),
      testUser,
    );
    expect(fresh, isA<Ok<void>>());
    final job = h.outbox.jobs.single;
    api.offline = false;
    await h.connectivity.check();
    await h.outbox.drain();
    expect(h.outbox.jobs, isEmpty);
    expect(api.bodyOf(route)['id'], job.id);
  });

  test('upload done, send failed, replay with a 409: sent once', () async {
    final h = OutboxHarness();
    addTearDown(h.dispose);
    uploadsWork(api);
    api.on(route, [
      apiError(500, 'internal', 'Boom'),
      apiError(409, 'already_exists', 'That post already exists.'),
    ]);
    await repo(h: h).savePost(
      't1',
      PostDraft(
        post: const TeamPost(id: '', body: 'pic'),
        newImages: [NewAttachment(name: 'a.jpg', bytes: Uint8List(4))],
      ),
      testUser,
    );
    expect(h.outbox.jobs.single.uploads.keys, [0]);
    h.passTime();
    await h.outbox.drain();
    expect(h.outbox.jobs, isEmpty);
    expect(api.to('POST /v1/uploads'), hasLength(1));
    final sent = [for (final s in api.to(route)) s.body as Map];
    expect(sent[0]['uploadIds'], sent[1]['uploadIds']);
    expect(sent[0]['id'], sent[1]['id']);
  });

  test('a post queued by an older build still goes out', () async {
    final h = OutboxHarness(
      saved: [
        {
          'id': 'oldt',
          'uid': 'u1',
          'kind': 'teamPost',
          'createdAt': '2026-11-20T10:00:00.000Z',
          'target': 't1',
          'label': 'Team post',
          'payload': {
            'post': {
              'title': 'Old',
              'body': 'from before',
              'location': '',
              'links': <String>[],
              'images': <Object?>[],
              'public': true,
            },
          },
          'state': 'waiting',
          'attempts': 0,
        },
      ],
    );
    addTearDown(h.dispose);
    repo(h: h);
    await h.outbox.drain();
    expect(api.bodyOf(route), {
      'id': 'oldt',
      'title': 'Old',
      'body': 'from before',
      'location': '',
      'links': <String>[],
      'public': true,
      'uploadIds': <String>[],
    });
  });
}
