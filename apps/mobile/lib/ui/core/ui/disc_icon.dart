import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A flying disc drawn in the outlined style of Material's rounded icons,
/// for places an `Icon` would go (notifications use it instead of a
/// bell). Like [Icon], it takes its size and colour from the surrounding
/// [IconTheme] unless given.
class DiscIcon extends StatelessWidget {
  const DiscIcon({super.key, this.size, this.color, this.semanticLabel});

  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final paint = color ?? theme.color ?? Colors.black;
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: s,
          child: CustomPaint(painter: _DiscPainter(paint)),
        ),
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  _DiscPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round;

    // The disc, tilted as if in flight, right of centre to leave room
    // for the motion lines.
    canvas.save();
    canvas.translate(s * 0.58, s * 0.5);
    canvas.rotate(-math.pi / 10);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: s * 0.76, height: s * 0.5),
      stroke,
    );
    // The rim's inner edge, along the near side of the disc.
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(0, -s * 0.04),
        width: s * 0.46,
        height: s * 0.24,
      ),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      stroke,
    );
    canvas.restore();

    // Motion lines trailing to the left.
    canvas.drawLine(
      Offset(s * 0.05, s * 0.44),
      Offset(s * 0.13, s * 0.44),
      stroke,
    );
    canvas.drawLine(
      Offset(s * 0.08, s * 0.62),
      Offset(s * 0.17, s * 0.62),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.color != color;
}
