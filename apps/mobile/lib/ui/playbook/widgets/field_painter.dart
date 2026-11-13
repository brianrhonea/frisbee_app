import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../domain/models/play.dart';
import '../../core/themes/theme.dart';
import '../view_models/play_editor_viewmodel.dart' show Trail;
import 'field_geometry.dart';

/// Paints an ultimate field with a play diagram on top.
class FieldPainter extends CustomPainter {
  FieldPainter({
    required this.play,
    required this.horizontal,
    this.selectedId,
    this.draft = const [],
    this.draftKind,
    this.trails = const [],
    this.ghosts = const [],
  });

  final Play play;
  final bool horizontal;
  final String? selectedId;

  /// In-progress arrow being drawn.
  final List<FieldPoint> draft;
  final ArrowKind? draftKind;

  /// Movement paths of the current animation step.
  final List<Trail> trails;

  /// Faded elements marking where movers started the step.
  final List<PlayElement> ghosts;

  @override
  void paint(Canvas canvas, Size size) {
    final g = FieldGeometry(size, horizontal: horizontal);
    _paintField(canvas, g);
    if (ghosts.isNotEmpty) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = const Color.fromRGBO(0, 0, 0, 0.35),
      );
      for (final e in ghosts) {
        _paintElement(canvas, g, e, selected: false);
      }
      canvas.restore();
    }
    for (final t in trails) {
      if (t.points.length < 2) continue;
      _paintArrow(
        canvas,
        g,
        t.kind == ElementKind.disc ? ArrowKind.throw_ : ArrowKind.cut,
        t.points,
        selected: false,
        color: _trailColor(t.kind),
      );
    }
    for (final a in play.arrows) {
      _paintArrow(canvas, g, a.kind, a.points, selected: a.id == selectedId);
    }
    if (draftKind != null && draft.length > 1) {
      _paintArrow(canvas, g, draftKind!, draft, selected: false);
    }
    for (final e in play.elements) {
      _paintElement(canvas, g, e, selected: e.id == selectedId);
    }
  }

  void _paintField(Canvas canvas, FieldGeometry g) {
    final rect = Offset.zero & g.size;
    canvas.drawRect(rect, Paint()..color = FieldColors.grass);

    const ez = FieldGeometry.endzoneYards / FieldGeometry.lengthYards;
    final endzonePaint = Paint()..color = FieldColors.endzone;
    canvas.drawRect(_band(g, 0, ez), endzonePaint);
    canvas.drawRect(_band(g, 1 - ez, 1), endzonePaint);

    final line = Paint()
      ..color = FieldColors.lines
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, g.shortSide * 0.006);
    canvas.drawRect(rect.deflate(line.strokeWidth / 2), line);
    for (final y in [ez, 1 - ez]) {
      canvas.drawLine(
        g.toCanvas(FieldPoint(0, y)),
        g.toCanvas(FieldPoint(1, y)),
        line,
      );
    }

    // Brick marks: 20 yd from each goal line, centered.
    const brick =
        (FieldGeometry.endzoneYards + FieldGeometry.brickYards) /
        FieldGeometry.lengthYards;
    final mark = g.shortSide * 0.02;
    for (final y in [brick, 1 - brick]) {
      final c = g.toCanvas(FieldPoint(0.5, y));
      canvas.drawLine(c - Offset(mark, mark), c + Offset(mark, mark), line);
      canvas.drawLine(c - Offset(mark, -mark), c + Offset(mark, -mark), line);
    }
  }

  Rect _band(FieldGeometry g, double y0, double y1) => Rect.fromPoints(
    g.toCanvas(FieldPoint(0, y0)),
    g.toCanvas(FieldPoint(1, y1)),
  );

  static Color _trailColor(ElementKind kind) => switch (kind) {
    ElementKind.offense => const Color(0xFF90CAF9),
    ElementKind.defense => const Color(0xFFEF9A9A),
    ElementKind.disc => FieldColors.throwLine,
    ElementKind.cone => FieldColors.cone,
  };

  void _paintArrow(
    Canvas canvas,
    FieldGeometry g,
    ArrowKind kind,
    List<FieldPoint> points, {
    required bool selected,
    Color? color,
  }) {
    final pts = points.map(g.toCanvas).toList();
    color ??= kind == ArrowKind.cut ? FieldColors.cut : FieldColors.throwLine;
    final width = math.max(2.0, g.shortSide * 0.008);

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      // Smooth freehand cuts with quadratic segments through midpoints.
      if (i < pts.length - 1) {
        final mid = (pts[i] + pts[i + 1]) / 2;
        path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
      } else {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
    }

    if (selected) {
      canvas.drawPath(
        path,
        Paint()
          ..color = FieldColors.selection.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 3
          ..strokeCap = StrokeCap.round,
      );
    }

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      kind == ArrowKind.throw_ ? _dashed(path, width * 4, width * 3) : path,
      stroke,
    );

    // Arrowhead aligned with the final segment.
    final tip = pts.last;
    var from = pts[pts.length - 2];
    for (var i = pts.length - 2; i >= 0 && (tip - from).distance < 4; i--) {
      from = pts[i];
    }
    final angle = (tip - from).direction;
    final head = width * 4.5;
    final arrowHead = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - head * math.cos(angle - 0.45),
        tip.dy - head * math.sin(angle - 0.45),
      )
      ..lineTo(
        tip.dx - head * math.cos(angle + 0.45),
        tip.dy - head * math.sin(angle + 0.45),
      )
      ..close();
    canvas.drawPath(arrowHead, Paint()..color = color);
  }

  Path _dashed(Path source, double dash, double gap) {
    final out = Path();
    for (final ui.PathMetric m in source.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        out.addPath(
          m.extractPath(d, math.min(d + dash, m.length)),
          Offset.zero,
        );
        d += dash + gap;
      }
    }
    return out;
  }

  void _paintElement(
    Canvas canvas,
    FieldGeometry g,
    PlayElement e, {
    required bool selected,
  }) {
    final c = g.toCanvas(e.position);
    final r = g.elementRadius;

    if (selected) {
      canvas.drawCircle(
        c,
        r * 1.45,
        Paint()..color = FieldColors.selection.withValues(alpha: 0.6),
      );
    }

    switch (e.kind) {
      case ElementKind.offense || ElementKind.defense:
        final fill = e.kind == ElementKind.offense
            ? FieldColors.offense
            : FieldColors.defense;
        canvas.drawCircle(c, r, Paint()..color = fill);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, r * 0.15),
        );
        _paintLabel(canvas, c, r, e.label);
      case ElementKind.disc:
        final dr = r * 0.6;
        canvas.drawCircle(c, dr, Paint()..color = FieldColors.disc);
        canvas.drawCircle(
          c,
          dr * 0.6,
          Paint()
            ..color = Colors.black26
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      case ElementKind.cone:
        final h = r * 1.1;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - h)
            ..lineTo(c.dx + h * 0.8, c.dy + h * 0.7)
            ..lineTo(c.dx - h * 0.8, c.dy + h * 0.7)
            ..close(),
          Paint()..color = FieldColors.cone,
        );
    }
  }

  void _paintLabel(Canvas canvas, Offset c, double r, String label) {
    if (label.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: r * 1.0,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(FieldPainter old) =>
      old.play != play ||
      old.horizontal != horizontal ||
      old.selectedId != selectedId ||
      old.draft != draft ||
      old.draftKind != draftKind ||
      old.trails != trails ||
      old.ghosts != ghosts;
}
