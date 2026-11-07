import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../domain/models/notification.dart';
import '../../../utils/on_screen.dart';

/// The small bubble shown while the app is open when a notification
/// arrives: a new message, comment, follower and so on.
///
/// Driven by the in-app feed, so it works on every platform and whether or
/// not push is allowed. Repeats of the one showing (more messages in the
/// same chat) update it in place instead of stacking up, and nothing shows
/// for the page you're already on.
class InAppNoticesViewModel extends ChangeNotifier {
  InAppNoticesViewModel({
    required AuthRepository authRepository,
    required NotificationRepository notificationRepository,
    required String? Function() currentLocation,
    this.showFor = const Duration(seconds: 4),
  }) : _auth = authRepository,
       _repo = notificationRepository,
       _currentLocation = currentLocation {
    _auth.addListener(_onAuth);
    _onAuth();
  }

  final AuthRepository _auth;
  final NotificationRepository _repo;
  final String? Function() _currentLocation;

  /// How long a bubble stays up.
  final Duration showFor;

  String? _uid;
  StreamSubscription<List<AppNotification>>? _feed;
  Timer? _hide;

  /// What each entry looked like last time; null until the first list, so
  /// what was already there when the app opened isn't announced.
  Map<String, ({int count, bool read})>? _seen;

  AppNotification? _current;

  /// The bubble to show, or null.
  AppNotification? get current => _current;

  void _onAuth() {
    final uid = _auth.currentUser?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _feed?.cancel();
    _feed = null;
    _seen = null;
    dismiss();
    if (uid == null) return;
    _feed = _repo.watchFeed(uid).listen(_onFeed, onError: (_) {});
  }

  void _onFeed(List<AppNotification> feed) {
    final seen = _seen;
    _seen = {for (final n in feed) n.id: (count: n.count, read: n.read)};
    if (seen == null) return;
    // Newest first: announce the newest thing that's new.
    for (final n in feed) {
      if (n.read) continue;
      final before = seen[n.id];
      final isNew = before == null || before.read || n.count > before.count;
      if (!isNew || _isOpen(n.route) || OnScreen.isShowing(n.id)) continue;
      _show(n);
      return;
    }
    // Read elsewhere (or on this page) while it showed: take it down.
    if (_current case final c? when _seen![c.id]?.read ?? true) dismiss();
  }

  bool _isOpen(String? route) {
    final here = _currentLocation();
    if (route == null || here == null) return false;
    return Uri.parse(route).path == Uri.parse(here).path;
  }

  void _show(AppNotification n) {
    _current = n;
    _hide?.cancel();
    _hide = Timer(showFor, dismiss);
    notifyListeners();
  }

  void dismiss() {
    _hide?.cancel();
    _hide = null;
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// The bubble was tapped: where to go, after taking it down and
  /// putting the entry away.
  String? open() {
    final n = _current;
    dismiss();
    final uid = _uid;
    if (n == null || uid == null) return null;
    unawaited(_repo.markSeen(uid, n.id));
    return n.route;
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    _feed?.cancel();
    _hide?.cancel();
    super.dispose();
  }
}
