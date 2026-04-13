import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';

/// Professional horizontal linear gauge with graduated segments, glow effects,
/// and optional warning/danger thresholds.
///
/// The bar fills with a gradient and features segment marks, scale labels, and
/// a glowing leading-edge dot.
class LinearGauge extends StatelessWidget {
  const LinearGauge({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.label = '',
    this.unit = '',
    this.warningThreshold,
    this.dangerThreshold,
  });

  final double? value;
  final double min;
  final double max;
  final String label;
  final String unit;
  final double? warningThreshold;
  final double? dangerThreshold;

  @override
  Widget build(BuildContext context) {
    final v = value ?? min;
    final fraction = ((v - min) / (max - min)).clamp(0.0, 1.0);

    Color barColor = MaritimePalette.lampGreen;
    if (dangerThreshold != null && v >= dangerThreshold!) {
      barColor = MaritimePalette.lampRed;
    } else if (warningThreshold != null && v >= warningThreshold!) {
      barColor = MaritimePalette.lampAmber;
    }

    final valueText = value != null
        ? '${value!.toStringAsFixed(0)} $unit'
        : '--- $unit';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: MaritimePalette.brass,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                valueText,
                style: TextStyle(
                  color: MaritimePalette.foam,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFeatures: kTabular,
                  shadows: value != null
                      ? const [
                          Shadow(color: MaritimePalette.foam, blurRadius: 6),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        SizedBox(
          height: 40,
          child: CustomPaint(
            size: const Size(double.infinity, 40),
            painter: _LinearGaugePainter(
              fraction: fraction,
              barColor: value != null ? barColor : MaritimePalette.lampOff,
              hasValue: value != null,
              min: min,
              max: max,
              warningThreshold: warningThreshold,
              dangerThreshold: dangerThreshold,
            ),
          ),
        ),
      ],
    );
  }
}

class _LinearGaugePainter extends CustomPainter {
  _LinearGaugePainter({
    required this.fraction,
    required this.barColor,
    required this.hasValue,
    required this.min,
    required this.max,
    this.warningThreshold,
    this.dangerThreshold,
  });

  final double fraction;
  final Color barColor;
  final bool hasValue;
  final double min;
  final double max;
  final double? warningThreshold;
  final double? dangerThreshold;

  static const double _barHeight = 20.0;
  static const double _barTop = 0.0;
  static const double _labelTop = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width;
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, _barTop, barWidth, _barHeight),
      const Radius.circular(4),
    );

    // Track background with recessed look
    final trackPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, _barTop),
        Offset(0, _barTop + _barHeight),
        [const Color(0xFF060E18), MaritimePalette.deepHull],
      );
    canvas.drawRRect(barRect, trackPaint);

    // Track border
    final borderPaint = Paint()
      ..color = MaritimePalette.consoleBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(barRect, borderPaint);

    // Warning/danger zone backgrounds (subtle)
    if (warningThreshold != null) {
      final warnFrac = ((warningThreshold! - min) / (max - min)).clamp(
        0.0,
        1.0,
      );
      final dangerFrac = dangerThreshold != null
          ? ((dangerThreshold! - min) / (max - min)).clamp(0.0, 1.0)
          : 1.0;
      // Amber zone
      final amberRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          warnFrac * barWidth,
          _barTop,
          (dangerFrac - warnFrac) * barWidth,
          _barHeight,
        ),
        Radius.zero,
      );
      canvas.save();
      canvas.clipRRect(barRect);
      canvas.drawRRect(
        amberRect,
        Paint()..color = MaritimePalette.lampAmber.withValues(alpha: 0.08),
      );
      if (dangerThreshold != null) {
        final redRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            dangerFrac * barWidth,
            _barTop,
            (1.0 - dangerFrac) * barWidth,
            _barHeight,
          ),
          Radius.zero,
        );
        canvas.drawRRect(
          redRect,
          Paint()..color = MaritimePalette.lampRed.withValues(alpha: 0.08),
        );
      }
      canvas.restore();
    }

    // Active fill bar
    if (fraction > 0 && hasValue) {
      canvas.save();
      canvas.clipRRect(barRect);

      final fillWidth = fraction * barWidth;
      // Brighter version of bar color for gradient
      final barBright = Color.lerp(barColor, Colors.white, 0.3)!;

      final fillPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, _barTop),
          Offset(0, _barTop + _barHeight),
          [barBright, barColor],
        );
      final fillRect = Rect.fromLTWH(0, _barTop, fillWidth, _barHeight);
      canvas.drawRect(fillRect, fillPaint);

      // Glow at leading edge
      final glowPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(
        Offset(fillWidth, _barTop + _barHeight / 2),
        4,
        glowPaint,
      );
      // Sharp bright dot on top
      canvas.drawCircle(
        Offset(fillWidth, _barTop + _barHeight / 2),
        2,
        Paint()..color = Colors.white,
      );

      canvas.restore();
    }

    // Segment marks (every 10% of the range)
    final segPaint = Paint()
      ..color = MaritimePalette.consoleBorder.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 1; i < 10; i++) {
      final x = barWidth * i / 10;
      canvas.drawLine(
        Offset(x, _barTop + 2),
        Offset(x, _barTop + _barHeight - 2),
        segPaint,
      );
    }

    // Scale labels at key positions
    _drawScaleLabel(canvas, 0, min, barWidth);
    _drawScaleLabel(canvas, barWidth / 2, (min + max) / 2, barWidth);
    _drawScaleLabel(canvas, barWidth, max, barWidth);
  }

  void _drawScaleLabel(Canvas canvas, double x, double val, double totalWidth) {
    final tp = TextPainter(
      text: TextSpan(
        text: val.toStringAsFixed(0),
        style: const TextStyle(color: MaritimePalette.foamDim, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Clamp so labels don't go off-edge
    var dx = x - tp.width / 2;
    if (dx < 0) dx = 0;
    if (dx + tp.width > totalWidth) dx = totalWidth - tp.width;
    tp.paint(canvas, Offset(dx, _labelTop));
  }

  @override
  bool shouldRepaint(_LinearGaugePainter old) =>
      old.fraction != fraction ||
      old.barColor != barColor ||
      old.hasValue != hasValue;
}
