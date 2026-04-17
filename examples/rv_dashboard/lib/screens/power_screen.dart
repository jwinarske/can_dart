import 'dart:math';
import 'package:flutter/material.dart';

import '../services/rvc_service.dart';
import '../theme/cabin_theme.dart';
import '../widgets/status_card.dart';
import '../widgets/value_readout.dart';

/// Battery and power status — read-only page.
///
/// Shows battery SOC arc gauge (large, hero element) with battery icon outline,
/// voltage/current/temp readouts in a row, and prominent status indicators
/// for shore/generator/charger/inverter at the bottom.
class PowerScreen extends StatelessWidget {
  const PowerScreen({super.key, required this.service});

  final RvcService service;

  // DGN numbers (decimal equivalents of the hex constants).
  static const int _dcStatus1 = 0x1FFFD; // 131069
  static const int _dcStatus2 = 0x1FFFC; // 131068
  static const int _genStatus = 0x1FFDC; // 131036
  static const int _invStatus = 0x1FFC4; // 130948
  static const int _chgStatus = 0x1FFC7; // 130951

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final soc = service.signal(_dcStatus2, 0, 'stateOfCharge');
        final voltage = service.signal(_dcStatus1, 0, 'dcVoltage');
        final current = service.signal(_dcStatus1, 0, 'dcCurrent');
        final temp = service.signal(_dcStatus2, 0, 'sourceTemperature');

        final genStatus = service.signal(_genStatus, 0, 'operatingStatus');
        final invStatus = service.signal(_invStatus, 0, 'operatingStatus');
        final chgState = service.signal(_chgStatus, 0, 'operatingState');

