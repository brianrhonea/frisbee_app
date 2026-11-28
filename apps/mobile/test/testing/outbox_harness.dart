import 'package:frisbee_app/data/repositories/outbox/outbox_repository.dart';
import 'package:frisbee_app/data/services/connectivity_service.dart';

import 'fakes.dart';
import 'outbox_fakes.dart';

/// A real offline queue over in-memory storage, signed in as [testUser]:
/// what the repository tests send through, to prove "upload done, send
/// failed, then a replay".
class OutboxHarness {
  /// [saved] is what the device already holds (jobs queued by an older
  /// build, say), as the queue's JSON.
  OutboxHarness({List<Map<String, Object?>> saved = const []}) {
    store.saved = [...saved];
    connectivity = ConnectivityService(
      networkChanges: const Stream.empty(),
      probe: () async => true,
      probeEvery: const Duration(hours: 1),
      grace: Duration.zero,
    );
    outbox = OutboxRepository(
      store: store,
      connectivity: connectivity,
      auth: FakeAuthRepository(user: testUser),
      now: () => now,
    );
  }

  final store = MemoryOutboxStore();
  late final ConnectivityService connectivity;
  late final OutboxRepository outbox;

  /// The queue's clock; move it on to make a backed-off job due.
  DateTime now = DateTime.utc(2026, 11, 27, 12);

  /// Past the longest wait, so whatever backed off is due.
  void passTime() => now = now.add(const Duration(minutes: 10));

  void dispose() {
    outbox.dispose();
    connectivity.dispose();
  }
}
