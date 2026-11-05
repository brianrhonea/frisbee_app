import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/theme/theme_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    required AuthRepository authRepository,
    required ThemeRepository themeRepository,
    required NotificationRepository notificationRepository,
    required DirectMessageRepository directMessageRepository,
  }) : _auth = authRepository,
       _theme = themeRepository,
       _notifications = notificationRepository,
       _dms = directMessageRepository {
    setThemeMode = Command1<void, ThemeMode>(_theme.setThemeMode);
    _theme.addListener(notifyListeners);
    updateDisplayName = Command1<void, String>(_auth.updateDisplayName);
    // Stop this device's pushes first; afterwards the rules won't let us.
    signOut = Command0<void>(() async {
      await _unregister();
      return _auth.signOut();
    });
    deleteAccount = Command1<void, String?>(_deleteAccount);
    _auth.addListener(notifyListeners);
    setReadReceipts = Command1<void, bool>(_setReadReceipts);
    if (_auth.currentUser?.uid case final uid?) {
      _receiptsSub = _dms.watchReadReceipts(uid).listen((on) {
        _readReceipts = on;
        notifyListeners();
      }, onError: (Object _) {});
    }
  }

  final DirectMessageRepository _dms;
  StreamSubscription<bool>? _receiptsSub;
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

  @override
  void dispose() {
    _auth.removeListener(notifyListeners);
    _theme.removeListener(notifyListeners);
    setThemeMode.dispose();
    setReadReceipts.dispose();
    _receiptsSub?.cancel();
    super.dispose();
  }
}
