import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/callable_client.dart';
import 'package:frisbee_app/data/services/meeting_token_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Gated callables follow the account gate contract (account-gate.md
// sections 2 and 9) the way ApiClient does for the API's 403.

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

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// What `HttpsError('permission-denied', ..., details)` looks like on the wire.
http.Response _incomplete(List<String> fields) => _json({
  'error': {
    'message': 'Verify your email address to continue.',
    'status': 'PERMISSION_DENIED',
    'details': {
      'code': 'account_incomplete',
      'fields': {for (final f in fields) f: 'missing $f'},
    },
  },
}, 403);

http.Response _plainDenied() => _json({
  'error': {'message': 'Not on this team.', 'status': 'PERMISSION_DENIED'},
}, 403);

http.Response _status({required bool refresh}) =>
    _json({'complete': refresh, 'required': !refresh, 'refreshToken': refresh});

const _statusPath = '/v1/me/personal/status';

void main() {
  late _CountingUser user;
  late MockFirebaseAuth auth;
  late List<String> calls;
  late List<Map<String, Object?>> reported;
  late http.Response Function(http.Request) handler;
  late http.Client mock;

  setUp(() {
    user = _CountingUser();
    auth = MockFirebaseAuth(signedIn: true, mockUser: user);
    calls = [];
    reported = [];
    mock = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      return handler(req);
    });
  });

  ApiClient api() => ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    auth: auth,
    client: mock,
  )..onAccountIncomplete = (fields) => reported.add(fields);

  Future<Object?> callable(ApiClient? a) => CallableClient(
    projectId: 'p',
    auth: auth,
    client: mock,
    api: a,
  ).call('leagues-startDraft', {'leagueId': 'l1'});

  Future<Object?> meeting(ApiClient? a) => MeetingTokenService(
    projectId: 'p',
    auth: auth,
    client: mock,
    api: a,
  ).joinToken('t1', 'm1');

  http.Response ok(http.Request req) => req.url.path.contains('joinToken')
      ? _json({
          'result': {'url': 'wss://x', 'token': 'tok'},
        })
      : _json({'result': 'done'});

  final subjects = <String, Future<Object?> Function(ApiClient? api)>{
    'CallableClient': callable,
    'MeetingTokenService': meeting,
  };

  for (final MapEntry(key: name, value: invoke) in subjects.entries) {
    group(name, () {
      test('incomplete, refresh, retry: succeeds', () async {
        var attempts = 0;
        handler = (req) {
          if (req.url.path == _statusPath) return _status(refresh: true);
          return ++attempts == 1 ? _incomplete(['terms']) : ok(req);
        };
        await invoke(api());
        expect(calls.length, 3);
        expect(calls[1], 'GET $_statusPath');
        expect(calls[0], calls[2]);
        expect(user.forced, 1);
        expect(reported, isEmpty);
      });

      test('still incomplete after the retry: routed, no third call', () async {
        handler = (req) => req.url.path == _statusPath
            ? _status(refresh: true)
            : _incomplete(['age', 'terms']);
        await expectLater(invoke(api()), throwsA(isA<Exception>()));
        expect(calls.length, 3, reason: 'call, status, one retry');
        expect(reported.single.keys, ['age', 'terms']);
      });

      test('status has nothing to refresh: routed without a retry', () async {
        handler = (req) => req.url.path == _statusPath
            ? _status(refresh: false)
            : _incomplete(['email_unverified']);
        await expectLater(invoke(api()), throwsA(isA<Exception>()));
        expect(calls.length, 2);
        expect(user.forced, 0);
        expect(reported.single.keys, ['email_unverified']);
      });

      test('a failing status call keeps the refusal and routes', () async {
        handler = (req) => req.url.path == _statusPath
            ? _json({
                'error': {'code': 'internal', 'message': 'x'},
              }, 500)
            : _incomplete(['terms']);
        await expectLater(invoke(api()), throwsA(isA<Exception>()));
        expect(calls.length, 2);
        expect(reported.single.keys, ['terms']);
      });

      test('other permission-denied errors are unchanged', () async {
        handler = (_) => _plainDenied();
        await expectLater(
          invoke(api()),
          throwsA(
            predicate(
              (e) => e.toString() == 'Not on this team.',
              'the function message',
            ),
          ),
        );
        expect(calls.length, 1, reason: 'no status call, no retry');
        expect(user.forced, 0);
        expect(reported, isEmpty);
      });

      test('without an ApiClient the refusal is thrown as before', () async {
        handler = (_) => _incomplete(['terms']);
        await expectLater(
          invoke(null),
          throwsA(
            predicate(
              (e) => e.toString() == 'Verify your email address to continue.',
              'the function message',
            ),
          ),
        );
        expect(calls.length, 1);
      });

      test('success needs no status call', () async {
        handler = ok;
        await invoke(api());
        expect(calls.length, 1);
      });
    });
  }
}
