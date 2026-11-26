// The sign-up checks fail closed: an API error or an unreadable answer is a
// failed check (the router then blocks), never "let them in". Stale answers
// from a previous account are ignored. Mirrors the website's sign-up check.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/agreement/agreement_repository.dart';
import 'package:frisbee_app/data/repositories/personal/personal_repository_api.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../testing/fakes.dart';

void main() {
  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  /// An API whose answer to [path] comes from [answer], called per request.
  ApiClient api(Future<http.Response> Function() answer) => ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1')),
    client: MockClient((_) => answer()),
  );

  group('agreement', () {
    AgreementRepositoryApi repo(
      Future<http.Response> Function() answer, {
      FakeAuthRepository? auth,
    }) => AgreementRepositoryApi(
      api: api(answer),
      auth: auth ?? FakeAuthRepository(user: const AppUser(uid: 'u1')),
    );

    test('a definite answer is kept, and nothing is failed', () async {
      final r = repo(() async => json({'agreed': false}));
      await r.refresh();
      expect(r.agreed, isFalse);
      expect(r.mustAgree, isTrue);
      expect(r.checkFailed, isFalse);
    });

    test('an API error fails the check', () async {
      final r = repo(
        () async => json({
          'error': {'code': 'internal'},
        }, 500),
      );
      await r.refresh();
      expect(r.checkFailed, isTrue);
      expect(r.agreed, isNull);
    });

    test('a network error fails the check', () async {
      final r = repo(() async => throw http.ClientException('offline'));
      await r.refresh();
      expect(r.checkFailed, isTrue);
    });

    for (final bad in <Object>[
      <String, Object?>{},
      {'agreed': 'yes'},
      {'agreed': null},
      {'agreed': 1},
    ]) {
      test('a malformed answer $bad fails the check', () async {
        final r = repo(() async => json(bad));
        await r.refresh();
        expect(r.checkFailed, isTrue);
        expect(r.agreed, isNull);
      });
    }

    test('a retry that works clears the failure', () async {
      var ok = false;
      final r = repo(() async => ok ? json({'agreed': true}) : json({}, 503));
      await r.refresh();
      expect(r.checkFailed, isTrue);
      ok = true;
      await r.refresh();
      expect(r.checkFailed, isFalse);
      expect(r.agreed, isTrue);
    });

    test('with no API in the build, nobody is held up', () async {
      final r = AgreementRepositoryApi(
        api: null,
        auth: FakeAuthRepository(user: const AppUser(uid: 'u1')),
      );
      await r.refresh();
      expect(r.checkFailed, isFalse);
      expect(r.agreed, isNull);
    });

    test('an answer for the previous account is ignored', () async {
      final late = Completer<http.Response>();
      final auth = FakeAuthRepository(user: const AppUser(uid: 'u1'));
      var n = 0;
      final r = repo(
        () => n++ == 0 ? late.future : Completer<http.Response>().future,
        auth: auth,
      );
      // u1's request is in flight (started when the repository was built).
      auth.setUser(const AppUser(uid: 'u2'));
      late.complete(json({'agreed': false}));
      await Future<void>.delayed(Duration.zero);
      expect(r.agreed, isNull, reason: "u1's answer must not apply to u2");
      expect(r.checkFailed, isFalse);
    });

    test('a failure for the previous account is ignored too', () async {
      final late = Completer<http.Response>();
      final auth = FakeAuthRepository(user: const AppUser(uid: 'u1'));
      var n = 0;
      final r = repo(
        () => n++ == 0 ? late.future : Completer<http.Response>().future,
        auth: auth,
      );
      auth.setUser(const AppUser(uid: 'u2'));
      late.complete(json({}, 500));
      await Future<void>.delayed(Duration.zero);
      expect(r.checkFailed, isFalse);
    });

    test('switching account clears a failure', () async {
      final auth = FakeAuthRepository(user: const AppUser(uid: 'u1'));
      final r = repo(() async => json({}, 500), auth: auth);
      await Future<void>.delayed(Duration.zero);
      expect(r.checkFailed, isTrue);
      auth.setUser(null);
      expect(r.checkFailed, isFalse);
    });
  });

  group('personal details status', () {
    PersonalDetailsRepositoryApi repo(
      Future<http.Response> Function() answer, {
      FakeAuthRepository? auth,
    }) => PersonalDetailsRepositoryApi(
      api: api(answer),
      auth: auth ?? FakeAuthRepository(user: const AppUser(uid: 'u1')),
    );

    test('a definite answer is kept', () async {
      final r = repo(() async => json({'complete': false, 'required': true}));
      await r.refreshStatus();
      expect(r.mustComplete, isTrue);
      expect(r.checkFailed, isFalse);
    });

    test('an API error fails the check', () async {
      final r = repo(() async => json({}, 500));
      await r.refreshStatus();
      expect(r.checkFailed, isTrue);
      expect(r.status, isNull);
    });

    for (final bad in <Object>[
      <String, Object?>{},
      {'complete': true},
      {'complete': 'true', 'required': false},
      {'complete': null, 'required': null},
    ]) {
      test('a malformed answer $bad fails the check', () async {
        final r = repo(() async => json(bad));
        await r.refreshStatus();
        expect(r.checkFailed, isTrue);
        expect(r.status, isNull);
      });
    }

    test('a retry that works clears the failure', () async {
      var ok = false;
      final r = repo(
        () async =>
            ok ? json({'complete': true, 'required': true}) : json({}, 503),
      );
      await r.refreshStatus();
      expect(r.checkFailed, isTrue);
      ok = true;
      await r.refreshStatus();
      expect(r.checkFailed, isFalse);
      expect(r.status!.complete, isTrue);
    });

    test('with no API in the build, nobody is held up', () async {
      final r = PersonalDetailsRepositoryApi(
        api: null,
        auth: FakeAuthRepository(user: const AppUser(uid: 'u1')),
      );
      await r.refreshStatus();
      expect(r.checkFailed, isFalse);
    });

    test('an answer for the previous account is ignored', () async {
      final late = Completer<http.Response>();
      final auth = FakeAuthRepository(user: const AppUser(uid: 'u1'));
      var n = 0;
      final r = repo(
        () => n++ == 0 ? late.future : Completer<http.Response>().future,
        auth: auth,
      );
      auth.setUser(const AppUser(uid: 'u2'));
      late.complete(json({'complete': false, 'required': true}));
      await Future<void>.delayed(Duration.zero);
      expect(r.status, isNull);
      expect(r.mustComplete, isFalse);
      expect(r.checkFailed, isFalse);
    });

    test(
      'an older request finishing last does not overwrite a newer one',
      () async {
        final first = Completer<http.Response>();
        var calls = 0;
        final r = repo(() {
          calls++;
          return calls == 1
              ? first.future
              : Future.value(json({'complete': true, 'required': false}));
        });
        // Call 1 started with the repository; call 2 is the retry.
        await r.refreshStatus();
        expect(r.status!.complete, isTrue);
        first.complete(json({}, 500));
        await Future<void>.delayed(Duration.zero);
        expect(r.checkFailed, isFalse);
        expect(r.status!.complete, isTrue);
      },
    );
  });
}
