import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';
import 'console_frame.dart';

/// Single value + unit tile. The ValueTile equivalent from charger_ui but
/// scaled down for the 480×272 display and styled with the maritime palette.
class ReadoutTile extends StatelessWidget {
  const ReadoutTile({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.accent,
    this.valueSize = 18,
  });

  final String label;
  final String value;
  final String unit;
  final Color? accent;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? MaritimePalette.foam;
    // The tile has a fixed "natural" size driven by the font metrics, but
    // the parent flex cells can shrink below that when the viewport is
    // tight. Wrap in a FittedBox so oversized content scales down instead
    // of overflowing — we keep the design at its intended size in the
    // common case and degrade gracefully when it doesn't fit.
    return ConsoleFrame(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 7,
                color: MaritimePalette.brass,
                letterSpacing: 0.8,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 1),
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: valueSize,
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: kTabular,
                ),
                children: [
                  TextSpan(text: value),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                        fontSize: valueSize * 0.55,
                        color: MaritimePalette.foamDim,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