        return Container(
          color: CabinPalette.darkWood,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'POWER',
                  style: TextStyle(
                    color: CabinPalette.copperBright,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Divider(color: CabinPalette.copper, height: 4),
                const SizedBox(height: 4),

                // Hero SOC gauge with battery outline
                Center(
                  child: SizedBox(
                    width: 240,
                    height: 220,
                    child: CustomPaint(
                      painter: _BatterySocPainter(soc: soc),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 30),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                soc != null
                                    ? '${soc.toStringAsFixed(0)}%'
                                    : '---',
                                style: TextStyle(
                                  color: CabinPalette.warmWhite,
                                  fontSize: 44,
                                  fontWeight: FontWeight.bold,
                                  fontFeatures: kTabular,
                                  shadows: soc != null
                                      ? [
                                          Shadow(
                                            color: _socColor(
                                              soc,
                                            ).withValues(alpha: 0.5),
                                            blurRadius: 12,
                                          ),
                                          Shadow(
                                            color: CabinPalette.warmWhite
                                                .withValues(alpha: 0.3),
                                            blurRadius: 6,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              const Text(
                                'STATE OF CHARGE',
                                style: TextStyle(
                                  color: CabinPalette.copper,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Battery readouts row
                Row(
                  children: [
                    Expanded(
                      child: ValueReadout(
                        label: 'VOLTAGE',
                        value: voltage != null
                            ? voltage.toStringAsFixed(1)
                            : '---',
                        unit: 'V',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ValueReadout(
                        label: 'CURRENT',
                        value: current != null
                            ? current.toStringAsFixed(1)
                            : '---',
                        unit: 'A',
                        valueColor: current != null
                            ? (current > 0
                                  ? CabinPalette.lampGreen
                                  : CabinPalette.lampAmber)
                            : CabinPalette.warmWhite,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ValueReadout(
                        label: 'TEMP',
                        value: temp != null ? temp.toStringAsFixed(0) : '---',
                        unit: '\u00B0C',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Status indicators — horizontal row of prominent icons
                Row(
                  children: [
                    Expanded(
                      child: _PowerStatusIndicator(
                        label: 'GENERATOR',
                        icon: Icons.electric_bolt,
                        active: genStatus != null && genStatus == 1,
                        activeColor: CabinPalette.lampGreen,
                        activeText: 'RUNNING',
                        inactiveText: 'STOPPED',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PowerStatusIndicator(
                        label: 'INVERTER',
                        icon: Icons.power,
                        active: invStatus != null && invStatus == 1,
                        activeColor: CabinPalette.lampGreen,
                        activeText: 'ON',
                        inactiveText: 'OFF',
                        fault: invStatus != null && invStatus == 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PowerStatusIndicator(
                        label: 'CHARGER',
                        icon: Icons.battery_charging_full,
                        active:
                            chgState != null && chgState > 0 && chgState != 2,
                        activeColor: CabinPalette.lampGreen,
                        activeText: _chargerStateText(chgState),
                        inactiveText: _chargerStateText(chgState),
                        fault: chgState != null && chgState.toInt() == 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Charger detail card
                StatusCard(
                  title: 'CHARGER DETAIL',
                  statusColor: _chargerLampColor(chgState),
                  statusText: _chargerStateText(chgState),
                  child: Row(
                    children: [
                      Expanded(
                        child: ValueReadout(
                          label: 'CHG VOLTAGE',
                          value: _fmtSignal(
                            service.signal(_chgStatus, 0, 'chargeVoltage'),
                            1,
                          ),
                          unit: 'V',
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ValueReadout(
                          label: 'CHG CURRENT',
                          value: _fmtSignal(
                            service.signal(_chgStatus, 0, 'chargeCurrent'),
                            1,
                          ),
                          unit: 'A',
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Color _socColor(double? soc) {
    if (soc == null) return CabinPalette.warmWhiteDim;
    if (soc > 50) return CabinPalette.lampGreen;
    if (soc > 20) return CabinPalette.lampAmber;
    return CabinPalette.lampRed;
  }

  String _fmtSignal(double? v, int decimals) =>
      v != null ? v.toStringAsFixed(decimals) : '---';

  Color _chargerLampColor(double? state) {
    if (state == null) return CabinPalette.lampOff;
    final s = state.toInt();
    if (s == 0) return CabinPalette.lampOff; // disabled
    if (s == 2) return CabinPalette.lampRed; // fault
    return CabinPalette.lampGreen; // any charging state
  }

  String _chargerStateText(double? state) {
    if (state == null) return '---';
    const labels = {
      0: 'DISABLED',
      1: 'ENABLED',
      2: 'FAULT',
      3: 'BULK',
      4: 'ABSORB',
      5: 'FLOAT',
      6: 'EQUALIZE',
    };
    return labels[state.toInt()] ?? '---';
  }
}

/// Prominent power status indicator with icon, glow, and label.
class _PowerStatusIndicator extends StatelessWidget {
  const _PowerStatusIndicator({
    required this.label,
    required this.icon,
    required this.active,
    this.activeColor = CabinPalette.lampGreen,
    this.activeText = 'ON',
    this.inactiveText = 'OFF',
    this.fault = false,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final String activeText;
  final String inactiveText;
  final bool fault;

  @override
  Widget build(BuildContext context) {
    final color = fault
        ? CabinPalette.lampRed
        : (active ? activeColor : CabinPalette.lampOff);
    final text = fault ? 'FAULT' : (active ? activeText : inactiveText);
    final isLit = active || fault;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF221610), Color(0xFF1A1008)],
        ),
        border: Border.all(
          color: isLit ? color.withValues(alpha: 0.4) : CabinPalette.woodBorder,
          width: isLit ? 1.2 : 0.8,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon with glow
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLit ? color.withValues(alpha: 0.15) : Colors.transparent,
              boxShadow: isLit
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: isLit ? color : CabinPalette.warmWhiteDim,
              size: 20,
              shadows: isLit
                  ? [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 8)]
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          // Label
          Text(
            label,
            style: const TextStyle(
              color: CabinPalette.copper,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          // Status text
          Text(
            text,
            style: TextStyle(
              color: isLit ? color : CabinPalette.warmWhiteDim,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Combined battery outline + SOC arc gauge painter.
/// Draws a battery icon shape behind the arc gauge.
class _BatterySocPainter extends CustomPainter {
  _BatterySocPainter({this.soc});

  final double? soc;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.55);
    final radius = size.width * 0.38;
    const startAngle = pi + pi / 6; // 210 degrees
    const sweepTotal = pi + pi / 3; // 240 degrees
    const strokeWidth = 14.0;

    // --- Battery outline behind the gauge ---
    _drawBatteryOutline(canvas, size, center);

    // --- Background arc ---
    final bgPaint = Paint()
      ..color = CabinPalette.lampOff
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      bgPaint,
    );

    // --- Filled arc with gradient and glow ---
    if (soc != null) {
      final pct = soc!.clamp(0.0, 100.0) / 100.0;
      final sweep = sweepTotal * pct;
      final arcColor = PowerScreen._socColor(soc);

      // Glow behind the arc
      final glowPaint = Paint()
        ..color = arcColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        glowPaint,
      );

      // Main arc
      final fgPaint = Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        fgPaint,
      );

      // Tick marks at 25%, 50%, 75%
      for (final tick in [0.25, 0.5, 0.75]) {
        final tickAngle = startAngle + sweepTotal * tick;
        final innerR = radius - strokeWidth / 2 - 2;
        final outerR = radius + strokeWidth / 2 + 2;
        final cosA = cos(tickAngle);
        final sinA = sin(tickAngle);
        final tickPaint = Paint()
          ..color = CabinPalette.warmWhiteDim.withValues(alpha: 0.3)
          ..strokeWidth = 1;
        canvas.drawLine(
          Offset(center.dx + innerR * cosA, center.dy + innerR * sinA),
          Offset(center.dx + outerR * cosA, center.dy + outerR * sinA),
          tickPaint,
        );
      }
    }
  }

  void _drawBatteryOutline(Canvas canvas, Size size, Offset center) {
    // Battery body: rounded rectangle centered behind the gauge
    final bodyWidth = size.width * 0.55;
    final bodyHeight = size.height * 0.35;
    final bodyRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + 8),
      width: bodyWidth,
      height: bodyHeight,
    );
    final bodyRRect = RRect.fromRectAndRadius(
      bodyRect,
      const Radius.circular(6),
    );

    final bodyPaint = Paint()
      ..color = CabinPalette.woodBorder.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(bodyRRect, bodyPaint);

    // Battery terminal nub on the right
    final nubRect = Rect.fromCenter(
      center: Offset(bodyRect.right + 4, center.dy + 8),
      width: 6,
      height: bodyHeight * 0.35,
    );
    final nubRRect = RRect.fromRectAndRadius(nubRect, const Radius.circular(2));
    canvas.drawRRect(nubRRect, bodyPaint);
  }

  @override
  bool shouldRepaint(_BatterySocPainter old) => old.soc != soc;
}
