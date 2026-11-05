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

  bool _requiresApproval = false;
  bool _requested = false;
  StreamSubscription<bool>? _requestSub;

  /// The target is a private profile: Follow sends a request instead.
  bool get requiresApproval => _requiresApproval;

  set requiresApproval(bool value) {
    if (value == _requiresApproval) return;
    _requiresApproval = value;
    _requestSub?.cancel();
    _requestSub = null;
    _requested = false;
    final uid = _uid;
    if (value && uid.isNotEmpty && !isSelf) {
      _requestSub = _follows.watchFollowRequested(uid, target.id).listen((r) {
        _requested = r;
        notifyListeners();
      }, onError: (Object _) {});
    }
    notifyListeners();
  }

  /// Asked to follow a private profile and waiting for an answer.
  bool get requested => _requested && !following;
  bool get notifying => _follow?.notify ?? false;
  int get followers => _counts.followers;

  /// Follows or unfollows.
  late final Command0<void> toggleFollow;

  /// Turns post notifications on or off. Turning it on asks for push permission; the
  /// result is the device's push status then (null when turned off), so the
  /// screen can say when pushes are blocked. In-app notifications still
  /// arrive either way.
  late final Command0<PushStatus?> toggleNotify;

  Future<Result<void>> _toggleFollow() async {
    final uid = _uid;
    if (uid.isEmpty) return Result.error(Exception('Not signed in'));
    if (following) return _follows.unfollow(uid, target.key);
    if (requiresApproval) {
      final me = _auth.currentUser;
      if (me == null) return Result.error(Exception('Not signed in'));
      return _requested
          ? _follows.cancelFollowRequest(uid, target.id)
          : _follows.requestFollow(me, target.id);
    }
    return _follows.follow(uid, target);
  }

  Future<Result<PushStatus?>> _toggleNotify() async {
    final uid = _uid;
    if (uid.isEmpty) return Result.error(Exception('Not signed in'));
    final on = !notifying;
    if (!following && requiresApproval) {
      return Result.error(
        Exception('You can turn this on once ${target.name} accepts you.'),
      );
    }
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
    _requestSub?.cancel();
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
