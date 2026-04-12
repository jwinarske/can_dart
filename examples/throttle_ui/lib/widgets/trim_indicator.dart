import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';

/// Engine trim / tilt request indicator. On outboard and stern-drive
/// boats "trim" and "tilt" describe the same axis — the DBC calls this
/// signal Tilt_Req, but a helmsman reads it as trim, which is the
/// terminology the UI uses.
///
/// The widget shows three stacked states — UP, HOLD, DOWN — and lights
/// up whichever one Tilt_Req is currently commanding. FAULT maps to a
/// red glow on the centre pad. Unknown / absent → dark lamps.
enum TrimState { up, hold, down, fault, unknown }

TrimState trimStateFromLabel(String? label) {
  if (label == null) return TrimState.unknown;
  if (label.startsWith('TILT UP')) return TrimState.up;
  if (label.startsWith('TILT DOWN')) return TrimState.down;
  if (label.startsWith('NO REQUEST')) return TrimState.hold;
  if (label.startsWith('FAULT')) return TrimState.fault;
  return TrimState.unknown;
}

class TrimIndicator extends StatelessWidget {
  const TrimIndicator({
    super.key,
    required this.state,
    this.width = 26,
    this.height = 150,
  });

  final TrimState state;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _TrimPainter(state: state),
    );
  }
}

class _TrimPainter extends CustomPainter {
  _TrimPainter({required this.state});
  final TrimState state;

  @override
  void paint(Canvas canvas, Size size) {
    // Outer frame.
    final frameRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(1, 2, size.width - 1, size.height - 2),
      const Radius.circular(4),
    );
    canvas.drawRRect(frameRect, Paint()..color = MaritimePalette.midHull);
    canvas.drawRRect(
      frameRect,
      Paint()
        ..color = MaritimePalette.brass
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // "TRIM" label across the top.
    final labelPainter = TextPainter(
      text: const TextSpan(
        text: 'TRIM',
        style: TextStyle(
          fontSize: 6,
          color: MaritimePalette.brass,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(
      canvas,
      Offset((size.width - labelPainter.width) / 2, 3),
    );

    // Three arrow cells: UP (top), HOLD (middle), DOWN (bottom).
    final cellTop = 11.0;
    final cellBottom = size.height - 4.0;
    final cellHeight = (cellBottom - cellTop) / 3;
    _drawUp(
      canvas,
      Rect.fromLTWH(1, cellTop, size.width - 2, cellHeight),
      state == TrimState.up,
    );
    _drawHold(
      canvas,
      Rect.fromLTWH(1, cellTop + cellHeight, size.width - 2, cellHeight),
      state == TrimState.hold,
      fault: state == TrimState.fault,
    );
    _drawDown(
      canvas,
      Rect.fromLTWH(1, cellTop + cellHeight * 2, size.width - 2, cellHeight),
      state == TrimState.down,
    );
  }

  void _drawUp(Canvas canvas, Rect cell, bool active) {
    final color = active ? MaritimePalette.lampAmber : MaritimePalette.lampOff;
    final cx = cell.center.dx;
    final path = Path()
      ..moveTo(cx, cell.top + 2)
      ..lineTo(cell.right - 3, cell.bottom - 3)
      ..lineTo(cell.left + 3, cell.bottom - 3)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    _maybeGlow(canvas, path, active, color);
  }

  void _drawDown(Canvas canvas, Rect cell, bool active) {
    final color = active ? MaritimePalette.lampAmber : MaritimePalette.lampOff;
    final cx = cell.center.dx;
    final path = Path()
      ..moveTo(cx, cell.bottom - 2)
      ..lineTo(cell.right - 3, cell.top + 3)
      ..lineTo(cell.left + 3, cell.top + 3)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    _maybeGlow(canvas, path, active, color);
  }

  void _drawHold(Canvas canvas, Rect cell, bool active, {bool fault = false}) {
    final color = fault
        ? MaritimePalette.lampRed
        : (active ? MaritimePalette.lampGreen : MaritimePalette.lampOff);
    final pad = RRect.fromRectAndRadius(
      Rect.fromCenter(center: cell.center, width: cell.width - 6, height: 3),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(pad, Paint()..color = color);
    if (active || fault) {
      canvas.drawRRect(
        pad,
        Paint()
          ..color = color.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 2),
      );
    }
  }

  void _maybeGlow(Canvas canvas, Path path, bool active, Color color) {
    if (!active) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 2),
    );
  }

  @override
  bool shouldRepaint(covariant _TrimPainter old) => old.state != state;
}
