// Centralised look-and-feel for the throttle helm UI. Everything the
// dashboard draws — tile backgrounds, gauge arcs, lamp glows — comes from
// here so a future "daylight" or "night" mode is a single palette swap.
//
// The palette is loosely modelled on a nautical bridge console:
//
//   * Deep hull navy for the field background
//   * Varnished-teak brass for accents and rim highlights
//   * Pale foam cyan for live numeric readouts
//   * Rubino red for faults / e-stop / critical state
//   * Starboard green / port red used sparingly for navigation cues
//
// Text uses tabular figures so numbers don't jitter as they update.

import 'package:flutter/material.dart';

/// Physical target display: Winstar WF43HSIAEDNNB, 4.3". The panel is
/// 480 × 272 in its native landscape orientation, but the helm console
/// runs in **portrait** — screen mounted on its side — so the logical
/// viewport the UI lays out against is 272 × 480.
const Size kPhysicalDisplaySize = Size(272, 480);

/// Maritime colour palette.
class MaritimePalette {
  const MaritimePalette._();

  // Hull & field
  static const Color deepHull = Color(0xFF0A1826);
  static const Color midHull = Color(0xFF102236);
  static const Color consoleBorder = Color(0xFF1C3350);

  // Readouts & accents
  static const Color foam = Color(0xFF8FE6FF);
  static const Color foamDim = Color(0xFF4B9DB8);
  static const Color brass = Color(0xFFC7A24A);
  static const Color brassBright = Color(0xFFF0D27A);
  static const Color teak = Color(0xFF6B3E1A);

  // Status lamps
  static const Color lampGreen = Color(0xFF3FE082);
  static const Color lampAmber = Color(0xFFFFB93B);
  static const Color lampRed = Color(0xFFE84545);
  static const Color lampOff = Color(0xFF2A3B52);

  // Navigation
  static const Color starboardGreen = Color(0xFF15A34A);
  static const Color portRed = Color(0xFFD64545);
}

/// Global Flutter theme. We stay on Material3 dark so unstyled widgets
/// (dialogs, snackbars) still look at home alongside the custom console.
ThemeData buildMaritimeTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: MaritimePalette.deepHull,
    colorScheme: const ColorScheme.dark(
      primary: MaritimePalette.brassBright,
      onPrimary: MaritimePalette.deepHull,
      secondary: MaritimePalette.foam,
      onSecondary: MaritimePalette.deepHull,
      surface: MaritimePalette.midHull,
      onSurface: MaritimePalette.foam,
      surfaceContainerHighest: MaritimePalette.midHull,
      error: MaritimePalette.lampRed,
    ),
    fontFamily: 'monospace',
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: MaritimePalette.foam,
      displayColor: MaritimePalette.brassBright,
    ),
  );
}

/// Tabular-figures TextStyle helper — use this for anything that changes
/// over time so digits don't dance.
const List<FontFeature> kTabular = [FontFeature.tabularFigures()];
