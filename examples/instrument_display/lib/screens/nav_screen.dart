import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/n2k_service.dart';
import '../theme/maritime_theme.dart';
import '../widgets/rose_compass.dart';
import '../widgets/value_display.dart';

/// Navigation page — large compass rose with COG needle, heading bar,
/// position, SOG, and UTC time.
class NavScreen extends StatelessWidget {
  const NavScreen({super.key, required this.service});

  final N2kService service;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final lat = service.signal('latitude');
        final lon = service.signal('longitude');
        final cogRad = service.signal('cog');
        final sogMs = service.signal('sog');
        final headingRad = service.signal('heading');
        final timeSec = service.signal('secondsSinceMidnight');

        final cogDeg = cogRad != null ? (cogRad * 180.0 / pi) % 360 : 0.0;
        final headingDeg = headingRad != null
            ? (headingRad * 180.0 / pi) % 360
            : null;
        final sogKts = sogMs != null ? sogMs * 1.94384 : null;

        return Container(
          color: MaritimePalette.deepHull,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: compass rose + heading bar
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    // Rose compass — fills available space
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: RoseCompass(
                          cogDeg: cogDeg,
                          headingDeg: headingDeg,
                          sogKts: sogKts,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Heading bar below compass
                    _HeadingBar(cogDeg: cogDeg, headingDeg: headingDeg),
                  ],
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
                      _sectionHeader('POSITION'),
                      const SizedBox(height: 6),
                      _LatLonDisplay(label: 'LAT', degrees: lat, isLat: true),
                      const SizedBox(height: 4),
                      _LatLonDisplay(label: 'LON', degrees: lon, isLat: false),
                      const SizedBox(height: 16),
                      _sectionHeader('COURSE & SPEED'),
                      const SizedBox(height: 6),
                      _CogDisplay(cogDeg: cogRad != null ? cogDeg : null),
                      const SizedBox(height: 4),
                      ValueDisplay(
                        label: 'SOG',
                        value: sogKts,
                        unit: 'kts',
                        decimals: 1,
                        fontSize: 32,
                      ),
                      if (headingDeg != null) ...[
                        const SizedBox(height: 4),
                        ValueDisplay(
                          label: 'HDG',
                          value: headingDeg,
                          unit: '\u00B0',
                          decimals: 1,
                          fontSize: 32,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _sectionHeader('TIME (UTC)'),
                      const SizedBox(height: 6),
                      _TimeDisplay(secondsSinceMidnight: timeSec),
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
}

// ── Heading bar ──────────────────────────────────────────────────────────────
//
// A horizontal scrolling-tape heading indicator beneath the compass rose.
// Shows a graduated scale with the current heading centered, cardinal and
// intercardinal labels, and a fixed lubber-line triangle at the top centre.

class _HeadingBar extends StatelessWidget {
  const _HeadingBar({required this.cogDeg, this.headingDeg});

  final double cogDeg;
  final double? headingDeg;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1E30), MaritimePalette.deepHull],
        ),
        border: Border.all(color: MaritimePalette.consoleBorder, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CustomPaint(
          painter: _HeadingBarPainter(cogDeg: cogDeg, headingDeg: headingDeg),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _HeadingBarPainter extends CustomPainter {
  _HeadingBarPainter({required this.cogDeg, this.headingDeg});

  final double cogDeg;
  final double? headingDeg;

  static const _cardinals = {
    0: 'N',
    45: 'NE',
    90: 'E',
    135: 'SE',
    180: 'S',
    225: 'SW',
    270: 'W',
    315: 'NW',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    // Degrees visible in the bar width (wider window = more degrees).
    const visibleRange = 120.0;
    final pixPerDeg = size.width / visibleRange;

    // Draw tick marks and labels for the visible range.
    final startDeg = (cogDeg - visibleRange / 2).floor();
    final endDeg = (cogDeg + visibleRange / 2).ceil();

    for (var deg = startDeg; deg <= endDeg; deg++) {
      final normalized = ((deg % 360) + 360) % 360;
      final px = cx + (deg - cogDeg) * pixPerDeg;

      if (px < -20 || px > size.width + 20) continue;

      if (deg % 10 == 0) {
        // Major tick
        canvas.drawLine(
          Offset(px, 0),
          Offset(px, 10),
          Paint()
            ..color = MaritimePalette.foam
            ..strokeWidth = 1.5,
        );

        // Label
        final label = _cardinals[normalized];
        if (label != null) {
          // Cardinal / intercardinal
          final isCardinal = normalized % 90 == 0;
          final color = normalized == 0
              ? MaritimePalette.lampRed
              : (isCardinal ? MaritimePalette.foam : MaritimePalette.foamDim);
          _drawLabel(
            canvas,
            Offset(px, 18),
            label,
            color,
            isCardinal ? 13.0 : 10.0,
            true,
          );
        } else {
          // Degree number
          _drawLabel(
            canvas,
            Offset(px, 17),
            normalized.toString().padLeft(3, '0'),
            MaritimePalette.foamDim,
            9.0,
            false,
          );
        }
      } else if (deg % 5 == 0) {
        // Medium tick
        canvas.drawLine(
          Offset(px, 0),
          Offset(px, 6),
          Paint()
            ..color = MaritimePalette.foamDim
            ..strokeWidth = 1,
        );
      } else {
        // Minor tick
        canvas.drawLine(
          Offset(px, 0),
          Offset(px, 3),
          Paint()
            ..color = MaritimePalette.consoleBorder
            ..strokeWidth = 0.5,
        );
      }
    }

    // Heading ghost line (if heading differs from COG)
    if (headingDeg != null) {
      var hdgDelta = headingDeg! - cogDeg;
      if (hdgDelta > 180) hdgDelta -= 360;
      if (hdgDelta < -180) hdgDelta += 360;
      final hdgPx = cx + hdgDelta * pixPerDeg;
      if (hdgPx > 0 && hdgPx < size.width) {
        canvas.drawLine(
          Offset(hdgPx, 0),
          Offset(hdgPx, size.height),
          Paint()
            ..color = MaritimePalette.brass.withValues(alpha: 0.4)
            ..strokeWidth = 1.5,
        );
      }
    }

    // COG digital readout centered at bottom
    final cogStr = 'COG ${cogDeg.toStringAsFixed(1)}\u00B0';
    final cogTp = TextPainter(
      text: TextSpan(
        text: cogStr,
        style: const TextStyle(
          color: MaritimePalette.foam,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFeatures: kTabular,
          shadows: [Shadow(color: MaritimePalette.foam, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    cogTp.paint(canvas, Offset(cx - cogTp.width / 2, size.height - 16));

    // Fixed lubber-line triangle at top centre
    final lubberPath = Path()
      ..moveTo(cx, 0)
      ..lineTo(cx - 5, -1)
      ..lineTo(cx + 5, -1)
      ..close();
    canvas.drawPath(
      lubberPath,
      Paint()
        ..color = MaritimePalette.brassBright
        ..style = PaintingStyle.fill,
    );

    // Vertical centre reference line
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, 12),
      Paint()
        ..color = MaritimePalette.brassBright
        ..strokeWidth = 2,
    );

    // Edge fade gradients
    final fadeWidth = size.width * 0.12;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, fadeWidth, size.height),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(fadeWidth, 0), [
          MaritimePalette.deepHull,
          MaritimePalette.deepHull.withValues(alpha: 0),
        ]),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - fadeWidth, 0, fadeWidth, size.height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width - fadeWidth, 0),
          Offset(size.width, 0),
          [
            MaritimePalette.deepHull.withValues(alpha: 0),
            MaritimePalette.deepHull,
          ],
        ),
    );
  }

  void _drawLabel(
    Canvas canvas,
    Offset pos,
    String text,
    Color color,
    double fontSize,
    bool bold,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontFeatures: kTabular,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(_HeadingBarPainter old) =>
      old.cogDeg != cogDeg || old.headingDeg != headingDeg;
}

// ── Supporting display widgets ───────────────────────────────────────────────

class _LatLonDisplay extends StatelessWidget {
  const _LatLonDisplay({
    required this.label,
    required this.degrees,
    required this.isLat,
  });

  final String label;
  final double? degrees;
  final bool isLat;

  @override
  Widget build(BuildContext context) {
    String valueText = '---';
    if (degrees != null) {
      final abs = degrees!.abs();
      final deg = abs.floor();
      final min = (abs - deg) * 60;
      final hemisphere = isLat
          ? (degrees! >= 0 ? 'N' : 'S')
          : (degrees! >= 0 ? 'E' : 'W');
      valueText = "$deg\u00B0 ${min.toStringAsFixed(3)}' $hemisphere";
    }

    return Container(
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
          Text(
            valueText,
            style: const TextStyle(
              color: MaritimePalette.foam,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFeatures: kTabular,
              shadows: [Shadow(color: MaritimePalette.foam, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

class _CogDisplay extends StatelessWidget {
  const _CogDisplay({required this.cogDeg});

  final double? cogDeg;

  String _compassDirection(double deg) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((deg + 22.5) % 360 / 45).floor();
    return dirs[index];
  }

  @override
  Widget build(BuildContext context) {
    String valueText = '---';
    if (cogDeg != null) {
      final normalized = cogDeg! % 360;
      valueText =
          '${normalized.toStringAsFixed(1)}\u00B0 ${_compassDirection(normalized)}';
    }

    return Container(
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
          const Text(
            'COG',
            style: TextStyle(
              color: MaritimePalette.brass,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          Text(
            valueText,
            style: const TextStyle(
              color: MaritimePalette.foam,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              fontFeatures: kTabular,
              shadows: [Shadow(color: MaritimePalette.foam, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeDisplay extends StatelessWidget {
  const _TimeDisplay({required this.secondsSinceMidnight});

  final double? secondsSinceMidnight;

  @override
  Widget build(BuildContext context) {
    String valueText = '--:--:--';
    if (secondsSinceMidnight != null) {
      final total = secondsSinceMidnight!.toInt();
      final h = (total ~/ 3600) % 24;
      final m = (total % 3600) ~/ 60;
      final s = total % 60;
      valueText =
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1E30), MaritimePalette.deepHull],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: MaritimePalette.consoleBorder, width: 0.5),
      ),
      child: Text(
        valueText,
        style: const TextStyle(
          color: MaritimePalette.foam,
          fontSize: 36,
          fontWeight: FontWeight.bold,
          fontFeatures: kTabular,
          shadows: [Shadow(color: MaritimePalette.foam, blurRadius: 6)],
        ),
      ),
    );
  }
}
