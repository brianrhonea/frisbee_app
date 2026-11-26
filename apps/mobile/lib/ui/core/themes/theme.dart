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
          error: c.error,
          onError: c.card,
          errorContainer: c.errorSoft,
          onErrorContainer: c.error,
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
      // Unread counts are the user's to clear: indigo.
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
        backgroundColor: c.ink,
        contentTextStyle: TextStyle(fontFamily: appFont, color: c.background),
        actionTextColor: c.background,
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

/// Named colors (zinc + indigo), shared with the website through
/// packages/shared/fixtures/design_tokens/tokens.json: indigo for
/// actions, amber pills for what needs you, red only for live games.
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
    required this.error,
    required this.errorSoft,
    required this.positive,
    required this.positiveSoft,
    required this.chipOn,
    required this.onChipOn,
    required this.team,
    required this.personal,
    required this.badge,
    required this.media,
    required this.media2,
    required this.onMedia,
    required this.onMediaMuted,
  });

  /// The page behind cards.
  final Color background;

  /// Cards, sheets and bars.
  final Color card;

  /// Fill of text fields, search boxes and segmented controls.
  final Color field;

  /// Card borders and dividers.
  final Color border;

  /// Outline for inputs, outline buttons and unselected chips (3:1 on
  /// cards and field fill).
  final Color border2;

  /// Primary text.
  final Color ink;

  /// Secondary text that still needs weight.
  final Color ink2;

  /// Meta text.
  final Color muted;

  /// Indigo: primary actions, links and selected state.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Soft indigo fill: selected chips, date tiles, soft badges.
  final Color accentSoft;

  /// Text on [accentSoft].
  final Color accentInk;

  /// Unread / attention fill (indigo): unread dots, count badges and
  /// what is yours to do. Never decoration.
  final Color highlight;

  /// Text on [highlight].
  final Color onHighlight;

  /// Soft amber fill of a "needs you" pill or row.
  final Color highlightSoft;

  /// Amber text of "needs you" pills and labels.
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

  /// Retired dark card (UI-Q6): now holds light-card values (white card
  /// in light, surface in dark). Pair only with [onFeature] etc. For
  /// video and call stages use [media].
  final Color feature;

  final Color onFeature;

  /// Secondary text on [feature].
  final Color onFeatureMuted;

  /// Secondary buttons and tiles on [feature].
  final Color featureHighlight;

  /// Error text, icons and outlines.
  final Color error;

  /// Fill of an error banner or pill.
  final Color errorSoft;

  /// Success only: wins and confirmations.
  final Color positive;

  final Color positiveSoft;

  /// A selected filter chip: solid indigo.
  final Color chipOn;

  final Color onChipOn;

  /// Marks team events vs the user's personal events on schedules.
  final Color team;

  final Color personal;

  /// Team badge fill (white initials), indigo in both modes.
  final Color badge;

  /// Video and call stages: dark in both themes.
  final Color media;

  /// Tiles and control buttons on [media].
  final Color media2;

  /// Text and icons on [media].
  final Color onMedia;

  /// Secondary text on [media].
  final Color onMediaMuted;

  static const light = AppColors(
    background: Color(0xFFF4F4F5),
    card: Color(0xFFFFFFFF),
    field: Color(0xFFE4E4E7),
    border: Color(0xFFD4D4D8),
    border2: Color(0xFF71717A),
    ink: Color(0xFF18181B),
    ink2: Color(0xFF3F3F46),
    muted: Color(0xFF52525B),
    accent: Color(0xFF4338CA),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFEEF2FF),
    accentInk: Color(0xFF3730A3),
    highlight: Color(0xFF4338CA),
    onHighlight: Color(0xFFFFFFFF),
    highlightSoft: Color(0xFFFEF3C7),
    highlightInk: Color(0xFF92400E),
    live: Color(0xFFBE123C),
    liveSoft: Color(0xFFFFE4E6),
    liveInk: Color(0xFFBE123C),
    error: Color(0xFFB91C1C),
    errorSoft: Color(0xFFFEE2E2),
    positive: Color(0xFF166534),
    positiveSoft: Color(0xFFDCFCE7),
    sidebar: Color(0xFFFFFFFF),
    onSidebar: Color(0xFF18181B),
    onSidebarMuted: Color(0xFF52525B),
    feature: Color(0xFFFFFFFF),
    onFeature: Color(0xFF18181B),
    onFeatureMuted: Color(0xFF52525B),
    featureHighlight: Color(0xFFE4E4E7),
    chipOn: Color(0xFF4338CA),
    onChipOn: Color(0xFFFFFFFF),
    team: Color(0xFF1D4ED8),
    personal: Color(0xFFA21CAF),
    badge: Color(0xFF4338CA),
    media: Color(0xFF18181B),
    media2: Color(0xFF27272A),
    onMedia: Color(0xFFFAFAFA),
    onMediaMuted: Color(0xFFA1A1AA),
  );

  static const dark = AppColors(
    background: Color(0xFF09090B),
    card: Color(0xFF18181B),
    field: Color(0xFF27272A),
    border: Color(0xFF3F3F46),
    border2: Color(0xFF71717A),
    ink: Color(0xFFFAFAFA),
    ink2: Color(0xFFD4D4D8),
    muted: Color(0xFFA1A1AA),
    accent: Color(0xFFA5B4FC),
    onAccent: Color(0xFF18181B),
    accentSoft: Color(0xFF1E1B4B),
    accentInk: Color(0xFFC7D2FE),
    highlight: Color(0xFFA5B4FC),
    onHighlight: Color(0xFF18181B),
    highlightSoft: Color(0xFF451A03),
    highlightInk: Color(0xFFFCD34D),
    live: Color(0xFFFDA4AF),
    liveSoft: Color(0xFF4C0519),
    liveInk: Color(0xFFFDA4AF),
    error: Color(0xFFFCA5A5),
    errorSoft: Color(0xFF450A0A),
    positive: Color(0xFF86EFAC),
    positiveSoft: Color(0xFF052E16),
    sidebar: Color(0xFF18181B),
    onSidebar: Color(0xFFFAFAFA),
    onSidebarMuted: Color(0xFFA1A1AA),
    feature: Color(0xFF18181B),
    onFeature: Color(0xFFFAFAFA),
    onFeatureMuted: Color(0xFFA1A1AA),
    featureHighlight: Color(0xFF27272A),
    chipOn: Color(0xFFA5B4FC),
    onChipOn: Color(0xFF18181B),
    team: Color(0xFF93C5FD),
    personal: Color(0xFFF0ABFC),
    badge: Color(0xFF4338CA),
    media: Color(0xFF18181B),
    media2: Color(0xFF27272A),
    onMedia: Color(0xFFFAFAFA),
    onMediaMuted: Color(0xFFA1A1AA),
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
      error: l(error, other.error),
      errorSoft: l(errorSoft, other.errorSoft),
      positive: l(positive, other.positive),
      positiveSoft: l(positiveSoft, other.positiveSoft),
      chipOn: l(chipOn, other.chipOn),
      onChipOn: l(onChipOn, other.onChipOn),
      team: l(team, other.team),
      personal: l(personal, other.personal),
      badge: l(badge, other.badge),
      media: l(media, other.media),
      media2: l(media2, other.media2),
      onMedia: l(onMedia, other.onMedia),
      onMediaMuted: l(onMediaMuted, other.onMediaMuted),
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

  // Whiteboard pen colours (DrawingColor). Turf is a light tint so it
  // shows on the grass; amber is the disc amber.
  static const penInk = Color(0xFF14213A);
  static const penTurf = Color(0xFF7FDDB4);
  static const penAmber = Color(0xFFFFB627);
  static const penWhite = Color(0xFFFFFFFF);
}
