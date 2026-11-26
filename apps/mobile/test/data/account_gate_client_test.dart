import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/account_gate/account_gate.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A user that counts forced ID-token refreshes.
// ignore: must_be_immutable
class _CountingUser extends MockUser {
  _CountingUser() : super(uid: 'u1');

  int forced = 0;

  @override
  Future<String> getIdToken([bool forceRefresh = false]) {
    if (forceRefresh) forced++;
    return super.getIdToken(forceRefresh);
  }
}

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _incomplete(List<String> fields) => _json({
  'error': {
    'code': 'account_incomplete',
    'message': 'Verify your email address to continue.',
    'fields': {for (final f in fields) f: 'missing $f'},
  },
}, 403);

void main() {
  late _CountingUser user;
  late List<String> calls;
  late List<Map<String, Object?>> reported;

  ApiClient client(Future<http.Response> Function(http.Request) handler) {
    user = _CountingUser();
    calls = [];
    reported = [];
    return ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      auth: MockFirebaseAuth(signedIn: true, mockUser: user),
      client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return handler(req);
      }),
    )..onAccountIncomplete = (fields) => reported.add(fields);
  }

  group('403 account_incomplete', () {
    test(
      'status says refresh: token refreshed, request retried once',
      () async {
        var writes = 0;
        final api = client((req) async {
          if (req.url.path == '/v1/me/personal/status') {
            return _json({
              'complete': true,
              'required': false,
              'refreshToken': true,
            }, 200);
          }
          return ++writes == 1
              ? _incomplete(['terms'])
              : _json({'ok': true}, 200);
        });

        expect(await api.post('/v1/teams', {'name': 'Haze'}), {'ok': true});
        expect(calls, [
          'POST /v1/teams',
          'GET /v1/me/personal/status',
          'POST /v1/teams',
        ]);
        expect(user.forced, 1);
        expect(reported, isEmpty);
      },
    );

    test(
      'still incomplete after the retry: routed, no third request',
      () async {
        final api = client((req) async {
          if (req.url.path == '/v1/me/personal/status') {
            return _json({
              'complete': false,
              'required': true,
              'refreshToken': true,
            }, 200);
          }
          return _incomplete(['age', 'terms']);
        });

        await expectLater(
          api.post('/v1/teams', {}),
          throwsA(
            isA<ApiException>().having((e) => e.accountIncomplete, 'is', true),
          ),
        );
        expect(calls, [
          'POST /v1/teams',
          'GET /v1/me/personal/status',
          'POST /v1/teams',
        ]);
        expect(reported.single.keys, ['age', 'terms']);
      },
    );

    test('status has nothing to refresh: reported without a retry', () async {
      final api = client((req) async {
        if (req.url.path == '/v1/me/personal/status') {
          return _json({'complete': false, 'required': true}, 200);
        }
        return _incomplete(['email_unverified']);
      });

      await expectLater(api.put('/v1/me/x', {}), throwsA(isA<ApiException>()));
      expect(calls, ['PUT /v1/me/x', 'GET /v1/me/personal/status']);
      expect(user.forced, 0);
      expect(reported.single.keys, ['email_unverified']);
    });

    test('a failing status call keeps the original refusal', () async {
      final api = client((req) async {
        if (req.url.path == '/v1/me/personal/status') {
          return _json({
            'error': {'code': 'internal', 'message': 'x'},
          }, 500);
        }
        return _incomplete(['terms']);
      });
      await expectLater(api.post('/v1/a', {}), throwsA(isA<ApiException>()));
      expect(calls, ['POST /v1/a', 'GET /v1/me/personal/status']);
      expect(reported.single.keys, ['terms']);
    });

    test('the status call itself is never retried through the gate', () async {
      final api = client((_) async => _incomplete(['terms']));
      await expectLater(
        api.send('GET', '/v1/me/personal/status'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, ['GET /v1/me/personal/status']);
    });

    test('other errors pass straight through', () async {
      final api = client(
        (_) async => _json({
          'error': {'code': 'permission_denied', 'message': 'No.'},
        }, 403),
      );
      await expectLater(api.post('/v1/a', {}), throwsA(isA<ApiException>()));
      expect(calls, ['POST /v1/a']);
      expect(reported, isEmpty);
    });
  });

  group('refreshToken: true', () {
    test('any answer that carries it takes a new ID token', () async {
      final api = client(
        (_) async => _json({'agreed': true, 'refreshToken': true}, 200),
      );
      await api.put('/v1/me/agreement', {'version': 1});
      expect(user.forced, 1);
    });

    test('an answer without it does not', () async {
      final api = client((_) async => _json({'agreed': true}, 200));
      await api.put('/v1/me/agreement', {'version': 1});
      expect(user.forced, 0);
    });
  });

  group('AccountGate', () {
    test('reports in the contract order and clears step by step', () {
      final gate = AccountGate();
      gate.report(['terms', 'email_unverified', 'nonsense']);
      expect(gate.first, AccountGate.emailUnverified);
      gate.clear(AccountGate.emailUnverified);
      expect(gate.first, AccountGate.terms);
      gate.clear(AccountGate.terms);
      expect(gate.first, isNull);
    });

    test('under 18 is its own dead end and reset clears it', () {
      final gate = AccountGate()..markUnderAge();
      expect(gate.underAge, isTrue);
      gate.reset();
      expect(gate.underAge, isFalse);
    });
  });
}
