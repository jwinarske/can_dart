import 'dart:math';

import 'package:flutter/material.dart';

/// A circular gauge widget for displaying OBD-II values.
class Gauge extends StatelessWidget {
  final String label;
  final String unit;
  final double value;
  final double min;
  final double max;
  final Color? color;

  const Gauge({
    super.key,
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gaugeColor = color ?? theme.colorScheme.primary;
    final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return SizedBox(
      width: 160,
      height: 180,
      child: Column(
        children: [
          SizedBox(
            width: 140,
            height: 140,
            child: CustomPaint(
              painter: _GaugePainter(
                fraction: fraction,
                color: gaugeColor,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatValue(value),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      unit,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatValue(double v) {
    if (v.abs() >= 1000) return v.toStringAsFixed(0);
    if (v.abs() >= 100) return v.toStringAsFixed(0);
    if (v.abs() >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(1);
  }
}

class _GaugePainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color backgroundColor;

  _GaugePainter({
    required this.fraction,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 8;
    const startAngle = 0.75 * pi; // 135 degrees
    const sweepAngle = 1.5 * pi;  // 270 degrees

    // Background arc
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * fraction,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      fraction != oldDelegate.fraction ||
      color != oldDelegate.color;
}
