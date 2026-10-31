import 'package:flutter/material.dart';

/// Condensed display face for headings and the wordmark.
const headingFont = 'Barlow Condensed';

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
          onPrimary: Colors.white,
          surface: c.background,
          onSurface: c.ink,
          onSurfaceVariant: c.muted,
          surfaceContainerLowest: c.card,
          surfaceContainerLow: c.card,
          surfaceContainer: c.card,
          outline: c.muted,
          outlineVariant: c.border,
        );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
    );
    TextStyle? heading(TextStyle? s, {FontWeight w = FontWeight.w700}) =>
        s?.copyWith(fontFamily: headingFont, fontWeight: w, letterSpacing: 0.2);
    final text = base.textTheme;
    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      extensions: [c],
      textTheme: text.copyWith(
        displaySmall: heading(text.displaySmall, w: FontWeight.w800),
        headlineLarge: heading(text.headlineLarge, w: FontWeight.w800),
        headlineMedium: heading(text.headlineMedium, w: FontWeight.w800),
        headlineSmall: heading(text.headlineSmall),
        titleLarge: heading(text.titleLarge),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: heading(
          text.titleLarge,
        )?.copyWith(color: c.ink, fontSize: 24),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: c.card,
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        elevation: 0,
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        height: 64,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? c.accent : c.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? c.accent : c.muted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.card,
        indicatorColor: c.accentSoft,
        selectedIconTheme: IconThemeData(color: c.accent),
        unselectedIconTheme: IconThemeData(color: c.muted),
      ),
      dividerTheme: DividerThemeData(color: c.border),
    );
  }
}

/// Named colors from the app's design (slate background, navy ink and
/// feature cards, terracotta accent). Read with `AppColors.of(context)`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.card,
    required this.border,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.feature,
    required this.onFeature,
    required this.onFeatureMuted,
    required this.featureHighlight,
    required this.positive,
    required this.positiveSoft,
    required this.team,
    required this.personal,
  });

  final Color background;
  final Color card;
  final Color border;
  final Color ink;
  final Color muted;
  final Color accent;

  /// Tinted fill behind accent content, e.g. a date tile.
  final Color accentSoft;

  /// Dark navy "feature" cards (rankings, hero) and their text.
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
    background: Color(0xFFE3E9F0),
    card: Color(0xFFF0F3F7),
    border: Color(0xFFCFD8E2),
    ink: Color(0xFF1E2A36),
    muted: Color(0xFF5C6B7A),
    accent: Color(0xFFC0533B),
    accentSoft: Color(0xFFF2DDD6),
    feature: Color(0xFF27323E),
    onFeature: Color(0xFFF3F5F8),
    onFeatureMuted: Color(0xFF9DAAB7),
    featureHighlight: Color(0xFF3A4653),
    positive: Color(0xFF9FD3AE),
    positiveSoft: Color(0xFF3B5246),
    team: Color(0xFF1E6FD9),
    personal: Color(0xFF8A4FD1),
  );

  static const dark = AppColors(
    background: Color(0xFF11161C),
    card: Color(0xFF1A2129),
    border: Color(0xFF2A343E),
    ink: Color(0xFFE8EDF2),
    muted: Color(0xFF93A1AF),
    accent: Color(0xFFE07A5F),
    accentSoft: Color(0xFF3A2621),
    feature: Color(0xFF222C37),
    onFeature: Color(0xFFF3F5F8),
    onFeatureMuted: Color(0xFF9DAAB7),
    featureHighlight: Color(0xFF33404D),
    positive: Color(0xFF9FD3AE),
    positiveSoft: Color(0xFF2F4239),
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
      border: l(border, other.border),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
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
