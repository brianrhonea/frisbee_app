import 'package:flutter/material.dart';

import '../themes/theme.dart';

/// The app's segmented control: a row of equal-width segments in one
/// outlined pill. The selected segment is filled indigo ([AppColors.chipOn])
/// with an [AppColors.onChipOn] label, and bolder text, so it reads without
/// relying on colour alone.
///
/// Built from plain widgets (Material + InkWell per segment) so it follows the
/// text direction and the text scale. Segments are at least 48 px tall and
/// grow with their label. The API mirrors [SegmentedButton]'s, using
/// [ButtonSegment] for the segment data.
class AppSegmentedButton<T> extends StatelessWidget {
  const AppSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    this.onSelectionChanged,
    this.multiSelectionEnabled = false,
    this.emptySelectionAllowed = false,
    this.showSelectedIcon = true,
    this.expandedInsets,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;

  /// Null disables the whole control.
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool multiSelectionEnabled;
  final bool emptySelectionAllowed;

  /// Shows a check in place of the segment's icon while it is selected.
  final bool showSelectedIcon;

  /// When set, the control fills the available width (less these insets)
  /// instead of sizing to its labels.
  final EdgeInsets? expandedInsets;

  /// Width of the selected outline.
  static const outlineWidth = 1.5;

  /// Least height of a segment.
  static const minHeight = 48.0;

  void _tap(T value) {
    final cb = onSelectionChanged;
    if (cb == null) return;
    final on = selected.contains(value);
    if (multiSelectionEnabled) {
      final next = {...selected};
      on ? next.remove(value) : next.add(value);
      if (next.isEmpty && !emptySelectionAllowed) return;
      cb(next);
    } else if (on) {
      if (emptySelectionAllowed) cb(<T>{});
    } else {
      cb({value});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final on = selected.contains(s.value);
      if (i > 0) {
        // A hairline between neighbours, unless a selected outline is there.
        final prevOn = selected.contains(segments[i - 1].value);
        children.add(
          SizedBox(
            width: 1,
            child: ColoredBox(
              color: on || prevOn ? Colors.transparent : c.border2,
            ),
          ),
        );
      }
      final enabled = onSelectionChanged != null && s.enabled;
      Widget label = _SegmentLabel(
        selected: on,
        icon: on && showSelectedIcon ? const Icon(Icons.check) : s.icon,
        label: s.label,
      );
      if (s.tooltip != null) {
        label = Tooltip(message: s.tooltip!, child: label);
      }
      children.add(
        Expanded(
          child: AppSegment(
            selected: on,
            onTap: enabled ? () => _tap(s.value) : null,
            child: label,
          ),
        ),
      );
    }
    Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    row = IntrinsicHeight(child: row);
    final expanded = expandedInsets;
    if (expanded == null) {
      // Equal-width segments sized to the widest label.
      row = IntrinsicWidth(child: row);
    }
    final bar = DecoratedBox(
      decoration: ShapeDecoration(
        color: c.card,
        shape: StadiumBorder(side: BorderSide(color: c.border2)),
      ),
      child: row,
    );
    return expanded == null ? bar : Padding(padding: expanded, child: bar);
  }
}

/// One segment: a tappable, rounded cell that is filled indigo
/// ([AppColors.chipOn]) with an [AppColors.onChipOn] label when [selected]. The building block of
/// [AppSegmentedButton]; use it directly where segments are driven by
/// something else (a tab controller).
class AppSegment extends StatelessWidget {
  const AppSegment({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;

  /// Null shows the segment disabled.
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // Stadium ends match the control's own; the outline sits on top of the
    // control's border on the sides it shares.
    final shape = StadiumBorder(
      side: selected
          ? BorderSide(color: c.chipOn, width: AppSegmentedButton.outlineWidth)
          : BorderSide.none,
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: onTap != null,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? c.chipOn : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSegmentedButton.minHeight,
            ),
            child: Center(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: onTap == null
                      ? c.muted
                      : selected
                      ? c.onChipOn
                      : c.ink2,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: 18,
                    color: onTap == null
                        ? c.muted
                        : selected
                        ? c.onChipOn
                        : c.ink2,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: child,
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

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.selected,
    required this.icon,
    required this.label,
  });

  final bool selected;
  final Widget? icon;
  final Widget? label;

  @override
  Widget build(BuildContext context) {
    final text = label == null
        ? null
        : DefaultTextStyle.merge(
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            child: label!,
          );
    if (icon == null) return text ?? const SizedBox.shrink();
    if (text == null) return icon!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon!,
        const SizedBox(width: 6),
        Flexible(child: text),
      ],
    );
  }
}
