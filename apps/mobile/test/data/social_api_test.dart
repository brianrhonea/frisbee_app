import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/follow/follow_repository_firebase.dart';
import 'package:frisbee_app/data/repositories/outbox/outbox_repository.dart';
import 'package:frisbee_app/data/repositories/post_comment/post_comment_repository_firebase.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository_firebase.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/domain/models/outbox.dart';
import 'package:frisbee_app/domain/models/post_comment.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/domain/models/workout.dart';
import 'package:frisbee_app/domain/models/workout_route.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/api_fakes.dart';
import '../testing/fakes.dart';
import '../testing/outbox_harness.dart';

/// Social writes through the API (contracts/phase1-writes.md §3.1, §3.2):
/// posts, comments, follows. Each test names the route, the exact body and
/// how errors come back.
void main() {
  late FakeApi api;
  late FakeFirebaseFirestore db;

  setUp(() {
    api = FakeApi();
    db = FakeFirebaseFirestore();
  });

  Object errorOf(Result<Object?> r) => (r as Error).error;

  group('user posts', () {
    UserPostRepositoryFirebase repo({OutboxRepository? outbox}) =>
        UserPostRepositoryFirebase(
          attachments: AttachmentStorage(),
          firestore: db,
          api: api.client(),
          uploads: api.uploadClient(),
          outbox: outbox,
        );

    test('a text post: POST /v1/posts with its id, body and links', () async {
      final r = await repo().savePost(
        const UserPostDraft(
          post: UserPost(id: '', body: ' Hello ', links: ['https://a.b']),
        ),
        testUser,
      );
      final id = (r as Ok<String>).value;
      expect(api.bodyOf('POST /v1/posts'), {
        'id': id,
        'body': 'Hello',
        'links': ['https://a.b'],
        'uploadIds': <String>[],
      });
    });

    test('a photo is uploaded as a post upload for the post id', () async {
      uploadsWork(api);
      final r = await repo().savePost(
        UserPostDraft(
          post: const UserPost(id: ''),
          newImages: [NewAttachment(name: 'a.jpg', bytes: Uint8List(5))],
        ),
        testUser,
      );
      final id = (r as Ok<String>).value;
      expect(api.bodyOf('POST /v1/uploads'), {
        'purpose': 'post',
        'contentType': 'image/jpeg',
        'size': 5,
        'itemId': id,
      });
      expect(api.bodyOf('POST /v1/posts'), {
        'id': id,
        'body': '',
        'links': <String>[],
        'uploadIds': ['up1'],
      });
    });

    test('a shared event and a tournament tag are in the body', () async {
      await repo().savePost(
        UserPostDraft(
          post: UserPost(
            id: '',
            body: 'Game on',
            event: SharedEvent(
              eventId: 'e1',
              title: 'Game',
              startsAt: DateTime.utc(2027, 1, 5),
              teamId: 't1',
              teamName: 'Haze',
            ),
            tournamentKey: 'tournament_h1_t9',
            tournamentName: 'Open',
          ),
        ),
        testUser,
      );
      final b = api.bodyOf('POST /v1/posts');
      expect(b['shareEvent'], {'eventId': 'e1', 'teamId': 't1'});
      expect(b['tournament'], {'key': 'tournament_h1_t9', 'name': 'Open'});
      expect(b.containsKey('workout'), isFalse);
    });

    test('a typed workout goes through the API in its shape', () async {
      await repo().savePost(
        const UserPostDraft(
          post: UserPost(
            id: '',
            workout: Workout(
              activity: WorkoutActivity.gym,
              durationMinutes: 45,
              effort: 7,
              exercises: [WorkoutExercise(name: 'Squat', sets: 3, reps: 5)],
            ),
          ),
        ),
        testUser,
      );
      expect(api.bodyOf('POST /v1/posts')['workout'], {
        'activity': 'gym',
        'durationMinutes': 45,
        'effort': 7,
        'exercises': [
          {'name': 'Squat', 'sets': 3, 'reps': 5},
        ],
      });
    });

    test('a recorded run: seconds and route go through the API', () async {
      final r = await repo().savePost(
        UserPostDraft(
          post: UserPost(
            id: '',
            workout: Workout(
              activity: WorkoutActivity.run,
              durationMinutes: 20,
              durationSeconds: 1230,
              distanceKm: 3,
              route: WorkoutRoute(
                path: const [RoutePoint(40, -105), RoutePoint(40.01, -105.01)],
                splitsKm: const [400, 410],
                elevationGainMeters: 12,
              ),
            ),
          ),
        ),
        testUser,
      );
      final id = (r as Ok<String>).value;
      final b = api.bodyOf('POST /v1/posts');
      expect(b['id'], id);
      final w = b['workout'] as Map;
      expect(w['durationSeconds'], 1230);
      final route = w['route'] as Map;
      expect(decodePolyline(route['path'] as String), hasLength(2));
      expect(route['splitsKm'], [400, 410]);
      expect(route['elevationGainM'], 12);
      // No direct Firestore write any more.
      expect((await db.collection('posts').get()).docs, isEmpty);
    });

    test('a recorded run with photos uploads them as post uploads', () async {
      uploadsWork(api);
      final r = await repo().savePost(
        UserPostDraft(
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
          newImages: [NewAttachment(name: 'a.jpg', bytes: Uint8List(5))],
        ),
        testUser,
      );
      final id = (r as Ok<String>).value;
      expect(api.bodyOf('POST /v1/uploads')['itemId'], id);
      expect(api.bodyOf('POST /v1/uploads')['purpose'], 'post');
      expect(api.bodyOf('POST /v1/posts')['uploadIds'], ['up1']);
    });

    test(
      'an oversize route is thinned to 4000 points before sending',
      () async {
        final path = [
          for (var i = 0; i < 6000; i++)
            RoutePoint(40 + i * 0.00005, -105 + (i.isEven ? 0.0002 : 0)),
        ];
        await repo().savePost(
          UserPostDraft(
            post: UserPost(
              id: '',
              workout: Workout(
                durationMinutes: 60,
                durationSeconds: 3600,
                route: WorkoutRoute(path: path),
              ),
            ),
          ),
          testUser,
        );
        final sent =
            (api.bodyOf('POST /v1/posts')['workout'] as Map)['route'] as Map;
        expect(
          decodePolyline(sent['path'] as String).length,
          lessThanOrEqualTo(WorkoutRoute.maxPoints),
        );
      },
    );

    test('a route too short is refused client-side, nothing sent', () async {
      final r = await repo().savePost(
        UserPostDraft(
          post: UserPost(
            id: '',
            workout: Workout(
              durationMinutes: 5,
              durationSeconds: 300,
              route: WorkoutRoute(path: const [RoutePoint(40, -105)]),
            ),
          ),
        ),
        testUser,
      );
      expect(r, isA<Error<String>>());
      expect(api.sent, isEmpty);
    });

    test('the server refusing an impossible pace shows its message', () async {
      api.on(
        'POST /v1/posts',
        apiError(400, 'invalid_argument', 'That pace is too fast.'),
      );
      final r = await repo().savePost(
        UserPostDraft(
          post: UserPost(
            id: '',
            workout: Workout(
              durationMinutes: 1,
              durationSeconds: 60,
              distanceKm: 900,
              route: WorkoutRoute(
                path: const [RoutePoint(40, -105), RoutePoint(40.01, -105.01)],
              ),
            ),
          ),
        ),
        testUser,
      );
      expect((r as Error).error.toString(), 'That pace is too fast.');
    });

    test('an edit: PATCH with keepImages, new uploads and the tag', () async {
      uploadsWork(api);
      final r = await repo().savePost(
        UserPostDraft(
          post: const UserPost(
            id: 'p1',
            body: 'Edited',
            links: ['https://x.y'],
            images: [
              ChatAttachment(
                path: 'users/u1/posts/p1/k.jpg',
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
      expect(r, isA<Ok<String>>());
      expect(api.bodyOf('PATCH /v1/posts/p1'), {
        'body': 'Edited',
        'links': ['https://x.y'],
        'keepImages': ['users/u1/posts/p1/k.jpg'],
        'uploadIds': ['up1'],
        'tournament': null,
      });
      expect(api.bodyOf('POST /v1/uploads')['itemId'], 'p1');
    });

    test('editing a repost sends only its note', () async {
      await repo().savePost(
        const UserPostDraft(
          post: UserPost(
            id: 'r1',
            body: 'note',
            repostOf: RepostOf(postId: 'p0', authorId: 'u9'),
          ),
        ),
        testUser,
      );
      expect(api.bodyOf('PATCH /v1/posts/r1'), {'body': 'note'});
    });

    test('like, unlike, repost, undo and delete use their routes', () async {
      final posts = repo();
      await posts.setLiked('p1', 'u1', true);
      await posts.setLiked('p1', 'u1', false);
      final r = await posts.repost(
        const UserPost(id: 'p1', authorId: 'u9'),
        ' nice ',
        testUser,
      );
      expect((r as Ok<String>).value, 'r_p1_u1');
      await posts.undoRepost('p1', 'u1');
      await posts.deletePost('p1');
      expect(
        [for (final s in api.sent) '${s.method} ${s.path}'],
        [
          'PUT /v1/posts/p1/like',
          'DELETE /v1/posts/p1/like',
          'PUT /v1/posts/p1/repost',
          'DELETE /v1/posts/p1/repost',
          'DELETE /v1/posts/p1',
        ],
      );
      expect(api.bodyOf('PUT /v1/posts/p1/repost'), {'note': 'nice'});
    });

    test('reposting a repost acts on its original', () async {
      await repo().repost(
        const UserPost(
          id: 'r_p0_u9',
          repostOf: RepostOf(postId: 'p0', authorId: 'u9'),
        ),
        '',
        testUser,
      );
      expect(api.to('PUT /v1/posts/p0/repost'), hasLength(1));
    });

    test('the server message comes back as the error', () async {
      api.on(
        'PUT /v1/posts/p1/like',
        apiError(403, 'permission_denied', "You can't do that: blocked."),
      );
      final r = await repo().setLiked('p1', 'u1', true);
      expect(errorOf(r), isA<ApiException>());
      expect(errorOf(r).toString(), "You can't do that: blocked.");
    });

    test('offline: a retryable error, not a hanging write', () async {
      api.offline = true;
      final r = await repo().setLiked('p1', 'u1', true);
      expect(
        errorOf(r),
        isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
      );
      expect(
        errorOf(r).toString(),
        "Couldn't reach the server. Check your connection and try again.",
      );
    });

    test('account_incomplete: refused after the one retry, and told', () async {
      Map<String, String>? told;
      api.on('GET /v1/me/personal/status', {'refreshToken': false});
      api.on(
        'POST /v1/posts',
        apiError(403, 'account_incomplete', 'Finish setting up first.'),
      );
      final posts = UserPostRepositoryFirebase(
        attachments: AttachmentStorage(),
        firestore: db,
        api: api.client(onIncomplete: (f) => told = f),
      );
      final r = await posts.savePost(
        const UserPostDraft(
          post: UserPost(id: '', body: 'x'),
        ),
        testUser,
      );
      expect((errorOf(r) as ApiException).accountIncomplete, isTrue);
      expect(told, isNotNull);
      // The queue fails it for good (D3): no waiting on a gate.
      expect(outboxFailureFor(errorOf(r)), OutboxFailure.permanent);
    });

    test('no API in this build: a clear error, no direct write', () async {
      final posts = UserPostRepositoryFirebase(
        attachments: AttachmentStorage(),
        firestore: db,
      );
      final r = await posts.setLiked('p1', 'u1', true);
      expect(errorOf(r), isA<ApiException>());
      expect((await posts.deletePost('p1')), isA<Error<void>>());
      expect((await db.collection('posts').get()).docs, isEmpty);
    });

    group('with the offline queue', () {
      late OutboxHarness h;
      setUp(() => h = OutboxHarness());
      tearDown(() => h.dispose());

      Future<Result<String>> postWithPhoto() => repo(outbox: h.outbox).savePost(
        UserPostDraft(
          post: const UserPost(id: '', body: 'pic'),
          newImages: [NewAttachment(name: 'a.jpg', bytes: Uint8List(5))],
        ),
        testUser,
      );

      test('upload done, send failed, replay: no second upload', () async {
        uploadsWork(api);
        api.on('POST /v1/posts', [
          apiError(500, 'internal', 'Boom'),
          {'id': 'x'},
        ]);
        final r = await postWithPhoto();
        final id = (r as Ok<String>).value;
        expect(h.outbox.jobs.single.id, id);
        expect(h.outbox.jobs.single.uploads.keys, [0]);
        expect(api.to('POST /v1/uploads'), hasLength(1));

        h.passTime();
        await h.outbox.drain();
        expect(h.outbox.jobs, isEmpty);
        // Still one upload; the same id was sent both times.
        expect(api.to('POST /v1/uploads'), hasLength(1));
        final bodies = [
          for (final s in api.to('POST /v1/posts')) s.body as Map,
        ];
        expect(bodies, hasLength(2));
        expect(bodies.map((b) => b['id']).toSet(), {id});
        expect(bodies.map((b) => '${b['uploadIds']}').toSet(), {'[up1]'});
      });

      test('a 409 on the replay counts as sent', () async {
        uploadsWork(api);
        api.on('POST /v1/posts', [
          apiError(500, 'internal', 'Boom'),
          apiError(409, 'already_exists', 'That post already exists.'),
        ]);
        await postWithPhoto();
        expect(h.outbox.jobs, hasLength(1));
        h.passTime();
        await h.outbox.drain();
        expect(h.outbox.jobs, isEmpty);
        expect(api.to('POST /v1/posts'), hasLength(2));
        expect(api.to('POST /v1/uploads'), hasLength(1));
      });

      test('offline: queued, then sent when back', () async {
        api.offline = true;
        final r = await repo(outbox: h.outbox).savePost(
          const UserPostDraft(
            post: UserPost(id: '', body: 'later'),
          ),
          testUser,
        );
        expect(r, isA<Ok<String>>());
        expect(h.outbox.jobs.single.version, OutboxJob.currentVersion);
        api.offline = false;
        await h.connectivity.check();
        await h.outbox.drain();
        expect(h.outbox.jobs, isEmpty);
        expect(api.bodyOf('POST /v1/posts')['body'], 'later');
      });

      test('a post queued by an older build still goes out', () async {
        final old = OutboxHarness(
          saved: [
            {
              'id': 'old1',
              'uid': 'u1',
              'kind': 'userPost',
              'createdAt': '2026-11-20T10:00:00.000Z',
              'target': 'posts',
              'label': 'Post',
              'payload': {
                'post': {
                  'kind': 'text',
                  'body': 'from before',
                  'links': ['https://a.b'],
                  'images': <Object?>[],
                  'workout': null,
                  'event': null,
                  'repostOf': null,
                  'tournamentKey': 'tournament_h1_t9',
                  'tournamentName': 'Open',
                },
              },
              'state': 'waiting',
              'attempts': 0,
            },
          ],
        );
        addTearDown(old.dispose);
        repo(outbox: old.outbox);
        await old.outbox.drain();
        expect(api.bodyOf('POST /v1/posts'), {
          'id': 'old1',
          'body': 'from before',
          'links': ['https://a.b'],
          'tournament': {'key': 'tournament_h1_t9', 'name': 'Open'},
          'uploadIds': <String>[],
        });
        expect(old.outbox.jobs, isEmpty);
      });

      test('a job that cannot be mapped fails, and is kept', () async {
        final old = OutboxHarness(
          saved: [
            {
              'id': 'bad1',
              'uid': 'u1',
              'kind': 'userPost',
              'createdAt': '2026-11-20T10:00:00.000Z',
              'target': 'posts',
              'label': 'Post',
              'payload': {'something': 'else'},
              'state': 'waiting',
              'attempts': 0,
            },
          ],
        );
        addTearDown(old.dispose);
        repo(outbox: old.outbox);
        await old.outbox.drain();
        final job = old.outbox.jobs.single;
        expect(job.state, OutboxState.failed);
        expect(job.error, "Couldn't be sent.");
        expect(api.sent, isEmpty);
      });
    });
  });

  group('comments', () {
    PostCommentRepositoryFirebase repo({OutboxRepository? outbox}) =>
        PostCommentRepositoryFirebase(
          firestore: db,
          api: api.client(),
          outbox: outbox,
        );

    PostComment comment({String? parentId}) => PostComment(
      id: 'c1',
      postId: 'p1',
      authorId: 'u9',
      authorName: 'Sam',
      body: 'x',
      parentId: parentId,
    );

    test('add: POST with its id; a reply names the comment answered', () async {
      final c = repo();
      final top = await c.addComment('p1', 'Nice', testUser);
      final reply = await c.addComment(
        'p1',
        'Agreed',
        testUser,
        replyTo: comment(parentId: 'c0'),
      );
      final sent = api.to('POST /v1/posts/p1/comments');
      expect(sent[0].body, {'id': (top as Ok<String>).value, 'body': 'Nice'});
      expect(sent[1].body, {
        'id': (reply as Ok<String>).value,
        'body': 'Agreed',
        'replyTo': 'c1',
      });
    });

    test('edit, like, unlike and delete use their routes', () async {
      final c = repo();
      await c.editComment(comment(), ' new ');
      await c.setCommentLiked(comment(), 'u1', liked: true);
      await c.setCommentLiked(comment(), 'u1', liked: false);
      await c.deleteComment(comment());
      expect(
        [for (final s in api.sent) '${s.method} ${s.path}'],
        [
          'PATCH /v1/posts/p1/comments/c1',
          'PUT /v1/posts/p1/comments/c1/like',
          'DELETE /v1/posts/p1/comments/c1/like',
          'DELETE /v1/posts/p1/comments/c1',
        ],
      );
      expect(api.bodyOf('PATCH /v1/posts/p1/comments/c1'), {'body': 'new'});
    });

    test('a refused comment shows the server message', () async {
      api.on(
        'POST /v1/posts/p1/comments',
        apiError(429, 'resource_exhausted', 'Slow down: wait 2 minutes.'),
      );
      final r = await repo().addComment('p1', 'Nice', testUser);
      expect(errorOf(r).toString(), 'Slow down: wait 2 minutes.');
    });

    test('offline: queued, then sent once back, with one id', () async {
      final h = OutboxHarness();
      addTearDown(h.dispose);
      api.offline = true;
      final r = await repo(
        outbox: h.outbox,
      ).addComment('p1', 'Later', testUser);
      final id = (r as Ok<String>).value;
      expect(h.outbox.jobs.single.id, id);
      api.offline = false;
      await h.connectivity.check();
      await h.outbox.drain();
      expect(h.outbox.jobs, isEmpty);
      expect(api.bodyOf('POST /v1/posts/p1/comments'), {
        'id': id,
        'body': 'Later',
      });
    });

    test('a 409 replay is sent, not an error', () async {
      final h = OutboxHarness();
      addTearDown(h.dispose);
      api.on('POST /v1/posts/p1/comments', [
        apiError(500, 'internal', 'Boom'),
        apiError(409, 'already_exists', 'That comment was already posted.'),
      ]);
      await repo(outbox: h.outbox).addComment('p1', 'Twice', testUser);
      expect(h.outbox.jobs, hasLength(1));
      h.passTime();
      await h.outbox.drain();
      expect(h.outbox.jobs, isEmpty);
    });

    test('a comment queued by an older build: parentId is replyTo', () async {
      final h = OutboxHarness(
        saved: [
          {
            'id': 'oldc',
            'uid': 'u1',
            'kind': 'comment',
            'createdAt': '2026-11-20T10:00:00.000Z',
            'target': 'p1',
            'label': 'Comment',
            'payload': {
              'body': 'hello',
              'parentId': 'c0',
              'replyToName': 'Sam',
            },
            'state': 'waiting',
            'attempts': 0,
          },
        ],
      );
      addTearDown(h.dispose);
      repo(outbox: h.outbox);
      await h.outbox.drain();
      expect(api.bodyOf('POST /v1/posts/p1/comments'), {
        'id': 'oldc',
        'body': 'hello',
        'replyTo': 'c0',
      });
      expect(h.outbox.jobs, isEmpty);
    });
  });

  group('follows', () {
    FollowRepositoryFirebase repo() =>
        FollowRepositoryFirebase(firestore: db, api: api.client());

    test('follow a player, a team and a tournament', () async {
      final f = repo();
      await f.follow('u1', const FollowTarget.user('u9', 'Sam'), notify: true);
      await f.follow('u1', const FollowTarget.team('t1', 'Haze'));
      await f.follow('u1', const FollowTarget.tournament('h1', 't9', 'Open'));
      expect(
        [for (final s in api.to('PUT /v1/follows')) s.body],
        [
          {'type': 'user', 'targetId': 'u9', 'notify': true},
          {'type': 'team', 'targetId': 't1', 'notify': false},
          {
            'type': 'tournament',
            'targetId': 't9',
            'groupId': 'h1',
            'notify': false,
          },
        ],
      );
    });

    test(
      'unfollow, notify, request, cancel, decline use their routes',
      () async {
        final f = repo();
        await f.unfollow('u1', 'user_u9');
        await f.setNotify('u1', 'user_u9', true);
        await f.requestFollow(testUser, 'u9');
        await f.cancelFollowRequest('u1', 'u9');
        await f.declineFollowRequest('u1', 'u5');
        expect(
          [for (final s in api.sent) '${s.method} ${s.path}'],
          [
            'DELETE /v1/follows/user_u9',
            'PATCH /v1/follows/user_u9',
            'PUT /v1/follows',
            'DELETE /v1/follows/requests/u9',
            'DELETE /v1/me/follow-requests/u5',
          ],
        );
        expect(api.bodyOf('PATCH /v1/follows/user_u9'), {'notify': true});
        expect(api.bodyOf('PUT /v1/follows'), {
          'type': 'user',
          'targetId': 'u9',
          'notify': false,
        });
      },
    );

    test('accept: the route, and a second accept is done', () async {
      final f = repo();
      const request = FollowRequest(uid: 'u5', name: 'Pat');
      expect(await f.acceptFollowRequest(testUser, request), isA<Ok<void>>());
      expect(api.to('POST /v1/me/follow-requests/u5/accept'), hasLength(1));
      api.on(
        'POST /v1/me/follow-requests/u5/accept',
        apiError(404, 'not_found', 'That request is gone.'),
      );
      expect(await f.acceptFollowRequest(testUser, request), isA<Ok<void>>());
    });

    test('a block comes back as the server message', () async {
      api.on(
        'PUT /v1/follows',
        apiError(
          403,
          'permission_denied',
          "You can't do that: one of you blocked the other.",
        ),
      );
      final r = await repo().follow('u1', const FollowTarget.user('u9', 'S'));
      expect(
        errorOf(r).toString(),
        "You can't do that: one of you blocked the other.",
      );
    });

    test('offline: a retryable error', () async {
      api.offline = true;
      final r = await repo().unfollow('u1', 'user_u9');
      expect(
        errorOf(r),
        isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
      );
    });
  });
}
