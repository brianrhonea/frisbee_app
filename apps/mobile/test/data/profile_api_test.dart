import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository_firebase.dart';
import 'package:frisbee_app/data/repositories/profile/profile_repository_firebase.dart';
import 'package:frisbee_app/data/services/account_service.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/auth_service.dart';
import 'package:frisbee_app/data/services/feature_flags.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/username.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<Map<String, Object?>> sent;
  late FakeFirebaseFirestore db;
  late http.Response Function() respond;
  late MockFirebaseAuth auth;

  ApiClient client() => ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    auth: auth,
    client: MockClient((req) async {
      sent.add({
        'method': req.method,
        'path': req.url.path,
        'body': jsonDecode(req.body),
      });
      return respond();
    }),
  );

  http.Response ok(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  setUp(() {
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'u1', displayName: 'Pat'),
    );
    sent = [];
    db = FakeFirebaseFirestore();
    respond = () => ok({});
  });

  const me = AppUser(uid: 'u1', displayName: 'Pat');

  group('ProfileRepositoryFirebase through the API', () {
    ProfileRepositoryFirebase repo({FeatureFlags? flags}) =>
        ProfileRepositoryFirebase(firestore: db, api: client(), flags: flags);

    test(
      'saves details, privacy and visibility, writing nothing itself',
      () async {
        final r = repo();
        expect(
          await r.saveDetails(
            me,
            const ProfileDetails(bio: ' Hi ', playingSince: 2015),
            tags: ['ut'],
          ),
          isA<Ok<void>>(),
        );
        expect(await r.setPrivate(me, true), isA<Ok<void>>());
        expect(
          await r.saveVisibility(me, const ProfileVisibility(stats: false)),
          isA<Ok<void>>(),
        );
        expect(sent, [
          {
            'method': 'PUT',
            'path': '/v1/me/profile/details',
            'body': {
              'bio': 'Hi',
              'pronouns': '',
              'hometown': '',
              'school': '',
              'throwingHand': null,
              'playingSince': 2015,
              'visibility': {'stats': true, 'teams': true, 'games': true},
              'tags': ['ut'],
            },
          },
          {
            'method': 'PUT',
            'path': '/v1/me/profile/privacy',
            'body': {'private': true},
          },
          {
            'method': 'PUT',
            'path': '/v1/me/profile/visibility',
            'body': {
              'visibility': {'stats': false, 'teams': true, 'games': true},
              'tags': <String>[],
            },
          },
        ]);
        expect((await db.collection('profiles').get()).docs, isEmpty);
      },
    );

    test('writes Firestore itself when use_api_profiles is off', () async {
      await repo(
        flags: FeatureFlags.fixed({'use_api_profiles': false}),
      ).saveDetails(me, const ProfileDetails(bio: 'Hi'), tags: const []);
      expect(sent, isEmpty);
      expect((await db.doc('profiles/u1').get()).get('bio'), 'Hi');
    });
  });

  group('AuthRepositoryFirebase.claimUsername through the API', () {
    late AuthRepositoryFirebase repo;

    setUp(() async {
      repo = AuthRepositoryFirebase(
        authService: AuthService(auth: auth),
        accountService: AccountService(projectId: 'demo', auth: auth),
        firestore: db,
        api: client(),
      );
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() => repo.dispose());

    test('claims through the API', () async {
      respond = () => ok({'username': 'pat_lee'});
      expect(await repo.claimUsername('@Pat_Lee'), isA<Ok<void>>());
      expect(sent.single['body'], {'username': 'pat_lee'});
      expect(repo.currentUser?.username, 'pat_lee');
      expect((await db.collection('usernames').get()).docs, isEmpty);
    });

    test('a taken name is UsernameTakenException, as before', () async {
      respond = () => http.Response(
        jsonEncode({
          'error': {
            'code': 'already_exists',
            'message': '@pat is taken. Try another.',
          },
        }),
        409,
        headers: {'content-type': 'application/json'},
      );
      final r = await repo.claimUsername('pat');
      expect(
        r,
        isA<Error<void>>().having(
          (e) => e.error,
          'error',
          isA<UsernameTakenException>(),
        ),
      );
    });
  });
}
