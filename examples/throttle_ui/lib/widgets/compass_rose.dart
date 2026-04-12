import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';

/// A nautical compass rose. Inner dial rotates under a fixed lubber line
/// so the ring (N/E/S/W, 0/90/180/270) rotates opposite to [headingRad],
/// matching the behaviour of a real ship's compass.
///
/// Paint-only, no hit testing.
class CompassRose extends StatelessWidget {
  const CompassRose({super.key, required this.headingRad, this.size = 96});

  /// Course over ground, in radians, 0..2π, north = 0, clockwise.
  final double headingRad;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CompassPainter(headingRad: headingRad),
    );
  }
}

class _CompassPainter extends CustomPainter {
  _CompassPainter({required this.headingRad});
  final double headingRad;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    // Outer bezel (brass).
    final bezelPaint = Paint()
      ..color = MaritimePalette.brass
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1, bezelPaint);

    // Field.
    final fieldPaint = Paint()
      ..shader = const RadialGradient(
        colors: [MaritimePalette.midHull, MaritimePalette.deepHull],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius - 2, fieldPaint);

    // Rotating compass card — we rotate the canvas so the marks
    // travel the correct direction under a fixed lubber line.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-headingRad);

    final tickMajor = Paint()
      ..color = MaritimePalette.brassBright
      ..strokeWidth = 1.4;
    final tickMinor = Paint()
      ..color = MaritimePalette.foamDim
      ..strokeWidth = 0.8;

    for (var i = 0; i < 72; i++) {
      final angle = i * (math.pi / 36);
      final isMajor = i % 9 == 0; // N, E, S, W
      final isMid = i % 3 == 0; // every 15°
      final outer = radius - 4;
      final inner =
          outer -
          (isMajor
              ? 10
              : isMid
              ? 6
              : 3);
      canvas.drawLine(
        Offset(math.sin(angle) * inner, -math.cos(angle) * inner),
        Offset(math.sin(angle) * outer, -math.cos(angle) * outer),
        isMajor || isMid ? tickMajor : tickMinor,
      );
    }

    // Cardinal letters.
    const labels = ['N', 'E', 'S', 'W'];
    const labelStyle = TextStyle(
      color: MaritimePalette.brassBright,
      fontSize: 11,
      fontWeight: FontWeight.bold,
    );
    for (var i = 0; i < 4; i++) {
      final angle = i * (math.pi / 2);
      final painter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: labels[i] == 'N'
              ? labelStyle.copyWith(color: MaritimePalette.lampRed)
              : labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = math.sin(angle) * (radius - 20) - painter.width / 2;
      final ly = -math.cos(angle) * (radius - 20) - painter.height / 2;
      // Counter-rotate the glyph itself so it stays upright.
      canvas.save();
      canvas.translate(lx + painter.width / 2, ly + painter.height / 2);
      canvas.rotate(headingRad);
      canvas.translate(-painter.width / 2, -painter.height / 2);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    canvas.restore();

    // Fixed lubber line (pointing up = ship heading).
    final lubberPaint = Paint()
      ..color = MaritimePalette.lampRed
      ..style = PaintingStyle.fill;
    final lubberPath = Path()
      ..moveTo(center.dx, center.dy - radius + 1)
      ..lineTo(center.dx - 4, center.dy - radius + 9)
      ..lineTo(center.dx + 4, center.dy - radius + 9)
      ..close();
    canvas.drawPath(lubberPath, lubberPaint);

    // Center hub.
    canvas.drawCircle(center, 4, Paint()..color = MaritimePalette.brass);
    canvas.drawCircle(
      center,
      4,
      Paint()
        ..color = MaritimePalette.teak
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) =>
      old.headingRad != headingRad;
}
