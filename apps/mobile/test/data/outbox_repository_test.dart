import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/outbox/outbox_repository.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/connectivity_service.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/outbox.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/outbox_fakes.dart';

/// The server: what's been written, and what the next sends do.
class FakeServer {
  final written = <String, Map<String, Object?>>{};
  final sendsSeen = <String>[];

  /// Each send takes the next of these (default: it goes through).
  final next = <Object Function(String id)>[];

  Future<Result<void>> send(
    OutboxJob job,
    List<NewAttachment> files,
    AppUser author,
  ) async {
    sendsSeen.add(job.id);
    final step = next.isEmpty ? null : next.removeAt(0);
    final outcome = step?.call(job.id);
    if (outcome is Exception) return Result.error(outcome);
    if (written.containsKey(job.id)) {
      return Result.error(const ApiException('already_exists', 'Exists'));
    }
    written[job.id] = {...job.payload, 'files': files.length};
    // A response lost on the way back: written, but the app hears nothing.
    if (outcome == 'lost') {
      return Result.error(const ApiException('unavailable', 'Lost'));
    }
    return const Result.ok(null);
  }

  OutboxHandler get handler => OutboxHandler(
    send: send,
    sent: (job) async => written.containsKey(job.id),
  );
}

const _me = AppUser(uid: 'me', displayName: 'Me');

