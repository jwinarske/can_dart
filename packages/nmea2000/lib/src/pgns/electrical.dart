// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// Electrical and fluid level NMEA 2000 PGN definitions.

const batteryStatusPgn = PgnDefinition(
  pgn: 127508,
  name: 'Battery Status',
  transport: 0, // single
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'batteryInstance',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'batteryVoltage',
      bitOffset: 8,
      bitLength: 16,
      resolution: 0.01, // V
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'batteryCurrent',
      bitOffset: 24,
      bitLength: 16,
      resolution: 0.1, // A
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'batteryCaseTemperature',
      bitOffset: 40,
      bitLength: 16,
      resolution: 0.01, // K
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'sid',
      bitOffset: 56,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
  ],
);

const fluidLevelPgn = PgnDefinition(
  pgn: 127505,
  name: 'Fluid Level',
  transport: 0, // single
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'instance',
      bitOffset: 0,
      bitLength: 4,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'fluidType',
      bitOffset: 4,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {
        0: 'fuel',
        1: 'water',
        2: 'grayWater',
        3: 'liveWell',
        4: 'oil',
        5: 'blackWater',
      },
    ),
    FieldDefinition(
      name: 'level',
      bitOffset: 8,
      bitLength: 16,
      resolution: 0.004, // %
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'capacity',
      bitOffset: 24,
      bitLength: 32,
      resolution: 0.1, // L
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 56,
      bitLength: 8,
      type: FieldType.reserved,
    ),
  ],
);

/// All electrical PGN definitions.
const electricalPgns = [
  batteryStatusPgn,
  fluidLevelPgn,
];
