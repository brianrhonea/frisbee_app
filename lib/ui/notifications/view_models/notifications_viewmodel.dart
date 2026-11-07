import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../domain/models/follow.dart';
import '../../../domain/models/notification.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// The in-app notification feed, newest first. New followers can be
/// followed back from it.
class NotificationsViewModel extends ChangeNotifier {
  NotificationsViewModel({
    required NotificationRepository notificationRepository,
    required AuthRepository authRepository,
    FollowRepository? followRepository,
  }) : _repo = notificationRepository,
       _follows = followRepository,
       uid = authRepository.currentUser?.uid ?? '' {
    open = Command1<void, AppNotification>(_open);
    followBack = Command1<void, AppNotification>(_followBack);
    if (followRepository != null && uid.isNotEmpty) {
      _followsSub = followRepository.watchFollows(uid).listen((f) {
        _following = {
          for (final x in f)
            if (x.target.type == FollowType.user) x.target.targetId,
        };
        notifyListeners();
      }, onError: (Object _) {});
    }
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
  final FollowRepository? _follows;
  StreamSubscription<List<Follow>>? _followsSub;
  Set<String> _following = const {};
  final String uid;
  late final StreamSubscription<List<AppNotification>> _sub;
  List<AppNotification>? _items;
  Object? _error;

  bool get loaded => _items != null;
  List<AppNotification> get items => _items ?? const [];
  Object? get error => _error;
  int get unreadCount => items.where((n) => !n.read).length;

  /// Puts [AppNotification] away (it's been checked); the screen then
  /// follows its route.
  late final Command1<void, AppNotification> open;
  late final Command0<void> markAllRead;

  /// Follows back the new follower [AppNotification.followBack].
  late final Command1<void, AppNotification> followBack;

  /// Whether a Follow back button makes sense: following is available
  /// here, and the user doesn't follow them yet.
  bool canFollowBack(AppNotification n) =>
      _follows != null &&
      n.followBack != null &&
      n.followBack!.uid != uid &&
      !_following.contains(n.followBack!.uid);

  bool isFollowing(String otherUid) => _following.contains(otherUid);
  late final Command0<void> clearAll;

  Future<Result<void>> _open(AppNotification n) async {
    await _repo.markSeen(uid, n.id);
    return const Result.ok(null);
  }

  Future<Result<void>> _followBack(AppNotification n) async {
    final who = n.followBack;
    final follows = _follows;
    if (who == null || follows == null) {
      return Result.error(Exception("Can't follow from here"));
    }
    final result = await follows.follow(
      uid,
      FollowTarget.user(who.uid, who.name, photoUrl: who.photoUrl),
    );
    if (result is Ok && !n.read) await _repo.markRead(uid, [n.id]);
    return result;
  }

  @override
  void dispose() {
    _sub.cancel();
    _followsSub?.cancel();
    open.dispose();
    followBack.dispose();
    markAllRead.dispose();
    clearAll.dispose();
    super.dispose();
  }
}
