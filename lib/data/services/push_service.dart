import 'dart:async';

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
  PushService({FirebaseMessaging? messaging}) : _messaging = messaging;

  final FirebaseMessaging? _messaging;
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
    final status = _status(await _fcm.requestPermission());
    if (status == PushStatus.enabled) {
      // Banners while the app is open (iOS and macOS; Android shows none).
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    return status;
  }

  static PushStatus _status(NotificationSettings s) =>
      switch (s.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushStatus.enabled,
        AuthorizationStatus.denied ||
        AuthorizationStatus.deniedPermanently => PushStatus.denied,
        AuthorizationStatus.notDetermined => PushStatus.notDetermined,
      };

  /// Registers with FCM and returns this device's FID, or null if
  /// registration didn't finish.
  Future<String?> register() async {
    if (!isSupported) return null;
    try {
      final fid = _fcm.onRegistered.first.timeout(const Duration(seconds: 30));
      await _fcm.register();
      return await fid;
    } on Exception catch (e) {
      _log.warning('FCM registration failed', e);
      return null;
    }
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
