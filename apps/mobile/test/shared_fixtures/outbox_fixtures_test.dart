// Shared vectors for the offline queue's rules (lib/domain/models/outbox.dart),
// checked by packages/shared/test/outbox_fixtures.test.ts against
// outbox.ts. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/outbox.dart';

import 'fixture_file.dart';

final _now = DateTime.utc(2026, 11, 16, 12);

OutboxJob _job(
  String id,
  String target, {
  int minute = 0,
  OutboxState state = OutboxState.waiting,
  DateTime? nextTryAt,
  String uid = 'me',
  int attempts = 0,
}) => OutboxJob(
  id: id,
  uid: uid,
  kind: OutboxKind.directMessage,
  createdAt: DateTime.utc(2026, 11, 16, 11, minute),
  target: target,
  label: '',
  payload: const {},
  state: state,
  attempts: attempts,
  nextTryAt: nextTryAt,
);

Map<String, Object?> _view(OutboxJob? j) => j == null
    ? {'done': true}
    : {
        'state': j.state.name,
        'attempts': j.attempts,
        'nextTryAt': j.nextTryAt?.toUtc().toIso8601String(),
        'error': j.error,
      };

void main() {
  test('error codes', () {
    const codes = [
      'unavailable',
      'network',
      'network-request-failed',
      'deadline-exceeded',
      'retry-limit-exceeded',
      'unauthenticated',
      'internal',
      'unknown',
      'aborted',
      'resource-exhausted',
      'resource_exhausted',
      'already_exists',
      'already-exists',
      'permission_denied',
      'permission-denied',
      'not_found',
      'failed_precondition',
      'invalid_argument',
    ];
    expect(outboxFailureOf('unavailable'), OutboxFailure.network);
    expect(outboxFailureOf('permission_denied'), OutboxFailure.permanent);
    checkFixture('outbox/failures.json', 'outboxFailureOf(code)', [
      for (final c in codes) {'code': c, 'failure': outboxFailureOf(c).name},
    ]);
  });

  test('backoff', () {
    expect(outboxBackoff(0), const Duration(seconds: 5));
    expect(outboxBackoff(99), const Duration(minutes: 5));
    checkFixture('outbox/backoff.json', 'outboxBackoff(attempts) in ms', [
      for (final a in [0, 1, 2, 3, 4, 5, 6, 20])
        {'attempts': a, 'ms': outboxBackoff(a).inMilliseconds},
    ]);
  });

  test('after a try', () {
    final j = _job('a', 't', attempts: 2);
    expect(afterTry(j, null, _now), isNull);
    expect(
      afterTry(j, OutboxFailure.retry, _now)!.nextTryAt,
      _now.add(const Duration(seconds: 30)),
    );
    expect(afterTry(j, OutboxFailure.network, _now)!.attempts, 2);
    checkFixture(
      'outbox/after_try.json',
      'afterTry(job attempts 2, failure, now)',
      [
        for (final f in [null, ...OutboxFailure.values])
          {
            'now': _now.toIso8601String(),
            'attempts': 2,
            'failure': f?.name,
            'message': 'Removed from the team.',
            'result': _view(
              afterTry(j, f, _now, message: 'Removed from the team.'),
            ),
          },
      ],
    );
  });

  test('which are due', () {
    final cases = <String, List<OutboxJob>>{
      'oldest first, only mine': [
        _job('b', 'x', minute: 2),
        _job('a', 'y', minute: 1),
        _job('other', 'x', uid: 'them'),
      ],
      'backoff holds its place back, not others': [
        _job(
          'a',
          'x',
          minute: 1,
          nextTryAt: _now.add(const Duration(minutes: 1)),
        ),
        _job('b', 'x', minute: 2),
        _job('c', 'y', minute: 3),
      ],
      'a due retry goes': [
        _job(
          'a',
          'x',
          minute: 1,
          nextTryAt: _now.subtract(const Duration(seconds: 1)),
        ),
        _job('b', 'x', minute: 2),
      ],
      "failed and sending don't go or hold back": [
        _job('a', 'x', minute: 1, state: OutboxState.failed),
        _job('b', 'x', minute: 2, state: OutboxState.sending),
        _job('c', 'x', minute: 3),
      ],
    };
    expect(
      dueJobs(cases['oldest first, only mine']!, 'me', _now).map((j) => j.id),
      ['a', 'b'],
    );
    checkFixture('outbox/due.json', 'dueJobs(jobs, "me", now): ids in order', [
      for (final e in cases.entries)
        {
          'name': e.key,
          'now': _now.toIso8601String(),
          'jobs': [
            for (final j in e.value)
              {
                'id': j.id,
                'uid': j.uid,
                'target': j.target,
                'createdAt': j.createdAt.toIso8601String(),
                'state': j.state.name,
                'nextTryAt': j.nextTryAt?.toIso8601String(),
              },
          ],
          'due': [for (final j in dueJobs(e.value, 'me', _now)) j.id],
        },
    ]);
  });
}
