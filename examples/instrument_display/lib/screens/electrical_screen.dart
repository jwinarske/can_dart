import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/n2k_service.dart';
import '../theme/maritime_theme.dart';
import '../widgets/arc_gauge.dart';

/// Electrical page — two-column layout with battery voltage arc gauge and fuel
/// tank indicator on the left, and recessed-panel readouts for voltage, current,
/// fuel level, and charging state on the right.
class ElectricalScreen extends StatelessWidget {
  const ElectricalScreen({super.key, required this.service});

  final N2kService service;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final voltage = service.signal('batteryVoltage');
        final current = service.signal('batteryCurrent');
        final fuelLevel = service.signal('level');

        final isCharging = current != null && current > 0;

        return Container(
          color: MaritimePalette.deepHull,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: arc gauge + fuel tank
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      // Voltage arc gauge
                      Expanded(
                        flex: 3,
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
                                  child: ArcGauge(
                                    value: voltage,
                                    min: 10,
                                    max: 16,
                                    label: 'VOLTS',
                                    unit: 'V',
                                    decimals: 1,
                                    warningThreshold: 11.5,
                                    dangerThreshold: 11.0,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      _sectionHeader('FUEL TANK'),
                      const SizedBox(height: 6),
                      // Fuel tank indicator
                      Expanded(
                        flex: 2,
                        child: _FuelTankIndicator(percent: fuelLevel ?? 0),
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
                      _sectionHeader('BATTERY VOLTAGE'),
                      const SizedBox(height: 6),
                      _recessedValue(
                        label: 'VOLTAGE',
                        value: voltage,
                        unit: 'V',
                        fontSize: 36,
                        decimals: 2,
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader('BATTERY CURRENT'),
                      const SizedBox(height: 6),
                      _recessedValue(
                        label: 'CURRENT',
                        value: current,
                        unit: 'A',
                        fontSize: 32,
                        decimals: 1,
                        valueColor: current != null
                            ? (current > 0
                                  ? MaritimePalette.lampGreen
                                  : MaritimePalette.lampAmber)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader('FUEL LEVEL'),
                      const SizedBox(height: 6),
                      _recessedValue(
                        label: 'FUEL',
                        value: fuelLevel,
                        unit: '%',
                        fontSize: 36,
                        decimals: 0,
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader('CHARGE STATE'),
                      const SizedBox(height: 6),
                      _chargingIndicator(
                        current: current,
                        isCharging: isCharging,
                      ),
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
    int decimals = 1,
    Color? valueColor,
  }) {
    final hasValue = value != null && !value.isNaN;
    final text = hasValue ? value.toStringAsFixed(decimals) : '---';
    final color =
        valueColor ??
        (hasValue ? MaritimePalette.foam : MaritimePalette.foamDim);

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
                  color: color,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  fontFeatures: kTabular,
                  shadows: hasValue
                      ? [Shadow(color: color, blurRadius: 4)]
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

  Widget _chargingIndicator({
    required double? current,
    required bool isCharging,
  }) {
    final Color bgColor;
    final Color textColor;
    final String text;
    final List<Shadow>? shadows;

    if (current == null) {
      bgColor = MaritimePalette.lampOff;
      textColor = MaritimePalette.foamDim;
      text = 'NO DATA';
      shadows = null;
    } else if (isCharging) {
      bgColor = MaritimePalette.lampGreen.withValues(alpha: 0.15);
      textColor = MaritimePalette.lampGreen;
      text = 'CHARGING';
      shadows = [const Shadow(color: MaritimePalette.lampGreen, blurRadius: 6)];
    } else {
      bgColor = MaritimePalette.lampAmber.withValues(alpha: 0.15);
      textColor = MaritimePalette.lampAmber;
      text = 'ON BATTERY';
      shadows = [const Shadow(color: MaritimePalette.lampAmber, blurRadius: 6)];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: MaritimePalette.consoleBorder, width: 0.5),
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

// ── Fuel tank indicator ─────────────────────────────────────────────────────

class _FuelTankIndicator extends StatelessWidget {
  const _FuelTankIndicator({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FuelTankPainter(percent: percent),
      child: const SizedBox.expand(),
    );
  }
}

class _FuelTankPainter extends CustomPainter {
  _FuelTankPainter({required this.percent});

  final double percent;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final tankWidth = min(size.width * 0.6, 80.0);
    final tankLeft = cx - tankWidth / 2;
    final tankTop = 4.0;
    final tankHeight = size.height - 8;
    final tankRect = Rect.fromLTWH(tankLeft, tankTop, tankWidth, tankHeight);
    final tankRRect = RRect.fromRectAndRadius(
      tankRect,
      const Radius.circular(8),
    );

    // Metallic bezel
    final bezelPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(tankLeft - 2, 0),
        Offset(tankLeft + tankWidth + 2, 0),
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
      ..strokeWidth = 3;
    canvas.drawRRect(tankRRect, bezelPaint);

    // Highlight
    canvas.drawRRect(
      RRect.fromRectAndRadius(tankRect.inflate(1.5), const Radius.circular(10)),
      Paint()
        ..color = MaritimePalette.brassBright.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Dark inner fill
    final innerRect = tankRect.deflate(2);
    final innerRRect = RRect.fromRectAndRadius(
      innerRect,
      const Radius.circular(6),
    );
    canvas.save();
    canvas.clipRRect(innerRRect);

    canvas.drawRect(innerRect, Paint()..color = const Color(0xFF061520));

    // Fuel fill from bottom
    final frac = (percent / 100).clamp(0.0, 1.0);
    final fillHeight = innerRect.height * frac;
    final fillTop = innerRect.bottom - fillHeight;

    if (fillHeight > 0) {
      // Color: green above 25%, amber 10-25%, red below 10%
      Color fillColorTop;
      Color fillColorBottom;
      if (percent > 25) {
        fillColorTop = MaritimePalette.lampGreen.withValues(alpha: 0.7);
        fillColorBottom = MaritimePalette.lampAmber.withValues(alpha: 0.5);
      } else if (percent > 10) {
        fillColorTop = MaritimePalette.lampAmber.withValues(alpha: 0.7);
        fillColorBottom = MaritimePalette.lampAmber.withValues(alpha: 0.3);
      } else {
        fillColorTop = MaritimePalette.lampRed.withValues(alpha: 0.7);
        fillColorBottom = MaritimePalette.lampRed.withValues(alpha: 0.3);
      }

      final fillPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, fillTop),
          Offset(0, innerRect.bottom),
          [fillColorTop, fillColorBottom],
        );
      canvas.drawRect(
        Rect.fromLTWH(innerRect.left, fillTop, innerRect.width, fillHeight),
        fillPaint,
      );
    }

    canvas.restore();

    // Percentage text centered
    final pctStr = '${percent.toStringAsFixed(0)}%';
    final tp = TextPainter(
      text: TextSpan(
        text: pctStr,
        style: const TextStyle(
          color: MaritimePalette.foam,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          fontFeatures: kTabular,
          shadows: [Shadow(color: MaritimePalette.foam, blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(cx - tp.width / 2, tankTop + tankHeight / 2 - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_FuelTankPainter old) => old.percent != percent;
}
