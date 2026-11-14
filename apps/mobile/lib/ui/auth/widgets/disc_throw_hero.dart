import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';

/// The website's palette: a Midnight sky over an indigo field, and an
/// amber disc.
abstract final class _Palette {
  static const skyTop = Color(0xFF121521);
  static const field = Color(0xFF3B3290);
  static const fieldDeep = Color(0xFF2C2570);
  static const chalk = Color(0xFFF3F5FB);
  static const disc = Color(0xFFF0D8A8);
  static const discRim = Color(0xFFB98A3E);
  static const discLine = Color(0xFFC99D54);
}

/// The background colour at the bottom of the hero, for whatever sits
/// against it.
const discHeroBottomColor = _Palette.fieldDeep;

/// Where each part of the animation happens, as fractions of its length.
abstract final class DiscThrowTimeline {
  static const flight = Interval(0, 0.62, curve: Curves.easeOutCubic);
  static const flipUp = Interval(0.56, 0.78, curve: Curves.easeOutBack);
  static const oneIn = Interval(0.68, 0.86, curve: Curves.easeOutCubic);
  static const tagline = Interval(0.78, 1, curve: Curves.easeOut);
  static const form = Interval(0.5, 0.95, curve: Curves.easeOutCubic);

  /// The stall count while the disc flies: 1 to 9, then 10 on the catch.
  static int stall(double t) {
    if (t >= flipUp.begin + 0.06) return 10;
    final f = (t / flight.end).clamp(0.0, 1.0);
    return 1 + (f * 8.999).floor();
  }
}

/// The disc's size and where it's caught, for a hero of [size]. The
/// wordmark sits just below the caught disc.
({double radius, double landY, double belowDisc}) discThrowGeometry(Size size) {
  final r = math.min(96.0, math.min(size.width * 0.16, size.height * 0.19));
  final landY = size.height * 0.4;
  return (radius: r, landY: landY, belowDisc: landY + r * 1.12);
}

/// A disc thrown across an ultimate field that is caught as the "0" of the
/// Stall 10 logo, while the wordmark counts the stall. Driven by
/// [animation] (0 to 1); tap it to throw again with [onReplay].
class DiscThrowHero extends StatelessWidget {
  const DiscThrowHero({super.key, required this.animation, this.onReplay});

