import 'package:flutter/foundation.dart';

import '../data/services/google_desktop_oauth.dart';

/// Which sign-in providers work on the current platform.
///
/// Windows desktop has no Google/Apple sign-in plugin. Google sign-in there
/// goes through the browser ([GoogleDesktopOAuth]) and is shown only once its
/// OAuth client is configured; Apple sign-in is not offered.
abstract final class PlatformSupport {
  static bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get googleSignIn =>
      !_isWindows || GoogleDesktopOAuth.isConfigured;

  static bool get appleSignIn => !_isWindows;

  /// Google sign-in via the system browser and a loopback redirect.
  static bool get desktopGoogleSignIn => _isWindows;

  /// Native Google sign-in via the google_sign_in plugin (vs. web popup).
  static bool get nativeGoogleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
}
