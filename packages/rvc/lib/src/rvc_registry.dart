// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

import 'dgns/charger.dart';
import 'dgns/datetime_alarm.dart';
import 'dgns/dc_power.dart';
import 'dgns/generator.dart';
import 'dgns/hvac.dart';
import 'dgns/inverter.dart';
import 'dgns/lighting.dart';
import 'dgns/tanks.dart';

/// Registry of known RV-C DGN definitions.
///
/// The standard factory pre-loads the dashboard DGN set (~30 DGNs).
/// Apps register additional DGNs at construction time via [register]:
///
/// ```dart
/// final registry = RvcRegistry.standard()
///   ..register(myCustomDgns);
/// ```
class RvcRegistry {
  RvcRegistry._();

  final Map<int, MessageDefinition> _dgns = {};

  /// Create a registry pre-loaded with the standard RV-C dashboard DGN set
  /// covering DC power, tanks, HVAC, lighting, generator, charger, inverter,
  /// and date/time/alarm.
  factory RvcRegistry.standard() {
    final r = RvcRegistry._();
    r.register(dcPowerDgns);
    r.register(tankDgns);
    r.register(hvacDgns);
    r.register(lightingDgns);
    r.register(generatorDgns);
    r.register(chargerDgns);
    r.register(inverterDgns);
    r.register(dateTimeAlarmDgns);
    return r;
  }

  /// Create an empty registry (for testing or custom configurations).
  factory RvcRegistry.empty() => RvcRegistry._();

  /// Register additional DGN definitions. Overwrites any existing definition
  /// for the same DGN number.
  void register(List<MessageDefinition> dgns) {
    for (final d in dgns) {
      _dgns[d.pgn] = d;
    }
  }

  /// Look up a DGN definition by number.
  MessageDefinition? lookup(int dgn) => _dgns[dgn];

  /// All registered DGN definitions.
  Iterable<MessageDefinition> get allDgns => _dgns.values;

  /// All registered DGN numbers.
  Iterable<int> get dgnNumbers => _dgns.keys;
}
