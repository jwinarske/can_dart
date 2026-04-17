import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/cabin_theme.dart';

/// Reusable status/control card — a recessed panel with title bar,
/// status lamp, content area, and optional action buttons.
/// Enhanced with depth: inner shadow, copper highlight line, larger lamp.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.title,
    this.statusColor,
    this.statusText,
    required this.child,
    this.actions,
  });

  final String title;
  final Color? statusColor;
  final String? statusText;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF221610), Color(0xFF1A1008)],
        ),
        border: Border.all(color: CabinPalette.woodBorder, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thin copper highlight line at the very top (beveled look)
          Container(
            height: 0.5,
            color: CabinPalette.copper.withValues(alpha: 0.6),
          ),
          // Title bar — slightly taller with more visual weight
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A1C10), Color(0xFF221610)],
              ),
              border: Border(
                bottom: BorderSide(color: CabinPalette.woodBorder),
              ),
            ),
            child: Row(
              children: [
                if (statusColor != null) ...[
                  // Larger lamp (14px) with prominent glow
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: statusColor != CabinPalette.lampOff
                            ? statusColor!.withValues(alpha: 0.3)
                            : CabinPalette.woodBorder,
                        width: 1,
                      ),
                      boxShadow: statusColor != CabinPalette.lampOff
                          ? [
                              BoxShadow(
                                color: statusColor!.withValues(alpha: 0.7),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                              BoxShadow(
                                color: statusColor!.withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: CabinPalette.copperBright,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (statusText != null)
                  Text(
                    statusText!,
                    style: TextStyle(
                      color: statusColor ?? CabinPalette.warmWhiteDim,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
              ],
            ),
          ),
          // Inner shadow band at top of content area
          CustomPaint(
            painter: _InnerShadowPainter(),
            child: const SizedBox(height: 6, width: double.infinity),
          ),
          // Content area
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: child,
          ),
          // Action buttons
          if (actions != null && actions!.isNotEmpty) ...[
            const Divider(color: CabinPalette.woodBorder, height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: actions!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Draws a subtle inner shadow (darker gradient band) at the top.
class _InnerShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
        const Color(0xFF0D0804),
        const Color(0x001A1008),
      ]);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_InnerShadowPainter old) => false;
}