void main() {
  late MemoryOutboxStore store;
  late FakeServer server;
  late ConnectivityService connectivity;
  late StreamController<bool> network;
  late FakeAuthRepository auth;
  late DateTime now;
  var probeOk = true;

  OutboxRepository make() {
    final repo = OutboxRepository(
      store: store,
      connectivity: connectivity,
      auth: auth,
      now: () => now,
    );
    repo.register(OutboxKind.directMessage, server.handler);
    repo.register(OutboxKind.comment, server.handler);
    return repo;
  }

  Future<Result<void>> submit(
    OutboxRepository repo,
    String id, {
    String target = 'c1',
    OutboxKind kind = OutboxKind.directMessage,
    List<NewAttachment> files = const [],
  }) => repo.submit(
    kind: kind,
    id: id,
    target: target,
    label: 'Message',
    payload: {'text': 'hi $id'},
    files: files,
    sendNow: () => server.send(
      OutboxJob(
        id: id,
        uid: 'me',
        kind: kind,
        createdAt: now,
        target: target,
        label: 'Message',
        payload: {'text': 'hi $id'},
      ),
      files,
      _me,
    ),
  );

  Future<void> goOffline() async {
    network.add(false);
    await pumpEventQueue();
  }

  Future<void> goOnline() async {
    network.add(true);
    await pumpEventQueue();
  }

  setUp(() {
    store = MemoryOutboxStore();
    server = FakeServer();
    network = StreamController<bool>();
    probeOk = true;
    connectivity = ConnectivityService(
      networkChanges: network.stream,
      probe: () async => probeOk,
      probeEvery: const Duration(hours: 1),
      grace: Duration.zero,
    );
    auth = FakeAuthRepository(user: _me);
    now = DateTime.utc(2026, 11, 16, 12);
  });

  tearDown(() async {
    connectivity.dispose();
    await network.close();
  });

  test('online, it sends straight away and queues nothing', () async {
    final repo = make();
    expect(await submit(repo, 'm1'), isA<Ok<void>>());
    expect(server.written.keys, ['m1']);
    expect(repo.jobs, isEmpty);
    repo.dispose();
  });

  test('offline, it queues and sends in order once back', () async {
    final repo = make();
    await goOffline();
    final queued = <String>[];
    repo.queued.listen((j) => queued.add(j.id));
    await submit(repo, 'm1');
    await submit(repo, 'm2');
    await pumpEventQueue();
    expect(server.written, isEmpty);
    expect([for (final j in repo.jobs) j.id], ['m1', 'm2']);
    expect(queued, ['m1', 'm2']);
    expect(repo.waitingCount, 2);

    await goOnline();
    await repo.drain();
    expect(server.written.keys, ['m1', 'm2']);
    expect(repo.jobs, isEmpty);
    expect(store.saved, isEmpty);
    repo.dispose();
  });

  test(
    'one failed send queues, but the app stays online and resends',
    () async {
      final repo = make();
      server.next.add((_) => const ApiException('unavailable', 'Stale socket'));
      expect(await submit(repo, 'm1'), isA<Ok<void>>());
      expect(repo.jobs.single.id, 'm1');
      // The server answers the check: not offline, and the queue tries again
      // by itself.
      await pumpEventQueue();
      await repo.drain();
      await pumpEventQueue();
      expect(connectivity.online, isTrue);
      expect(server.written.keys, ['m1']);
      expect(repo.jobs, isEmpty);
      repo.dispose();
    },
  );

  test('a send that fails with the server down is queued, offline', () async {
    final repo = make();
    probeOk = false;
    server.next.add((_) => const ApiException('unavailable', 'No network'));
    expect(await submit(repo, 'm1'), isA<Ok<void>>());
    expect(repo.jobs.single.id, 'm1');
    await pumpEventQueue();
    expect(connectivity.online, isFalse);
    expect(connectivity.status, ConnectionStatus.serverUnreachable);
    // Offline, the next send is queued without trying.
    await submit(repo, 'm2');
    expect(server.sendsSeen, ['m1']);
    expect(repo.jobs.map((j) => j.id), ['m1', 'm2']);
    probeOk = true;

    await connectivity.check();
    await repo.drain();
    expect(server.written.keys, ['m1', 'm2']);
    repo.dispose();
  });

  test('a lost response is never posted twice', () async {
    final repo = make();
    server.next.add((_) => 'lost');
    await submit(repo, 'm1');
    // The server took it, but the app heard nothing and queued it.
    expect(server.written.keys, ['m1']);
    expect(repo.jobs.single.id, 'm1');

    await connectivity.check();
    await repo.drain();
    expect(server.written.length, 1);
    expect(repo.jobs, isEmpty);
    // The check found it there; no second send.
    expect(server.sendsSeen, ['m1']);
    repo.dispose();
  });

  test('queued items outlast the app being closed', () async {
    var repo = make();
    await goOffline();
    await submit(
      repo,
      'm1',
      files: [NewAttachment(name: 'a.png', bytes: Uint8List(3))],
    );
    repo.dispose();

    // A new start reads the saved queue and sends it, attachment and all.
    repo = make();
    await repo.loaded;
    expect(repo.jobs.single.id, 'm1');
    await goOnline();
    await repo.drain();
    expect(server.written['m1']?['files'], 1);
    expect(store.files, isEmpty);
    repo.dispose();
  });

  test('one turned down does not hold up the rest', () async {
    final repo = make();
    await goOffline();
    await submit(repo, 'm1');
    await submit(repo, 'm2');
    server.next.add(
      (_) => const ApiException('permission_denied', 'You left this chat.'),
    );
    await goOnline();
    await repo.drain();
    expect(server.written.keys, ['m2']);
    expect(repo.failedCount, 1);
    expect(repo.jobs.single.error, 'You left this chat.');

    // Discard drops it; Retry sends it again.
    await repo.retry('m1');
    expect(repo.failedCount, 0);
    expect(server.written.keys, ['m2', 'm1']);
    repo.dispose();
  });

  test('a server error waits, and holds back only its own thread', () async {
    final repo = make();
    await goOffline();
    await submit(repo, 'm1', target: 'c1');
    await submit(repo, 'm2', target: 'c1');
    await submit(repo, 'x1', target: 'other');
    server.next.add((_) => const ApiException('internal', 'Oops'));
    await goOnline();
    await repo.drain();
    // m1 waits out its backoff; m2 (same chat) waits behind it; x1 goes.
    expect(server.written.keys, ['x1']);
    expect([for (final j in repo.jobs) j.id], ['m1', 'm2']);

    now = now.add(const Duration(minutes: 1));
    await repo.drain();
    expect(server.written.keys, ['x1', 'm1', 'm2']);
    repo.dispose();
  });

  test("another account's items are not shown or sent", () async {
    final repo = make();
    await goOffline();
    await submit(repo, 'm1');
    auth.setUser(const AppUser(uid: 'someone-else'));
    expect(repo.jobs, isEmpty);
    await goOnline();
    await repo.drain();
    expect(server.written, isEmpty);

    auth.setUser(_me);
    await repo.drain();
    expect(server.written.keys, ['m1']);
    repo.dispose();
  });

  test('a send already on the server counts as sent', () async {
    final repo = make();
    server.written['m1'] = {};
    expect(await submit(repo, 'm1'), isA<Ok<void>>());
    expect(repo.jobs, isEmpty);
    repo.dispose();
  });

  test('a send turned down straight away is not queued', () async {
    final repo = make();
    server.next.add((_) => const ApiException('invalid_argument', 'Too long'));
    final r = await submit(repo, 'm1');
    expect(r, isA<Error<void>>());
    expect(repo.jobs, isEmpty);
    repo.dispose();
  });

  test('the queue has a limit', () async {
    final repo = make();
    await goOffline();
    for (var i = 0; i < OutboxLimits.maxItems; i++) {
      await submit(repo, 'm$i');
    }
    expect(await submit(repo, 'over'), isA<Error<void>>());
    expect(repo.jobs.length, OutboxLimits.maxItems);
    repo.dispose();
  });

  test('outboxFailureFor sorts errors', () {
    expect(
      outboxFailureFor(const ApiException('unavailable', '')),
      OutboxFailure.network,
    );
    expect(outboxFailureFor(TimeoutException('')), OutboxFailure.network);
    expect(
      outboxFailureFor(const ApiException('already_exists', '')),
      OutboxFailure.sent,
    );
    expect(
      outboxFailureFor(const ApiException('permission_denied', '')),
      OutboxFailure.permanent,
    );
    expect(outboxFailureFor(Exception('x')), OutboxFailure.permanent);
  });

  test(
    'ConnectivityService: no network is offline; the server decides back',
    () async {
      await goOffline();
      expect(connectivity.online, isFalse);
      probeOk = false;
      await goOnline();
      expect(connectivity.online, isFalse);
      probeOk = true;
      expect(await connectivity.check(), isTrue);
      expect(connectivity.online, isTrue);
    },
  );
}
