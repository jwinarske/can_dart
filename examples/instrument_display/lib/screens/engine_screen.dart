import 'package:flutter/material.dart';

import '../services/n2k_service.dart';
import '../theme/maritime_theme.dart';
import '../widgets/arc_gauge.dart';
import '../widgets/linear_gauge.dart';

/// Engine page — two-column layout with large RPM arc gauge and stacked
/// recessed-panel readouts for oil pressure, coolant temp, fuel rate, hours,
/// engine load, and gear indicator.
class EngineScreen extends StatelessWidget {
  const EngineScreen({super.key, required this.service});

  final N2kService service;

  static const _gearNames = {0: 'FWD', 1: 'N', 2: 'REV'};

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final rpm = service.signal('engineSpeed');
        final oilPa = service.signal('oilPressure');
        final tempK = service.signal('temperature');
        final fuelM3h = service.signal('fuelRate');
        final hoursSec = service.signal('totalEngineHours');
        final gear = service.signal('transmissionGear');
        final load = service.signal('percentEngineLoad');

        final oilKpa = oilPa != null ? oilPa / 1000 : null;
        final tempC = tempK != null ? tempK - 273.15 : null;
        final fuelLh = fuelM3h != null ? fuelM3h * 1000 : null;
        final hours = hoursSec != null ? hoursSec / 3600 : null;
        final gearLabel = gear != null
            ? (_gearNames[gear.toInt()] ?? '?')
            : '---';

        Color gearColor = MaritimePalette.lampAmber;
        if (gearLabel == 'FWD') gearColor = MaritimePalette.lampGreen;
        if (gearLabel == 'REV') gearColor = MaritimePalette.lampRed;

        return Container(
          color: MaritimePalette.deepHull,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: large RPM arc gauge
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side = constraints.maxWidth < constraints.maxHeight
                          ? constraints.maxWidth
                          : constraints.maxHeight;
                      return Center(
                        child: SizedBox(
                          width: side,
                          height: side,
                          child: FittedBox(
                            child: ArcGauge(
                              value: rpm,
                              min: 0,
                              max: 4000,
                              label: 'RPM',
                              unit: 'rpm',
                              warningThreshold: 3000,
                              dangerThreshold: 3500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Right: stacked readouts
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('OIL PRESSURE'),
                      const SizedBox(height: 6),
                      _recessedValue(
                        label: 'OIL',
                        value: oilKpa,
                        unit: 'kPa',
                        fontSize: 28,
                      ),
                      const SizedBox(height: 4),
                      LinearGauge(
                        value: oilKpa,
                        min: 0,
                        max: 800,
                        warningThreshold: 600,
                        dangerThreshold: 700,
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader('COOLANT TEMP'),
                      const SizedBox(height: 6),
                      _recessedValue(
                        label: 'TEMP',
                        value: tempC,
                        unit: '\u00B0C',
                        fontSize: 28,
                      ),
                      const SizedBox(height: 4),
                      LinearGauge(
                        value: tempC,
                        min: 0,
                        max: 120,
                        warningThreshold: 95,
                        dangerThreshold: 105,
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader('FUEL & HOURS'),
                      const SizedBox(height: 6),
                      _recessedValue(
                        label: 'FUEL RATE',
                        value: fuelLh,
                        unit: 'L/h',
                        fontSize: 24,
                      ),
                      const SizedBox(height: 4),
                      _recessedValue(
                        label: 'ENGINE HOURS',
                        value: hours,
                        unit: 'h',
                        fontSize: 24,
                      ),
                      if (load != null) ...[
                        const SizedBox(height: 12),
                        _sectionHeader('ENGINE LOAD'),
                        const SizedBox(height: 6),
                        _recessedValue(
                          label: 'LOAD',
                          value: load,
                          unit: '%',
                          fontSize: 24,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _sectionHeader('GEAR'),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF0D1E30),
                              MaritimePalette.deepHull,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: MaritimePalette.consoleBorder,
                            width: 0.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            gearLabel,
                            style: TextStyle(
                              color: gearColor,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              fontFeatures: kTabular,
                              shadows: [
                                Shadow(color: gearColor, blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
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
}
