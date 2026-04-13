import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/n2k_service.dart';
import '../theme/maritime_theme.dart';

/// Depth / Speed page — dramatic vertical sonar depth gauge with digital
/// readouts, boat speed, SOG, and shallow-water alarm.
class DepthScreen extends StatelessWidget {
  const DepthScreen({super.key, required this.service});

  final N2kService service;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final depthM = service.signal('depth');
        final speedMs = service.signal('speedWaterRef');
        final sogMs = service.signal('sog');

        final speedKts = speedMs != null ? speedMs * 1.94384 : null;
        final sogKts = sogMs != null ? sogMs * 1.94384 : null;
        final isShallow = depthM != null && depthM < 3.0;

        return Container(
          color: MaritimePalette.deepHull,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: vertical depth gauge
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      _sectionHeader('DEPTH'),
                      const SizedBox(height: 6),
                      Expanded(
                        child: _DepthGauge(depthM: depthM ?? 0, maxDepth: 100),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Right: data readouts
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('DEPTH'),
                      const SizedBox(height: 6),
                      _recessedValue(
                        label: 'DEPTH',
                        value: depthM,
                        unit: 'm',
                        fontSize: 40,
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader('SPEED'),
                      const SizedBox(height: 6),
                      _recessedValue(
                        label: 'STW',
                        value: speedKts,
                        unit: 'kts',
                        fontSize: 32,
                      ),
                      const SizedBox(height: 4),
                      _recessedValue(
                        label: 'SOG',
                        value: sogKts,
                        unit: 'kts',
                        fontSize: 32,
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader('ALARM'),
                      const SizedBox(height: 6),
                      _shallowAlarm(depthM: depthM, isShallow: isShallow),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: MaritimePalette.brassBright,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    );
  }

  Widget _recessedValue({
    required String label,
    required double? value,
    required String unit,
    double fontSize = 32,
  }) {
    final hasValue = value != null && !value.isNaN;
    final text = hasValue ? value.toStringAsFixed(1) : '---';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1E30), MaritimePalette.deepHull],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: MaritimePalette.consoleBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: MaritimePalette.brass,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                text,
                style: TextStyle(
                  color: hasValue
                      ? MaritimePalette.foam
                      : MaritimePalette.foamDim,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  fontFeatures: kTabular,
                  shadows: hasValue
                      ? const [
                          Shadow(color: MaritimePalette.foam, blurRadius: 4),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                unit,
                style: const TextStyle(
                  color: MaritimePalette.foamDim,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shallowAlarm({required double? depthM, required bool isShallow}) {
    final Color bgColor;
    final Color textColor;
    final String text;
    final List<Shadow>? shadows;

    if (depthM == null) {
      bgColor = MaritimePalette.lampOff;
      textColor = MaritimePalette.foamDim;
      text = 'NO DATA';
      shadows = null;
    } else if (isShallow) {
      bgColor = MaritimePalette.lampRed.withValues(alpha: 0.3);
      textColor = MaritimePalette.lampRed;
      text = 'SHALLOW';
      shadows = [const Shadow(color: MaritimePalette.lampRed, blurRadius: 8)];
    } else {
      bgColor = MaritimePalette.lampGreen.withValues(alpha: 0.15);
      textColor = MaritimePalette.lampGreen;
      text = 'DEPTH OK';
      shadows = null;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isShallow
              ? MaritimePalette.lampRed.withValues(alpha: 0.5)
              : MaritimePalette.consoleBorder,
          width: isShallow ? 1.0 : 0.5,
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
            shadows: shadows,
          ),
        ),
      ),
    );
  }
}

// ── Vertical depth gauge ────────────────────────────────────────────────────

class _DepthGauge extends StatelessWidget {
  const _DepthGauge({required this.depthM, required this.maxDepth});

  final double depthM;
  final double maxDepth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DepthGaugePainter(depthM: depthM, maxDepth: maxDepth),
      child: const SizedBox.expand(),
    );
  }
}

class _DepthGaugePainter extends CustomPainter {
  _DepthGaugePainter({required this.depthM, required this.maxDepth});

  final double depthM;
  final double maxDepth;

