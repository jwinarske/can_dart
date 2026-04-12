import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';

/// A tiny indicator lamp used for fault/state flags. Off = dark slate,
/// on = glowing colour with a soft halo so the dashboard feels alive
/// even at a glance.
class StatusLamp extends StatelessWidget {
  const StatusLamp({
    super.key,
    required this.label,
    required this.on,
    this.activeColor = MaritimePalette.lampRed,
    this.size = 8,
  });

  final String label;
  final bool on;
  final Color activeColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = on ? activeColor : MaritimePalette.lampOff;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.black, width: 0.5),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 7,
            color: on ? MaritimePalette.foam : MaritimePalette.foamDim,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
