// Centralised look-and-feel for the RV dashboard. Everything the
// dashboard draws — tile backgrounds, gauge arcs, lamp glows — comes from
// here so a future "daylight" or "night" mode is a single palette swap.
//
// The palette is modelled on an RV cabin interior:
//
//   * Deep walnut for the field background
//   * Mid wood for panel backgrounds
//   * Copper/brass for accents and rim highlights
//   * Warm white for live numeric readouts
//   * Standard lamp green/amber/red for status indicators
//
// Text uses tabular figures so numbers don't jitter as they update.

import 'package:flutter/material.dart';

/// RV cabin colour palette — warm dark wood tones.
class CabinPalette {
  const CabinPalette._();

  // Wood & field
  static const Color darkWood = Color(0xFF1A1008);
  static const Color midWood = Color(0xFF2A1C10);
  static const Color woodBorder = Color(0xFF3D2A16);

  // Readouts & accents
  static const Color warmWhite = Color(0xFFF5E6C8);
  static const Color warmWhiteDim = Color(0xFFA08860);
  static const Color copper = Color(0xFFD4853A);
  static const Color copperBright = Color(0xFFE8A858);

  // Status lamps
  static const Color lampGreen = Color(0xFF3FE082);
  static const Color lampAmber = Color(0xFFFFB93B);
  static const Color lampRed = Color(0xFFE84545);
  static const Color lampOff = Color(0xFF3A2E20);
}

/// Global Flutter theme. Material3 dark with cabin palette colours.
ThemeData buildCabinTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: CabinPalette.darkWood,
    colorScheme: const ColorScheme.dark(
      primary: CabinPalette.copperBright,
      onPrimary: CabinPalette.darkWood,
      secondary: CabinPalette.warmWhite,
      onSecondary: CabinPalette.darkWood,
      surface: CabinPalette.midWood,
      onSurface: CabinPalette.warmWhite,
      surfaceContainerHighest: CabinPalette.midWood,
      error: CabinPalette.lampRed,
    ),
    fontFamily: 'monospace',
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: CabinPalette.warmWhite,
      displayColor: CabinPalette.copperBright,
    ),
  );
}

/// Tabular-figures TextStyle helper — use this for anything that changes
/// over time so digits don't dance.
const List<FontFeature> kTabular = [FontFeature.tabularFigures()];
