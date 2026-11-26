import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../themes/theme.dart';

/// A [SegmentedButton] whose selected segments also get an indigo
/// ([AppColors.accent]) outline.
///
/// The selected fill alone ([AppColors.accentSoft]) is about 1.1:1 against
/// its neighbours; Material draws one outline for the whole control and no
/// per-segment one, so this paints it over the segments. The check icon,
/// colours and everything else are the [SegmentedButton]'s (see
/// `segmentedButtonTheme` in the app theme).
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
    this.style,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool multiSelectionEnabled;
  final bool emptySelectionAllowed;
  final bool showSelectedIcon;
  final EdgeInsets? expandedInsets;
  final ButtonStyle? style;

  /// Width of the selected outline.
  static const outlineWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return _SelectedOutline(
      selected: [for (final s in segments) selected.contains(s.value)],
      color: c.accent,
      child: SegmentedButton<T>(
        segments: segments,
        selected: selected,
        onSelectionChanged: onSelectionChanged,
        multiSelectionEnabled: multiSelectionEnabled,
        emptySelectionAllowed: emptySelectionAllowed,
        showSelectedIcon: showSelectedIcon,
        expandedInsets: expandedInsets,
        style: style,
      ),
    );
  }
}

class _SelectedOutline extends SingleChildRenderObjectWidget {
  const _SelectedOutline({
    required this.selected,
    required this.color,
    required super.child,
  });

  final List<bool> selected;
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSelectedOutline(selected, color);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSelectedOutline renderObject,
  ) {
    renderObject
      ..selected = selected
      ..color = color;
  }
}

class _RenderSelectedOutline extends RenderProxyBox {
  _RenderSelectedOutline(this._selected, this._color);

  List<bool> _selected;
  Color _color;

  set selected(List<bool> value) {
    _selected = value;
    markNeedsPaint();
  }

  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  /// The segment buttons: the first descendant with exactly one child per
  /// segment (the SegmentedButton's own render object).
  RenderBox? _findSegments(RenderObject from) {
    RenderBox? found;
    void visit(RenderObject node) {
      if (found != null) return;
      var count = 0;
      node.visitChildren((_) => count++);
      if (node is RenderBox && count == _selected.length && count > 1) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    from.visitChildren(visit);
    return found;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final row = _findSegments(this);
    if (row == null) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppSegmentedButton.outlineWidth
      ..color = _color;
    var i = 0;
    row.visitChildren((child) {
      final index = i++;
      if (index >= _selected.length || !_selected[index]) return;
      final box = child as RenderBox;
      final origin = MatrixUtils.transformPoint(
        box.getTransformTo(this),
        Offset.zero,
      );
      // Inset by half the stroke so the line sits inside the control.
      final rect = (offset + origin & box.size).deflate(
        AppSegmentedButton.outlineWidth / 2,
      );
      final r = Radius.circular(rect.height / 2);
      final first = index == 0;
      final last = index == _selected.length - 1;
      context.canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: first ? r : Radius.zero,
          bottomLeft: first ? r : Radius.zero,
          topRight: last ? r : Radius.zero,
          bottomRight: last ? r : Radius.zero,
        ),
        paint,
      );
    });
  }
}
