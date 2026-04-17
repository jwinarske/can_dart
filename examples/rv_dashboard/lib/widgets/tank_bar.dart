import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/cabin_theme.dart';

/// Vertical tank level indicator with metallic bezel, gradient fill,
/// surface line, tick marks, and warning colors.
class TankBar extends StatelessWidget {
  const TankBar({
    super.key,
    required this.level,
    required this.label,
    this.fillColor = CabinPalette.lampGreen,
    this.tankType,
  });

  /// Fill level 0-100 (clamped).
  final double? level;

  /// Tank name label shown below the bar.
  final String label;

  /// Fill colour for the tank bar.
  final Color fillColor;

  /// Optional tank type for warning logic: 'fresh', 'gray', 'black', 'lpg'.
  final String? tankType;

  @override
  Widget build(BuildContext context) {
    final pct = (level ?? 0).clamp(0.0, 100.0);
    final isLow = _isLowWarning(pct);
    final isCritical = _isCriticalWarning(pct);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tank type icon/label at the top
        Text(
          _tankIcon,
          style: TextStyle(
            color: isCritical
                ? CabinPalette.lampRed
                : isLow
                ? CabinPalette.lampAmber
                : CabinPalette.copper,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        // Tank bar
        Expanded(
          child: SizedBox(
            width: 80,
            child: CustomPaint(
              painter: _TankBarPainter(
                level: pct / 100.0,
                fillColor: fillColor,
                hasData: level != null,
                isLow: isLow,
                isCritical: isCritical,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Label
        Text(
          label,
          style: TextStyle(
            color: isCritical
                ? CabinPalette.lampRed
                : isLow
                ? CabinPalette.lampAmber
                : CabinPalette.copper,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String get _tankIcon {
    switch (tankType) {
      case 'fresh':
        return '\u{1F4A7}'; // droplet
      case 'gray':
        return '\u{1F6BF}'; // shower
      case 'black':
        return '\u{1F6BD}'; // toilet
      case 'lpg':
        return '\u{1F525}'; // fire
      default:
        return '';
    }
  }

  bool _isLowWarning(double pct) {
    if (tankType == 'fresh' || tankType == 'lpg') {
      return pct < 15 && pct >= 5;
    }
    return false;
  }

  bool _isCriticalWarning(double pct) {
    if (tankType == 'fresh' || tankType == 'lpg') {
      return pct < 5;
    }
    return false;
  }
}

class _TankBarPainter extends CustomPainter {
  _TankBarPainter({
    required this.level,
    required this.fillColor,
    required this.hasData,
    required this.isLow,
    required this.isCritical,
  });

  final double level; // 0.0 - 1.0
  final Color fillColor;
  final bool hasData;
  final bool isLow;
  final bool isCritical;

  @override
  void paint(Canvas canvas, Size size) {
    const bezelWidth = 3.0;
    const cornerRadius = 6.0;
    final outerRect = Offset.zero & size;
    final outerRRect = RRect.fromRectAndRadius(
      outerRect,
      const Radius.circular(cornerRadius),
    );
    final innerRect = outerRect.deflate(bezelWidth);
    final innerRRect = RRect.fromRectAndRadius(
      innerRect,
      const Radius.circular(cornerRadius - 2),
    );

    // --- Metallic bezel frame ---
    final bezelColor = isCritical
        ? CabinPalette.lampRed
        : isLow
        ? CabinPalette.lampAmber
        : CabinPalette.copper;
    final bezelPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(size.width, size.height),
        [
          bezelColor.withValues(alpha: 0.9),
          bezelColor.withValues(alpha: 0.3),
          bezelColor.withValues(alpha: 0.7),
          bezelColor.withValues(alpha: 0.2),
          bezelColor.withValues(alpha: 0.8),
        ],
        [0.0, 0.25, 0.5, 0.75, 1.0],
      );
    canvas.drawRRect(outerRRect, bezelPaint);

    // Inner background (dark recessed area)
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, size.height), [
        const Color(0xFF0D0804),
        const Color(0xFF1A1008),
      ]);
    canvas.drawRRect(innerRRect, bgPaint);

    // --- Gradient fill ---
    if (hasData && level > 0) {
      final fillHeight = innerRect.height * level;
      final fillTop = innerRect.top + innerRect.height - fillHeight;

      canvas.save();
      canvas.clipRRect(innerRRect);

      // Main liquid fill with vertical gradient (lighter at top, darker at bottom)
      final lighterFill = Color.lerp(fillColor, Colors.white, 0.3)!;
      final darkerFill = Color.lerp(fillColor, Colors.black, 0.4)!;
      final fillPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, fillTop),
          Offset(0, innerRect.bottom),
          [
            lighterFill.withValues(alpha: 0.85),
            fillColor.withValues(alpha: 0.7),
            darkerFill.withValues(alpha: 0.6),
          ],
          [0.0, 0.4, 1.0],
        );

      final fillRect = Rect.fromLTRB(
        innerRect.left,
        fillTop,
        innerRect.right,
        innerRect.bottom,
      );
      canvas.drawRect(fillRect, fillPaint);

      // --- Surface line with glow ---
      if (level > 0.02) {
        // Glow behind the surface line
        final glowPaint = Paint()
          ..color = lighterFill.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawLine(
          Offset(innerRect.left, fillTop),
          Offset(innerRect.right, fillTop),
          glowPaint,
        );

        // Bright surface line
        final linePaint = Paint()
          ..color = lighterFill.withValues(alpha: 0.9)
          ..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawLine(
          Offset(innerRect.left, fillTop),
          Offset(innerRect.right, fillTop),
          linePaint,
        );
      }

      canvas.restore();

      // --- Large percentage text centered at fill level ---
      final pctText = '${(level * 100).toStringAsFixed(0)}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: pctText,
          style: TextStyle(
            color: CabinPalette.warmWhite,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFeatures: kTabular,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Position: centered horizontally, vertically at fill level
      // but clamped so text stays within the bar
      final textY =
          (fillTop + math.min(fillHeight / 2, 20) - textPainter.height / 2)
              .clamp(
                innerRect.top + 2,
                innerRect.bottom - textPainter.height - 2,
              );
      final textX = innerRect.left + (innerRect.width - textPainter.width) / 2;

      // Glow behind text
      final glowTextPainter = TextPainter(
        text: TextSpan(
          text: pctText,
          style: TextStyle(
            color: CabinPalette.warmWhite.withValues(alpha: 0.6),
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFeatures: kTabular,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.clipRRect(innerRRect);
      // Paint glow layer
      canvas.saveLayer(outerRect, Paint());
      glowTextPainter.paint(canvas, Offset(textX, textY));
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(
            textX + textPainter.width / 2,
            textY + textPainter.height / 2,
          ),
          width: textPainter.width + 16,
          height: textPainter.height + 12,
        ),
        Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
          ..blendMode = BlendMode.dstIn
          ..color = Colors.white,
      );
      canvas.restore();

      // Sharp text on top
      textPainter.paint(canvas, Offset(textX, textY));
      canvas.restore();
    } else if (!hasData) {
      // No data — show '---' centered
      final textPainter = TextPainter(
        text: const TextSpan(
          text: '---',
          style: TextStyle(
            color: CabinPalette.warmWhiteDim,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          innerRect.left + (innerRect.width - textPainter.width) / 2,
          innerRect.top + (innerRect.height - textPainter.height) / 2,
        ),
      );
    }

    // --- Tick marks on the right side ---
    const ticks = [0.0, 0.25, 0.50, 0.75, 1.0];
    const tickLabels = ['0', '25', '50', '75', '100'];
    final tickPaint = Paint()
      ..color = CabinPalette.warmWhiteDim.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    for (var i = 0; i < ticks.length; i++) {
      final y = innerRect.bottom - innerRect.height * ticks[i];
      // Tick line
      canvas.drawLine(
        Offset(innerRect.right - 8, y),
        Offset(innerRect.right - 2, y),
        tickPaint,
      );
      // Tick label
      final labelPainter = TextPainter(
        text: TextSpan(
          text: tickLabels[i],
          style: TextStyle(
            color: CabinPalette.warmWhiteDim.withValues(alpha: 0.4),
            fontSize: 7,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(
          innerRect.right - 8 - labelPainter.width - 2,
          y - labelPainter.height / 2,
        ),
      );
    }

    // --- Outer bezel highlight (thin bright line on top-left edges) ---
    final highlightPaint = Paint()
      ..color = bezelColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawRRect(outerRRect, highlightPaint);
  }

  @override
  bool shouldRepaint(_TankBarPainter old) =>
      old.level != level ||
      old.fillColor != fillColor ||
      old.hasData != hasData ||
      old.isLow != isLow ||
      old.isCritical != isCritical;
}
