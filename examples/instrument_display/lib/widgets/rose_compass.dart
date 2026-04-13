import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';

/// A full 32-point compass rose with COG needle, metallic bezel, graduated
/// degree ring, fleur-de-lis at North, and glowing course line. Designed
/// as the hero widget for the navigation page.
class RoseCompass extends StatelessWidget {
  const RoseCompass({
    super.key,
    required this.cogDeg,
    this.headingDeg,
    this.sogKts,
  });

  /// Course over ground in degrees (0-360).
  final double cogDeg;

  /// Ship heading in degrees — draws a subtle heading reference if different
  /// from COG (showing leeway/current offset).
  final double? headingDeg;

  /// Speed over ground — displayed at the centre.
  final double? sogKts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = min(constraints.maxWidth, constraints.maxHeight);
        return SizedBox(
          width: side,
          height: side,
          child: CustomPaint(
            painter: _RoseCompassPainter(
              cogDeg: cogDeg,
              headingDeg: headingDeg,
              sogKts: sogKts,
            ),
          ),
        );
      },
    );
  }
}

class _RoseCompassPainter extends CustomPainter {
  _RoseCompassPainter({required this.cogDeg, this.headingDeg, this.sogKts});

  final double cogDeg;
  final double? headingDeg;
  final double? sogKts;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final outerR = min(cx, cy) - 4;

