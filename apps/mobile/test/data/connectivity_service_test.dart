// REL1: the "You're offline" banner must not show from one failed request.
// Offline is no network, or a server that stays unreachable after a
// confirming re-check; the app start and a resume get a grace period.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/connectivity_service.dart';

void main() {
  late StreamController<bool> network;
  late List<bool> answers;
  late int asked;
  var alwaysDown = false;
  final made = <ConnectivityService>[];

  /// A test that disposes what it made before the timer check.
  void tw(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (t) async {
        await body(t);
        for (final c in made) {
          c.dispose();
        }
        made.clear();
      });

  /// The probe: each answer from [answers] in turn, then [alwaysDown].
  Future<bool> probe() async {
    asked++;
    if (answers.isNotEmpty) return answers.removeAt(0);
    return !alwaysDown;
  }

  ConnectivityService make({Duration grace = Duration.zero, bool? resume}) {
    final c = ConnectivityService(
      networkChanges: network.stream,
      probe: probe,
      grace: grace,
      probeEvery: const Duration(seconds: 15),
      networkNow: resume == null ? null : () async => resume,
    );
    made.add(c);
    return c;
  }

  setUp(() {
    network = StreamController<bool>();
    answers = [];
    asked = 0;
    alwaysDown = false;
  });

  tearDown(() => network.close());

  tw('one failed request does not mark the app offline', (t) async {
    final c = make();
    answers = [false, true];
    c.reportFailure();
    await t.pump();
    // The first check failed; the re-check found the server fine.
    expect(asked, 2);
    expect(c.online, isTrue);
    expect(c.status, ConnectionStatus.online);
    expect(c.recoveries, 1, reason: 'the outbox is told to try again');
  });

  tw('a failure with a healthy server never flips the state', (t) async {
    final c = make();
    var changes = 0;
    c.addListener(() => changes++);
    c.reportFailure();
    await t.pump();
    expect(c.online, isTrue);
    expect(asked, 1);
    // Only the recovery nudge, never an offline state in between.
    expect(c.status, ConnectionStatus.online);
    expect(changes, 1);
  });

  tw('a confirmed failure shows the server unreachable', (t) async {
    final c = make();
    alwaysDown = true;
    c.reportFailure();
    await t.pump();
    expect(asked, 2, reason: 'asked, then re-checked');
    expect(c.online, isFalse);
    expect(c.status, ConnectionStatus.serverUnreachable);
    expect(c.hasNetwork, isTrue);
  });

  tw('no network flips at once, without asking the server', (t) async {
    final c = make(grace: const Duration(seconds: 8));
    network.add(false);
    await t.pump();
    expect(c.status, ConnectionStatus.noNetwork);
    expect(c.hasNetwork, isFalse);
    expect(asked, 0);
  });

  tw('the network back asks the server; it decides', (t) async {
    final c = make();
    network.add(false);
    await t.pump();
    alwaysDown = true;
    network.add(true);
    await t.pump();
    expect(c.status, ConnectionStatus.serverUnreachable);
    alwaysDown = false;
    await t.pump(const Duration(seconds: 15));
    expect(c.status, ConnectionStatus.online);
  });

  tw('after the app starts, a failure waits out the grace period', (t) async {
    final c = make(grace: const Duration(seconds: 8));
    alwaysDown = true;
    c.reportFailure();
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 6));
    expect(c.online, isTrue, reason: 'still inside the grace period');
    await t.pump(const Duration(seconds: 2));
    expect(c.status, ConnectionStatus.serverUnreachable);
  });

  tw('a failure that clears within the grace period stays online', (t) async {
    final c = make(grace: const Duration(seconds: 8));
    answers = [false];
    c.reportFailure();
    await t.pump(const Duration(seconds: 9));
    expect(c.online, isTrue, reason: 'the re-check after the grace answered');
  });

  tw('resuming starts a new grace period', (t) async {
    final c = make(grace: const Duration(seconds: 8), resume: true);
    await t.pump(const Duration(seconds: 20));
    alwaysDown = true;
    // Past the start grace: a failure is confirmed straight away.
    c.reportFailure();
    await t.pump();
    expect(c.status, ConnectionStatus.serverUnreachable);

    // Back online, then the app goes to the background and returns.
    alwaysDown = false;
    await t.pump(const Duration(seconds: 15));
    expect(c.online, isTrue);
    unawaited(c.resumed());
    await t.pump();
    alwaysDown = true;
    c.reportFailure();
    await t.pump(const Duration(seconds: 7));
    expect(c.online, isTrue, reason: 'inside the grace after resuming');
    await t.pump(const Duration(seconds: 2));
    expect(c.status, ConnectionStatus.serverUnreachable);
  });

  tw('resuming reads the network again', (t) async {
    final c = make(resume: false);
    await c.resumed();
    expect(c.status, ConnectionStatus.noNetwork);
  });

  tw('the server answering again clears offline, with backoff', (t) async {
    final c = make();
    alwaysDown = true;
    c.reportFailure();
    await t.pump();
    expect(c.online, isFalse);
    final base = asked;
    // 15 s, then 30 s, then 60 s between asks.
    await t.pump(const Duration(seconds: 15));
    expect(asked, base + 1);
    await t.pump(const Duration(seconds: 15));
    expect(asked, base + 1, reason: 'the wait doubled');
    await t.pump(const Duration(seconds: 15));
    expect(asked, base + 2);

    alwaysDown = false;
    await t.pump(const Duration(seconds: 70));
    expect(c.online, isTrue);
    final settled = asked;
    await t.pump(const Duration(minutes: 5));
    expect(asked, settled, reason: 'no probing once back');
  });

  tw('something reaching the server clears an offline state', (t) async {
    final c = make();
    alwaysDown = true;
    c.reportFailure();
    await t.pump();
    expect(c.online, isFalse);
    c.reportOnline();
    expect(c.online, isTrue);
  });

  tw('without a network a failure is simply offline', (t) async {
    final c = make();
    network.add(false);
    await t.pump();
    c.reportFailure();
    expect(c.status, ConnectionStatus.noNetwork);
    expect(asked, 0);
  });
}
