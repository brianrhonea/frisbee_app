import 'package:flutter/material.dart';

/// The app's typeface, for body text and headings alike.
const appFont = 'Inter';

/// Headings use the app font at heavier weights.
const headingFont = appFont;

/// The condensed sports face for scores, big numbers, date badges and the
/// wordmark (always weight 800).
const scoreFont = 'Barlow Condensed';

/// Corner radius of cards and panels.
const cardRadius = 16.0;

/// Corner radius of buttons, fields and small tiles.
const controlRadius = 12.0;

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
          side: BorderSide(color: c.border2),
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
        backgroundColor: c.card,
        selectedColor: c.chipOn,
        side: BorderSide(color: c.border2),
        shape: const StadiumBorder(),
        // Filter chips: outlined, and filled navy (light) or ink (dark)
        // when selected, so their label switches to its contrasting ink.
        labelStyle: TextStyle(
          fontFamily: appFont,
          fontFeatures: tabularFigures,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.onChipOn : c.ink,
          ),
        ),
        checkmarkColor: c.onChipOn,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.ink,
        unselectedLabelColor: c.muted,
        indicatorColor: c.accent,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: c.accent, width: 3),
        ),
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
      // Unread counts are the user's to clear: disc amber.
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
      // On: turf track, white thumb. Off: outlined track on the card.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onAccent : c.border2,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.field,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Colors.transparent : c.border2,
        ),
      ),
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

