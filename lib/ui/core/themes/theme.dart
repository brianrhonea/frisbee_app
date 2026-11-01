import 'package:flutter/material.dart';

/// The app's typeface, for body text and headings alike.
const appFont = 'Inter';

/// Headings use the app font at heavier weights.
const headingFont = appFont;

/// Corner radius of cards and panels.
const cardRadius = 14.0;

/// Corner radius of buttons, fields and small tiles.
const controlRadius = 10.0;

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light, AppColors.light);

  static ThemeData get dark => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors c) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: c.accent,
          brightness: brightness,
        ).copyWith(
          primary: c.accent,
          onPrimary: c.onAccent,
          primaryContainer: c.accentSoft,
          onPrimaryContainer: c.ink,
          secondary: c.highlight,
          onSecondary: c.onHighlight,
          secondaryContainer: c.accentSoft,
          onSecondaryContainer: c.ink,
          surface: c.background,
          onSurface: c.ink,
          onSurfaceVariant: c.muted,
          surfaceContainerLowest: c.card,
          surfaceContainerLow: c.card,
          surfaceContainer: c.card,
          surfaceContainerHigh: c.card,
          surfaceContainerHighest: c.accentSoft,
          outline: c.muted,
          outlineVariant: c.border,
        );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
      fontFamily: appFont,
    );
    TextStyle? heading(
      TextStyle? s, {
      FontWeight w = FontWeight.w700,
      double spacing = -0.3,
    }) => s?.copyWith(fontWeight: w, letterSpacing: spacing, color: c.ink);
    final text = base.textTheme;
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    const buttonText = TextStyle(
      fontFamily: appFont,
      fontWeight: FontWeight.w600,
      fontSize: 14,
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      extensions: [c],
      textTheme: text.copyWith(
        displaySmall: heading(text.displaySmall, w: FontWeight.w800),
        headlineLarge: heading(text.headlineLarge, w: FontWeight.w800),
        headlineMedium: heading(
          text.headlineMedium,
          w: FontWeight.w800,
          spacing: -0.8,
        ),
        headlineSmall: heading(text.headlineSmall, w: FontWeight.w800),
        titleLarge: heading(text.titleLarge),
        titleMedium: heading(text.titleMedium, spacing: -0.1),
        titleSmall: heading(text.titleSmall, spacing: 0),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: appFont,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: -0.3,
          color: c.ink,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: controlShape,
          textStyle: buttonText,
          padding: buttonPadding,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: controlShape,
          textStyle: buttonText,
          padding: buttonPadding,
          foregroundColor: c.ink,
          backgroundColor: c.card,
          side: BorderSide(color: c.border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: controlShape,
          textStyle: buttonText,
          foregroundColor: c.ink,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.field,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: c.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        elevation: 0,
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: c.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius + 4),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          side: BorderSide(color: c.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.accentSoft,
        selectedColor: c.highlight,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          fontFamily: appFont,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: c.ink,
        ),
        checkmarkColor: c.onHighlight,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.ink,
        unselectedLabelColor: c.muted,
        indicatorColor: c.ink,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: c.border,
        labelStyle: const TextStyle(
          fontFamily: appFont,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: appFont,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: c.highlight,
        textColor: c.onHighlight,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accentSoft,
        height: 64,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? c.ink : c.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: appFont,
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? c.ink : c.muted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.sidebar,
        indicatorColor: c.highlight,
        selectedIconTheme: IconThemeData(color: c.onHighlight),
        unselectedIconTheme: IconThemeData(color: c.onSidebarMuted),
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: c.ink,
        selectedTileColor: c.accentSoft,
        iconColor: c.muted,
      ),
      dividerTheme: DividerThemeData(color: c.border, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.feature,
        contentTextStyle: TextStyle(fontFamily: appFont, color: c.onFeature),
        actionTextColor: c.highlight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    );
  }
}

