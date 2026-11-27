import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/crash_reporting.dart';

class _FakeReporter implements CrashReporter {
  bool? collection;
  final flutterErrors = <FlutterErrorDetails>[];
  final errors = <(Object, bool)>[];
  int crashes = 0;
  Object? failOn;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    if (failOn != null) throw failOn!;
    collection = enabled;
  }

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async =>
      flutterErrors.add(details);

  @override
  Future<void> recordError(
    Object error,
    StackTrace stack, {
    bool fatal = true,
  }) async => errors.add((error, fatal));

  @override
  void crash() => crashes++;
}

void main() {
  late FlutterExceptionHandler? savedHandler;
  late PlatformDispatcher dispatcher;
  late ErrorCallback? savedDispatcherHandler;

  setUp(() {
    savedHandler = FlutterError.onError;
    dispatcher = PlatformDispatcher.instance;
    savedDispatcherHandler = dispatcher.onError;
  });

  tearDown(() {
    FlutterError.onError = savedHandler;
    dispatcher.onError = savedDispatcherHandler;
    CrashReporting.reset();
  });

  test('collection is off in debug builds and on in release', () async {
    final debug = _FakeReporter();
    await CrashReporting.init(() => debug, debug: true, dispatcher: dispatcher);
    expect(debug.collection, isFalse);

    final release = _FakeReporter();
    await CrashReporting.init(
      () => release,
      debug: false,
      dispatcher: dispatcher,
    );
    expect(release.collection, isTrue);
  });

  test(
    'Flutter errors are recorded as fatal and still reach the old handler',
    () async {
      final fake = _FakeReporter();
      final seen = <FlutterErrorDetails>[];
      await CrashReporting.init(
        () => fake,
        debug: false,
        previousFlutterHandler: seen.add,
        dispatcher: dispatcher,
      );
      final details = FlutterErrorDetails(exception: StateError('boom'));
      FlutterError.onError!(details);
      expect(fake.flutterErrors, [details]);
      expect(seen, [details]);
    },
  );

  test(
    'errors that reach the platform dispatcher are recorded and handled',
    () async {
      final fake = _FakeReporter();
      await CrashReporting.init(
        () => fake,
        debug: false,
        dispatcher: dispatcher,
      );
      final handled = dispatcher.onError!(
        StateError('async boom'),
        StackTrace.current,
      );
      expect(handled, isTrue, reason: 'reported, so not rethrown');
      expect(fake.errors.single.$1, isA<StateError>());
      expect(fake.errors.single.$2, isTrue);
    },
  );

  test('a reporter that fails to start never blocks the launch', () async {
    final fake = _FakeReporter()..failOn = StateError('no crashlytics');
    final before = FlutterError.onError;
    await CrashReporting.init(() => fake, debug: false, dispatcher: dispatcher);
    expect(CrashReporting.active, isFalse);
    expect(FlutterError.onError, same(before), reason: 'hooks untouched');
    CrashReporting.sendTestCrash();
    expect(fake.crashes, 0);
  });

  test('a reporter that cannot be created is survived too', () async {
    await CrashReporting.init(
      () => throw StateError('no Firebase'),
      debug: false,
      dispatcher: dispatcher,
    );
    expect(CrashReporting.active, isFalse);
  });

  test('the test crash reaches the reporter only once it is on', () async {
    final fake = _FakeReporter();
    CrashReporting.sendTestCrash();
    expect(fake.crashes, 0);
    await CrashReporting.init(() => fake, debug: false, dispatcher: dispatcher);
    CrashReporting.sendTestCrash();
    expect(fake.crashes, 1);
  });
}
