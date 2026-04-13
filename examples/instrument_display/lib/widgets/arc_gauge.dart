import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';

/// Semicircular sweep gauge for engine RPM and similar metrics.
///
/// Features a 270-degree arc with metallic bezel, graduated scale with labels,
/// colour zones (green/amber/red), a glowing needle, and digital readout.
class ArcGauge extends StatelessWidget {
  const ArcGauge({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.label = '',
    this.unit = '',
    this.decimals = 0,
    this.warningThreshold,
    this.dangerThreshold,
  });

  final double? value;
  final double min;
  final double max;
  final String label;
  final String unit;
  final int decimals;
  final double? warningThreshold;
  final double? dangerThreshold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: CustomPaint(
        painter: _ArcGaugePainter(
          value: value,
          min: min,
          max: max,
          label: label,
          unit: unit,
          decimals: decimals,
          warningThreshold: warningThreshold,
          dangerThreshold: dangerThreshold,
        ),
      ),
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  _ArcGaugePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.unit,
    required this.decimals,
    this.warningThreshold,
    this.dangerThreshold,
  });

  final double? value;
  final double min;
  final double max;
  final String label;
  final String unit;
  final int decimals;
  final double? warningThreshold;
  final double? dangerThreshold;

  // Arc spans 270 degrees: from 135deg to 405deg (i.e., bottom-left to bottom-right)
  static const double _startAngle = 135 * math.pi / 180;
  static const double _sweepAngle = 270 * math.pi / 180;

  double _valueToAngle(double v) {
    final frac = ((v - min) / (max - min)).clamp(0.0, 1.0);
    return _startAngle + frac * _sweepAngle;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final outerRadius = math.min(cx, cy) - 4;
    final bezelWidth = 5.0;
    final innerRadius = outerRadius - bezelWidth;

    _drawBezel(canvas, center, outerRadius, innerRadius, bezelWidth);
    _drawBackground(canvas, center, innerRadius);
    _drawZoneArcs(canvas, center, innerRadius);
    _drawTrackArc(canvas, center, innerRadius);
    _drawActiveArc(canvas, center, innerRadius);
    _drawTicks(canvas, center, innerRadius);
    _drawNeedle(canvas, center, innerRadius);
    _drawCenterCap(canvas, center);
    _drawReadout(canvas, center);
    _drawLabel(canvas, center, innerRadius);
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

    final highlightPaint = Paint()
      ..color = MaritimePalette.brassBright.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawCircle(center, outer, highlightPaint);
  }

  void _drawBackground(Canvas canvas, Offset center, double radius) {
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

  void _drawZoneArcs(Canvas canvas, Offset center, double radius) {
    final arcRadius = radius - 8;
    final rect = Rect.fromCircle(center: center, radius: arcRadius);
    final arcWidth = 4.0;

    // Warning zone (amber)
    if (warningThreshold != null) {
      final warnStart = _valueToAngle(warningThreshold!);
      final warnEnd = dangerThreshold != null
          ? _valueToAngle(dangerThreshold!)
          : _startAngle + _sweepAngle;
      canvas.drawArc(
        rect,
        warnStart,
        warnEnd - warnStart,
        false,
        Paint()
          ..color = MaritimePalette.lampAmber.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = arcWidth,
      );
    }

    // Danger zone (red)
    if (dangerThreshold != null) {
      final dangerStart = _valueToAngle(dangerThreshold!);
      final dangerEnd = _startAngle + _sweepAngle;
      canvas.drawArc(
        rect,
        dangerStart,
        dangerEnd - dangerStart,
        false,
        Paint()
          ..color = MaritimePalette.lampRed.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = arcWidth,
      );
    }
  }

  void _drawTrackArc(Canvas canvas, Offset center, double radius) {
    final arcRadius = radius - 14;
    final rect = Rect.fromCircle(center: center, radius: arcRadius);
    final trackPaint = Paint()
      ..color = MaritimePalette.deepHull
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, _sweepAngle, false, trackPaint);
  }

  void _drawActiveArc(Canvas canvas, Offset center, double radius) {
    if (value == null) return;
    final v = value!;
    final frac = ((v - min) / (max - min)).clamp(0.0, 1.0);
    if (frac <= 0) return;

    final arcRadius = radius - 14;
    final rect = Rect.fromCircle(center: center, radius: arcRadius);
    final activeSweep = frac * _sweepAngle;

    // Determine colour based on thresholds
    Color arcColor = MaritimePalette.lampGreen;
    if (dangerThreshold != null && v >= dangerThreshold!) {
      arcColor = MaritimePalette.lampRed;
    } else if (warningThreshold != null && v >= warningThreshold!) {
      arcColor = MaritimePalette.lampAmber;
    }
    final arcBright = Color.lerp(arcColor, Colors.white, 0.3)!;

    // Glow
    canvas.drawArc(
      rect,
      _startAngle,
      activeSweep,
      false,
      Paint()
        ..color = arcColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Active arc with gradient feel (solid since arc shader is complex)
    canvas.drawArc(
      rect,
      _startAngle,
      activeSweep,
      false,
      Paint()
        ..shader = ui.Gradient.sweep(
          center,
          [arcColor, arcBright],
          [0.0, 1.0],
          TileMode.clamp,
          _startAngle,
          _startAngle + activeSweep,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    final tickOuterR = radius - 2;
    // Determine nice tick intervals
    final range = max - min;
    final majorInterval = _niceInterval(range, 6);
    final minorInterval = majorInterval / 5;

    var tickVal = min;
    while (tickVal <= max + minorInterval * 0.1) {
      final angle = _valueToAngle(tickVal.clamp(min, max));
      final isMajor =
          (tickVal - min).abs() < 0.01 ||
          ((tickVal - min) % majorInterval).abs() < minorInterval * 0.1;
      final tickLen = isMajor ? 10.0 : 5.0;
      final tickWidth = isMajor ? 1.5 : 0.8;
      final tickColor = isMajor
          ? MaritimePalette.foam
          : MaritimePalette.consoleBorder;

      final outer =
          center +
          Offset(math.cos(angle) * tickOuterR, math.sin(angle) * tickOuterR);
      final inner =
          center +
          Offset(
            math.cos(angle) * (tickOuterR - tickLen),
            math.sin(angle) * (tickOuterR - tickLen),
          );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = tickColor
          ..strokeWidth = tickWidth,
      );

      // Labels on major ticks
      if (isMajor) {
        final labelR = tickOuterR - tickLen - 8;
        final pos =
            center + Offset(math.cos(angle) * labelR, math.sin(angle) * labelR);
        final tp = TextPainter(
          text: TextSpan(
            text: tickVal.toStringAsFixed(0),
            style: const TextStyle(color: MaritimePalette.foamDim, fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }

      tickVal += minorInterval;
    }
  }

  void _drawNeedle(Canvas canvas, Offset center, double radius) {
    if (value == null) return;
    final angle = _valueToAngle(value!.clamp(min, max));
    final needleLen = radius - 20;
    final tip =
        center +
        Offset(math.cos(angle) * needleLen, math.sin(angle) * needleLen);

    // Needle as thin triangle
    final perpAngle = angle + math.pi / 2;
    final baseHalf = 3.0;
    final baseLeft =
        center +
        Offset(math.cos(perpAngle) * baseHalf, math.sin(perpAngle) * baseHalf);
    final baseRight =
        center -
        Offset(math.cos(perpAngle) * baseHalf, math.sin(perpAngle) * baseHalf);

    final needlePath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseLeft.dx, baseLeft.dy)
      ..lineTo(baseRight.dx, baseRight.dy)
      ..close();

    // Glow
    canvas.drawPath(
      needlePath,
      Paint()
        ..color = MaritimePalette.foam
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Sharp
    canvas.drawPath(
      needlePath,
      Paint()
        ..color = MaritimePalette.foam
        ..style = PaintingStyle.fill,
    );
  }

  void _drawCenterCap(Canvas canvas, Offset center) {
    // Metallic center cap
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..shader = ui.Gradient.radial(center + const Offset(-2, -2), 8, [
          MaritimePalette.brassBright,
          MaritimePalette.brass,
        ])
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..color = MaritimePalette.brass
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  void _drawReadout(Canvas canvas, Offset center) {
    final hasValue = value != null;
    final valStr = hasValue ? value!.toStringAsFixed(decimals) : '---';

    // Value text
    final valTp = TextPainter(
      text: TextSpan(
        text: valStr,
        style: TextStyle(
          color: hasValue ? MaritimePalette.foam : MaritimePalette.foamDim,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          fontFeatures: kTabular,
          shadows: hasValue
              ? const [Shadow(color: MaritimePalette.foam, blurRadius: 6)]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    valTp.paint(canvas, Offset(center.dx - valTp.width / 2, center.dy + 16));

    // Unit text
    if (unit.isNotEmpty) {
      final unitTp = TextPainter(
        text: TextSpan(
          text: unit,
          style: const TextStyle(color: MaritimePalette.foamDim, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      unitTp.paint(
        canvas,
        Offset(center.dx - unitTp.width / 2, center.dy + 40),
      );
    }
  }

  void _drawLabel(Canvas canvas, Offset center, double radius) {
    if (label.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: label.toUpperCase(),
        style: const TextStyle(
          color: MaritimePalette.brass,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - 30));
  }

  /// Calculate a "nice" interval for tick marks.
  double _niceInterval(double range, int targetTicks) {
    final rough = range / targetTicks;
    final magnitude = math
        .pow(10, (math.log(rough) / math.ln10).floor())
        .toDouble();
    final residual = rough / magnitude;
    double nice;
    if (residual <= 1.5) {
      nice = 1;
    } else if (residual <= 3) {
      nice = 2;
    } else if (residual <= 7) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * magnitude;
  }

  @override
  bool shouldRepaint(_ArcGaugePainter old) =>
      old.value != value ||
      old.min != min ||
      old.max != max ||
      old.warningThreshold != warningThreshold ||
      old.dangerThreshold != dangerThreshold;
}