    _drawBezel(canvas, center, outerR);
    _drawDegreeRing(canvas, center, outerR);
    _drawRosePoints(canvas, center, outerR);
    _drawInnerRing(canvas, center, outerR);
    _drawCardinalLabels(canvas, center, outerR);
    _drawIntercardinalLabels(canvas, center, outerR);
    _drawFleurDeLis(canvas, center, outerR);
    if (headingDeg != null && (headingDeg! - cogDeg).abs() > 0.5) {
      _drawHeadingGhost(canvas, center, outerR);
    }
    _drawCogNeedle(canvas, center, outerR);
    _drawCenterHub(canvas, center, outerR);
    _drawSogReadout(canvas, center);
  }

  // ── Bezel ──────────────────────────────────────────────────────────────

  void _drawBezel(Canvas canvas, Offset center, double outerR) {
    final bezelW = outerR * 0.045;
    final midR = outerR - bezelW / 2;

    // Metallic radial gradient
    final bezelPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        outerR,
        [
          MaritimePalette.brassBright,
          MaritimePalette.brass,
          const Color(0xFF1A1408),
          MaritimePalette.brass,
          MaritimePalette.brassBright,
        ],
        [0.0, 0.25, 0.5, 0.75, 1.0],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = bezelW;
    canvas.drawCircle(center, midR, bezelPaint);

    // Outer highlight
    canvas.drawCircle(
      center,
      outerR,
      Paint()
        ..color = MaritimePalette.brassBright.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Inner dark fill
    final innerR = outerR - bezelW;
    canvas.drawCircle(
      center,
      innerR,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          innerR,
          [const Color(0xFF060E18), MaritimePalette.deepHull],
          [0.0, 1.0],
        )
        ..style = PaintingStyle.fill,
    );
  }

  // ── Degree ring ────────────────────────────────────────────────────────

  void _drawDegreeRing(Canvas canvas, Offset center, double outerR) {
    final bezelW = outerR * 0.045;
    final ringOuter = outerR - bezelW - 1;

    for (var deg = 0; deg < 360; deg++) {
      final rad = deg * pi / 180 - pi / 2;
      double tickLen;
      Paint tickPaint;

      if (deg % 10 == 0) {
        tickLen = outerR * 0.065;
        tickPaint = Paint()
          ..color = MaritimePalette.foam
          ..strokeWidth = 1.5;
      } else if (deg % 5 == 0) {
        tickLen = outerR * 0.04;
        tickPaint = Paint()
          ..color = MaritimePalette.foamDim
          ..strokeWidth = 1.0;
      } else {
        tickLen = outerR * 0.022;
        tickPaint = Paint()
          ..color = MaritimePalette.consoleBorder
          ..strokeWidth = 0.5;
      }

      final outer = center + Offset(cos(rad) * ringOuter, sin(rad) * ringOuter);
      final inner =
          center +
          Offset(
            cos(rad) * (ringOuter - tickLen),
            sin(rad) * (ringOuter - tickLen),
          );
      canvas.drawLine(inner, outer, tickPaint);
    }

    // Degree labels every 30° (skip cardinals — they get letter labels)
    final labelR = ringOuter - outerR * 0.09;
    for (var deg = 0; deg < 360; deg += 30) {
      if (deg % 90 == 0) continue; // cardinals get letter labels
      final rad = deg * pi / 180 - pi / 2;
      final pos = center + Offset(cos(rad) * labelR, sin(rad) * labelR);
      _drawText(
        canvas,
        pos,
        deg.toString().padLeft(3, '0'),
        MaritimePalette.foamDim,
        outerR * 0.048,
      );
    }
  }

  // ── 32-point rose ──────────────────────────────────────────────────────

  void _drawRosePoints(Canvas canvas, Offset center, double outerR) {
    final bezelW = outerR * 0.045;
    final ringInner = outerR - bezelW - 1 - outerR * 0.065;

    // Three tiers of points
    final cardinalLen = ringInner * 0.55; // N/S/E/W
    final interLen = ringInner * 0.40; // NE/SE/SW/NW
    final secondaryLen = ringInner * 0.28; // NNE, ENE, etc.

    // Draw secondary intercardinals first (behind)
    for (var i = 0; i < 16; i++) {
      final deg = i * 22.5;
      if (deg % 45 == 0) continue; // skip cardinal and intercardinal
      _drawRosePoint(
        canvas,
        center,
        deg,
        secondaryLen,
        outerR * 0.018,
        MaritimePalette.consoleBorder,
        const Color(0xFF1A2840),
      );
    }

    // Draw intercardinals
    for (var i = 0; i < 8; i++) {
      final deg = i * 45.0;
      if (deg % 90 == 0) continue; // skip cardinals
      _drawRosePoint(
        canvas,
        center,
        deg,
        interLen,
        outerR * 0.03,
        MaritimePalette.foamDim,
        const Color(0xFF162234),
      );
    }

    // Draw cardinals (on top)
    for (var i = 0; i < 4; i++) {
      final deg = i * 90.0;
      final isNorth = deg == 0;
      final lightColor = isNorth
          ? MaritimePalette.lampRed
          : MaritimePalette.brass;
      final darkColor = isNorth
          ? const Color(0xFF6B1A1A)
          : const Color(0xFF3A2810);
      _drawRosePoint(
        canvas,
        center,
        deg,
        cardinalLen,
        outerR * 0.045,
        lightColor,
        darkColor,
      );
    }
  }

  /// Draw a single diamond-shaped compass rose point at [deg] degrees.
  /// The point is split down the middle — left half [darkColor], right
  /// half [lightColor] — the classic compass rose rendering.
  void _drawRosePoint(
    Canvas canvas,
    Offset center,
    double deg,
    double length,
    double halfWidth,
    Color lightColor,
    Color darkColor,
  ) {
    final rad = deg * pi / 180 - pi / 2;
    final perpRad = rad + pi / 2;

    final tip = center + Offset(cos(rad) * length, sin(rad) * length);
    final left =
        center + Offset(cos(perpRad) * halfWidth, sin(perpRad) * halfWidth);
    final right =
        center - Offset(cos(perpRad) * halfWidth, sin(perpRad) * halfWidth);

    // Right half (light)
    final rightPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(rightPath, Paint()..color = lightColor);

    // Left half (dark)
    final leftPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..close();
    canvas.drawPath(leftPath, Paint()..color = darkColor);

    // Outline for definition
    final outlinePath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(
      outlinePath,
      Paint()
        ..color = lightColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  // ── Inner decorative ring ──────────────────────────────────────────────

  void _drawInnerRing(Canvas canvas, Offset center, double outerR) {
    final ringR = outerR * 0.22;
    // Double ring
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..color = MaritimePalette.brass.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      center,
      ringR - 3,
      Paint()
        ..color = MaritimePalette.brass.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Small decorative ticks on the inner ring at cardinal/intercardinal
    for (var i = 0; i < 8; i++) {
      final rad = i * pi / 4 - pi / 2;
      final outer = center + Offset(cos(rad) * ringR, sin(rad) * ringR);
      final inner =
          center + Offset(cos(rad) * (ringR - 5), sin(rad) * (ringR - 5));
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = MaritimePalette.brass.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
    }
  }

  // ── Cardinal / intercardinal labels ────────────────────────────────────

  void _drawCardinalLabels(Canvas canvas, Offset center, double outerR) {
    final bezelW = outerR * 0.045;
    final labelR = outerR - bezelW - outerR * 0.16;

    const labels = ['N', 'E', 'S', 'W'];
    const angles = [-pi / 2, 0.0, pi / 2, pi];
    final colors = [
      MaritimePalette.lampRed,
      MaritimePalette.foam,
      MaritimePalette.foam,
      MaritimePalette.foam,
    ];
    final sizes = [
      outerR * 0.1,
      outerR * 0.075,
      outerR * 0.075,
      outerR * 0.075,
    ];

    for (var i = 0; i < 4; i++) {
      final pos =
          center + Offset(cos(angles[i]) * labelR, sin(angles[i]) * labelR);

      // Glow for N
      if (i == 0) {
        _drawText(
          canvas,
          pos,
          labels[i],
          colors[i],
          sizes[i],
          bold: true,
          shadows: [Shadow(color: MaritimePalette.lampRed, blurRadius: 8)],
        );
      } else {
        _drawText(canvas, pos, labels[i], colors[i], sizes[i], bold: true);
      }
    }
  }

  void _drawIntercardinalLabels(Canvas canvas, Offset center, double outerR) {
    final bezelW = outerR * 0.045;
    final labelR = outerR - bezelW - outerR * 0.16;

    const labels = ['NE', 'SE', 'SW', 'NW'];
    const angles = [-pi / 4, pi / 4, 3 * pi / 4, -3 * pi / 4];

    for (var i = 0; i < 4; i++) {
      final pos =
          center + Offset(cos(angles[i]) * labelR, sin(angles[i]) * labelR);
      _drawText(
        canvas,
        pos,
        labels[i],
        MaritimePalette.foamDim,
        outerR * 0.045,
      );
    }
  }

  // ── Fleur-de-lis at North ──────────────────────────────────────────────

  void _drawFleurDeLis(Canvas canvas, Offset center, double outerR) {
    final bezelW = outerR * 0.045;
    final ringInner = outerR - bezelW - 1 - outerR * 0.065;
    final tipY = center.dy - ringInner * 0.55;
    final baseY = center.dy - ringInner * 0.40;
    final s = outerR * 0.025; // scale factor

    // Central petal — a pointed arch shape
    final petalPath = Path()
      ..moveTo(center.dx, tipY - s * 4) // peak above the cardinal point
      ..cubicTo(
        center.dx - s * 2.5,
        tipY - s * 2,
        center.dx - s * 3,
        tipY + s * 1,
        center.dx - s * 1,
        baseY,
      )
      ..lineTo(center.dx + s * 1, baseY)
      ..cubicTo(
        center.dx + s * 3,
        tipY + s * 1,
        center.dx + s * 2.5,
        tipY - s * 2,
        center.dx,
        tipY - s * 4,
      )
      ..close();

    // Glow
    canvas.drawPath(
      petalPath,
      Paint()
        ..color = MaritimePalette.lampRed.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Fill
    canvas.drawPath(
      petalPath,
      Paint()
        ..color = MaritimePalette.lampRed
        ..style = PaintingStyle.fill,
    );

    // Side scrolls — small curved arms
    for (final sign in [-1.0, 1.0]) {
      final scrollPath = Path()
        ..moveTo(center.dx + sign * s * 1, baseY)
        ..quadraticBezierTo(
          center.dx + sign * s * 4,
          baseY - s * 1,
          center.dx + sign * s * 3.5,
          baseY + s * 2,
        );
      canvas.drawPath(
        scrollPath,
        Paint()
          ..color = MaritimePalette.lampRed
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  // ── COG needle ─────────────────────────────────────────────────────────

  void _drawCogNeedle(Canvas canvas, Offset center, double outerR) {
    final bezelW = outerR * 0.045;
    final needleLen = outerR - bezelW - 2;
    final cogRad = cogDeg * pi / 180 - pi / 2;
    final perpRad = cogRad + pi / 2;
    final halfWidth = outerR * 0.02;

    final tip =
        center + Offset(cos(cogRad) * needleLen, sin(cogRad) * needleLen);
    final tailLen = outerR * 0.15;
    final tail = center - Offset(cos(cogRad) * tailLen, sin(cogRad) * tailLen);
    final left =
        center + Offset(cos(perpRad) * halfWidth, sin(perpRad) * halfWidth);
    final right =
        center - Offset(cos(perpRad) * halfWidth, sin(perpRad) * halfWidth);

    // Forward half — bright
    final fwdPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    // Glow
    canvas.drawPath(
      fwdPath,
      Paint()
        ..color = MaritimePalette.foam.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      fwdPath,
      Paint()
        ..color = MaritimePalette.foam
        ..style = PaintingStyle.fill,
    );

    // Tail half — darker accent
    final tailLeft =
        center +
        Offset(cos(perpRad) * halfWidth * 0.7, sin(perpRad) * halfWidth * 0.7);
    final tailRight =
        center -
        Offset(cos(perpRad) * halfWidth * 0.7, sin(perpRad) * halfWidth * 0.7);
    final tailPath = Path()
      ..moveTo(tail.dx, tail.dy)
      ..lineTo(tailLeft.dx, tailLeft.dy)
      ..lineTo(tailRight.dx, tailRight.dy)
      ..close();
    canvas.drawPath(
      tailPath,
      Paint()
        ..color = MaritimePalette.foamDim
        ..style = PaintingStyle.fill,
    );

    // Needle outline
    final outlinePath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(tail.dx, tail.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(
      outlinePath,
      Paint()
        ..color = MaritimePalette.foam.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  // ── Heading ghost (when heading ≠ COG, shows leeway) ───────────────────

  void _drawHeadingGhost(Canvas canvas, Offset center, double outerR) {
    final bezelW = outerR * 0.045;
    final len = outerR - bezelW - 2;
    final hdgRad = headingDeg! * pi / 180 - pi / 2;
    final tip = center + Offset(cos(hdgRad) * len, sin(hdgRad) * len);

    // Dashed-style ghost line
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = MaritimePalette.brass.withValues(alpha: 0.25)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // Small diamond at tip
    final perpRad = hdgRad + pi / 2;
    final d = outerR * 0.015;
    final diamondPath = Path()
      ..moveTo(tip.dx + cos(hdgRad) * d * 2, tip.dy + sin(hdgRad) * d * 2)
      ..lineTo(tip.dx + cos(perpRad) * d, tip.dy + sin(perpRad) * d)
      ..lineTo(tip.dx - cos(hdgRad) * d * 2, tip.dy - sin(hdgRad) * d * 2)
      ..lineTo(tip.dx - cos(perpRad) * d, tip.dy - sin(perpRad) * d)
      ..close();
    canvas.drawPath(
      diamondPath,
      Paint()
        ..color = MaritimePalette.brass.withValues(alpha: 0.4)
        ..style = PaintingStyle.fill,
    );
  }

  // ── Center hub ─────────────────────────────────────────────────────────

  void _drawCenterHub(Canvas canvas, Offset center, double outerR) {
    final hubR = outerR * 0.06;

    // Metallic hub with gradient
    canvas.drawCircle(
      center,
      hubR,
      Paint()
        ..shader = ui.Gradient.radial(
          center + Offset(-hubR * 0.3, -hubR * 0.3),
          hubR * 2,
          [
            MaritimePalette.brassBright,
            MaritimePalette.brass,
            const Color(0xFF2A1C08),
          ],
          [0.0, 0.5, 1.0],
        )
        ..style = PaintingStyle.fill,
    );
    // Rim highlight
    canvas.drawCircle(
      center,
      hubR,
      Paint()
        ..color = MaritimePalette.brassBright.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Center jewel dot
    canvas.drawCircle(
      center,
      hubR * 0.35,
      Paint()
        ..color = MaritimePalette.foam
        ..style = PaintingStyle.fill,
    );
    // Jewel glow
    canvas.drawCircle(
      center,
      hubR * 0.35,
      Paint()
        ..color = MaritimePalette.foam.withValues(alpha: 0.4)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  // ── SOG readout at center ──────────────────────────────────────────────

  void _drawSogReadout(Canvas canvas, Offset center) {
    if (sogKts == null) return;
    final sogStr = sogKts!.toStringAsFixed(1);
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: sogStr,
            style: const TextStyle(
              color: MaritimePalette.foam,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFeatures: kTabular,
              shadows: [Shadow(color: MaritimePalette.foam, blurRadius: 4)],
            ),
          ),
          const TextSpan(
            text: ' kts',
            style: TextStyle(color: MaritimePalette.foamDim, fontSize: 9),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Position below center hub
    tp.paint(canvas, center + Offset(-tp.width / 2, 18));
  }

  // ── Text helper ────────────────────────────────────────────────────────

  void _drawText(
    Canvas canvas,
    Offset pos,
    String text,
    Color color,
    double fontSize, {
    bool bold = false,
    List<Shadow>? shadows,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontFeatures: kTabular,
          shadows: shadows,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_RoseCompassPainter old) =>
      old.cogDeg != cogDeg ||
      old.headingDeg != headingDeg ||
      old.sogKts != sogKts;
}
