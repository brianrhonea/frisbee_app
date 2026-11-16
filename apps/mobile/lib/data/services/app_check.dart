import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final _log = Logger('AppCheck');

/// Firebase App Check: proves requests come from this app on a real
/// device, so Firestore, Storage and Cloud Functions can turn away scripts
/// and fake traffic once enforcement is on (firebase/docs/app-check.md).
abstract final class AppCheck {
  /// A debug token registered in the Firebase console, from
  /// `APP_CHECK_DEBUG_TOKEN` in secrets.local.json. Debug builds use it.
  static const _debugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

  static bool _active = false;

  /// Starts App Check. Call once, right after Firebase.initializeApp.
  static Future<void> activate() async {
    final token = _debugToken.isEmpty ? null : _debugToken;
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? AndroidDebugProvider(debugToken: token)
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? AppleDebugProvider(debugToken: token)
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
      _active = true;
    } on Object catch (e) {
      _log.warning('App Check unavailable: $e');
    }
  }

  /// The `X-Firebase-AppCheck` header for calls made over plain HTTPS
  /// (CallableClient and friends), or none when App Check is off or has no
  /// token yet.
  static Future<Map<String, String>> headers() async {
    if (!_active) return const {};
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      return token == null ? const {} : {'X-Firebase-AppCheck': token};
    } on Object catch (e) {
      _log.fine('No App Check token: $e');
      return const {};
    }
  }
}
