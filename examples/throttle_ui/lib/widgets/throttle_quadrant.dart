import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';

/// Vertical throttle quadrant: a polished brass lever sliding in a slot,
/// with ahead / astern markings. Read-only; reflects the last Throttle
/// value the service has decoded (per the DBC, -5.12..5.11).
class ThrottleQuadrant extends StatelessWidget {
  const ThrottleQuadrant({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.size = const Size(36, 140),
  });

  final double value;
  final double min;
  final double max;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: size,
      painter: _QuadrantPainter(value: value, min: min, max: max),
    );
  }
}

class _QuadrantPainter extends CustomPainter {
  _QuadrantPainter({required this.value, required this.min, required this.max});
  final double value;
  final double min;
  final double max;

  // Left gutter reserved for AH / N / AS labels, outside the frame rect.
  // Everything inside the slider lives in the region [gutter, size.width].
  static const double _labelGutter = 13;

  @override
  void paint(Canvas canvas, Size size) {
    final frameLeft = _labelGutter;
    final frameRight = size.width - 2;
    final frameWidth = frameRight - frameLeft;
    final centerX = frameLeft + frameWidth / 2;

    // Backing frame.
    final framePaint = Paint()
      ..color = MaritimePalette.midHull
      ..style = PaintingStyle.fill;
    final frameRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(frameLeft, 2, frameRight, size.height - 2),
      const Radius.circular(6),
    );
    canvas.drawRRect(frameRect, framePaint);

    final borderPaint = Paint()
      ..color = MaritimePalette.brass
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(frameRect, borderPaint);

    // Slot that the lever rides in.
    final slotRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(centerX - 2, 10, centerX + 2, size.height - 10),
      const Radius.circular(2),
    );
    canvas.drawRRect(slotRect, Paint()..color = MaritimePalette.deepHull);

    // Neutral detent mark & ahead/astern scale ticks.
    final tickPaint = Paint()
      ..color = MaritimePalette.foamDim
      ..strokeWidth = 1;
    const stops = [0.0, 0.25, 0.5, 0.75, 1.0];
    for (final s in stops) {
      final y = 10 + (size.height - 20) * s;
      canvas.drawLine(
        Offset(centerX - 8, y),
        Offset(centerX - 3, y),
        tickPaint,
      );
      canvas.drawLine(
        Offset(centerX + 3, y),
        Offset(centerX + 8, y),
        tickPaint,
      );
    }

    // Labels — drawn in the dedicated left gutter, aligned to the
    // ahead / neutral / astern scale positions, right-aligned so that
    // "AH" and "AS" sit flush against the frame without touching it.
    _drawLabel(canvas, 'AH', frameLeft: frameLeft, centerY: 10);
    _drawLabel(canvas, 'N', frameLeft: frameLeft, centerY: size.height / 2);
    _drawLabel(canvas, 'AS', frameLeft: frameLeft, centerY: size.height - 10);

    // Lever position. Invert Y — ahead is at the top.
    final clamped = value.clamp(min, max);
    final fraction = 1.0 - ((clamped - min) / (max - min));
    final knobY = 10 + (size.height - 20) * fraction;
    final knobLeft = centerX - 12;
    final knobRect = Rect.fromLTWH(knobLeft, knobY - 6, 24, 12);
    final knobPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          MaritimePalette.brassBright,
          MaritimePalette.brass,
          MaritimePalette.teak,
        ],
        stops: [0, 0.5, 1],
      ).createShader(knobRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(knobRect, const Radius.circular(3)),
      knobPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(knobRect, const Radius.circular(3)),
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Index line on the knob.
    canvas.drawLine(
      Offset(centerX - 9, knobY),
      Offset(centerX + 9, knobY),
      Paint()
        ..color = Colors.black87
        ..strokeWidth = 1,
    );
  }

  void _drawLabel(
    Canvas canvas,
    String text, {
    required double frameLeft,
    required double centerY,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 7,
          color: MaritimePalette.brass,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Right-align the label inside the gutter, leaving a 2 px air gap
    // between the glyph and the frame border.
    final x = frameLeft - 2 - painter.width;
    final y = centerY - painter.height / 2;
    painter.paint(canvas, Offset(x.clamp(0, frameLeft).toDouble(), y));
  }

  @override
  bool shouldRepaint(covariant _QuadrantPainter old) =>
      old.value != value || old.min != min || old.max != max;
}