/// Named colors of the "Turf & Disc" design, shared with the website:
/// turf green for actions, scoreboard navy for anything live or today,
/// disc amber only for what is yours to do, red only for live games.
/// Read with `AppColors.of(context)`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.card,
    required this.field,
    required this.border,
    required this.border2,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentInk,
    required this.highlight,
    required this.onHighlight,
    required this.highlightSoft,
    required this.highlightInk,
    required this.live,
    required this.liveSoft,
    required this.liveInk,
    required this.sidebar,
    required this.onSidebar,
    required this.onSidebarMuted,
    required this.feature,
    required this.onFeature,
    required this.onFeatureMuted,
    required this.featureHighlight,
    required this.positive,
    required this.positiveSoft,
    required this.chipOn,
    required this.onChipOn,
    required this.team,
    required this.personal,
    required this.badge,
  });

  /// The page behind cards.
  final Color background;

  /// Cards, sheets and bars.
  final Color card;

  /// Fill of text fields, search boxes and segmented controls.
  final Color field;

  /// Card borders and dividers.
  final Color border;

  /// Outline buttons and unselected chips.
  final Color border2;

  /// Primary text.
  final Color ink;

  /// Secondary text that still needs weight.
  final Color ink2;

  /// Meta text.
  final Color muted;

  /// Turf green: primary actions, links and selected state.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Soft turf fill: selected chips, date tiles, soft badges.
  final Color accentSoft;

  /// Text on [accentSoft].
  final Color accentInk;

  /// Disc amber: only for what is yours to do (report a score, RSVP,
  /// unread counts). Never decoration.
  final Color highlight;

  /// Text on [highlight].
  final Color onHighlight;

  /// Soft amber fill behind a "needs you" row.
  final Color highlightSoft;

  /// Amber text for "needs you" labels on cards.
  final Color highlightInk;

  /// Red, only for live games: the live dot.
  final Color live;

  /// Fill of a live pill.
  final Color liveSoft;

  /// Text of a live pill.
  final Color liveInk;

  /// The navigation sidebar and rail, and the phone's top bar.
  final Color sidebar;

  final Color onSidebar;
  final Color onSidebarMuted;

  /// Scoreboard navy: anything live or today (scoreboard cards,
  /// live headers).
  final Color feature;

  final Color onFeature;

  /// Secondary text on [feature].
  final Color onFeatureMuted;

  /// Secondary buttons and tiles on [feature].
  final Color featureHighlight;

  /// Wins and confirmations.
  final Color positive;

  final Color positiveSoft;

  /// A selected filter chip.
  final Color chipOn;

  final Color onChipOn;

  /// Marks team events vs the user's personal events on schedules.
  final Color team;

  final Color personal;

  /// Team badge fill (white initials), the same in both modes.
  final Color badge;

  static const light = AppColors(
    background: Color(0xFFF5F6F1),
    card: Color(0xFFFFFFFF),
    field: Color(0xFFEEF0EA),
    border: Color(0xFFE1E4DC),
    border2: Color(0xFFD5D9CF),
    ink: Color(0xFF0F1A2A),
    ink2: Color(0xFF3B4352),
    muted: Color(0xFF5E6573),
    accent: Color(0xFF12805C),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE3F2EA),
    accentInk: Color(0xFF0B5E43),
    highlight: Color(0xFFFFB627),
    onHighlight: Color(0xFF2A1B00),
    highlightSoft: Color(0xFFFFF1D1),
    highlightInk: Color(0xFF8A5A00),
    live: Color(0xFFD93636),
    liveSoft: Color(0xFFFDE7E7),
    liveInk: Color(0xFFB42323),
    sidebar: Color(0xFFFFFFFF),
    onSidebar: Color(0xFF0F1A2A),
    onSidebarMuted: Color(0xFF5E6573),
    feature: Color(0xFF0F1A2A),
    onFeature: Color(0xFFFFFFFF),
    onFeatureMuted: Color(0xFFB7C0CE),
    featureHighlight: Color(0xFF22324A),
    positive: Color(0xFF12805C),
    positiveSoft: Color(0xFFE3F2EA),
    chipOn: Color(0xFF0F1A2A),
    onChipOn: Color(0xFFFFFFFF),
    team: Color(0xFF2C6FB7),
    personal: Color(0xFFA8407A),
    badge: Color(0xFF2C6FB7),
  );

  static const dark = AppColors(
    background: Color(0xFF0B121D),
    card: Color(0xFF152030),
    field: Color(0xFF1B2838),
    border: Color(0xFF24324A),
    border2: Color(0xFF2E3D55),
    ink: Color(0xFFEAF0F5),
    ink2: Color(0xFFC4CDD8),
    muted: Color(0xFF93A0B2),
    accent: Color(0xFF3DBE8B),
    onAccent: Color(0xFF06281B),
    accentSoft: Color(0xFF133528),
    accentInk: Color(0xFF7FDDB4),
    highlight: Color(0xFFFFC24D),
    onHighlight: Color(0xFF2A1B00),
    highlightSoft: Color(0xFF3A2C0E),
    highlightInk: Color(0xFFFFC24D),
    live: Color(0xFFFF5A5A),
    liveSoft: Color(0xFF3A1A1E),
    liveInk: Color(0xFFFF8A8A),
    sidebar: Color(0xFF152030),
    onSidebar: Color(0xFFEAF0F5),
    onSidebarMuted: Color(0xFF93A0B2),
    feature: Color(0xFF1A2940),
    onFeature: Color(0xFFFFFFFF),
    onFeatureMuted: Color(0xFFA9B6C8),
    featureHighlight: Color(0xFF26385A),
    positive: Color(0xFF3DBE8B),
    positiveSoft: Color(0xFF133528),
    chipOn: Color(0xFFEAF0F5),
    onChipOn: Color(0xFF0B121D),
    team: Color(0xFF7FB0EE),
    personal: Color(0xFFE08BB8),
    badge: Color(0xFF2C6FB7),
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
      border2: l(border2, other.border2),
      ink: l(ink, other.ink),
      ink2: l(ink2, other.ink2),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentSoft: l(accentSoft, other.accentSoft),
      accentInk: l(accentInk, other.accentInk),
      highlight: l(highlight, other.highlight),
      onHighlight: l(onHighlight, other.onHighlight),
      highlightSoft: l(highlightSoft, other.highlightSoft),
      highlightInk: l(highlightInk, other.highlightInk),
      live: l(live, other.live),
      liveSoft: l(liveSoft, other.liveSoft),
      liveInk: l(liveInk, other.liveInk),
      sidebar: l(sidebar, other.sidebar),
      onSidebar: l(onSidebar, other.onSidebar),
      onSidebarMuted: l(onSidebarMuted, other.onSidebarMuted),
      feature: l(feature, other.feature),
      onFeature: l(onFeature, other.onFeature),
      onFeatureMuted: l(onFeatureMuted, other.onFeatureMuted),
      featureHighlight: l(featureHighlight, other.featureHighlight),
      positive: l(positive, other.positive),
      positiveSoft: l(positiveSoft, other.positiveSoft),
      chipOn: l(chipOn, other.chipOn),
      onChipOn: l(onChipOn, other.onChipOn),
      team: l(team, other.team),
      personal: l(personal, other.personal),
      badge: l(badge, other.badge),
    );
  }
}

/// Colors used for play diagrams; fixed so diagrams look the same in
/// light and dark mode.
abstract final class FieldColors {
  static const grass = Color(0xFF2E7D4F);
  static const endzone = Color(0xFF256B43);
  static const lines = Color(0xE6FFFFFF);
  // Team blue for offense and scoreboard navy for defense: distinct, and
  // no red (red is only for live games).
  static const offense = Color(0xFF2F78C8);
  static const defense = Color(0xFF14213A);
  static const disc = Color(0xFFFFFFFF);
  static const cone = Color(0xFFFF8A1F);
  static const cut = Color(0xFFFFFFFF);
  static const throwLine = Color(0xFFFFEB3B);
  static const selection = Color(0xFFFFEB3B);
}
