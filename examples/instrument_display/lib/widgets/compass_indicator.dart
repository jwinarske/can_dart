import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';

/// Professional marine compass heading indicator with metallic bezel,
/// graduated scale, cardinal labels, heading pointer with glow, lubber line,
/// and ship outline at centre.
class CompassIndicator extends StatelessWidget {
  const CompassIndicator({super.key, required this.headingDeg});

  final double headingDeg;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 240,
      child: CustomPaint(painter: _CompassPainter(headingDeg: headingDeg)),
    );
  }
}

class _CompassPainter extends CustomPainter {
  _CompassPainter({required this.headingDeg});

  final double headingDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    // Shift compass centre up to leave room for readout below
    final cy = size.width / 2;
    final center = Offset(cx, cy);
    final outerRadius = cx - 6;
    final bezelWidth = 6.0;
    final innerRadius = outerRadius - bezelWidth;

    _drawBezel(canvas, center, outerRadius, innerRadius, bezelWidth);
    _drawInnerFill(canvas, center, innerRadius);
    _drawTicks(canvas, center, innerRadius);
    _drawDegreeLabels(canvas, center, innerRadius);
    _drawCardinalLabels(canvas, center, innerRadius);
    _drawHeadingPointer(canvas, center, innerRadius, outerRadius);
    _drawLubberLine(canvas, center, outerRadius);
    _drawCenterShip(canvas, center);
    _drawHeadingReadout(canvas, cx, cy + outerRadius + 10);
  }

  void _drawBezel(
    Canvas canvas,
    Offset center,
    double outer,
    double inner,
    double width,
  ) {
    // Metallic radial gradient bezel ring
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

  void _drawInnerFill(Canvas canvas, Offset center, double radius) {
    final fillPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [const Color(0xFF0C1622), MaritimePalette.deepHull],
        [0.0, 1.0],
      )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, fillPaint);
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    for (var deg = 0; deg < 360; deg += 5) {
      final rad = deg * pi / 180 - pi / 2;
      final outerR = radius - 1;
      double innerR;
      Paint tickPaint;

      if (deg % 30 == 0) {
        // Major tick
        innerR = outerR - 14;
        tickPaint = Paint()
          ..color = MaritimePalette.foam
          ..strokeWidth = 2;
      } else if (deg % 10 == 0) {
        // Medium tick
        innerR = outerR - 8;
        tickPaint = Paint()
          ..color = MaritimePalette.foamDim
          ..strokeWidth = 1.5;
      } else {
        // Minor tick
        innerR = outerR - 5;
        tickPaint = Paint()
          ..color = MaritimePalette.consoleBorder
          ..strokeWidth = 1;
      }

      final outer = center + Offset(cos(rad) * outerR, sin(rad) * outerR);
      final inner = center + Offset(cos(rad) * innerR, sin(rad) * innerR);
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  void _drawDegreeLabels(Canvas canvas, Offset center, double radius) {
    final labelRadius = radius - 20;
    const labels = [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330];

    for (final deg in labels) {
      // Skip cardinal positions — they get letter labels instead
      if (deg % 90 == 0) continue;

      final rad = deg * pi / 180 - pi / 2;
      final pos =
          center + Offset(cos(rad) * labelRadius, sin(rad) * labelRadius);

      final tp = TextPainter(
        text: TextSpan(
          text: '$deg',
          style: const TextStyle(color: MaritimePalette.foamDim, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _drawCardinalLabels(Canvas canvas, Offset center, double radius) {
    final labelRadius = radius - 28;
    const labels = ['N', 'E', 'S', 'W'];
    const angles = [-pi / 2, 0.0, pi / 2, pi];
    const colors = [
      MaritimePalette.lampRed,
      MaritimePalette.foam,
      MaritimePalette.foam,
      MaritimePalette.foam,
    ];

    for (var i = 0; i < 4; i++) {
      final pos =
          center +
          Offset(cos(angles[i]) * labelRadius, sin(angles[i]) * labelRadius);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: colors[i],
            fontSize: labels[i] == 'N' ? 16 : 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _drawHeadingPointer(
    Canvas canvas,
    Offset center,
    double innerRadius,
    double outerRadius,
  ) {
    final headingRad = headingDeg * pi / 180 - pi / 2;
    final pointerTip =
        center +
        Offset(
          cos(headingRad) * (innerRadius - 2),
          sin(headingRad) * (innerRadius - 2),
        );

    // Triangle pointer pointing inward
    final pointerLen = 14.0;
    final pointerHalfWidth = 5.0;
    final pointerBase =
        center +
        Offset(
          cos(headingRad) * (innerRadius - 2 - pointerLen),
          sin(headingRad) * (innerRadius - 2 - pointerLen),
        );
    final perpRad = headingRad + pi / 2;
    final left =
        pointerBase +
        Offset(
          cos(perpRad) * pointerHalfWidth,
          sin(perpRad) * pointerHalfWidth,
        );
    final right =
        pointerBase -
        Offset(
          cos(perpRad) * pointerHalfWidth,
          sin(perpRad) * pointerHalfWidth,
        );

    final pointerPath = Path()
      ..moveTo(pointerTip.dx, pointerTip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    // Glow layer
    final glowPaint = Paint()
      ..color = MaritimePalette.foam
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(pointerPath, glowPaint);

    // Sharp layer
    final sharpPaint = Paint()
      ..color = MaritimePalette.foam
      ..style = PaintingStyle.fill;
    canvas.drawPath(pointerPath, sharpPaint);
  }

  void _drawLubberLine(Canvas canvas, Offset center, double outerRadius) {
    // Fixed reference mark at top (ship's bow direction)
    final topCenter = Offset(center.dx, center.dy - outerRadius);
    final lubberLen = 10.0;

    // Small triangular marker pointing down
    final triPath = Path()
      ..moveTo(topCenter.dx, topCenter.dy + lubberLen)
      ..lineTo(topCenter.dx - 4, topCenter.dy)
      ..lineTo(topCenter.dx + 4, topCenter.dy)
      ..close();

    final lubberPaint = Paint()
      ..color = MaritimePalette.brassBright
      ..style = PaintingStyle.fill;
    canvas.drawPath(triPath, lubberPaint);
  }

  void _drawCenterShip(Canvas canvas, Offset center) {
    // Ship outline — pointed bow at top, wider stern below
    final shipPath = Path()
      ..moveTo(center.dx, center.dy - 16) // bow
      ..lineTo(center.dx - 7, center.dy + 4) // port side
      ..quadraticBezierTo(
        center.dx - 8,
        center.dy + 12,
        center.dx - 5,
        center.dy + 14,
      )
      ..lineTo(center.dx + 5, center.dy + 14) // transom
      ..quadraticBezierTo(
        center.dx + 8,
        center.dy + 12,
        center.dx + 7,
        center.dy + 4,
      )
      ..close();

    // Fill
    canvas.drawPath(
      shipPath,
      Paint()
        ..color = MaritimePalette.midHull
        ..style = PaintingStyle.fill,
    );
    // Outline
    canvas.drawPath(
      shipPath,
      Paint()
        ..color = MaritimePalette.brass
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Center dot
    canvas.drawCircle(
      center,
      2.5,
      Paint()
        ..color = MaritimePalette.brass
        ..style = PaintingStyle.fill,
    );

    // Crosshair lines
    final crossPaint = Paint()
      ..color = MaritimePalette.consoleBorder
      ..strokeWidth = 0.5;
    canvas.drawLine(
      center + const Offset(-20, 0),
      center + const Offset(-10, 0),
      crossPaint,
    );
    canvas.drawLine(
      center + const Offset(10, 0),
      center + const Offset(20, 0),
      crossPaint,
    );
  }

  void _drawHeadingReadout(Canvas canvas, double cx, double top) {
    final hdgStr = 'HDG ${headingDeg.toStringAsFixed(1)}\u00B0';
    final tp = TextPainter(
      text: TextSpan(
        text: hdgStr,
        style: const TextStyle(
          color: MaritimePalette.brassBright,
          fontSize: 16,
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
  bool shouldRepaint(_CompassPainter old) => old.headingDeg != headingDeg;
}
