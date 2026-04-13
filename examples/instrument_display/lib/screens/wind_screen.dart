import 'dart:math';

import 'package:flutter/material.dart';

import '../services/n2k_service.dart';
import '../theme/maritime_theme.dart';
import '../widgets/wind_indicator.dart';

/// Wind page — large wind indicator with speed, angle, reference, and Beaufort
/// scale readouts styled as recessed brass-accented instrument panels.
class WindScreen extends StatelessWidget {
  const WindScreen({super.key, required this.service});

  final N2kService service;

  static const _referenceNames = {
    0: 'True (Ground)',
    1: 'Magnetic (Ground)',
    2: 'Apparent',
    3: 'True (Boat)',
    4: 'True (Water)',
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final speedMs = service.signal('windSpeed');
        final angleRad = service.signal('windAngle');
        final ref = service.signal('reference');

        final speedKts = speedMs != null ? speedMs * 1.94384 : null;
        final angleDeg = angleRad != null ? angleRad * 180.0 / pi : null;
        final refLabel = ref != null
            ? _referenceNames[ref.toInt()] ?? 'Unknown'
            : '---';

        // Port / starboard logic
        String angleSuffix = '';
        double? displayAngle = angleDeg;
        if (angleDeg != null) {
          final norm = angleDeg % 360;
          if (norm <= 180) {
            displayAngle = norm;
            angleSuffix = 'STBD';
          } else {
            displayAngle = 360 - norm;
            angleSuffix = 'PORT';
          }
        }

        // Beaufort scale
        final beaufort = _beaufort(speedKts ?? 0);

        return Container(
          color: MaritimePalette.deepHull,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: large wind indicator
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
                            child: WindIndicator(
                              angleDeg: angleDeg ?? 0,
                              speedKts: speedKts ?? 0,
                            ),
                          ),
                        ),
                      );
                    },
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
                      _sectionHeader('WIND SPEED'),
                      const SizedBox(height: 6),
                      _recessedPanel(
                        label: 'AWS',
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              speedKts != null
                                  ? speedKts.toStringAsFixed(1)
                                  : '---',
                              style: TextStyle(
                                color: speedKts != null
                                    ? MaritimePalette.foam
                                    : MaritimePalette.foamDim,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                fontFeatures: kTabular,
                                shadows: speedKts != null
                                    ? const [
                                        Shadow(
                                          color: MaritimePalette.foam,
                                          blurRadius: 4,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'kts',
                              style: TextStyle(
                                color: MaritimePalette.foamDim,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader('WIND ANGLE'),
                      const SizedBox(height: 6),
                      _recessedPanel(
                        label: 'AWA',
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              displayAngle != null
                                  ? '${displayAngle.toStringAsFixed(0)}\u00B0'
                                  : '---',
                              style: TextStyle(
                                color: displayAngle != null
                                    ? MaritimePalette.foam
                                    : MaritimePalette.foamDim,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                fontFeatures: kTabular,
                                shadows: displayAngle != null
                                    ? const [
                                        Shadow(
                                          color: MaritimePalette.foam,
                                          blurRadius: 4,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            if (angleSuffix.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                angleSuffix,
                                style: TextStyle(
                                  color: angleSuffix == 'STBD'
                                      ? MaritimePalette.starboardGreen
                                      : MaritimePalette.portRed,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader('REFERENCE'),
                      const SizedBox(height: 6),
                      _recessedPanel(
                        child: Text(
                          refLabel,
                          style: TextStyle(
                            color: ref != null
                                ? MaritimePalette.foam
                                : MaritimePalette.foamDim,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            shadows: ref != null
                                ? const [
                                    Shadow(
                                      color: MaritimePalette.foam,
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader('BEAUFORT SCALE'),
                      const SizedBox(height: 6),
                      _recessedPanel(
                        child: Text(
                          'F${beaufort.force} ${beaufort.name}',
                          style: TextStyle(
                            color: beaufort.color,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: beaufort.color, blurRadius: 4),
                            ],
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

  Widget _recessedPanel({String? label, required Widget child}) {
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
          if (label != null)
            Text(
              label,
              style: const TextStyle(
                color: MaritimePalette.brass,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          child,
        ],
      ),
    );
  }

  static _BeaufortEntry _beaufort(double kts) {
    if (kts < 1) { return _BeaufortEntry(0, 'Calm', MaritimePalette.lampGreen); }
    if (kts <= 3) { return _BeaufortEntry(1, 'Light air', MaritimePalette.lampGreen); }
    if (kts <= 6) { return _BeaufortEntry(2, 'Light breeze', MaritimePalette.lampGreen); }
    if (kts <= 10) { return _BeaufortEntry(3, 'Gentle breeze', MaritimePalette.lampGreen); }
    if (kts <= 16) { return _BeaufortEntry(4, 'Moderate breeze', MaritimePalette.lampGreen); }
    if (kts <= 21) { return _BeaufortEntry(5, 'Fresh breeze', MaritimePalette.lampAmber); }
    if (kts <= 27) { return _BeaufortEntry(6, 'Strong breeze', MaritimePalette.lampAmber); }
    if (kts <= 33) { return _BeaufortEntry(7, 'Near gale', MaritimePalette.lampAmber); }
    if (kts <= 40) { return _BeaufortEntry(8, 'Gale', MaritimePalette.lampRed); }
    if (kts <= 47) { return _BeaufortEntry(9, 'Strong gale', MaritimePalette.lampRed); }
    if (kts <= 55) { return _BeaufortEntry(10, 'Storm', MaritimePalette.lampRed); }
    if (kts <= 63) { return _BeaufortEntry(11, 'Violent storm', MaritimePalette.lampRed); }
    return _BeaufortEntry(12, 'Hurricane', MaritimePalette.lampRed);
  }
}

class _BeaufortEntry {
  const _BeaufortEntry(this.force, this.name, this.color);
  final int force;
  final String name;
  final Color color;
}
