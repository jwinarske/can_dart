import 'package:flutter/material.dart';

import '../theme/cabin_theme.dart';

/// Numeric readout for the cabin theme — recessed panel with glowing
/// warm white text and copper labels.
class ValueReadout extends StatelessWidget {
  const ValueReadout({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.fontSize = 28,
    this.labelFontSize = 11,
    this.valueColor = CabinPalette.warmWhite,
  });

  final String label;
  final String value;
  final String unit;
  final double fontSize;
  final double labelFontSize;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1008), Color(0xFF221610)],
        ),
        border: Border.all(color: CabinPalette.woodBorder, width: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: CabinPalette.copper,
              fontSize: labelFontSize,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  fontFeatures: kTabular,
                  shadows: value != '---'
                      ? [
                          Shadow(
                            color: valueColor.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    color: CabinPalette.warmWhiteDim,
                    fontSize: fontSize * 0.5,
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
