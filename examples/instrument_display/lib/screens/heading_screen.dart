import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/n2k_service.dart';
import '../theme/maritime_theme.dart';
import '../widgets/compass_indicator.dart';

/// Heading page — large compass indicator with heading, rate of turn, rudder
/// angle readouts, and a horizontal rudder angle bar.
class HeadingScreen extends StatelessWidget {
  const HeadingScreen({super.key, required this.service});

  final N2kService service;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final headingRad = service.signal('heading');
        final rateRadS = service.signal('rate');
        final rudderRad = service.signal('position');

        final headingDeg = headingRad != null
            ? (headingRad * 180.0 / pi) % 360
            : null;
        final rateDegMin = rateRadS != null
            ? rateRadS * 180.0 / pi * 60.0
            : null;
        final rudderDeg = rudderRad != null ? rudderRad * 180.0 / pi : null;

        // Rate of turn suffix
        String rotSuffix = '';
        if (rateDegMin != null) {
          rotSuffix = rateDegMin >= 0 ? 'STBD' : 'PORT';
        }

        // Rudder suffix
        String rudderSuffix = '';
        if (rudderDeg != null) {
          rudderSuffix = rudderDeg >= 0 ? 'STBD' : 'PORT';
        }

        return Container(
          color: MaritimePalette.deepHull,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: large compass indicator
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side = min(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return Center(
                        child: SizedBox(
                          width: side,
                          height: side,
                          child: FittedBox(
                            child: CompassIndicator(
                              headingDeg: headingDeg ?? 0,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Right: readouts + rudder bar
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Readouts
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionHeader('HEADING'),
                            const SizedBox(height: 6),
                            _recessedValue(
                              label: 'HDG',
                              value: headingDeg,
                              unit: '\u00B0',
                              fontSize: 36,
                            ),
                            const SizedBox(height: 12),
                            _sectionHeader('RATE OF TURN'),
                            const SizedBox(height: 6),
                            _recessedValueWithSuffix(
                              label: 'ROT',
                              value: rateDegMin,
                              unit: '\u00B0/min',
                              suffix: rotSuffix,
                              suffixColor: rateDegMin != null
                                  ? (rateDegMin >= 0
                                        ? MaritimePalette.starboardGreen
                                        : MaritimePalette.portRed)
                                  : MaritimePalette.foamDim,
                              fontSize: 28,
                            ),
                            const SizedBox(height: 12),
                            _sectionHeader('RUDDER ANGLE'),
                            const SizedBox(height: 6),
                            _recessedValueWithSuffix(
                              label: 'RUDDER',
                              value: rudderDeg,
                              unit: '\u00B0',
                              suffix: rudderSuffix,
                              suffixColor: rudderDeg != null
                                  ? (rudderDeg >= 0
                                        ? MaritimePalette.starboardGreen
                                        : MaritimePalette.portRed)
                                  : MaritimePalette.foamDim,
                              fontSize: 28,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Rudder bar at the bottom
                    const SizedBox(height: 8),
                    _sectionHeader('RUDDER'),
                    const SizedBox(height: 6),
                    _RudderBar(rudderDeg: rudderDeg ?? 0),
                  ],
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

  Widget _recessedValueWithSuffix({
    required String label,
    required double? value,
    required String unit,
    required String suffix,
    required Color suffixColor,
    double fontSize = 28,
  }) {
    final hasValue = value != null && !value.isNaN;
    final text = hasValue ? value.abs().toStringAsFixed(1) : '---';

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
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  color: MaritimePalette.foamDim,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (suffix.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  suffix,
                  style: TextStyle(
                    color: suffixColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Horizontal rudder angle bar ─────────────────────────────────────────────

class _RudderBar extends StatelessWidget {
  const _RudderBar({required this.rudderDeg});

  final double rudderDeg;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1E30), MaritimePalette.deepHull],
        ),
        border: Border.all(color: MaritimePalette.consoleBorder, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CustomPaint(
          painter: _RudderBarPainter(rudderDeg: rudderDeg),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _RudderBarPainter extends CustomPainter {
  _RudderBarPainter({required this.rudderDeg});

  final double rudderDeg;

  static const double _maxAngle = 35.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Port (left) background tint — red
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cx, size.height),
      Paint()..color = MaritimePalette.portRed.withValues(alpha: 0.05),
    );

    // Starboard (right) background tint — green
    canvas.drawRect(
      Rect.fromLTWH(cx, 0, cx, size.height),
      Paint()..color = MaritimePalette.starboardGreen.withValues(alpha: 0.05),
    );

    // Center line
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height),
      Paint()
        ..color = MaritimePalette.brassBright
        ..strokeWidth = 1.5,
    );

    // Tick marks at 5-degree intervals
    for (var deg = -35; deg <= 35; deg += 5) {
      final frac = (deg / _maxAngle + 1) / 2; // 0..1
      final x = frac * size.width;
      final isMajor = deg % 10 == 0;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, isMajor ? 8 : 5),
        Paint()
          ..color = isMajor
              ? MaritimePalette.foam
              : MaritimePalette.consoleBorder
          ..strokeWidth = isMajor ? 1.0 : 0.5,
      );

      // Labels at 0, 10, 20, 30
      if (isMajor) {
        final labelText = deg.abs().toString();
        final tp = TextPainter(
          text: TextSpan(
            text: '$labelText\u00B0',
            style: TextStyle(
              color: deg == 0
                  ? MaritimePalette.brassBright
                  : MaritimePalette.foamDim,
              fontSize: 8,
              fontFeatures: kTabular,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 10));
      }
    }

    // PORT / STBD labels
    _drawSideLabel(
      canvas,
      'PORT',
      size.width * 0.15,
      cy + 6,
      MaritimePalette.portRed,
    );
    _drawSideLabel(
      canvas,
      'STBD',
      size.width * 0.85,
      cy + 6,
      MaritimePalette.starboardGreen,
    );

    // Rudder indicator marker
    final clampedDeg = rudderDeg.clamp(-_maxAngle, _maxAngle);
    final markerFrac = (clampedDeg / _maxAngle + 1) / 2;
    final markerX = markerFrac * size.width;

    // Glow
    canvas.drawLine(
      Offset(markerX, 0),
      Offset(markerX, size.height),
      Paint()
        ..color = MaritimePalette.foam
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Sharp marker line
    canvas.drawLine(
      Offset(markerX, 0),
      Offset(markerX, size.height),
      Paint()
        ..color = MaritimePalette.foam
        ..strokeWidth = 2.5,
    );

    // Marker triangle at bottom
    final triPath = Path()
      ..moveTo(markerX, size.height)
      ..lineTo(markerX - 5, size.height + 1)
      ..lineTo(markerX + 5, size.height + 1)
      ..close();
    canvas.drawPath(
      triPath,
      Paint()
        ..color = MaritimePalette.foam
        ..style = PaintingStyle.fill,
    );

    // Digital readout
    final rdStr =
        '${clampedDeg.abs().toStringAsFixed(1)}\u00B0 ${clampedDeg >= 0 ? 'STBD' : 'PORT'}';
    final rdTp = TextPainter(
      text: TextSpan(
        text: rdStr,
        style: const TextStyle(
          color: MaritimePalette.foam,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFeatures: kTabular,
          shadows: [Shadow(color: MaritimePalette.foam, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rdTp.paint(canvas, Offset(cx - rdTp.width / 2, size.height - 16));

    // Edge fade gradients
    final fadeWidth = size.width * 0.08;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, fadeWidth, size.height),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(fadeWidth, 0), [
          MaritimePalette.deepHull,
          MaritimePalette.deepHull.withValues(alpha: 0),
        ]),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - fadeWidth, 0, fadeWidth, size.height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width - fadeWidth, 0),
          Offset(size.width, 0),
          [
            MaritimePalette.deepHull.withValues(alpha: 0),
            MaritimePalette.deepHull,
          ],
        ),
    );
  }

  void _drawSideLabel(
    Canvas canvas,
    String text,
    double x,
    double y,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withValues(alpha: 0.5),
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y));
  }

  @override
  bool shouldRepaint(_RudderBarPainter old) => old.rudderDeg != rudderDeg;
}
