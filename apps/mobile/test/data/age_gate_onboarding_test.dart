import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository_firebase.dart';
import 'package:frisbee_app/data/services/account_service.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/auth_service.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An auth service whose `ageOk` claim the test controls.
class _Service extends AuthService {
  _Service(MockFirebaseAuth auth) : super(auth: auth);

  bool claim = false;
  int verificationsSent = 0;
  bool verified = false;

  @override
  Future<bool> ageOk() async => claim;

  @override
  Future<void> sendEmailVerification() async => verificationsSent++;

  @override
  bool get emailVerified => verified;

  @override
  Future<bool> reloadVerified() async => verified;
}

/// The server refuses the directory profile, the username and a photo until
/// the token has `ageOk` (account-gate contract, review finding F1): the app
/// must not even try before the birth date step has succeeded.
void main() {
  late MockFirebaseAuth auth;
  late _Service service;
  late FakeFirebaseFirestore db;
  late List<String> apiCalls;
  late AuthRepositoryFirebase repo;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  AuthRepositoryFirebase build() => AuthRepositoryFirebase(
    authService: service,
    accountService: AccountService(
      projectId: 'demo',
      auth: auth,
      client: MockClient((_) async => http.Response('{}', 500)),
    ),
    firestore: db,
    api: ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      auth: auth,
      client: MockClient((req) async {
        apiCalls.add('${req.method} ${req.url.path}');
        return http.Response(
          jsonEncode({}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );

  Future<bool> exists(String path) async => (await db.doc(path).get()).exists;

  setUp(() async {
    apiCalls = [];
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: 'u1',
        email: 'pat@example.com',
        displayName: 'Pat Lee',
      ),
    );
    service = _Service(auth);
    repo = build();
    await settle();
  });

  tearDown(() => repo.dispose());

  test(
    'before ageOk: no directory profile, no username, no API call',
    () async {
      expect(repo.ageOk, isFalse);
      // The user's own doc is on the open path, so it is still written.
      expect(await exists('users/u1'), isTrue);
      expect(await exists('profiles/u1'), isFalse);

      final result = await repo.claimUsername('patlee');
      expect(result, isA<Error<void>>());
      expect((result as Error<void>).error, isA<AgeNotConfirmedException>());
      expect(apiCalls, isEmpty);
      expect(await exists('usernames/patlee'), isFalse);
      expect(await exists('profiles/u1'), isFalse);
    },
  );

  test('once the token has ageOk the held-back profile is written', () async {
    expect(await exists('profiles/u1'), isFalse);
    service.claim = true;
    // A refreshed token (or "I've verified") re-reads the claim.
    await repo.checkEmailVerified();
    await settle();
    expect(repo.ageOk, isTrue);
    expect(await exists('profiles/u1'), isTrue);
  });

  test('and a username can then be claimed through the API', () async {
    service.claim = true;
    final result = await repo.claimUsername('patlee');
    expect(result, isA<Ok<void>>());
    expect(apiCalls, ['POST /v1/me/username']);
  });

  group('email sign-up order', () {
    late List<String> order;

    setUp(() {
      order = [];
    });

    test(
      'verification email, birth date, token claim, then the username',
      () async {
        await auth.signOut();
        await settle();
        final result = await repo.signUpWithEmail(
          email: 'new@example.com',
          password: 'correct horse battery',
          firstName: 'New',
          lastName: 'Person',
          username: 'newperson',
          afterCreate: () async {
            order.add('birth-date');
            // The server set ageOk and the ApiClient refreshed the token.
            expect(apiCalls, isEmpty);
            expect(service.verificationsSent, 1);
            service.claim = true;
            return true;
          },
        );
        expect(result, isA<Ok<void>>());
        expect(order, ['birth-date']);
        // The username came after the birth date step.
        expect(apiCalls, ['POST /v1/me/username']);
      },
    );

    test('birth date refused: no username and no profile', () async {
      await auth.signOut();
      await settle();
      await repo.signUpWithEmail(
        email: 'new@example.com',
        password: 'correct horse battery',
        firstName: 'New',
        lastName: 'Person',
        username: 'newperson',
        afterCreate: () async => false,
      );
      expect(apiCalls, isEmpty);
      expect(await exists('usernames/newperson'), isFalse);
      final uid = auth.currentUser!.uid;
      expect(await exists('profiles/$uid'), isFalse);
    });

    test('birth date unreachable (no claim): the username waits', () async {
      await auth.signOut();
      await settle();
      final result = await repo.signUpWithEmail(
        email: 'new@example.com',
        password: 'correct horse battery',
        firstName: 'New',
        lastName: 'Person',
        username: 'newperson',
        afterCreate: () async => true,
      );
      expect(result, isA<Ok<void>>());
      expect(apiCalls, isEmpty);
      final uid = auth.currentUser!.uid;
      expect(await exists('profiles/$uid'), isFalse);
    });
  });
}
