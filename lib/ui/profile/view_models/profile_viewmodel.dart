import 'package:flutter/material.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/theme/theme_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../utils/command.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    required AuthRepository authRepository,
    required ThemeRepository themeRepository,
  }) : _auth = authRepository,
       _theme = themeRepository {
    setThemeMode = Command1<void, ThemeMode>(_theme.setThemeMode);
    _theme.addListener(notifyListeners);
    updateDisplayName = Command1<void, String>(_auth.updateDisplayName);
    signOut = Command0<void>(_auth.signOut);
    deleteAccount = Command0<void>(_auth.deleteAccount);
    _auth.addListener(notifyListeners);
  }

  final AuthRepository _auth;
  final ThemeRepository _theme;

  /// Light, dark, or following the device.
  ThemeMode get themeMode => _theme.themeMode;

  late final Command1<void, ThemeMode> setThemeMode;

  AppUser? get user => _auth.currentUser;

  late final Command1<void, String> updateDisplayName;
  late final Command0<void> signOut;
  late final Command0<void> deleteAccount;

  @override
  void dispose() {
    _auth.removeListener(notifyListeners);
    _theme.removeListener(notifyListeners);
    setThemeMode.dispose();
    super.dispose();
  }
}
