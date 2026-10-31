import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../domain/models/notification.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// The in-app notification feed, newest first.
class NotificationsViewModel extends ChangeNotifier {
  NotificationsViewModel({
    required NotificationRepository notificationRepository,
    required AuthRepository authRepository,
  }) : _repo = notificationRepository,
       uid = authRepository.currentUser?.uid ?? '' {
    open = Command1<void, AppNotification>(_open);
    markAllRead = Command0<void>(
      () => _repo.markRead(uid, [
        for (final n in items)
          if (!n.read) n.id,
      ]),
    );
    clearAll = Command0<void>(
      () => _repo.delete(uid, [for (final n in items) n.id]),
    );
    _sub = _repo
        .watchFeed(uid)
        .listen(
          (items) {
            _items = items;
            _error = null;
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _items ??= const [];
            notifyListeners();
          },
        );
  }

  final NotificationRepository _repo;
  final String uid;
  late final StreamSubscription<List<AppNotification>> _sub;
  List<AppNotification>? _items;
  Object? _error;

  bool get loaded => _items != null;
  List<AppNotification> get items => _items ?? const [];
  Object? get error => _error;
  int get unreadCount => items.where((n) => !n.read).length;

  /// Marks [AppNotification] read; the screen then follows its route.
  late final Command1<void, AppNotification> open;
  late final Command0<void> markAllRead;
  late final Command0<void> clearAll;

  Future<Result<void>> _open(AppNotification n) async =>
      n.read ? const Result.ok(null) : _repo.markRead(uid, [n.id]);

  @override
  void dispose() {
    _sub.cancel();
    open.dispose();
    markAllRead.dispose();
    clearAll.dispose();
    super.dispose();
  }
}
