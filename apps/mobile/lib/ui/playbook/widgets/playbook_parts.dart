import 'package:flutter/material.dart';

import '../../core/themes/theme.dart';

/// A bar under the app bar or over the bottom edge: card fill with a
/// hairline between it and the field.
class PlaybookBar extends StatelessWidget {
  const PlaybookBar({super.key, required this.child, this.top = false});

  final Widget child;

  /// True for a bar at the bottom (the line goes on top).
  final bool top;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final line = BorderSide(color: c.border);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(
          top: top ? line : BorderSide.none,
          bottom: top ? BorderSide.none : line,
        ),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// A square tool button: icon over a short label, turf when selected.
class ToolTile extends StatelessWidget {
  const ToolTile({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final enabled = onPressed != null;
    final fg = selected ? c.accentInk : (enabled ? c.ink2 : c.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          selected: selected,
          enabled: enabled,
          label: tooltip,
          onTap: onPressed,
          excludeSemantics: true,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Material(
              color: selected ? c.accentSoft : c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(controlRadius),
                side: BorderSide(
                  color: selected ? c.accent : c.border,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 20, color: iconColor ?? fg),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round pen-colour swatch; a turf ring marks the chosen one.
class ColorDot extends StatelessWidget {
  const ColorDot({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkResponse(
          onTap: onPressed,
          radius: 22,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: Container(
                width: 30,
                height: 30,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? c.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    // White and ink need an edge on the card in one mode
                    // or the other.
                    border: Border.all(color: c.border2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
