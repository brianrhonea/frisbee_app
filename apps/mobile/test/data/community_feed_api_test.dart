import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository_firebase.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<String> asked;
  late Map<String, Object?> answer;
  late FakeFirebaseFirestore db;

  UserPostRepositoryFirebase repo({bool api = true}) =>
      UserPostRepositoryFirebase(
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
                  asked.add('${req.method} ${req.url.path}?${req.url.query}');
                  return http.Response(
                    jsonEncode(answer),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }),
              )
            : null,
      );

  setUp(() {
    asked = [];
    answer = {};
    db = FakeFirebaseFirestore();
  });

  test('pages through GET /v1/feed, ids in order and the cursor', () async {
    answer = {
      'posts': [
        {'id': 'b', 'likeCount': 0, 'repostCount': 0},
        {'id': 'a', 'likeCount': 2, 'repostCount': 0},
      ],
      'next': 1730000000000,
    };
    final first = await repo().fetchCommunityPage();
    expect(first, isA<Ok<CommunityFeedPage>>());
    final page = (first as Ok<CommunityFeedPage>).value;
    expect(page.ids, ['b', 'a']);
    expect(page.next, 1730000000000);

    answer = {'posts': <Object?>[], 'next': null};
    final last = await repo().fetchCommunityPage(before: 1730000000000);
    expect((last as Ok<CommunityFeedPage>).value.next, isNull);
    expect(asked, ['GET /v1/feed?', 'GET /v1/feed?before=1730000000000']);
  });

  test('builds without an API have no community feed', () async {
    final r = repo(api: false);
    expect(r.hasCommunityFeed, isFalse);
    expect(repo().hasCommunityFeed, isTrue);
    expect(await r.fetchCommunityPage(), isA<Error<CommunityFeedPage>>());
    expect(asked, isEmpty);
  });

  test('watches the posts it was given, newest first', () async {
    for (final (id, day) in [('a', 1), ('b', 3), ('c', 2)]) {
      await db.doc('posts/$id').set({
        'authorId': 'u$id',
        'authorName': 'Player $id',
        'body': 'Post $id',
        'createdAt': DateTime(2026, 11, day),
      });
    }
    final posts = await repo().watchPostsByIds(['a', 'b', 'gone']).first;
    expect(posts.map((p) => p.id), ['b', 'a']);
  });
}
