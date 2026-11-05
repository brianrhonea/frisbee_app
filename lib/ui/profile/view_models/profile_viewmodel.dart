import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/profile/profile_repository.dart';
import '../../../data/repositories/theme/theme_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/follow.dart';
import '../../../domain/models/player_profile.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// The Settings pages: theme, account, password, privacy and follow
/// requests. [ProfileRepository] and [FollowRepository] are only needed for
/// the private-profile switch and follow requests.
class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    required AuthRepository authRepository,
    required ThemeRepository themeRepository,
    required NotificationRepository notificationRepository,
    required DirectMessageRepository directMessageRepository,
    ProfileRepository? profileRepository,
    FollowRepository? followRepository,
  }) : _auth = authRepository,
       _theme = themeRepository,
       _notifications = notificationRepository,
       _dms = directMessageRepository,
       _profiles = profileRepository,
       _follows = followRepository {
    setThemeMode = Command1<void, ThemeMode>(_theme.setThemeMode);
    _theme.addListener(notifyListeners);
    updateDisplayName = Command1<void, String>(_auth.updateDisplayName);
    // Stop this device's pushes first; afterwards the rules won't let us.
    signOut = Command0<void>(() async {
      await _unregister();
      return _auth.signOut();
    });
    deleteAccount = Command1<void, String?>(_deleteAccount);
    changePassword = Command1<void, (String, String)>(
      (p) => _auth.changePassword(current: p.$1, next: p.$2),
    );
    sendPasswordReset = Command0<void>(
      () => _auth.sendPasswordReset(_auth.currentUser?.email ?? ''),
    );
    _auth.addListener(notifyListeners);
    setReadReceipts = Command1<void, bool>(_setReadReceipts);
    setPrivate = Command1<void, bool>(_setPrivate);
    setVisibility = Command1<void, ProfileVisibility>(_setVisibility);
    acceptRequest = Command1<void, FollowRequest>(_accept);
    declineRequest = Command1<void, FollowRequest>(
      (r) => _withFollows((f, me) => f.declineFollowRequest(me.uid, r.uid)),
    );
    if (_auth.currentUser?.uid case final uid?) {
      _subs.add(
        _dms.watchReadReceipts(uid).listen((on) {
          _readReceipts = on;
          notifyListeners();
        }, onError: (Object _) {}),
      );
      if (_profiles case final profiles?) {
        _subs.add(
          profiles.watchProfile(uid).listen((p) {
            _isPrivate = p?.isPrivate ?? false;
            _visibility = p?.details.visibility ?? const ProfileVisibility();
            notifyListeners();
          }, onError: (Object _) {}),
        );
      }
      if (_follows case final follows?) {
        _subs.add(
          follows.watchFollowRequests(uid).listen((r) {
            _requests = r;
            notifyListeners();
          }, onError: (Object _) {}),
        );
      }
    }
  }

  final ProfileRepository? _profiles;
  final FollowRepository? _follows;
  final List<StreamSubscription<Object?>> _subs = [];

  bool? _isPrivate;
  List<FollowRequest> _requests = const [];

  /// Whether only accepted followers see the profile beyond the name,
  /// username and photo; null until known.
  bool? get isPrivate => _isPrivate;

  late final Command1<void, bool> setPrivate;

  ProfileVisibility? _visibility;

  /// Which of stats, recent games and teams others see; null until known.
  ProfileVisibility? get visibility => _visibility;

  late final Command1<void, ProfileVisibility> setVisibility;

  Future<Result<void>> _setVisibility(ProfileVisibility v) async {
    final me = _auth.currentUser;
    final profiles = _profiles;
    if (me == null || profiles == null) {
      return Result.error(Exception('Not signed in'));
    }
    final before = _visibility;
    _visibility = v;
    notifyListeners();
    final result = await profiles.saveVisibility(me, v);
    if (result is Error) {
      _visibility = before;
      notifyListeners();
    }
    return result;
  }

  /// People asking to follow the user, oldest first.
  List<FollowRequest> get followRequests => _requests;

  late final Command1<void, FollowRequest> acceptRequest;
  late final Command1<void, FollowRequest> declineRequest;

  Future<Result<void>> _setPrivate(bool on) async {
    final me = _auth.currentUser;
    final profiles = _profiles;
    if (me == null || profiles == null) {
      return Result.error(Exception('Not signed in'));
    }
    final before = _isPrivate;
    _isPrivate = on;
    notifyListeners();
    final result = await profiles.setPrivate(me, on);
    if (result is Error) {
      _isPrivate = before;
      notifyListeners();
    }
    return result;
  }

  Future<Result<void>> _accept(FollowRequest r) =>
      _withFollows((f, me) => f.acceptFollowRequest(me, r));

  Future<Result<void>> _withFollows(
    Future<Result<void>> Function(FollowRepository, AppUser) run,
  ) async {
    final me = _auth.currentUser;
    final follows = _follows;
    if (me == null || follows == null) {
      return Result.error(Exception('Not signed in'));
    }
    return run(follows, me);
  }

  final DirectMessageRepository _dms;
  bool _readReceipts = true;

  /// Whether people see when the user has read their direct messages
  /// (and the user sees theirs).
  bool get readReceipts => _readReceipts;

  late final Command1<void, bool> setReadReceipts;

  Future<Result<void>> _setReadReceipts(bool on) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Result.error(Exception('Not signed in'));
    _readReceipts = on;
    notifyListeners();
    return _dms.setReadReceipts(uid, on: on);
  }

  final AuthRepository _auth;
  final ThemeRepository _theme;
  final NotificationRepository _notifications;

  Future<void> _unregister() async {
    if (_auth.currentUser?.uid case final uid?) {
      await _notifications.unregisterDevice(uid);
    }
  }

  /// Confirms it's the user (with [password] if they sign in with one),
  /// then deletes their account and everything they created.
  Future<Result<void>> _deleteAccount(String? password) async {
    final confirmed = await _auth.reauthenticate(password: password);
    if (confirmed is Error<void>) return confirmed;
    await _unregister();
    return _auth.deleteAccount();
  }

  /// How the user confirms it's them before deleting their account.
  SignInMethod? get reauthMethod => _auth.reauthMethod;

  /// Light, dark, or following the device.
  ThemeMode get themeMode => _theme.themeMode;

  late final Command1<void, ThemeMode> setThemeMode;

  AppUser? get user => _auth.currentUser;

  late final Command1<void, String> updateDisplayName;
  late final Command0<void> signOut;

  /// Takes the user's password, or null for Google and Apple accounts.
  late final Command1<void, String?> deleteAccount;

  /// Whether the account has a password to change (not Google or Apple
  /// only).
  bool get hasPassword => reauthMethod == SignInMethod.password;

  /// (current, new).
  late final Command1<void, (String, String)> changePassword;

  /// Emails a reset link, for when the current password is forgotten.
  late final Command0<void> sendPasswordReset;

  @override
  void dispose() {
    _auth.removeListener(notifyListeners);
    _theme.removeListener(notifyListeners);
    setThemeMode.dispose();
    setReadReceipts.dispose();
    setPrivate.dispose();
    setVisibility.dispose();
    acceptRequest.dispose();
    declineRequest.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
