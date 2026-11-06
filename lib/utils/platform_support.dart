import 'package:flutter/foundation.dart';

import '../data/services/google_desktop_oauth.dart';

/// Which sign-in providers work on the current platform.
///
/// Windows desktop has no Google/Apple sign-in plugin. Google sign-in there
/// goes through the browser ([GoogleDesktopOAuth]) and is shown only once its
/// OAuth client is configured; Apple sign-in is not offered.
///
/// On the web [defaultTargetPlatform] is the visitor's OS, so every check
/// rules out [kIsWeb] first.
abstract final class PlatformSupport {
  static bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// The website (lib/main_web.dart).
  static bool get web => kIsWeb;

  static bool get googleSignIn =>
      kIsWeb || !_isWindows || GoogleDesktopOAuth.isConfigured;

  /// Not on the web yet: it needs an Apple Services ID for the site.
  static bool get appleSignIn => !kIsWeb && !_isWindows;

  /// Google sign-in via the system browser and a loopback redirect.
  static bool get desktopGoogleSignIn => _isWindows;

  /// Google sign-in in a Firebase Auth popup.
  static bool get webGoogleSignIn => kIsWeb;

  /// Recording runs and rides with GPS: phones only.
  static bool get recordWorkouts =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Native Google sign-in via the google_sign_in plugin.
  static bool get nativeGoogleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
}
