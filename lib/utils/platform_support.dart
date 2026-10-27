import 'package:flutter/foundation.dart';

/// Which sign-in providers work on the current platform.
///
/// Windows desktop has no Google/Apple sign-in plugin, so only
/// email/password is offered there.
abstract final class PlatformSupport {
  static bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get googleSignIn => !_isWindows;

  static bool get appleSignIn => !_isWindows;

  /// Native Google sign-in via the google_sign_in plugin (vs. web popup).
  static bool get nativeGoogleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
}
