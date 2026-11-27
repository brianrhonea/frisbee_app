import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/team/team_repository_firebase.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team_page.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/api_fakes.dart';

/// Roster writes through the API (contracts/phase1-writes.md §3.6), and the
/// end of the app's legacy-status migration (D7).
void main() {
  late FakeApi api;
  late FakeFirebaseFirestore db;
  late TeamRepositoryFirebase repo;

  setUp(() {
    api = FakeApi();
    db = FakeFirebaseFirestore();
    repo = TeamRepositoryFirebase(
      attachments: AttachmentStorage(),
      firestore: db,
      api: api.client(),
    );
  });

  Object errorOf(Result<Object?> r) => (r as Error).error;

  test('a new spot: POST with a client id and the paid flag', () async {
    final r = await repo.savePlayer(
      't1',
      const RosterPlayer(
        id: '',
        name: ' Sam ',
        number: 7,
        position: PlayerPosition.handler,
        paid: true,
      ),
    );
    expect(r, isA<Ok<void>>());
    final b = api.bodyOf('POST /v1/teams/t1/roster-players');
    expect(b, {
      'id': b['id'],
      'name': 'Sam',
      'number': 7,
      'position': 'handler',
      'userId': null,
      'paid': true,
    });
    expect(b['id'], matches(RegExp(r'^[A-Za-z0-9]{1,40}$')));
  });

  test('saving a spot: PUT, with its link kept and no number', () async {
    await repo.savePlayer(
      't1',
      const RosterPlayer(id: 'p1', name: 'Pat', userId: 'u5'),
    );
    expect(api.bodyOf('PUT /v1/teams/t1/roster-players/p1'), {
      'name': 'Pat',
      'number': null,
      'position': 'hybrid',
      'userId': 'u5',
      'paid': false,
    });
  });

  test('link, unlink and delete use their routes', () async {
    await repo.linkPlayer('t1', 'p1', 'u5');
    await repo.linkPlayer('t1', 'p1', null);
    await repo.deletePlayer('t1', 'p1');
    expect(
      [for (final s in api.sent) '${s.method} ${s.path} ${s.body}'],
      [
        'PUT /v1/teams/t1/roster-players/p1/link {userId: u5}',
        'PUT /v1/teams/t1/roster-players/p1/link {userId: null}',
        'DELETE /v1/teams/t1/roster-players/p1 null',
      ],
    );
  });

  test('no direct write to the roster or its status', () async {
    await repo.savePlayer('t1', const RosterPlayer(id: '', name: 'Sam'));
    await repo.deletePlayer('t1', 'p1');
    expect((await db.collection('teams/t1/roster').get()).docs, isEmpty);
    expect((await db.collection('teams/t1/rosterStatus').get()).docs, isEmpty);
  });

  test('refused: the server message comes back', () async {
    api.on(
      'PUT /v1/teams/t1/roster-players/p1/link',
      apiError(
        403,
        'permission_denied',
        'This spot is linked to someone else.',
      ),
    );
    final r = await repo.linkPlayer('t1', 'p1', 'u1');
    expect(errorOf(r).toString(), 'This spot is linked to someone else.');
  });

  test(
    'a new spot with a member: one POST carrying userId; 412 surfaces',
    () async {
      api.on(
        'POST /v1/teams/t1/roster-players',
        apiError(
          412,
          'failed_precondition',
          'That person is already linked to another spot on this team',
        ),
      );
      final r = await repo.savePlayer(
        't1',
        const RosterPlayer(id: '', name: 'Sam', userId: 'u5'),
      );
      expect(api.bodyOf('POST /v1/teams/t1/roster-players')['userId'], 'u5');
      expect(
        errorOf(r).toString(),
        'That person is already linked to another spot on this team',
      );
    },
  );

  test('staff come from GET roster: coaches and owner, not players', () async {
    api.on('GET /v1/teams/t1/roster', {
      'kind': 'team',
      'players': [],
      'teams': [],
      'members': [
        {'uid': 'c', 'name': 'Cody', 'tier': 'coach', 'roles': []},
        {'uid': 'o', 'name': 'Olive', 'tier': 'owner', 'roles': []},
        {'uid': 'p', 'name': 'Pat', 'tier': 'player', 'roles': []},
      ],
    });
    final r = await repo.teamStaff('t1');
    expect(
      [
        for (final o in (r as Ok<List<CommunityOrganizer>>).value)
          (o.uid, o.label),
      ],
      [('o', 'Owner'), ('c', 'Coach')],
    );
  });

  test('a private group refuses its roster: no staff', () async {
    api.on(
      'GET /v1/teams/t1/roster',
      apiError(403, 'permission_denied', 'Members only.'),
    );
    expect(await repo.teamStaff('t1'), isA<Error<List<CommunityOrganizer>>>());
  });

  test('offline: a retryable error', () async {
    api.offline = true;
    final r = await repo.deletePlayer('t1', 'p1');
    expect(
      errorOf(r),
      isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
    );
  });

  test('viewing the roster no longer moves legacy status (D7)', () async {
    await db.doc('teams/t1/roster/p1').set({
      'name': 'Old',
      'position': 'hybrid',
      'paid': true,
    });
    final roster = await repo.watchRoster('t1', withStatus: true).first;
    // Still shown to an admin from the old field...
    expect(roster.single.paid, isTrue);
    // ...but nothing wrote the status or stripped the entry.
    await pumpEventQueue();
    expect((await db.doc('teams/t1/roster/p1').get()).data()?['paid'], true);
    expect((await db.collection('teams/t1/rosterStatus').get()).docs, isEmpty);
  });
}
