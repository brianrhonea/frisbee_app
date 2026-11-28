import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/team/team_repository_firebase.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/data/services/feature_flags.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _base = Uri.parse('https://api.test');

MockFirebaseAuth _signedIn() =>
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));

ApiClient _client(MockClientHandler handler, {MockFirebaseAuth? auth}) =>
    ApiClient(
      baseUrl: _base,
      auth: auth ?? _signedIn(),
      client: MockClient(handler),
    );

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('ApiClient', () {
    test('posts JSON with the ID token and returns the answer', () async {
      late http.Request sent;
      final api = _client((req) async {
        sent = req;
        return _json({'id': 't1'}, 201);
      });

      expect(await api.post('/v1/teams', {'name': 'Haze'}), {'id': 't1'});
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'https://api.test/v1/teams');
      expect(sent.headers['Authorization'], startsWith('Bearer '));
      expect(sent.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(sent.body), {'name': 'Haze'});
    });

    test(
      'a non-string error code falls back to internal, not a TypeError',
      () async {
        for (final code in [
          42,
          true,
          null,
          {'a': 1},
          ['x'],
        ]) {
          final api = _client(
            (_) async => _json({
              'error': {'code': code, 'message': 'Nope.'},
            }, 400),
          );
          await expectLater(
            api.post('/v1/teams', {}),
            throwsA(
              isA<ApiException>()
                  .having((e) => e.code, 'code', 'internal')
                  .having((e) => e.message, 'message', 'Nope.'),
            ),
            reason: 'code: $code',
          );
        }
      },
    );

    test("throws the API's own message and fields", () async {
      final api = _client(
        (_) async => _json({
          'error': {
            'code': 'invalid_argument',
            'message': 'Name your team.',
            'fields': {'name': 'Name your team.'},
          },
        }, 400),
      );

      await expectLater(
        api.post('/v1/teams', {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'invalid_argument')
              .having((e) => e.toString(), 'message', 'Name your team.')
              .having((e) => e.fields, 'fields', {'name': 'Name your team.'}),
        ),
      );
    });

    test('explains an answer that is not JSON', () async {
      final api = _client((_) async => http.Response('<html>502</html>', 502));
      await expectLater(
        api.post('/v1/teams', {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            "Couldn't reach the server (502).",
          ),
        ),
      );
    });

    test('explains a network failure', () async {
      final api = _client((_) async => throw const SocketException('down'));
      await expectLater(
        api.post('/v1/teams', {}),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
    });

    test('a dead kept-alive connection is retried once on a read', () async {
      var calls = 0;
      final api = _client((_) async {
        if (++calls == 1) throw http.ClientException('Connection closed');
        return _json({'ok': true}, 200);
      });
      expect(await api.send('GET', '/v1/me'), {'ok': true});
      expect(calls, 2);
    });

    test('a read that fails twice says unavailable, after one retry', () async {
      var calls = 0;
      final api = _client((_) async {
        calls++;
        throw const SocketException('down');
      });
      await expectLater(
        api.send('GET', '/v1/me'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
      expect(calls, 2);
    });

    test('a write is never sent twice by the client itself', () async {
      var calls = 0;
      final api = _client((_) async {
        calls++;
        throw http.ClientException('Connection closed');
      });
      await expectLater(
        api.post('/v1/teams', {}),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
      expect(calls, 1, reason: 'the offline queue retries writes safely');
    });

    test(
      'a DELETE resent after a dropped connection treats 404 as done',
      () async {
        var calls = 0;
        final api = _client((_) async {
          if (++calls == 1) throw http.ClientException('Connection closed');
          return _json({
            'error': {'code': 'not_found', 'message': 'Gone.'},
          }, 404);
        });
        expect(await api.delete('/v1/teams/t1/roster/p1'), isEmpty);
        expect(calls, 2);
      },
    );

    test('a 404 on a DELETE that was not resent is still an error', () async {
      final api = _client(
        (_) async => _json({
          'error': {'code': 'not_found', 'message': 'Gone.'},
        }, 404),
      );
      await expectLater(
        api.delete('/v1/teams/t1/roster/p1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_found')),
      );
    });

    test('a 404 on a resent PUT or GET is still an error', () async {
      for (final method in ['PUT', 'GET']) {
        var calls = 0;
        final api = _client((_) async {
          if (++calls == 1) throw http.ClientException('Connection closed');
          return _json({
            'error': {'code': 'not_found', 'message': 'Gone.'},
          }, 404);
        });
        await expectLater(
          api.send(method, '/v1/teams/t1'),
          throwsA(
            isA<ApiException>().having((e) => e.code, 'code', 'not_found'),
          ),
        );
        expect(calls, 2);
      }
    });

    test('a payment route is never resent', () async {
      for (final call in <(String, String)>[
        ('PUT', '/v1/tournaments/t1/payments/u2'),
        ('DELETE', '/v1/tournaments/t1/payments/u2'),
        ('GET', '/v1/payments/fees'),
        ('PUT', '/v1/tournaments/t1/pay/offline'),
        ('GET', '/v1/teams/t1/checkout'),
        ('DELETE', '/v1/tournaments/t1/checkout/c1'),
        ('GET', '/v1/me/earnings'),
        ('PUT', '/v1/teams/t1/earnings/e1'),
      ]) {
        var calls = 0;
        final api = _client((_) async {
          calls++;
          throw http.ClientException('Connection closed');
        });
        await expectLater(
          api.send(call.$1, call.$2),
          throwsA(
            isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
          ),
          reason: '$call',
        );
        expect(calls, 1, reason: '$call');
      }
    });

    test('needs someone signed in', () async {
      var called = false;
      final api = _client((_) async {
        called = true;
        return _json({}, 200);
      }, auth: MockFirebaseAuth());
      await expectLater(
        api.post('/v1/teams', {}),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'unauthenticated'),
        ),
      );
      expect(called, isFalse);
    });
  });

  group('TeamRepositoryFirebase.createTeam', () {
    const owner = AppUser(uid: 'u1', displayName: 'Pat');
    const team = NewTeam(
      name: 'The Haze',
      division: Division.open,
      level: CompetitionLevel.league,
      leagueId: 'l1',
    );

    late FakeFirebaseFirestore db;
    late List<Map<String, Object?>> bodies;
    late ApiClient api;

    setUp(() {
      db = FakeFirebaseFirestore();
      bodies = [];
      api = _client((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, Object?>);
        return _json({'id': 'fromApi'}, 201);
      });
    });

    TeamRepositoryFirebase repo({ApiClient? api, FeatureFlags? flags}) =>
        TeamRepositoryFirebase(
          attachments: AttachmentStorage(),
          firestore: db,
          api: api,
          flags: flags,
        );

    test('goes through the API when there is one', () async {
      final made = await repo(api: api).createTeam(team, owner);

      expect(made, isA<Ok<String>>().having((r) => r.value, 'id', 'fromApi'));
      expect(bodies, [
        {
          'name': 'The Haze',
          'division': 'open',
          'level': 'league',
          'city': '',
          'kind': 'team',
          'description': '',
          'requiresApproval': false,
          'location': null,
          'leagueId': 'l1',
        },
      ]);
      // The API writes Firestore, not the app.
      expect((await db.collection('teams').get()).docs, isEmpty);
    });

    test('writes Firestore itself when use_api_teams is off', () async {
      final made = await repo(
        api: api,
        flags: FeatureFlags.fixed({'use_api_teams': false}),
      ).createTeam(team, owner);

      expect(bodies, isEmpty);
      final id = (made as Ok<String>).value;
      final doc = await db.doc('teams/$id').get();
      expect(doc.data(), containsPair('ownerId', 'u1'));
      expect((await db.doc('teamDirectory/$id').get()).exists, isTrue);
    });

    test('writes Firestore itself in builds without an API', () async {
      final made = await repo().createTeam(team, owner);
      expect(made, isA<Ok<String>>());
      expect((await db.collection('teams').get()).docs, hasLength(1));
    });

    test("passes the API's refusal on", () async {
      final refusing = _client(
        (_) async => _json({
          'error': {
            'code': 'already_exists',
            'message': 'There\'s already a Open team called "Haze".',
          },
        }, 409),
      );
      final made = await repo(api: refusing).createTeam(team, owner);
      expect(
        made,
        isA<Error<String>>().having(
          (r) => r.error.toString(),
          'message',
          'There\'s already a Open team called "Haze".',
        ),
      );
    });
  });
}
