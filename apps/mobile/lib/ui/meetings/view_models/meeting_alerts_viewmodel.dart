import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/services/meeting_presence.dart';
import '../../../domain/models/notification.dart';

/// Pops up "meeting started" notices while the app is open, since pushes
/// don't show in the foreground on every platform (and Windows has none).
///
/// The notices come from the in-app feed, which the `meetingStarted` Cloud
/// Function writes for invitees attending, so the user's notification
/// settings apply. Notices for the room the user is already in are skipped.
class MeetingAlertsViewModel extends ChangeNotifier {
  MeetingAlertsViewModel({
    required AuthRepository authRepository,
    required NotificationRepository notificationRepository,
    required MeetingPresence presence,
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _notifications = notificationRepository,
       _presence = presence,
       _clock = clock ?? DateTime.now {
    _since = _clock();
    _auth.addListener(_onAuth);
    _onAuth();
  }

  /// Feed ids of these notices start with this; see notifications/model.ts.
  static const idPrefix = 'meetingStarted_';

  /// Notices older than this when they arrive aren't news any more.
  static const maxAge = Duration(minutes: 30);

  final AuthRepository _auth;
  final NotificationRepository _notifications;
  final MeetingPresence _presence;
  final DateTime Function() _clock;
  late DateTime _since;
  StreamSubscription<List<AppNotification>>? _feedSub;
  String? _uid;

  /// Each notice (by id and time) is shown once.
  final Set<String> _shown = {};

  AppNotification? _alert;

  /// Hands over the notice to show now, if any, so it's shown only once.
  AppNotification? takeAlert() {
    final alert = _alert;
    _alert = null;
    return alert;
  }

  void _onAuth() {
    final uid = _auth.currentUser?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _feedSub?.cancel();
    _feedSub = null;
    _alert = null;
    if (uid == null) return;
    _since = _clock();
    _feedSub = _notifications
        .watchFeed(uid)
        .listen(_onFeed, onError: (Object _) {});
  }

  void _onFeed(List<AppNotification> feed) {
    final now = _clock();
    for (final n in feed) {
      final at = n.createdAt;
      if (n.read ||
          !n.id.startsWith(idPrefix) ||
          at == null ||
          at.isBefore(_since) ||
          now.difference(at) > maxAge ||
          !_shown.add('${n.id}@${at.millisecondsSinceEpoch}')) {
        continue;
      }
      if (_inRoom(n.route)) continue;
      _alert = n;
      notifyListeners();
      return;
    }
  }

  /// Whether [route] is the meeting room the user has open.
  bool _inRoom(String? route) {
    final parts = Uri.tryParse(route ?? '')?.pathSegments ?? const [];
    return parts.length >= 3 && _presence.isIn(parts[1], parts[2]);
  }

  /// The user tapped Join on [alert]: it's read.
  void opened(AppNotification alert) {
    final uid = _uid;
    if (uid != null) unawaited(_notifications.markRead(uid, [alert.id]));
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    _feedSub?.cancel();
    super.dispose();
  }
}
