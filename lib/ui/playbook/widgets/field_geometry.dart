import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/models/play.dart';

/// Maps normalized [FieldPoint]s to canvas pixels and back.
///
/// The stored field is portrait: x spans the 40 yd width, y spans the
/// 110 yd length (20 yd endzones + 70 yd playing field). When [horizontal]
/// is true the field is drawn rotated to fill landscape screens.
class FieldGeometry {
  FieldGeometry(this.size, {required this.horizontal});

  static const widthYards = 40.0;
  static const lengthYards = 110.0;
  static const endzoneYards = 20.0;
  static const brickYards = 20.0;

  /// Width / length.
  static const aspect = widthYards / lengthYards;

  final Size size;
  final bool horizontal;

  double get shortSide => math.min(size.width, size.height);

  double get elementRadius => math.max(9, shortSide * 0.04);

  Offset toCanvas(FieldPoint p) => horizontal
      ? Offset(p.y * size.width, p.x * size.height)
      : Offset(p.x * size.width, p.y * size.height);

  FieldPoint toField(Offset o) => horizontal
      ? FieldPoint(o.dy / size.height, o.dx / size.width)
      : FieldPoint(o.dx / size.width, o.dy / size.height);

  /// Id of the element or arrow under [o], elements first.
  String? hitTest(Play play, Offset o) {
    final r = elementRadius * 1.3;
    for (final e in play.elements.reversed) {
      if ((toCanvas(e.position) - o).distance <= r) return e.id;
    }
    final tolerance = math.max(10.0, elementRadius * 0.8);
    for (final a in play.arrows.reversed) {
      for (var i = 0; i < a.points.length - 1; i++) {
        final d = _distanceToSegment(
          o,
          toCanvas(a.points[i]),
          toCanvas(a.points[i + 1]),
        );
        if (d <= tolerance) return a.id;
      }
    }
    return null;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }
}
