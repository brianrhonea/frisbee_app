import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/event/event_repository_firebase.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/api_fakes.dart';

/// Team events, RSVPs, reactions, votes and personal events through the API
/// (contracts/phase1-writes.md §3.5).
void main() {
  late FakeApi api;
  late FakeFirebaseFirestore db;
  late EventRepositoryFirebase repo;

  setUp(() {
    api = FakeApi();
    db = FakeFirebaseFirestore();
    repo = EventRepositoryFirebase(
      firestore: db,
      api: api.client(),
      timeZone: () async => 'America/Denver',
    );
  });

  Object errorOf(Result<Object?> r) => (r as Error).error;

  final start = DateTime.utc(2027, 1, 5, 18);
  final end = DateTime.utc(2027, 1, 5, 20);

  TeamEvent event({String id = ''}) => TeamEvent(
    id: id,
    title: 'Practice',
    type: EventType.practice,
    startsAt: start,
    endsAt: end,
    location: 'Field 2',
    notes: 'Bring water',
  );

  group('team events', () {
    test('create: POST with a client id, no repeat, no time zone', () async {
      final r = await repo.saveEvent('t1', event(), 'u1');
      final id = (r as Ok<String>).value;
      expect(api.bodyOf('POST /v1/teams/t1/events'), {
        'id': id,
        'title': 'Practice',
        'type': 'practice',
        'startsAt': '2027-01-05T18:00:00.000Z',
        'endsAt': '2027-01-05T20:00:00.000Z',
        'location': 'Field 2',
        'notes': 'Bring water',
        'poll': null,
        'public': false,
      });
      expect(id, matches(RegExp(r'^[A-Za-z0-9]{1,40}$')));
    });

    test('create a series: repeat and the device time zone go along', () async {
      api.on(
        'POST /v1/teams/t1/events',
        (Object? b) => {'id': '${(b as Map)['id']}_0'},
      );
      final r = await repo.saveEvent(
        't1',
        event().copyWith(isPublic: true),
        'u1',
        repeat: Repeat(
          freq: RepeatFrequency.weekly,
          until: DateTime(2027, 2, 2),
        ),
      );
      final b = api.bodyOf('POST /v1/teams/t1/events');
      expect(b['repeat'], {'freq': 'weekly', 'until': '2027-02-02'});
      expect(b['timeZone'], 'America/Denver');
      expect(b['public'], true);
      expect((r as Ok<String>).value, '${b['id']}_0');
    });

    test('a poll and an audience are in the body', () async {
      await repo.saveEvent(
        't1',
        event().copyWith(
          poll: () => const EventPoll(
            question: 'Cleats?',
            options: [
              PollOption(id: 'a', text: 'Yes'),
              PollOption(id: 'b', text: 'No'),
            ],
          ),
          audience: {'players', 'everyone'},
        ),
        'u1',
      );
      final b = api.bodyOf('POST /v1/teams/t1/events');
      expect(b['poll'], {
        'question': 'Cleats?',
        'options': [
          {'id': 'a', 'text': 'Yes'},
          {'id': 'b', 'text': 'No'},
        ],
        'multiple': false,
      });
      expect(b['audience'], ['everyone', 'players']);
    });

    test('a repeat that is too long is refused before sending', () async {
      final r = await repo.saveEvent(
        't1',
        event(),
        'u1',
        repeat: Repeat(
          freq: RepeatFrequency.daily,
          until: DateTime(2028, 6, 1),
        ),
      );
      expect(errorOf(r), isA<ApiException>());
      expect(api.sent, isEmpty);
    });

    test('edit one: PATCH without a scope or a time zone', () async {
      final r = await repo.saveEvent('t1', event(id: 'e1_2'), 'u1');
      expect((r as Ok<String>).value, 'e1_2');
      final b = api.bodyOf('PATCH /v1/teams/t1/events/e1_2');
      expect(b.containsKey('id'), isFalse);
      expect(b.containsKey('timeZone'), isFalse);
      expect(b['title'], 'Practice');
    });

    test(
      'edit this and following: ?scope=following with the time zone',
      () async {
        await repo.saveEvent(
          't1',
          event(id: 'e1_2'),
          'u1',
          scope: SeriesScope.following,
        );
        final sent = api.sent.single;
        expect(sent.path, '/v1/teams/t1/events/e1_2?scope=following');
        expect((sent.body as Map)['timeZone'], 'America/Denver');
      },
    );

    test('delete one and delete following', () async {
      await repo.deleteEvent('t1', 'e1');
      await repo.deleteEvent('t1', 'e1_2', scope: SeriesScope.following);
      expect(
        [for (final s in api.sent) '${s.method} ${s.path}'],
        [
          'DELETE /v1/teams/t1/events/e1',
          'DELETE /v1/teams/t1/events/e1_2?scope=following',
        ],
      );
    });

    test('RSVP, taking it back, reaction and votes use their routes', () async {
      await repo.setRsvp('t1', 'e1', 'u1', RsvpStatus.going);
      await repo.setRsvp('t1', 'e1', 'u1', null);
      await repo.setReaction('t1', 'e1', 'u1', Reaction.fire, on: true);
      await repo.setReaction('t1', 'e1', 'u1', Reaction.fire, on: false);
      await repo.setVotes('t1', 'e1', 'u1', ['a']);
      await repo.setVotes('t1', 'e1', 'u1', const []);
      expect(
        [for (final s in api.sent) '${s.method} ${s.path} ${s.body}'],
        [
          'PUT /v1/teams/t1/events/e1/rsvp {status: going}',
          'PUT /v1/teams/t1/events/e1/rsvp {status: null}',
          'PUT /v1/teams/t1/events/e1/reaction {reaction: fire, on: true}',
          'PUT /v1/teams/t1/events/e1/reaction {reaction: fire, on: false}',
          'PUT /v1/teams/t1/events/e1/votes {optionIds: [a]}',
          'PUT /v1/teams/t1/events/e1/votes {optionIds: []}',
        ],
      );
    });

    test('an RSVP note goes with the answer already given', () async {
      await db.doc('teams/t1/events/e1').set({
        'rsvps': {'u1': 'maybe'},
      });
      await repo.setRsvpNote('t1', 'e1', 'u1', ' Late 15 min ');
      await repo.setRsvpNote('t1', 'e1', 'u1', '');
      expect(
        [for (final s in api.sent) s.body],
        [
          {'status': 'maybe', 'note': ' Late 15 min '},
          {'status': 'maybe', 'note': null},
        ],
      );
    });

    test('a note without an answer says to answer first', () async {
      await db.doc('teams/t1/events/e1').set({'rsvps': <String, Object>{}});
      final r = await repo.setRsvpNote('t1', 'e1', 'u1', 'Late');
      expect(errorOf(r).toString(), 'Answer first, then add a note.');
      expect(api.sent, isEmpty);
    });

    test('not allowed: the server message comes back', () async {
      api.on(
        'POST /v1/teams/t1/events',
        apiError(
          403,
          'permission_denied',
          "You can't add events to this team.",
        ),
      );
      final r = await repo.saveEvent('t1', event(), 'u1');
      expect(errorOf(r).toString(), "You can't add events to this team.");
    });

    test('offline: a retryable error for every write', () async {
      api.offline = true;
      for (final r in [
        await repo.saveEvent('t1', event(), 'u1'),
        await repo.deleteEvent('t1', 'e1'),
        await repo.setRsvp('t1', 'e1', 'u1', RsvpStatus.going),
        await repo.setReaction('t1', 'e1', 'u1', Reaction.fire, on: true),
        await repo.setVotes('t1', 'e1', 'u1', ['a']),
      ]) {
        expect(
          errorOf(r),
          isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
        );
      }
    });

    test('no API in this build: no direct write', () async {
      final bare = EventRepositoryFirebase(firestore: db);
      final r = await bare.saveEvent('t1', event(), 'u1');
      expect(errorOf(r), isA<ApiException>());
      expect((await db.collection('teams/t1/events').get()).docs, isEmpty);
    });
  });

  group('personal events (My calendar)', () {
    test('create, with a repeat and the time zone', () async {
      api.on('POST /v1/calendars/u1/events', {'id': 'p1'});
      final r = await repo.saveMyEvent(
        'u1',
        event(),
        repeat: Repeat(
          freq: RepeatFrequency.daily,
          until: DateTime(2027, 1, 9),
        ),
      );
      expect((r as Ok<String>).value, 'p1');
      final posted = api.bodyOf('POST /v1/calendars/u1/events');
      expect(posted['id'], matches(RegExp(r'^[A-Za-z0-9]{1,40}$')));
      expect({...posted}..remove('id'), {
        'title': 'Practice',
        'type': 'practice',
        'startsAt': '2027-01-05T18:00:00.000Z',
        'endsAt': '2027-01-05T20:00:00.000Z',
        'location': 'Field 2',
        'notes': 'Bring water',
        'repeat': {'freq': 'daily', 'until': '2027-01-09'},
        'timeZone': 'America/Denver',
      });
    });

    test('a retry keeps the id; a 409 replay counts as sent', () async {
      api.on('POST /v1/calendars/u1/events', [
        apiError(500, 'internal', 'Boom'),
        apiError(409, 'already_exists', 'That event already exists.'),
      ]);
      final first = await repo.saveMyEvent('u1', event());
      expect(first, isA<Error<String>>());
      final second = await repo.saveMyEvent('u1', event());
      final ids = [
        for (final s in api.to('POST /v1/calendars/u1/events'))
          (s.body as Map)['id'],
      ];
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(1));
      expect((second as Ok<String>).value, ids.first);
    });

    test('edit and delete, with scope', () async {
      await repo.saveMyEvent(
        'u1',
        event(id: 'p1_1'),
        scope: SeriesScope.following,
      );
      await repo.saveMyEvent('u1', event(id: 'p2'));
      await repo.deleteMyEvent('u1', 'p1_1', scope: SeriesScope.following);
      await repo.deleteMyEvent('u1', 'p2');
      expect(
        [for (final s in api.sent) '${s.method} ${s.path}'],
        [
          'PATCH /v1/calendars/u1/events/p1_1?scope=following',
          'PATCH /v1/calendars/u1/events/p2',
          'DELETE /v1/calendars/u1/events/p1_1?scope=following',
          'DELETE /v1/calendars/u1/events/p2',
        ],
      );
      expect((api.sent[0].body as Map)['timeZone'], 'America/Denver');
      expect((api.sent[1].body as Map).containsKey('timeZone'), isFalse);
    });

    test('offline: a retryable error', () async {
      api.offline = true;
      final r = await repo.deleteMyEvent('u1', 'p1');
      expect(
        errorOf(r),
        isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
      );
    });
  });
}
