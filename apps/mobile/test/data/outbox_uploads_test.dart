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

/// The queue keeps the uploads a try made (`/v1/uploads`), so a replay after
/// "upload done, send failed" sends without uploading again.
void main() {
  late MemoryOutboxStore store;
  late ConnectivityService connectivity;
  late OutboxRepository outbox;
  var now = DateTime.utc(2026, 11, 27, 12);

  OutboxRepository make() => OutboxRepository(
    store: store,
    connectivity: connectivity,
    auth: FakeAuthRepository(user: const AppUser(uid: 'me')),
    now: () => now,
  );

  setUp(() {
    store = MemoryOutboxStore();
    connectivity = ConnectivityService(
      networkChanges: const Stream.empty(),
      probe: () async => true,
      probeEvery: const Duration(hours: 1),
      grace: Duration.zero,
    );
    outbox = make();
  });

  tearDown(() => connectivity.dispose());

  final file = NewAttachment(name: 'a.jpg', bytes: Uint8List(3));
  const up = ReadyUpload(
    id: 'up1',
    name: 'a.jpg',
    contentType: 'image/jpeg',
    size: 3,
  );

  test('uploads made before a failed send go on the queued job', () async {
    final r = await outbox.submit(
      kind: OutboxKind.userPost,
      id: 'p1',
      target: 'posts',
      label: 'Post',
      payload: {'body': 'hi'},
      files: [file],
      sendNow: () async {
        await outbox.markReady('p1', 0, up);
        return Result.error(const ApiException('unavailable', 'offline'));
      },
    );
    expect(r, isA<Ok<void>>());
    final job = outbox.jobs.single;
    expect(job.uploads.keys, [0]);
    expect(outbox.readyFor('p1')[0]?.id, 'up1');
    // It survives a restart, and new jobs say which layout they use.
    final saved = OutboxJob.fromJson(store.saved.single)!;
    expect(saved.uploads[0]?.id, 'up1');
    expect(saved.version, OutboxJob.currentVersion);
  });

  test('a send that went through leaves no uploads behind', () async {
    await outbox.submit(
      kind: OutboxKind.userPost,
      id: 'p2',
      target: 'posts',
      label: 'Post',
      payload: {'body': 'hi'},
      files: [file],
      sendNow: () async {
        await outbox.markReady('p2', 0, up);
        return const Result.ok(null);
      },
    );
    expect(outbox.jobs, isEmpty);
    expect(outbox.readyFor('p2'), isEmpty);
  });

  test('uploads noted while a queued job sends are kept if it fails', () async {
    final first = await outbox.submit(
      kind: OutboxKind.userPost,
      id: 'p3',
      target: 'posts',
      label: 'Post',
      payload: {'body': 'hi'},
      files: [file],
      sendNow: () async => Result.error(const ApiException('internal', 'down')),
    );
    expect(first, isA<Ok<void>>());
    now = now.add(const Duration(minutes: 1));
    var tries = 0;
    outbox.register(
      OutboxKind.userPost,
      OutboxHandler(
        send: (job, files, author) async {
          tries++;
          if (tries == 1) {
            // This try uploads, then the send is refused with a server error.
            await outbox.markReady(job.id, 0, up);
            return Result.error(const ApiException('internal', 'down'));
          }
          expect(job.uploads[0]?.id, 'up1');
          return const Result.ok(null);
        },
        sent: (_) async => false,
      ),
    );
    await outbox.drain();
    expect(tries, 1);
    final waiting = outbox.jobs.single;
    expect(waiting.uploads[0]?.id, 'up1');
    expect(waiting.attempts, 2);
  });

  test('a job saved before versions existed reads as version 1', () {
    final job = OutboxJob.fromJson({
      'id': 'old',
      'uid': 'me',
      'kind': 'comment',
      'payload': {'parentId': 'c0'},
    })!;
    expect(job.version, 1);
    expect(job.uploads, isEmpty);
  });
}