  final Animation<double> animation;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onReplay,
      child: Semantics(
        label: '$appName logo',
        image: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(painter: DiscThrowPainter(animation)),
            ),
            LayoutBuilder(
              builder: (context, box) {
                final g = discThrowGeometry(box.biggest);
                return Stack(
                  children: [
                    Positioned(
                      left: 24,
                      right: 24,
                      // Just under the disc, but never off the bottom.
                      top: math.min(g.belowDisc + 26, box.maxHeight - 76),
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) => _Wordmark(t: animation.value),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final n = DiscThrowTimeline.stall(t);
    final caught = n == 10;
    final tagline = DiscThrowTimeline.tagline.transform(t);
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Stall '),
                TextSpan(
                  text: '$n',
                  style: const TextStyle(color: _Palette.disc),
                ),
              ],
            ),
            style: TextStyle(
              fontFamily: appFont,
              fontWeight: FontWeight.w800,
              fontSize: caught ? 30 : 26,
              letterSpacing: -0.8,
              height: 1.1,
              color: _Palette.chalk.withValues(alpha: caught ? 1 : 0.75),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Opacity(
            opacity: tagline,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - tagline)),
              child: Text(
                'Your team, from the pull to the final point.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: appFont,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: _Palette.chalk.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the field, the disc's flight with its shadow and streaks, and the
/// "10" it becomes.
class DiscThrowPainter extends CustomPainter {
  DiscThrowPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static Offset _bezier(Offset a, Offset b, Offset c, Offset d, double s) {
    final m = 1 - s;
    return a * (m * m * m) +
        b * (3 * m * m * s) +
        c * (3 * m * s * s) +
        d * (s * s * s);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final w = size.width;
    final h = size.height;
    final g = discThrowGeometry(size);
    final r = g.radius;

    final flipUp = DiscThrowTimeline.flipUp.transform(t);
    final oneIn = DiscThrowTimeline.oneIn.transform(t);

    // Where the "10" ends up: centred, a little above the middle to leave
    // room for the wordmark.
    final finalRx = r * 0.82;
    final finalRy = r * 1.12;
    final one = _onePainter(finalRy);
    final groupWidth = one.width + finalRx * 1.85;
    final groupLeft = (w - groupWidth) / 2;
    final land = Offset(groupLeft + one.width + finalRx * 0.88, g.landY);

    // A big hook: out from the bottom right, up and away, round the left
    // and in to the catch from below, like the logo's streaks.
    final p0 = Offset(w * 1.1, h * 0.88);
    final p1 = Offset(w * 0.6, -h * 0.3);
    final p2 = Offset(-w * 0.3, h * 0.62);
    Offset at(double s) => _bezier(p0, p1, p2, land, s);
    double flightAt(double time) =>
        DiscThrowTimeline.flight.transform(time.clamp(0.0, 1.0));
    double depth(double s) =>
        lerpDouble(1.35, 1, s)! * (1 - 0.45 * math.sin(math.pi * s));

    _paintBackground(canvas, size);
    _paintField(canvas, size);

    // A soft glow where the disc is caught.
    if (flipUp > 0) {
      canvas.drawCircle(
        land,
        r * 2.6,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _Palette.disc.withValues(alpha: 0.16 * flipUp.clamp(0, 1)),
              _Palette.disc.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: land, radius: r * 2.6)),
      );
    }

    final s = flightAt(t);
    final pos = at(s);
    final scale = depth(s);

    // Shadow on the grass, falling away as the disc is caught.
    final shadowAlpha = 0.35 * (1 - flipUp.clamp(0.0, 1.0)) * (s > 0 ? 1 : 0);
    if (shadowAlpha > 0.01) {
      final altitude = h * (0.08 + 0.2 * math.sin(math.pi * s));
      canvas.drawOval(
        Rect.fromCenter(
          center: pos + Offset(r * 0.2 * scale, altitude),
          width: r * 2 * scale,
          height: r * 0.5 * scale,
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: shadowAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Motion streaks: where the disc was a moment ago. They fade as it's
    // caught.
    final streakFade = 1 - flipUp.clamp(0.0, 1.0);
    if (streakFade > 0.01 && s > 0) {
      _paintStreaks(
        canvas,
        [for (var k = 0; k <= 40; k++) at(flightAt(t - k * 0.0065))],
        r,
        fade: streakFade,
      );
    }

    // The "1" slides in next to the caught disc.
    if (oneIn > 0) {
      final baseline = one.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      final capCenter = baseline - one.text!.style!.fontSize! * 0.3635;
      canvas.saveLayer(
        null,
        Paint()..color = Colors.white.withValues(alpha: oneIn.clamp(0, 1)),
      );
      one.paint(
        canvas,
        Offset(groupLeft - r * 0.6 * (1 - oneIn), land.dy - capCenter),
      );
      canvas.restore();
    }

    if (s > 0) {
      final u = flipUp.clamp(0.0, 1.15);
      final bank = lerpDouble(0.3, -0.25, s)! + 0.25 * math.sin(math.pi * s);
      _paintDisc(
        canvas,
        center: pos,
        rx: lerpDouble(r * 1.05 * scale, finalRx, u)!,
        ry: lerpDouble(r * 0.34 * scale, finalRy, u)!,
        rotation: lerpDouble(bank, -0.42, u.clamp(0, 1))!,
        hole: lerpDouble(0, 0.6, ((u - 0.15) / 0.85).clamp(0, 1))!,
        spin: t * 26,
        spinMarks: 1 - u.clamp(0.0, 1.0),
      );
    }
  }

  TextPainter _onePainter(double ry) => TextPainter(
    text: TextSpan(
      text: '1',
      style: TextStyle(
        fontFamily: appFont,
        fontWeight: FontWeight.w800,
        // The cap height (0.727 em in Inter) matches the disc's height.
        fontSize: ry * 2 / 0.727,
        height: 1,
        color: _Palette.chalk,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_Palette.skyTop, _Palette.field, _Palette.fieldDeep],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
  }

  /// An ultimate field in perspective: mowing stripes, sidelines and the
  /// goal line. (No brick mark: it fell right behind the tagline.)
  void _paintField(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizon = h * 0.22;
    const far = 3.2;
    Offset project(double u, double v) {
      final z = 1 + v * far;
      return Offset(
        w / 2 + (u - 0.5) * w * 1.5 / z,
        horizon + (h - horizon) / z,
      );
    }

    Path quad(double u0, double u1, double v0, double v1) => Path()
      ..moveTo(project(u0, v0).dx, project(u0, v0).dy)
      ..lineTo(project(u1, v0).dx, project(u1, v0).dy)
      ..lineTo(project(u1, v1).dx, project(u1, v1).dy)
      ..lineTo(project(u0, v1).dx, project(u0, v1).dy)
      ..close();

    // Mowing stripes.
    const bands = 10;
    for (var i = 0; i < bands; i += 2) {
      canvas.drawPath(
        quad(-0.6, 1.6, i / bands, (i + 1) / bands),
        Paint()..color = Colors.white.withValues(alpha: 0.025),
      );
    }

    final chalk = Paint()
      ..color = _Palette.chalk.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // Sidelines and the far back line.
    for (final u in [0.0, 1.0]) {
      canvas.drawLine(project(u, 0), project(u, 1), chalk);
    }
    canvas.drawLine(project(0, 1), project(1, 1), chalk);
    // The goal line.
    canvas.drawLine(project(0, 0.55), project(1, 0.55), chalk);

    // Fade the field into the dark at the horizon.
    final fadeRect = Rect.fromLTWH(0, 0, w, project(0, 1).dy + h * 0.08);
    canvas.drawRect(
      fadeRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_Palette.skyTop, Color(0x00121521)],
        ).createShader(fadeRect),
    );
  }

  /// Three streaks along [points] (newest first), tapering as they go.
  void _paintStreaks(
    Canvas canvas,
    List<Offset> points,
    double r, {
    required double fade,
  }) {
    for (final lane in [-1.0, 0.0, 1.0]) {
      for (var i = 0; i < points.length - 1; i++) {
        final a = points[i];
        final b = points[i + 1];
        final d = b - a;
        final len = d.distance;
        if (len < 0.5) continue;
        final normal = Offset(-d.dy / len, d.dx / len) * (lane * r * 0.22);
        final f = 1 - i / (points.length - 1);
        canvas.drawLine(
          a + normal,
          b + normal,
          Paint()
            ..color = _Palette.disc.withValues(
              alpha: 0.55 * f * fade * (lane == 0 ? 1 : 0.7),
            )
            ..strokeWidth = (lane == 0 ? 3.2 : 2) * f + 0.4
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  /// The disc: a flat spinning ellipse in flight, a tilted ring (the logo's
  /// "0") once [hole] opens. Drawn with a darker rim behind it for depth.
  void _paintDisc(
    Canvas canvas, {
    required Offset center,
    required double rx,
    required double ry,
    required double rotation,
    required double hole,
    required double spin,
    required double spinMarks,
  }) {
    Path ring(Offset c) {
      final p = Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCenter(center: c, width: rx * 2, height: ry * 2));
      if (hole > 0.01) {
        p.addOval(
          Rect.fromCenter(
            center: c + Offset(rx * 0.06, ry * 0.04),
            width: rx * 2 * hole,
            height: ry * 2 * hole,
          ),
        );
      }
      return p;
    }

    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(rotation);
    final depthOffset = Offset(rx * 0.1, ry * 0.08 + 2);
    canvas.drawPath(ring(depthOffset), Paint()..color = _Palette.discRim);
    final face = ring(Offset.zero);
    canvas.drawPath(
      face,
      Paint()
        ..shader =
            const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFBEFD6), _Palette.disc, Color(0xFFDDB878)],
              stops: [0, 0.35, 1],
            ).createShader(
              Rect.fromCenter(
                center: Offset.zero,
                width: rx * 2,
                height: ry * 2,
              ),
            ),
    );
    // The flight ring moulded into the top of the disc.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: rx * 2 * lerpDouble(0.82, 0.8, hole)!,
        height: ry * 2 * lerpDouble(0.82, 0.8, hole)!,
      ),
      Paint()
        ..color = _Palette.discLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, rx * 0.025),
    );
    // Spin: a glint and a mark going round the rim.
    if (spinMarks > 0.01) {
      final rim = Rect.fromCenter(
        center: Offset.zero,
        width: rx * 1.8,
        height: ry * 1.8,
      );
      canvas
        ..drawArc(
          rim,
          spin,
          0.9,
          false,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.75 * spinMarks)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(1.5, ry * 0.12),
        )
        ..drawArc(
          rim,
          spin + math.pi,
          0.5,
          false,
          Paint()
            ..color = _Palette.discRim.withValues(alpha: 0.8 * spinMarks)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(1.5, ry * 0.1),
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DiscThrowPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
