import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../domain/models/follow.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Everything the user follows, with each one's bell.
class FollowingViewModel extends ChangeNotifier {
  FollowingViewModel({
    required FollowRepository followRepository,
    required NotificationRepository notificationRepository,
    required AuthRepository authRepository,
  }) : _follows = followRepository,
       _notifications = notificationRepository,
       _auth = authRepository {
    unfollow = Command1<void, String>((key) => _follows.unfollow(_uid, key));
    setNotify = Command1<void, (String, bool)>(_setNotify);
    final uid = _uid;
    if (uid.isEmpty) {
      _loaded = true;
      return;
    }
    _sub = _follows
        .watchFollows(uid)
        .listen(
          (f) {
            _list = f;
            _loaded = true;
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loaded = true;
            notifyListeners();
          },
        );
  }

  final FollowRepository _follows;
  final NotificationRepository _notifications;
  final AuthRepository _auth;
  StreamSubscription<List<Follow>>? _sub;

  String get _uid => _auth.currentUser?.uid ?? '';

  List<Follow> _list = const [];
  bool _loaded = false;
  Object? _error;

  bool get loaded => _loaded;
  Object? get error => _error;

  /// Grouped by kind: people, then teams and groups, then tournaments.
  List<Follow> get follows =>
      [..._list]..sort((a, b) => a.type.index.compareTo(b.type.index));

  late final Command1<void, String> unfollow;

  /// (key, on). Turning a bell on also asks for push permission.
  late final Command1<void, (String, bool)> setNotify;

  Future<Result<void>> _setNotify((String, bool) arg) async {
    final (key, on) = arg;
    final saved = await _follows.setNotify(_uid, key, on);
    if (saved is Ok && on) await _notifications.enablePush(_uid);
    return saved;
  }

  @override
  void dispose() {
    _sub?.cancel();
    unfollow.dispose();
    setNotify.dispose();
    super.dispose();
  }
}
