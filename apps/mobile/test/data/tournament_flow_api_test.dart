import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/hosted_tournament/hosted_tournament_repository_firebase.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/feature_flags.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The respond flow and the run sheet's writes: the paths and bodies the
/// API takes (entryRequestSchema, entryRosterRequestSchema,
/// seedsRequestSchema, publishAllRequestSchema), and the Firestore path
/// while `use_api_tournaments` is off.
void main() {
  late FakeFirebaseFirestore db;
  late List<Map<String, Object?>> sent;
  late http.Response Function() answer;

  HostedTournamentRepositoryFirebase repo({
    bool api = true,
    bool flag = true,
  }) => HostedTournamentRepositoryFirebase(
    firestore: db,
    flags: FeatureFlags.fixed({'use_api_tournaments': flag}),
    api: api
        ? ApiClient(
            baseUrl: Uri.parse('https://api.test'),
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'cap'),
            ),
            client: MockClient((req) async {
              sent.add({
                'method': req.method,
                'path': req.url.path,
                if (req.body.isNotEmpty) 'body': jsonDecode(req.body),
              });
              return answer();
            }),
          )
        : null,
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    sent = [];
    answer = () => http.Response('', 204);
  });

  test(
    'respond, roster, decline, seeds and publish all call the API',
    () async {
      final r = repo();
      answer = () => http.Response(jsonEncode({'status': 'waitlisted'}), 200);
      final status = await r.respond(
        'x',
        't1',
        divisionId: 'd1',
        captainIds: ['cap'],
      );
      expect((status as Ok<EntryStatus>).value, EntryStatus.waitlisted);
      answer = () => http.Response('', 204);
      expect(await r.saveRoster('x', 't1', ['p1', 'p2']), isA<Ok<void>>());
      expect(await r.declineInvite('x', 't1'), isA<Ok<void>>());
      expect(await r.saveSeeds('x', 'd1', ['a', 'b']), isA<Ok<void>>());
      expect(
        await r.saveSeeds('x', 'd1', ['a', 'b'], confirm: true),
        isA<Ok<void>>(),
      );
      const game = GroupGame(
        id: 'g1',
        order: 0,
        stage: GameStage.pool,
        round: 1,
        label: 'Round 1',
        teamA: 'a',
        teamB: 'b',
      );
      expect(
        await r.publishAll('x', {
          'd1': [game],
        }),
        isA<Ok<void>>(),
      );
      expect(sent.map((s) => '${s['method']} ${s['path']}'), [
        'PUT /v1/tournaments/x/entries/t1',
        'PUT /v1/tournaments/x/entries/t1/roster',
        'PUT /v1/tournaments/x/entries/t1/status',
        'PUT /v1/tournaments/x/divisions/d1/seeds',
        'PUT /v1/tournaments/x/divisions/d1/seeds',
        'PUT /v1/tournaments/x/schedule',
      ]);
      expect(sent[0]['body'], {
        'divisionId': 'd1',
        'captainIds': ['cap'],
      });
      expect(sent[1]['body'], {
        'playerIds': ['p1', 'p2'],
      });
      expect(sent[2]['body'], {'status': 'withdrawn', 'reason': 'declined'});
      expect(sent[3]['body'], {
        'seeds': ['a', 'b'],
      });
      expect(sent[4]['body'], {
        'seeds': ['a', 'b'],
        'confirm': true,
      });
      final divisions = (sent[5]['body'] as Map)['divisions'] as List;
      expect(divisions.single['divisionId'], 'd1');
      expect((divisions.single['games'] as List).single['id'], 'g1');
    },
  );

  test(
    'with the flag off, seeds, answers and declines write Firestore',
    () async {
      final r = repo(flag: false);
      await db.doc('tournaments/x/divisions/d1').set({
        'seeds': ['b', 'a'],
        'seedsConfirmedAt': DateTime(2026, 11, 20),
      });
      await db.doc('tournaments/x/entries/t1').set({
        'teamName': 'Northside',
        'divisionId': 'd1',
        'status': 'invited',
        'captainIds': <String>[],
      });
      expect(await r.saveSeeds('x', 'd1', ['a', 'b']), isA<Ok<void>>());
      final d = (await db.doc('tournaments/x/divisions/d1').get()).data()!;
      expect(d['seeds'], ['a', 'b']);
      expect(d['seedsConfirmedAt'], isNull);

      final status = await r.respond(
        'x',
        't1',
        divisionId: 'd1',
        captainIds: ['cap'],
      );
      expect((status as Ok<EntryStatus>).value, EntryStatus.applied);
      expect(
        (await db.doc('tournaments/x/entries/t1').get()).data()!['status'],
        'applied',
      );

      expect(await r.declineInvite('x', 't1'), isA<Ok<void>>());
      final e = (await db.doc('tournaments/x/entries/t1').get()).data()!;
      expect(e['status'], 'withdrawn');
      expect(e['reason'], 'declined');
      expect(sent, isEmpty);
    },
  );
}