  static const List<double> _ticks = [
    0,
    5,
    10,
    15,
    20,
    25,
    30,
    40,
    50,
    75,
    100,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final gaugeWidth = min(size.width * 0.5, 60.0);
    final gaugeLeft = (size.width - gaugeWidth) / 2;
    final gaugeTop = 8.0;
    final gaugeHeight = size.height - 16;
    final gaugeRect = Rect.fromLTWH(
      gaugeLeft,
      gaugeTop,
      gaugeWidth,
      gaugeHeight,
    );
    final gaugeRRect = RRect.fromRectAndRadius(
      gaugeRect,
      const Radius.circular(6),
    );

    // Outer metallic bezel
    final bezelPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(gaugeLeft - 3, 0),
        Offset(gaugeLeft + gaugeWidth + 3, 0),
        [
          MaritimePalette.brass,
          MaritimePalette.consoleBorder,
          const Color(0xFF0F1A2A),
          MaritimePalette.consoleBorder,
          MaritimePalette.brass,
        ],
        [0.0, 0.2, 0.5, 0.8, 1.0],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRRect(gaugeRRect, bezelPaint);

    // Highlight on bezel
    final hlPaint = Paint()
      ..color = MaritimePalette.brassBright.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(gaugeRect.inflate(2), const Radius.circular(8)),
      hlPaint,
    );

    // Dark inner fill
    final innerRect = gaugeRect.deflate(2);
    final innerRRect = RRect.fromRectAndRadius(
      innerRect,
      const Radius.circular(4),
    );
    canvas.save();
    canvas.clipRRect(innerRRect);

    final darkFill = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, innerRect.top),
        Offset(0, innerRect.bottom),
        [const Color(0xFF0A2840), const Color(0xFF061520)],
      );
    canvas.drawRect(innerRect, darkFill);

    // Water fill — inverted: shallow = more fill from bottom
    final depthClamped = depthM.clamp(0.0, maxDepth);
    // fraction 1 at depth=0 (full), 0 at depth=maxDepth (empty)
    final fillFrac = 1.0 - (depthClamped / maxDepth);
    final fillHeight = innerRect.height * fillFrac;
    final fillTop = innerRect.bottom - fillHeight;

    if (fillHeight > 0) {
      final fillPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, fillTop),
          Offset(0, innerRect.bottom),
          [const Color(0xFF1A4A6B), const Color(0xFF0A2840)],
        );
      canvas.drawRect(
        Rect.fromLTWH(innerRect.left, fillTop, innerRect.width, fillHeight),
        fillPaint,
      );
    }

    canvas.restore();

    // Tick marks and labels
    for (final tick in _ticks) {
      if (tick > maxDepth) continue;
      final frac = tick / maxDepth;
      final y = innerRect.top + frac * innerRect.height;

      // Tick line to the left of the gauge
      final tickLeft = gaugeLeft - 14;
      final tickRight = gaugeLeft - 2;
      final isMajor = tick % 10 == 0 || tick == 5 || tick == 75;

      canvas.drawLine(
        Offset(tickLeft, y),
        Offset(tickRight, y),
        Paint()
          ..color = isMajor
              ? MaritimePalette.foam
              : MaritimePalette.consoleBorder
          ..strokeWidth = isMajor ? 1.5 : 0.8,
      );

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: tick.toStringAsFixed(0),
          style: TextStyle(
            color: MaritimePalette.foamDim,
            fontSize: isMajor ? 10 : 8,
            fontFeatures: kTabular,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(tickLeft - tp.width - 4, y - tp.height / 2));
    }

    // Current depth marker line
    final markerFrac = depthClamped / maxDepth;
    final markerY = innerRect.top + markerFrac * innerRect.height;

    // Glow
    canvas.drawLine(
      Offset(gaugeLeft - 2, markerY),
      Offset(gaugeLeft + gaugeWidth + 2, markerY),
      Paint()
        ..color = MaritimePalette.foam
        ..strokeWidth = 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Sharp line
    canvas.drawLine(
      Offset(gaugeLeft - 2, markerY),
      Offset(gaugeLeft + gaugeWidth + 2, markerY),
      Paint()
        ..color = MaritimePalette.foam
        ..strokeWidth = 2,
    );

    // Digital depth readout near the marker (to the right)
    final depthStr = depthM.toStringAsFixed(1);
    final depthTp = TextPainter(
      text: TextSpan(
        text: '$depthStr m',
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

    final labelX = gaugeLeft + gaugeWidth + 8;
    final labelY = (markerY - depthTp.height / 2).clamp(
      innerRect.top,
      innerRect.bottom - depthTp.height,
    );
    depthTp.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(_DepthGaugePainter old) =>
      old.depthM != depthM || old.maxDepth != maxDepth;
}
