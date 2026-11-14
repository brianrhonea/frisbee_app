import 'package:flutter/material.dart';

/// The app's typeface, for body text and headings alike.
const appFont = 'Inter';

/// Headings use the app font at heavier weights.
const headingFont = appFont;

/// Corner radius of cards and panels.
const cardRadius = 14.0;

/// Corner radius of buttons, fields and small tiles.
const controlRadius = 10.0;

/// Digits all the same width, so counts, scores and timers don't shift
/// as they change. On by default for all text.
const tabularFigures = [FontFeature.tabularFigures()];

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
    final text = _withTabularFigures(base.textTheme);
    final controlShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    const buttonText = TextStyle(
      fontFamily: appFont,
      fontFeatures: tabularFigures,
      fontWeight: FontWeight.w600,
      fontSize: 14,
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      extensions: [c],
      // Native-feeling page changes: Android's predictive back (the page
      // follows the back swipe), iOS's slide, and a fade elsewhere.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        },
      ),
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
        shape: RoundedSuperellipseBorder(
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
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: c.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(cardRadius + 4),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        // A handle on every sheet that can be swiped down to close.
        showDragHandle: true,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          side: BorderSide(color: c.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.accentSoft,
        selectedColor: c.accent,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        // Selected chips are filled with the accent, so their label
        // switches to its contrasting ink.
        labelStyle: TextStyle(
          fontFamily: appFont,
          fontFeatures: tabularFigures,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.onAccent : c.ink,
          ),
        ),
        checkmarkColor: c.onAccent,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.accent,
        unselectedLabelColor: c.muted,
        indicatorColor: c.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: c.border,
        labelStyle: const TextStyle(
          fontFamily: appFont,
          fontFeatures: tabularFigures,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: appFont,
          fontFeatures: tabularFigures,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: c.accent,
        textColor: c.onAccent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accentSoft,
        height: 64,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? c.accent : c.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: appFont,
            fontFeatures: tabularFigures,
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? c.accent : c.muted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.sidebar,
        indicatorColor: c.accentSoft,
        selectedIconTheme: IconThemeData(color: c.accent),
        unselectedIconTheme: IconThemeData(color: c.onSidebarMuted),
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: c.accent,
        selectedTileColor: c.accentSoft,
        iconColor: c.muted,
      ),
      dividerTheme: DividerThemeData(color: c.border, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.feature,
        contentTextStyle: TextStyle(fontFamily: appFont, color: c.onFeature),
        actionTextColor: c.highlight,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    );
  }

  static TextTheme _withTabularFigures(TextTheme t) {
    TextStyle? tab(TextStyle? s) => s?.copyWith(fontFeatures: tabularFigures);
    return t.copyWith(
      displayLarge: tab(t.displayLarge),
      displayMedium: tab(t.displayMedium),
      displaySmall: tab(t.displaySmall),
      headlineLarge: tab(t.headlineLarge),
      headlineMedium: tab(t.headlineMedium),
      headlineSmall: tab(t.headlineSmall),
      titleLarge: tab(t.titleLarge),
      titleMedium: tab(t.titleMedium),
      titleSmall: tab(t.titleSmall),
      bodyLarge: tab(t.bodyLarge),
      bodyMedium: tab(t.bodyMedium),
      bodySmall: tab(t.bodySmall),
      labelLarge: tab(t.labelLarge),
      labelMedium: tab(t.labelMedium),
      labelSmall: tab(t.labelSmall),
    );
  }
}

/// Named colors from the app's design, shared with the website: a cool
/// off-white page, white cards and sidebar, indigo accent and feature cards,
/// and an amber highlight for calls to action on them. Read with
/// `AppColors.of(context)`.
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

  /// Amber: calls to action and marks on feature cards, and strong tags.
  final Color highlight;
  final Color onHighlight;

  /// The navigation sidebar and rail, and the phone's top bar (white, or
  /// Midnight's card, as on the website).
  final Color sidebar;
  final Color onSidebar;
  final Color onSidebarMuted;

  /// Indigo "feature" cards (up next, hero) and their text.
  final Color feature;
  final Color onFeature;
  final Color onFeatureMuted;
  final Color featureHighlight;
  final Color positive;
  final Color positiveSoft;

  /// Marks team events vs the user's personal events on schedules.
  final Color team;
  final Color personal;

  // The website's palette (apps/web/app/site.css): indigo on a cool
  // off-white, and "Midnight" in dark mode.
  static const light = AppColors(
    background: Color(0xFFF3F5FB),
    card: Color(0xFFFFFFFF),
    field: Color(0xFFF1F2F8),
    border: Color(0xFFE3E6F0),
    ink: Color(0xFF171A2E),
    muted: Color(0xFF686D86),
    accent: Color(0xFF5348B2),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFEAE7F9),
    highlight: Color(0xFFF0D8A8),
    onHighlight: Color(0xFF3A2A08),
    sidebar: Color(0xFFFFFFFF),
    onSidebar: Color(0xFF171A2E),
    onSidebarMuted: Color(0xFF686D86),
    feature: Color(0xFF5348B2),
    onFeature: Color(0xFFFFFFFF),
    onFeatureMuted: Color(0xFFD9D5F5),
    featureHighlight: Color(0xFF6A5FC6),
    positive: Color(0xFF2F8F57),
    positiveSoft: Color(0xFFDDEFD9),
    team: Color(0xFF2C6FB7),
    personal: Color(0xFFA8407A),
  );

  static const dark = AppColors(
    background: Color(0xFF121521),
    card: Color(0xFF1E2230),
    field: Color(0xFF252A3B),
    border: Color(0xFF2A3045),
    ink: Color(0xFFECEEF6),
    muted: Color(0xFF9398B0),
    accent: Color(0xFFA599F8),
    onAccent: Color(0xFF16132F),
    accentSoft: Color(0xFF2B2846),
    highlight: Color(0xFFF0D2A2),
    onHighlight: Color(0xFF2B1E06),
    sidebar: Color(0xFF171A28),
    onSidebar: Color(0xFFECEEF6),
    onSidebarMuted: Color(0xFF9398B0),
    feature: Color(0xFF4B41A8),
    onFeature: Color(0xFFFFFFFF),
    onFeatureMuted: Color(0xFFCFCAF3),
    featureHighlight: Color(0xFF5D53BA),
    positive: Color(0xFF8FD3A3),
    positiveSoft: Color(0xFF243A2C),
    team: Color(0xFF7FB0EE),
    personal: Color(0xFFE08BB8),
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
