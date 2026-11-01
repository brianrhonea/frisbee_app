import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../domain/models/follow.dart';
import '../../../domain/models/notification.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Backs a Follow button: whether the user follows [target], whether its
/// bell (post notifications) is on, and how many follow it.
class FollowViewModel extends ChangeNotifier {
  FollowViewModel({
    required this.target,
    required FollowRepository followRepository,
    required NotificationRepository notificationRepository,
    required AuthRepository authRepository,
  }) : _follows = followRepository,
       _notifications = notificationRepository,
       _auth = authRepository {
    toggleFollow = Command0<void>(_toggleFollow);
    toggleNotify = Command0<PushStatus?>(_toggleNotify);
    final uid = _uid;
    if (uid.isNotEmpty && !isSelf) {
      _subs.add(
        _follows
            .watchFollow(uid, target.key)
            .listen(
              (f) {
                _follow = f;
                _loaded = true;
                notifyListeners();
              },
              onError: (Object _) {
                _loaded = true;
                notifyListeners();
              },
            ),
      );
    }
    _subs.add(
      _follows.watchCounts(target.key).listen((c) {
        _counts = c;
        notifyListeners();
      }, onError: (Object _) {}),
    );
  }

  final FollowTarget target;
  final FollowRepository _follows;
  final NotificationRepository _notifications;
  final AuthRepository _auth;
  final List<StreamSubscription<Object?>> _subs = [];

  String get _uid => _auth.currentUser?.uid ?? '';

  /// People can't follow themselves.
  bool get isSelf => target.type == FollowType.user && target.id == _uid;

  Follow? _follow;
  bool _loaded = false;
  FollowCounts _counts = const FollowCounts();

  bool get loaded => _loaded || isSelf;
  bool get following => _follow != null;
  bool get notifying => _follow?.notify ?? false;
  int get followers => _counts.followers;

  /// Follows or unfollows.
  late final Command0<void> toggleFollow;

  /// Turns the bell on or off. Turning it on asks for push permission; the
  /// result is the device's push status then (null when turned off), so the
  /// screen can say when pushes are blocked. In-app notifications still
  /// arrive either way.
  late final Command0<PushStatus?> toggleNotify;

  Future<Result<void>> _toggleFollow() async {
    final uid = _uid;
    if (uid.isEmpty) return Result.error(Exception('Not signed in'));
    return following
        ? _follows.unfollow(uid, target.key)
        : _follows.follow(uid, target);
  }

  Future<Result<PushStatus?>> _toggleNotify() async {
    final uid = _uid;
    if (uid.isEmpty) return Result.error(Exception('Not signed in'));
    final on = !notifying;
    final Result<void> saved = following
        ? await _follows.setNotify(uid, target.key, on)
        : await _follows.follow(uid, target, notify: true);
    if (saved case Error(:final error)) return Result.error(error);
    if (!on) return const Result.ok(null);
    final push = await _notifications.enablePush(uid);
    return Result.ok(switch (push) {
      Ok(:final value) => value,
      Error() => PushStatus.unsupported,
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    toggleFollow.dispose();
    toggleNotify.dispose();
    super.dispose();
  }
}

/// Gives a page's view model a [FollowViewModel] for what the page shows,
/// made the first time it's asked for once the target is known. Without
/// the repositories (some tests) there's no Follow button.
class FollowSlot {
  FollowSlot({
    FollowRepository? followRepository,
    NotificationRepository? notificationRepository,
    AuthRepository? authRepository,
  }) : _follows = followRepository,
       _notifications = notificationRepository,
       _auth = authRepository;

  final FollowRepository? _follows;
  final NotificationRepository? _notifications;
  final AuthRepository? _auth;
  FollowViewModel? _vm;

  FollowViewModel? of(FollowTarget? target) {
    if (_vm != null) return _vm;
    final (follows, notifications, auth) = (_follows, _notifications, _auth);
    if (target == null ||
        follows == null ||
        notifications == null ||
        auth == null) {
      return null;
    }
    return _vm = FollowViewModel(
      target: target,
      followRepository: follows,
      notificationRepository: notifications,
      authRepository: auth,
    );
  }

  void dispose() => _vm?.dispose();
}
