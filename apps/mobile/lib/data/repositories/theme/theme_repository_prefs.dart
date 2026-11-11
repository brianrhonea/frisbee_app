import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../../../utils/result.dart';
import '../../services/shared_preferences_service.dart';
import 'theme_repository.dart';

/// [ThemeRepository] saved on the device.
class ThemeRepositoryPrefs extends ThemeRepository {
  ThemeRepositoryPrefs._(this._prefs, this._themeMode);

  static const _key = 'themeMode';
  static final _log = Logger('ThemeRepository');

  /// Reads the saved preference first, so the app opens in the right theme
  /// instead of flashing the default.
  static Future<ThemeRepositoryPrefs> load(
    SharedPreferencesService prefs,
  ) async {
    var mode = ThemeMode.system;
    try {
      mode = ThemeMode.values.asNameMap()[await prefs.getString(_key)] ?? mode;
    } on Exception catch (e) {
      _log.warning('Theme preference failed to load', e);
    }
    return ThemeRepositoryPrefs._(prefs, mode);
  }

  final SharedPreferencesService _prefs;
  ThemeMode _themeMode;

  @override
  ThemeMode get themeMode => _themeMode;

  @override
  Future<Result<void>> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      await _prefs.setString(_key, mode.name);
      return const Result.ok(null);
    } on Exception catch (e) {
      // Still applied for this session; it just won't be remembered.
      _log.warning('Theme preference failed to save', e);
      return Result.error(e);
    }
  }
}
