import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A headline whose lines are about even, like CSS `text-wrap: balance`:
/// it wraps at the narrowest width that still fits in the same number of
/// lines, so the last line is never a lone word. Start-aligned.
class BalancedText extends StatelessWidget {
  const BalancedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(this.style);
    return _Balance(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      child: Text(text, style: style),
    );
  }
}

class _Balance extends SingleChildRenderObjectWidget {
  const _Balance({
    required this.text,
    required this.textDirection,
    required this.textScaler,
    required super.child,
  });

  final TextSpan text;
  final TextDirection textDirection;
  final TextScaler textScaler;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBalance(text, textDirection, textScaler);

  @override
  void updateRenderObject(BuildContext context, _RenderBalance render) {
    render
      ..text = text
      ..textDirection = textDirection
      ..textScaler = textScaler;
  }
}

class _RenderBalance extends RenderProxyBox {
  _RenderBalance(TextSpan text, TextDirection direction, TextScaler scaler)
    : _painter = TextPainter(
        text: text,
        textDirection: direction,
        textScaler: scaler,
      );

  final TextPainter _painter;

  set text(TextSpan value) {
    if (_painter.text == value) return;
    _painter.text = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (_painter.textDirection == value) return;
    _painter.textDirection = value;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (_painter.textScaler == value) return;
    _painter.textScaler = value;
    markNeedsLayout();
  }

  int _lines(double width) {
    _painter.layout(maxWidth: width);
    return _painter.computeLineMetrics().length;
  }

  /// The narrowest width that keeps the line count it has at [max].
  double _balancedWidth(double max) {
    if (!max.isFinite) return max;
    final lines = _lines(max);
    if (lines <= 1) return max;
    var lo = max / lines * 0.8;
    var hi = max;
    for (var i = 0; i < 12 && hi - lo > 1; i++) {
      final mid = (lo + hi) / 2;
      if (_lines(mid) > lines) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return math.min(max, hi.ceilToDouble() + 1);
  }

  BoxConstraints _childConstraints(BoxConstraints c) => BoxConstraints(
    maxWidth: _balancedWidth(c.maxWidth),
    minHeight: c.minHeight,
    maxHeight: c.maxHeight,
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(
      child.getDryLayout(_childConstraints(constraints)),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
