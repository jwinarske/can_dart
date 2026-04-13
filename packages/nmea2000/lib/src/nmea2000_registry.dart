// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'pgn_definition.dart';
import 'pgns/depth_speed.dart';
import 'pgns/electrical.dart';
import 'pgns/engine.dart';
import 'pgns/heading.dart';
import 'pgns/mandatory.dart';
import 'pgns/navigation.dart';
import 'pgns/rudder.dart';
import 'pgns/set_drift.dart';
import 'pgns/wind.dart';

/// Registry of known PGN definitions.
///
/// The standard factory pre-loads the mandatory NMEA 2000 PGNs. Apps register
/// additional PGNs at construction time via [register]:
///
/// ```dart
/// final registry = Nmea2000Registry.standard()
///   ..register(myAppPgns);
/// ```
class Nmea2000Registry {
  Nmea2000Registry._();

  final Map<int, PgnDefinition> _pgns = {};

  /// Create a registry pre-loaded with the mandatory NMEA 2000 PGNs and
  /// the standard instrument display PGN set (~30 PGNs covering navigation,
  /// wind, depth, heading, engine, electrical, rudder, set & drift).
  factory Nmea2000Registry.standard() {
    final r = Nmea2000Registry._();
    r.register(mandatoryPgns);
    r.register(navigationPgns);
    r.register(windPgns);
    r.register(depthSpeedPgns);
    r.register(headingPgns);
    r.register(rudderPgns);
    r.register(enginePgns);
    r.register(electricalPgns);
    r.register(setDriftPgns);
    return r;
  }

  /// Create an empty registry (for testing or custom configurations).
  factory Nmea2000Registry.empty() => Nmea2000Registry._();

  /// Register additional PGN definitions. Overwrites any existing definition
  /// for the same PGN number.
  void register(List<PgnDefinition> pgns) {
    for (final p in pgns) {
      _pgns[p.pgn] = p;
    }
  }

  /// Look up a PGN definition by number.
  PgnDefinition? lookup(int pgn) => _pgns[pgn];

  /// All registered PGN definitions.
  Iterable<PgnDefinition> get allPgns => _pgns.values;

  /// All registered PGN numbers.
  Iterable<int> get pgnNumbers => _pgns.keys;

  /// PGN numbers for definitions with transport == fast_packet (1).
  List<int> get fastPacketPgns =>
      _pgns.values.where((p) => p.transport == 1).map((p) => p.pgn).toList();
}
