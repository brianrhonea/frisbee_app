import 'package:flutter/foundation.dart';

/// What works on the current platform. The app runs on Android and iOS;
/// tests may override [defaultTargetPlatform].
abstract final class PlatformSupport {
  static bool get _isPhoneOs =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Google sign-in via the google_sign_in plugin.
  static bool get googleSignIn => _isPhoneOs;

  /// Apple sign-in through Firebase Auth's provider flow.
  static bool get appleSignIn => _isPhoneOs;

  /// Recording runs and rides with GPS: phones only.
  static bool get recordWorkouts => _isPhoneOs;
}
