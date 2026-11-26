import 'package:flutter/material.dart';

import '../themes/theme.dart';

export '../themes/button_styles.dart' show AppButtonSize, AppButtonVariant;

/// The app's button: primary, secondary, ghost or destructive, in small,
/// medium or large. Every size has a tap area of at least 48 px.
///
/// States: enabled, pressed, hovered and focused (Material's overlay, plus an
/// ink outline on focus), disabled ([onPressed] null) and [loading] (the label
/// stays, so the width doesn't jump, with a spinner on top; taps are off and
/// screen readers hear "loading").
///
/// A plain `FilledButton`, `OutlinedButton` or `TextButton` takes the same
/// look from the theme; use this when you need the destructive or sized
/// variants, loading, or [expand].
///
/// Website counterpart: `AppButton` / `.btn` (apps/web).
class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.loading = false,
    this.expand = false,
  });

  const AppButton.primary(
    String label, {
    Key? key,
    required VoidCallback? onPressed,
    AppButtonSize size = AppButtonSize.medium,
    IconData? icon,
    bool loading = false,
    bool expand = false,
  }) : this(
         label,
         key: key,
         onPressed: onPressed,
         size: size,
         icon: icon,
         loading: loading,
         expand: expand,
       );

  const AppButton.secondary(
    String label, {
    Key? key,
    required VoidCallback? onPressed,
    AppButtonSize size = AppButtonSize.medium,
    IconData? icon,
    bool loading = false,
    bool expand = false,
  }) : this(
         label,
         key: key,
         onPressed: onPressed,
         variant: AppButtonVariant.secondary,
         size: size,
         icon: icon,
         loading: loading,
         expand: expand,
       );

  const AppButton.ghost(
    String label, {
    Key? key,
    required VoidCallback? onPressed,
    AppButtonSize size = AppButtonSize.medium,
    IconData? icon,
    bool loading = false,
    bool expand = false,
  }) : this(
         label,
         key: key,
         onPressed: onPressed,
         variant: AppButtonVariant.ghost,
         size: size,
         icon: icon,
         loading: loading,
         expand: expand,
       );

  const AppButton.destructive(
    String label, {
    Key? key,
    required VoidCallback? onPressed,
    AppButtonSize size = AppButtonSize.medium,
    IconData? icon,
    bool loading = false,
    bool expand = false,
  }) : this(
         label,
         key: key,
         onPressed: onPressed,
         variant: AppButtonVariant.destructive,
         size: size,
         icon: icon,
         loading: loading,
         expand: expand,
       );

  final String label;

  /// Null shows the button disabled.
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;

  /// Shown before the label.
  final IconData? icon;

  /// Busy: taps are ignored and a spinner shows over the label.
  final bool loading;

  /// Fill the available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = AppButtonStyles.of(c, variant, size);
    final tap = loading ? null : onPressed;
    final iconSize = size == AppButtonSize.large ? 20.0 : 18.0;
    final text = Text(label, textAlign: TextAlign.center);
    Widget content = icon == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: iconSize),
              const SizedBox(width: AppSpace.sm),
              Flexible(child: text),
            ],
          );
    if (loading) {
      content = Stack(
        alignment: Alignment.center,
        children: [
          Opacity(opacity: 0, child: content),
          Builder(
            builder: (context) => SizedBox(
              width: iconSize,
              height: iconSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: IconTheme.of(context).color,
              ),
            ),
          ),
        ],
      );
    }
    final button = switch (variant) {
      AppButtonVariant.primary || AppButtonVariant.destructive => FilledButton(
        style: style,
        onPressed: tap,
        child: content,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        style: style,
        onPressed: tap,
        child: content,
      ),
      AppButtonVariant.ghost => TextButton(
        style: style,
        onPressed: tap,
        child: content,
      ),
    };
    return Semantics(
      // Material already labels the button from its text; this adds "busy".
      container: false,
      label: loading ? '$label, loading' : null,
      excludeSemantics: loading,
      button: loading,
      enabled: loading ? false : null,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
