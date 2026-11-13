import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/shared_streams.dart';

void main() {
  late int opened;
  late int cancelled;
  late StreamController<int> upstream;

  Stream<int> open() {
    opened++;
    upstream = StreamController<int>(onCancel: () => cancelled++);
    return upstream.stream;
  }

  setUp(() {
    opened = 0;
    cancelled = 0;
  });

  test('subscribers to one key share one upstream listener', () async {
    final shared = SharedStreams(grace: Duration.zero);
    final a = <int>[], b = <int>[];
    final sa = shared.get('k', open).listen(a.add);
    final sb = shared.get('k', open).listen(b.add);
    await pumpEventQueue();
    upstream.add(1);
    await pumpEventQueue();
    expect(opened, 1);
    expect(a, [1]);
    expect(b, [1]);
    await sa.cancel();
    await sb.cancel();
    expect(shared.openCount, 0);
  });

  test('late subscribers get the latest value at once', () async {
    final shared = SharedStreams(grace: Duration.zero);
    final first = shared.get('k', open).listen((_) {});
    await pumpEventQueue();
    upstream
      ..add(1)
      ..add(2);
    await pumpEventQueue();
    expect(await shared.get('k', open).first, 2);
    expect(opened, 1);
    await first.cancel();
  });

  test('stays open for the grace period, then closes', () async {
    final shared = SharedStreams(grace: const Duration(milliseconds: 100));
    final sub = shared.get('k', open).listen((_) {});
    await pumpEventQueue();
    await sub.cancel();
    expect(shared.openCount, 1);

    // Coming back within the grace period reuses the listener.
    final again = shared.get('k', open).listen((_) {});
    await pumpEventQueue();
    expect(opened, 1);
    await again.cancel();

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(shared.openCount, 0);
    expect(cancelled, 1);
    shared.get('k', open).listen((_) {});
    await pumpEventQueue();
    expect(opened, 2);
    shared.clear();
  });

  test('different keys get their own listeners', () async {
    final shared = SharedStreams(grace: Duration.zero);
    final a = shared.get('a', open).listen((_) {});
    final b = shared.get('b', open).listen((_) {});
    await pumpEventQueue();
    expect(opened, 2);
    await a.cancel();
    await b.cancel();
  });

  test('an error reaches subscribers and the next one reopens', () async {
    final shared = SharedStreams();
    final errors = <Object>[];
    var done = false;
    shared
        .get('k', open)
        .listen((_) {}, onError: errors.add, onDone: () => done = true);
    await pumpEventQueue();
    upstream.addError('permission-denied');
    await pumpEventQueue();
    expect(errors, ['permission-denied']);
    expect(done, isTrue);
    expect(shared.openCount, 0);

    shared.get('k', open).listen((_) {});
    await pumpEventQueue();
    expect(opened, 2);
    shared.clear();
  });

  test('clear closes everything, e.g. on sign-out', () async {
    final shared = SharedStreams();
    var done = false;
    shared.get('k', open).listen((_) {}, onDone: () => done = true);
    await pumpEventQueue();
    shared.clear();
    await pumpEventQueue();
    expect(done, isTrue);
    expect(cancelled, 1);
    expect(shared.openCount, 0);
  });
}
