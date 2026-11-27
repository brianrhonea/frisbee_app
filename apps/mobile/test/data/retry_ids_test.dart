import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/event/event_repository_firebase.dart';
import 'package:frisbee_app/data/repositories/team/team_repository_firebase.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/api_fakes.dart';

/// L1: retrying the same create after a lost response reuses its id, and a
/// 409 counts as done.
void main() {
  late FakeApi api;
  late FakeFirebaseFirestore db;

  setUp(() {
    api = FakeApi();
    db = FakeFirebaseFirestore();
  });

  TeamEvent event(String title) => TeamEvent(
    id: '',
    title: title,
    type: EventType.practice,
    startsAt: DateTime.utc(2027, 1, 5, 18),
  );

  test(
    'event: same request, same id; 409 is success; new request, new id',
    () async {
      final repo = EventRepositoryFirebase(firestore: db, api: api.client());
      const route = 'POST /v1/teams/t1/events';
      api.on(route, [
        apiError(503, 'unavailable', 'lost'),
        apiError(409, 'already_exists', 'That event already exists.'),
        {'id': 'x'},
      ]);
      final first = await repo.saveEvent('t1', event('A'), 'u1');
      expect(first, isA<Error<String>>());
      final second = await repo.saveEvent('t1', event('A'), 'u1');
      final ids = [for (final s in api.to(route)) (s.body as Map)['id']];
      expect(ids[0], ids[1]);
      expect((second as Ok<String>).value, ids[0]);
      await repo.saveEvent('t1', event('A'), 'u1');
      expect((api.to(route).last.body as Map)['id'], isNot(ids[0]));
    },
  );

  test('roster: a retry reuses the id and a 409 is success', () async {
    final repo = TeamRepositoryFirebase(
      attachments: AttachmentStorage(),
      firestore: db,
      api: api.client(),
    );
    const route = 'POST /v1/teams/t1/roster-players';
    api.on(route, [
      apiError(503, 'unavailable', 'lost'),
      apiError(409, 'already_exists', 'exists'),
    ]);
    const p = RosterPlayer(id: '', name: 'Sam');
    expect(await repo.savePlayer('t1', p), isA<Error<void>>());
    expect(await repo.savePlayer('t1', p), isA<Ok<void>>());
    final ids = [for (final s in api.to(route)) (s.body as Map)['id']];
    expect(ids[0], ids[1]);
  });
}
