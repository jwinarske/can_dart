import 'package:flutter/material.dart';

import '../theme/maritime_theme.dart';

/// The brass-bezelled outer frame that every console panel sits in.
/// Renders a double border with a gradient interior so panels look
/// recessed, matching the look of a real bridge console cut-out.
class ConsoleFrame extends StatelessWidget {
  const ConsoleFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(6),
    this.label,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: MaritimePalette.brass, width: 1),
        borderRadius: BorderRadius.circular(4),
        gradient: const LinearGradient(
          colors: [MaritimePalette.midHull, MaritimePalette.deepHull],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      padding: padding,
      child: label == null
          ? child
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label!.toUpperCase(),
                  style: const TextStyle(
                    color: MaritimePalette.brass,
                    fontSize: 8,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(child: child),
              ],
            ),
    );
  }
}
