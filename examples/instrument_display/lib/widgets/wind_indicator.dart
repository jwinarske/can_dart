import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';

/// Professional marine wind angle indicator with metallic bezel,
/// port/starboard colour sectors, graduated scale, boat hull at centre,
/// wind arrow with glow, and speed/angle readouts.
class WindIndicator extends StatelessWidget {
  const WindIndicator({
    super.key,
    required this.angleDeg,
    required this.speedKts,
  });

  final double angleDeg;
  final double speedKts;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 240,
      child: CustomPaint(
        painter: _WindPainter(angleDeg: angleDeg, speedKts: speedKts),
      ),
    );
  }
}

class _WindPainter extends CustomPainter {
  _WindPainter({required this.angleDeg, required this.speedKts});

  final double angleDeg;
  final double speedKts;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.width / 2;
    final center = Offset(cx, cy);
    final outerRadius = cx - 6;
    final bezelWidth = 6.0;
    final innerRadius = outerRadius - bezelWidth;

    _drawBezel(canvas, center, outerRadius, innerRadius, bezelWidth);
    _drawPortStarboardSectors(canvas, center, innerRadius);
    _drawTicks(canvas, center, innerRadius);
    _drawScaleLabels(canvas, center, innerRadius);
    _drawBoat(canvas, center);
    _drawWindArrow(canvas, center, innerRadius);
    _drawSpeedDisplay(canvas, center);
    _drawAngleReadout(canvas, cx, cy + outerRadius + 10);
  }

  void _drawBezel(
    Canvas canvas,
    Offset center,
    double outer,
    double inner,
    double width,
  ) {
    final bezelPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        outer,
        [
          MaritimePalette.brass,
          MaritimePalette.consoleBorder,
          const Color(0xFF0F1A2A),
          MaritimePalette.consoleBorder,
          MaritimePalette.brass,
        ],
        [0.0, 0.3, 0.5, 0.7, 1.0],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawCircle(center, (outer + inner) / 2, bezelPaint);

    // Thin bright highlight on outer edge
    final highlightPaint = Paint()
      ..color = MaritimePalette.brassBright.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawCircle(center, outer, highlightPaint);
  }

  void _drawPortStarboardSectors(Canvas canvas, Offset center, double radius) {
    // Very subtle colour sectors — starboard (right/green) and port (left/red)
    // 0 deg = bow (top), angle measured clockwise
    // Starboard: 0-180 (right side), Port: 180-360 (left side)
    final sectorRadius = radius - 1;

    canvas.save();
    // Starboard (green) — right half: from -90deg to +90deg in canvas coords
    // That's from top (0 wind) clockwise to 180 wind
    final stbdPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: sectorRadius),
        -pi / 2, // start at top
        pi, // sweep 180 deg clockwise
        false,
      )
      ..close();
    canvas.drawPath(
      stbdPath,
      Paint()..color = MaritimePalette.starboardGreen.withValues(alpha: 0.06),
    );

    // Port (red) — left half
    final portPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: sectorRadius),
        pi / 2, // start at bottom
        pi, // sweep 180 deg clockwise (left half)
        false,
      )
      ..close();
    canvas.drawPath(
      portPath,
      Paint()..color = MaritimePalette.portRed.withValues(alpha: 0.06),
    );
    canvas.restore();

    // Dark inner fill on top (semi-transparent to let sectors show through)
    final fillPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [MaritimePalette.deepHull.withValues(alpha: 0.7), Colors.transparent],
        [0.0, 0.7],
      )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, sectorRadius, fillPaint);
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    for (var deg = 0; deg < 360; deg += 10) {
      final rad = deg * pi / 180 - pi / 2;
      final outerR = radius - 1;
      double innerR;
      Paint tickPaint;

      if (deg % 30 == 0) {
        innerR = outerR - 12;
        tickPaint = Paint()
          ..color = MaritimePalette.foam
          ..strokeWidth = 2;
      } else {
        innerR = outerR - 6;
        tickPaint = Paint()
          ..color = MaritimePalette.foamDim
          ..strokeWidth = 1;
      }

      final outer = center + Offset(cos(rad) * outerR, sin(rad) * outerR);
      final inner = center + Offset(cos(rad) * innerR, sin(rad) * innerR);
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  void _drawScaleLabels(Canvas canvas, Offset center, double radius) {
    final labelRadius = radius - 18;
    // Labels at 0, 30, 60, 90, 120, 150, 180 on both sides (mirrored)
    const majorAngles = [0, 30, 60, 90, 120, 150, 180];

    for (final deg in majorAngles) {
      // Right side (starboard)
      _drawAngleLabel(canvas, center, labelRadius, deg);
      // Left side (port) — mirror, skip 0 and 180 (already drawn)
      if (deg != 0 && deg != 180) {
        _drawAngleLabel(canvas, center, labelRadius, 360 - deg);
      }
    }
  }

  void _drawAngleLabel(Canvas canvas, Offset center, double radius, int deg) {
    final rad = deg * pi / 180 - pi / 2;
    final pos = center + Offset(cos(rad) * radius, sin(rad) * radius);

    // For display, show the effective angle (0-180)
    final displayDeg = deg <= 180 ? deg : 360 - deg;
    final tp = TextPainter(
      text: TextSpan(
        text: '$displayDeg',
        style: const TextStyle(color: MaritimePalette.foamDim, fontSize: 8),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawBoat(Canvas canvas, Offset center) {
    // Hull shape — pointed bow, curved sides, flat transom
    final boatPath = Path()
      ..moveTo(center.dx, center.dy - 22) // bow tip
      ..quadraticBezierTo(
        center.dx - 4,
        center.dy - 12,
        center.dx - 10,
        center.dy + 6,
      )
      ..quadraticBezierTo(
        center.dx - 11,
        center.dy + 14,
        center.dx - 8,
        center.dy + 18,
      )
      ..lineTo(center.dx + 8, center.dy + 18) // transom
      ..quadraticBezierTo(
        center.dx + 11,
        center.dy + 14,
        center.dx + 10,
        center.dy + 6,
      )
      ..quadraticBezierTo(
        center.dx + 4,
        center.dy - 12,
        center.dx,
        center.dy - 22,
      )
      ..close();

    // Fill
    canvas.drawPath(
      boatPath,
      Paint()
        ..color = MaritimePalette.midHull
        ..style = PaintingStyle.fill,
    );
    // Outline
    canvas.drawPath(
      boatPath,
      Paint()
        ..color = MaritimePalette.brass
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Keel line
    canvas.drawLine(
      Offset(center.dx, center.dy - 18),
      Offset(center.dx, center.dy + 14),
      Paint()
        ..color = MaritimePalette.brass.withValues(alpha: 0.3)
        ..strokeWidth = 0.5,
    );
  }

  void _drawWindArrow(Canvas canvas, Offset center, double radius) {
    final windRad = angleDeg * pi / 180 - pi / 2;

    // Arrow shaft from outer ring toward boat
    final shaftStart =
        center +
        Offset(cos(windRad) * (radius - 14), sin(windRad) * (radius - 14));
    final shaftEnd = center + Offset(cos(windRad) * 28, sin(windRad) * 28);

    // Glow layer
    final glowPaint = Paint()
      ..color = MaritimePalette.foam
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawLine(shaftStart, shaftEnd, glowPaint);

    // Sharp shaft
    final shaftPaint = Paint()
      ..color = MaritimePalette.foam
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(shaftStart, shaftEnd, shaftPaint);

    // Arrowhead at tip (near boat)
    final headAngle = atan2(
      shaftEnd.dy - shaftStart.dy,
      shaftEnd.dx - shaftStart.dx,
    );
    final headLen = 12.0;
    final h1 =
        shaftEnd -
        Offset(cos(headAngle - 0.4) * headLen, sin(headAngle - 0.4) * headLen);
    final h2 =
        shaftEnd -
        Offset(cos(headAngle + 0.4) * headLen, sin(headAngle + 0.4) * headLen);
    final headPath = Path()
      ..moveTo(shaftEnd.dx, shaftEnd.dy)
      ..lineTo(h1.dx, h1.dy)
      ..lineTo(h2.dx, h2.dy)
      ..close();

    // Glow arrowhead
    canvas.drawPath(
      headPath,
      Paint()
        ..color = MaritimePalette.foam
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Sharp arrowhead
    canvas.drawPath(
      headPath,
      Paint()
        ..color = MaritimePalette.foam
        ..style = PaintingStyle.fill,
    );
  }

  void _drawSpeedDisplay(Canvas canvas, Offset center) {
    // Speed value — large, centered in the boat area
    final speedStr = speedKts.toStringAsFixed(1);
    final speedTp = TextPainter(
      text: TextSpan(
        text: speedStr,
        style: const TextStyle(
          color: MaritimePalette.foam,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFeatures: kTabular,
          shadows: [Shadow(color: MaritimePalette.foam, blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    speedTp.paint(canvas, Offset(center.dx - speedTp.width / 2, center.dy - 4));

    // Unit label
    final unitTp = TextPainter(
      text: const TextSpan(
        text: 'kts',
        style: TextStyle(color: MaritimePalette.foamDim, fontSize: 8),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitTp.paint(canvas, Offset(center.dx - unitTp.width / 2, center.dy + 12));
  }

  void _drawAngleReadout(Canvas canvas, double cx, double top) {
    // Determine port or starboard
    final normalAngle = angleDeg % 360;
    final isStarboard = normalAngle >= 0 && normalAngle <= 180;
    final displayAngle = isStarboard ? normalAngle : 360 - normalAngle;
    final sideLabel = isStarboard ? 'STBD' : 'PORT';

    final text =
        'AWA ${displayAngle.toStringAsFixed(0).padLeft(3, '0')}\u00B0 $sideLabel';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: MaritimePalette.brassBright,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFeatures: kTabular,
          shadows: [Shadow(color: MaritimePalette.brassBright, blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, top));
  }

  @override
  bool shouldRepaint(_WindPainter old) =>
      old.angleDeg != angleDeg || old.speedKts != speedKts;
}