/// Named colors from the app's design: a warm off-white page, white cards,
/// forest-green ink, sidebar and feature cards, and a lime highlight. Read
/// with `AppColors.of(context)`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.card,
    required this.field,
    required this.border,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.highlight,
    required this.onHighlight,
    required this.sidebar,
    required this.onSidebar,
    required this.onSidebarMuted,
    required this.feature,
    required this.onFeature,
    required this.onFeatureMuted,
    required this.featureHighlight,
    required this.positive,
    required this.positiveSoft,
    required this.team,
    required this.personal,
  });

  /// The page behind cards.
  final Color background;
  final Color card;

  /// Fill of text fields and search boxes.
  final Color field;
  final Color border;
  final Color ink;
  final Color muted;

  /// Primary actions: filled buttons, the user's own message bubbles.
  final Color accent;
  final Color onAccent;

  /// Tinted fill behind accent content, e.g. a date tile or pinned bar.
  final Color accentSoft;

  /// Lime: the selected sidebar item, badges and calls to action on
  /// feature cards.
  final Color highlight;
  final Color onHighlight;

  /// The navigation sidebar and rail, and the phone's top bar.
  final Color sidebar;
  final Color onSidebar;
  final Color onSidebarMuted;

  /// Dark "feature" cards (up next, hero) and their text.
  final Color feature;
  final Color onFeature;
  final Color onFeatureMuted;
  final Color featureHighlight;
  final Color positive;
  final Color positiveSoft;

  /// Marks team events vs the user's personal events on schedules.
  final Color team;
  final Color personal;

  static const light = AppColors(
    background: Color(0xFFF4F4EF),
    card: Color(0xFFFFFFFF),
    field: Color(0xFFF4F5F0),
    border: Color(0xFFE3E5DC),
    ink: Color(0xFF18241D),
    muted: Color(0xFF6B736A),
    accent: Color(0xFF1F3B2C),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE8EDE1),
    highlight: Color(0xFFD7F06A),
    onHighlight: Color(0xFF18241D),
    sidebar: Color(0xFF1F3B2C),
    onSidebar: Color(0xFFF2F5EE),
    onSidebarMuted: Color(0xFFA9BAAC),
    feature: Color(0xFF1F3B2C),
    onFeature: Color(0xFFF2F5EE),
    onFeatureMuted: Color(0xFFA9BAAC),
    featureHighlight: Color(0xFF2D4D3B),
    positive: Color(0xFF2F8F57),
    positiveSoft: Color(0xFFDDEFD9),
    team: Color(0xFF2F6FD0),
    personal: Color(0xFF8A4FD1),
  );

  static const dark = AppColors(
    background: Color(0xFF0E1310),
    card: Color(0xFF161D18),
    field: Color(0xFF1C241E),
    border: Color(0xFF28322B),
    ink: Color(0xFFE7ECE4),
    muted: Color(0xFF98A399),
    accent: Color(0xFFC9E36B),
    onAccent: Color(0xFF142019),
    accentSoft: Color(0xFF223026),
    highlight: Color(0xFFC9E36B),
    onHighlight: Color(0xFF142019),
    sidebar: Color(0xFF121A15),
    onSidebar: Color(0xFFE7ECE4),
    onSidebarMuted: Color(0xFF8E9C91),
    feature: Color(0xFF1C2B22),
    onFeature: Color(0xFFF2F5EE),
    onFeatureMuted: Color(0xFFA3B3A6),
    featureHighlight: Color(0xFF2A3D31),
    positive: Color(0xFF8FD3A3),
    positiveSoft: Color(0xFF243A2C),
    team: Color(0xFF6AA6F5),
    personal: Color(0xFFB794EC),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      card: l(card, other.card),
      field: l(field, other.field),
      border: l(border, other.border),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentSoft: l(accentSoft, other.accentSoft),
      highlight: l(highlight, other.highlight),
      onHighlight: l(onHighlight, other.onHighlight),
      sidebar: l(sidebar, other.sidebar),
      onSidebar: l(onSidebar, other.onSidebar),
      onSidebarMuted: l(onSidebarMuted, other.onSidebarMuted),
      feature: l(feature, other.feature),
      onFeature: l(onFeature, other.onFeature),
      onFeatureMuted: l(onFeatureMuted, other.onFeatureMuted),
      featureHighlight: l(featureHighlight, other.featureHighlight),
      positive: l(positive, other.positive),
      positiveSoft: l(positiveSoft, other.positiveSoft),
      team: l(team, other.team),
      personal: l(personal, other.personal),
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
