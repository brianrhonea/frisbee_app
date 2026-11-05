import 'package:flutter/material.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/theme/theme_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// The website's frame: who's signed in, signing out and the theme.
class WebShellViewModel extends ChangeNotifier {
  WebShellViewModel({
    required AuthRepository authRepository,
    required ThemeRepository themeRepository,
  }) : _auth = authRepository,
       _theme = themeRepository {
    signOut = Command0<void>(_auth.signOut);
    setDark = Command1<void, bool>(_setDark);
    _auth.addListener(notifyListeners);
    _theme.addListener(notifyListeners);
  }

  final AuthRepository _auth;
  final ThemeRepository _theme;

  late final Command0<void> signOut;

  /// Picks dark (true) or light (false) over the system setting.
  late final Command1<void, bool> setDark;

  AppUser? get user => _auth.currentUser;

  String get userName => user?.label ?? '';

  Future<Result<void>> _setDark(bool dark) =>
      _theme.setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);

  @override
  void dispose() {
    _auth.removeListener(notifyListeners);
    _theme.removeListener(notifyListeners);
    signOut.dispose();
    setDark.dispose();
    super.dispose();
  }
}
