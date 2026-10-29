import 'package:flutter/material.dart';

import '../../../utils/result.dart';

/// The user's light/dark preference. [ThemeMode.system] follows the device.
abstract class ThemeRepository extends ChangeNotifier {
  ThemeMode get themeMode;

  Future<Result<void>> setThemeMode(ThemeMode mode);
}
