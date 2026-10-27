import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF1B7F5B); // field green

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
    );
  }
}

/// Colors used for play diagrams; fixed so diagrams look the same in
/// light and dark mode.
abstract final class FieldColors {
  static const grass = Color(0xFF2E7D4F);
  static const endzone = Color(0xFF256B43);
  static const lines = Color(0xE6FFFFFF);
  static const offense = Color(0xFF1E88E5);
  static const defense = Color(0xFFE53935);
  static const disc = Color(0xFFFFFFFF);
  static const cone = Color(0xFFFF9800);
  static const cut = Color(0xFFFFFFFF);
  static const throwLine = Color(0xFFFFEB3B);
  static const selection = Color(0xFFFFEB3B);
}
