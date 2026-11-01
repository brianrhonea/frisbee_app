import 'package:flutter/material.dart';

import '../../../data/repositories/auth/auth_repository.dart';
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
  }) : _auth = authRepository,
       _theme = themeRepository,
       _notifications = notificationRepository {
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
    super.dispose();
  }
}
