import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';

/// Reusable widget for displaying a numeric value with label and unit.
///
/// Shows "---" when value is null (no data received yet).
/// Uses tabular figures so digits don't dance on updates.
/// Styled as a recessed instrument panel with subtle LED glow on values.
class ValueDisplay extends StatelessWidget {
  const ValueDisplay({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.decimals = 1,
    this.fontSize = 36,
  });

  final String label;
  final double? value;
  final String unit;
  final int decimals;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && !value!.isNaN;
    final valueText = hasValue ? value!.toStringAsFixed(decimals) : '---';

    // Slightly lighter shade of deepHull for recessed gradient bottom
    const recessLight = Color(0xFF0D1E30);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MaritimePalette.deepHull, recessLight],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MaritimePalette.consoleBorder),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                valueText,
                style: TextStyle(
                  color: hasValue
                      ? MaritimePalette.foam
                      : MaritimePalette.foamDim,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  fontFeatures: kTabular,
                  shadows: hasValue
                      ? const [
                          Shadow(color: MaritimePalette.foam, blurRadius: 8),
                        ]
                      : null,
                ),
              ),
              if (unit.isNotEmpty) ...[
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
            ],
          ),
        ],
      ),
    );
  }
}
