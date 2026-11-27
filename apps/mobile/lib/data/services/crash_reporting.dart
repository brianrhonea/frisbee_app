import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final _log = Logger('CrashReporting');

/// What the app needs from a crash reporter. [FirebaseCrashReporter] is the
/// real one; tests pass a fake.
abstract class CrashReporter {
  /// Turns collection on or off for this launch.
  Future<void> setCollectionEnabled(bool enabled);

  /// Reports an error caught by the Flutter framework (fatal).
  Future<void> recordFlutterFatalError(FlutterErrorDetails details);

  /// Reports an error that reached the platform dispatcher.
  Future<void> recordError(Object error, StackTrace stack, {bool fatal});

  /// Crashes the app on purpose, to prove reports arrive.
  void crash();
}

class FirebaseCrashReporter implements CrashReporter {
  FirebaseCrashReporter([FirebaseCrashlytics? crashlytics])
    : _c = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _c;

  @override
  Future<void> setCollectionEnabled(bool enabled) =>
      _c.setCrashlyticsCollectionEnabled(enabled);

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) =>
      _c.recordFlutterFatalError(details);

  @override
  Future<void> recordError(
    Object error,
    StackTrace stack, {
    bool fatal = true,
  }) => _c.recordError(error, stack, fatal: fatal);

  @override
  void crash() => _c.crash();
}

/// Crash reporting (Crashlytics), started once from `main`.
abstract final class CrashReporting {
  static CrashReporter? _reporter;

  /// Whether reports are being collected.
  static bool get active => _reporter != null;

  /// Starts crash reporting with [reporter] and hooks the two places an
  /// uncaught error surfaces: [FlutterError.onError] and
  /// [PlatformDispatcher.onError]. Collection is off in debug builds
  /// ([debug]). Never throws: if the reporter can't start, the app starts
  /// without it and the error hooks stay as they were.
  static Future<void> init(
    CrashReporter Function() create, {
    required bool debug,
    FlutterExceptionHandler? previousFlutterHandler,
    required PlatformDispatcher dispatcher,
  }) async {
    try {
      final reporter = create();
      await reporter.setCollectionEnabled(!debug);
      final previous = previousFlutterHandler;
      FlutterError.onError = (details) {
        // Still prints to the console, as the default handler does.
        (previous ?? FlutterError.presentError)(details);
        reporter.recordFlutterFatalError(details).catchError((Object e) {
          _log.warning('Could not record a Flutter error: $e');
        });
      };
      dispatcher.onError = (error, stack) {
        reporter.recordError(error, stack, fatal: true).catchError((Object e) {
          _log.warning('Could not record an error: $e');
        });
        return true;
      };
      _reporter = reporter;
    } on Object catch (e) {
      _log.warning('Crash reporting unavailable: $e');
    }
  }

  /// Forgets the reporter (tests).
  @visibleForTesting
  static void reset() => _reporter = null;

  /// Crashes the app on purpose. Does nothing when reporting isn't on.
  static void sendTestCrash() => _reporter?.crash();
}
