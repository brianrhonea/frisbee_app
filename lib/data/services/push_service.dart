import 'dart:async';

import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../domain/models/notification.dart';

/// Firebase Cloud Messaging on Android, iOS and macOS. FCM has no Windows
/// plugin, so there every call is a no-op and [isSupported] is false.
///
/// Devices are addressed by their Firebase Installation ID (FID), which
/// Cloud Functions send to directly.
class PushService {
  PushService({
    FirebaseMessaging? messaging,
    FirebaseInstallations? installations,
  }) : _messaging = messaging,
       _installations = installations;

  final FirebaseMessaging? _messaging;
  final FirebaseInstallations? _installations;
  final _log = Logger('PushService');

  FirebaseMessaging get _fcm => _messaging ?? FirebaseMessaging.instance;

  bool get isSupported => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => true,
    _ => false,
  };

  String get platform => defaultTargetPlatform.name;

  Future<PushStatus> status() async {
    if (!isSupported) return PushStatus.unsupported;
    return _status(await _fcm.getNotificationSettings());
  }

  /// Shows the system prompt the first time; later calls just report.
  Future<PushStatus> requestPermission() async {
    if (!isSupported) return PushStatus.unsupported;
    return _status(await _fcm.requestPermission());
  }

  /// While the app is open, iOS and macOS show no banner or sound: the app
  /// shows its own small bubble from the feed instead. (Android never shows
  /// one in the foreground.)
  Future<void> _quietInForeground() =>
      _fcm.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );

  static PushStatus _status(NotificationSettings s) =>
      switch (s.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushStatus.enabled,
        AuthorizationStatus.denied ||
        AuthorizationStatus.deniedPermanently => PushStatus.denied,
        AuthorizationStatus.notDetermined => PushStatus.notDetermined,
      };

  /// Registers with FCM and returns this device's FID (the Firebase
  /// Installation ID Cloud Functions send to), or null where push isn't
  /// supported. Throws a [PushRegistrationException] saying what went
  /// wrong, so it can be shown and fixed rather than failing silently.
  Future<String?> register() async {
    if (!isSupported) return null;
    await _quietInForeground();
    if (defaultTargetPlatform case TargetPlatform.iOS || TargetPlatform.macOS) {
      await _awaitApnsToken();
    }
    try {
      await _fcm.register();
    } on Exception catch (e) {
      throw PushRegistrationException(
        "Firebase couldn't register this device for notifications ($e). "
        'On iPhone, invalid-request means the app build is missing '
        'FirebaseMessagingInstallationIdEnabled in Info.plist; other '
        'errors can mean the Firebase project has no APNs key (Project '
        'settings → Cloud Messaging).',
      );
    }
    // The FID is the installation ID. Read it directly: on iOS, FCM may
    // have registered at launch, before anything listened to
    // onRegistered, and it doesn't always announce it again.
    try {
      return await _installationId();
    } on Exception catch (e) {
      throw PushRegistrationException(
        "Couldn't read this device's Firebase installation ID ($e).",
      );
    }
  }

  Future<String> _installationId() =>
      (_installations ?? FirebaseInstallations.instance).getId();

  /// iOS needs an APNs token before FCM can register. It usually arrives
  /// within a second of asking; none after 15 seconds means the build
  /// can't receive push at all (its provisioning profile or entitlements
  /// lack Push Notifications).
  Future<void> _awaitApnsToken() async {
    for (var i = 0; i < 15; i++) {
      try {
        if (await _fcm.getAPNSToken() != null) return;
      } on Exception catch (e) {
        _log.fine('APNs token not ready', e);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw const PushRegistrationException(
      "iOS didn't give this device a push token (APNs). The app build "
      'needs the Push Notifications capability in its provisioning '
      'profile.',
    );
  }

  /// New FIDs after the first, e.g. when the installation is rotated.
  Stream<String> get registrations =>
      isSupported ? _fcm.onRegistered : const Stream.empty();

  Future<void> unregister() async {
    if (isSupported) await _fcm.unregister();
  }

  /// Routes of notifications the user tapped: the one that launched the
  /// app, then any tapped while it runs in the background.
  Stream<String> get openedRoutes async* {
    if (!isSupported) return;
    final initial = await _fcm.getInitialMessage();
    if (_route(initial) case final r?) yield r;
    yield* FirebaseMessaging.onMessageOpenedApp
        .map(_route)
        .where((r) => r != null)
        .cast<String>();
  }

  static String? _route(RemoteMessage? m) => switch (m?.data['route']) {
    final String r when r.startsWith('/') => r,
    _ => null,
  };
}

/// Why this device couldn't be registered for push, in words the user
/// (or whoever set up the Firebase project) can act on.
class PushRegistrationException implements Exception {
  const PushRegistrationException(this.message);

  final String message;

  @override
  String toString() => message;
}
