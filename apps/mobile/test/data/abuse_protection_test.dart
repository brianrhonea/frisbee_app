import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/api_search.dart';
import 'package:frisbee_app/data/services/callable_client.dart';
import 'package:frisbee_app/data/services/feature_flags.dart';
import 'package:frisbee_app/data/services/firestore_utils.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('muteAware', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());

    Future<void> denied() =>
        Future.error(FirebaseException(plugin: 'x', code: 'permission-denied'));

    test('explains a denial while the user is muted', () async {
      await db.doc('limits/u1').set({
        'mutedUntil': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 7)),
        ),
      });
      await expectLater(
        muteAware(db, 'u1', denied),
        throwsA(
          isA<RateLimitedException>().having(
            (e) => e.toString(),
            'message',
            contains('7 minutes'),
          ),
        ),
      );
    });

    test('passes other denials and results through', () async {
      await db.doc('limits/u1').set({
        'mutedUntil': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      });
      await expectLater(
        muteAware(db, 'u1', denied),
        throwsA(isA<FirebaseException>()),
      );
      expect(await muteAware(db, 'u2', () async => 5), 5);
    });
  });

  group('ApiSearch', () {
    late Map<String, Object?> sent;
    ApiSearch search(Object? result, {bool on = true}) => ApiSearch(
      functions: CallableClient(
        projectId: 'p',
        auth: MockFirebaseAuth(signedIn: true),
        client: MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, Object?>;
          return http.Response(jsonEncode({'result': result}), 200);
        }),
      ),
      flags: FeatureFlags.fixed({'use_api_search': on}),
    );

    test('follows the use_api_search flag', () {
      expect(search(null).enabled, isTrue);
      expect(search(null, on: false).enabled, isFalse);
    });

    test('sends the kind and key and decodes timestamps', () async {
      final hits = await search({
        'results': [
          {
            'id': 'a',
            'data': {
              'name': 'Pat',
              'updatedAt': {'__ts': 1000},
              'teams': [
                {
                  'id': 't',
                  'joined': {'__ts': 2000},
                },
              ],
            },
          },
          {'id': 5, 'data': {}},
        ],
      }).search(SearchKind.players, 'pat');
      expect(sent, {
        'data': {'kind': 'players', 'key': 'pat'},
      });
      expect(hits, hasLength(1));
      expect(hits.single.id, 'a');
      expect(
        hits.single.data['updatedAt'],
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(
        (hits.single.data['teams'] as List).single['joined'],
        DateTime.fromMillisecondsSinceEpoch(2000),
      );
    });

    test('rejects a malformed answer', () {
      expect(
        search({'nope': 1}).search(SearchKind.teams, 'x'),
        throwsA(isA<CallableException>()),
      );
    });
  });
}
