import 'package:flutter/material.dart';

import 'theme.dart';

/// Which button: the look and the weight of the action.
///
/// * [primary]: the one main action (filled accent).
/// * [secondary]: another action (outlined).
/// * [ghost]: a quiet action such as Cancel (text only).
/// * [destructive]: delete, remove, leave (filled error).
enum AppButtonVariant { primary, secondary, ghost, destructive }

/// How big. Every size has a 48 px tap area (the guide's minimum): [small]
/// looks 36 px tall and pads out to 48.
enum AppButtonSize { small, medium, large }

/// The one set of button styles. The Material button themes in [AppTheme] and
/// [AppButton] both read from here, so a plain `FilledButton` and an
/// `AppButton.primary` look the same.
abstract final class AppButtonStyles {
  /// The least tap area of any button.
  static const minTarget = 48.0;

  /// Outline drawn on a focused button (keyboards, switch access).
  static const focusWidth = 2.0;

  static ButtonStyle of(
    AppColors c,
    AppButtonVariant variant, [
    AppButtonSize size = AppButtonSize.medium,
    bool filledColors = true,
  ]) {
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
    );
    final (EdgeInsets padding, double height, TextStyle text) = switch (size) {
      AppButtonSize.small => (
        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        36.0,
        AppText.label,
      ),
      AppButtonSize.medium => (
        const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        minTarget,
        AppText.label,
      ),
      AppButtonSize.large => (
        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        56.0,
        AppText.bodyStrong,
      ),
    };
    final minimum = Size(64, height);
    final outline = BorderSide(color: c.border2);
    final (Color? bg, Color fg, BorderSide? side) = switch (variant) {
      AppButtonVariant.primary => (c.accent, c.onAccent, null),
      AppButtonVariant.destructive => (c.error, c.card, null),
      AppButtonVariant.secondary => (c.card, c.ink, outline),
      AppButtonVariant.ghost => (null, c.ink, null),
    };
    final base = switch (variant) {
      AppButtonVariant.primary ||
      AppButtonVariant.destructive => FilledButton.styleFrom(
        // The theme leaves the colours off so `FilledButton.tonal` keeps its
        // own (soft accent); AppButton passes them.
        backgroundColor: filledColors ? bg : null,
        foregroundColor: filledColors ? fg : null,
        shape: shape,
        textStyle: text,
        padding: padding,
        minimumSize: minimum,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      AppButtonVariant.secondary => OutlinedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        shape: shape,
        textStyle: text,
        padding: padding,
        minimumSize: minimum,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      AppButtonVariant.ghost => TextButton.styleFrom(
        foregroundColor: fg,
        shape: shape,
        textStyle: text,
        padding: padding,
        minimumSize: minimum,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    };
    // A focused button gets an ink outline on every variant (fills and
    // outlines alike), so keyboard focus never rests on colour alone.
    return base.copyWith(
      side: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.focused)
            ? BorderSide(color: c.ink, width: focusWidth)
            : side,
      ),
    );
  }
}
