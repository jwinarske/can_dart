// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import '../pgn_definition.dart';

/// Wind-related NMEA 2000 PGN definitions.

const windDataPgn = PgnDefinition(
  pgn: 130306,
  name: 'Wind Data',
  transport: 0, // single
  dataLength: 6,
  fields: [
    FieldDefinition(
      name: 'sid',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'windSpeed',
      bitOffset: 8,
      bitLength: 16,
      resolution: 0.01, // m/s
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'windAngle',
      bitOffset: 24,
      bitLength: 16,
      resolution: 0.0001, // radians
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reference',
      bitOffset: 40,
      bitLength: 3,
      type: FieldType.lookup,
      lookupTable: {
        0: 'trueGround',
        1: 'magneticGround',
        2: 'apparent',
        3: 'trueBoat',
        4: 'trueWater',
      },
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 43,
      bitLength: 5,
      type: FieldType.reserved,
    ),
  ],
);

/// All wind PGN definitions.
const windPgns = [
  windDataPgn,
];
