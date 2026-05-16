import 'package:flutter/material.dart';

// ── Brand tokens ──────────────────────────────────────────────
abstract final class DiscUpColors {
  // Primary — field green
  static const green50  = Color(0xFFE8F5E9);
  static const green400 = Color(0xFF4CAF50);
  static const green600 = Color(0xFF2E7D32);
  static const green800 = Color(0xFF1B5E20);

  // Accent — disc orange
  static const orange50  = Color(0xFFFFF3E0);
  static const orange400 = Color(0xFFFF9800);
  static const orange600 = Color(0xFFE65100);

  // Neutrals
  static const grey50  = Color(0xFFF9FAFB);
  static const grey100 = Color(0xFFF3F4F6);
  static const grey200 = Color(0xFFE5E7EB);
  static const grey400 = Color(0xFF9CA3AF);
  static const grey600 = Color(0xFF4B5563);
  static const grey900 = Color(0xFF111827);

  // Semantic
  static const error   = Color(0xFFDC2626);
  static const warning = Color(0xFFF59E0B);
  static const success = Color(0xFF10B981);
  static const info    = Color(0xFF3B82F6);

  // Dark surface
  static const darkSurface    = Color(0xFF1A1A2E);
  static const darkSurfaceAlt = Color(0xFF16213E);
  static const darkCard       = Color(0xFF0F3460);
}

abstract final class DiscUpTextStyles {
  static const _baseFamily = 'Outfit'; // add to pubspec + Google Fonts

  static const displayLarge = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const headlineMedium = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  static const titleLarge = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static const titleMedium = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  static const bodyLarge = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const bodyMedium = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const labelLarge = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static const labelSmall = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
  );
}

// ── Theme builder ─────────────────────────────────────────────
abstract final class DiscUpTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Outfit',
    );

    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: DiscUpColors.green600,
        brightness: Brightness.light,
        primary: DiscUpColors.green600,
        onPrimary: Colors.white,
        secondary: DiscUpColors.orange400,
        onSecondary: Colors.white,
        surface: DiscUpColors.grey50,
        onSurface: DiscUpColors.grey900,
        error: DiscUpColors.error,
      ),
      scaffoldBackgroundColor: DiscUpColors.grey100,
      textTheme: _buildTextTheme(DiscUpColors.grey900),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: DiscUpColors.grey900,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: DiscUpTextStyles.titleLarge.copyWith(
          color: DiscUpColors.grey900,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: DiscUpColors.green600,
        unselectedItemColor: DiscUpColors.grey400,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 11,
        ),
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DiscUpColors.grey200),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DiscUpColors.green600,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: DiscUpTextStyles.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DiscUpColors.green600,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: DiscUpColors.green600, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: DiscUpTextStyles.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DiscUpColors.grey100,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DiscUpColors.grey200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: DiscUpColors.green600,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DiscUpColors.error),
        ),
        hintStyle: DiscUpTextStyles.bodyMedium.copyWith(
          color: DiscUpColors.grey400,
        ),
        labelStyle: DiscUpTextStyles.bodyMedium,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: DiscUpColors.grey100,
        selectedColor: DiscUpColors.green50,
        labelStyle: DiscUpTextStyles.labelSmall,
        side: const BorderSide(color: DiscUpColors.grey200),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(
        color: DiscUpColors.grey200,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: DiscUpColors.grey900,
        contentTextStyle: DiscUpTextStyles.bodyMedium.copyWith(
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Outfit',
    );

    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: DiscUpColors.green400,
        brightness: Brightness.dark,
        primary: DiscUpColors.green400,
        onPrimary: Colors.black,
        secondary: DiscUpColors.orange400,
        surface: DiscUpColors.darkSurface,
        onSurface: Colors.white,
        error: DiscUpColors.error,
      ),
      scaffoldBackgroundColor: DiscUpColors.darkSurface,
      textTheme: _buildTextTheme(Colors.white),
      appBarTheme: AppBarTheme(
        backgroundColor: DiscUpColors.darkSurfaceAlt,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: DiscUpTextStyles.titleLarge.copyWith(
          color: Colors.white,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: DiscUpColors.darkSurfaceAlt,
        selectedItemColor: DiscUpColors.green400,
        unselectedItemColor: DiscUpColors.grey400,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 11,
        ),
      ),
      cardTheme: CardTheme(
        color: DiscUpColors.darkSurfaceAlt,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DiscUpColors.green400,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: DiscUpTextStyles.labelLarge,
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DiscUpColors.darkCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: DiscUpColors.green400,
            width: 1.5,
          ),
        ),
        hintStyle: DiscUpTextStyles.bodyMedium.copyWith(
          color: DiscUpColors.grey400,
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme(Color baseColor) {
    return TextTheme(
      displayLarge: DiscUpTextStyles.displayLarge.copyWith(color: baseColor),
      headlineMedium: DiscUpTextStyles.headlineMedium.copyWith(color: baseColor),
      titleLarge: DiscUpTextStyles.titleLarge.copyWith(color: baseColor),
      titleMedium: DiscUpTextStyles.titleMedium.copyWith(color: baseColor),
      bodyLarge: DiscUpTextStyles.bodyLarge.copyWith(color: baseColor),
      bodyMedium: DiscUpTextStyles.bodyMedium.copyWith(
        color: baseColor.withOpacity(0.75),
      ),
      labelLarge: DiscUpTextStyles.labelLarge.copyWith(color: baseColor),
      labelSmall: DiscUpTextStyles.labelSmall.copyWith(
        color: baseColor.withOpacity(0.6),
      ),
    );
  }
}