// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// Depth and speed NMEA 2000 PGN definitions.

const waterDepthPgn = PgnDefinition(
  pgn: 128267,
  name: 'Water Depth',
  transport: 0, // single
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'sid',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'depth',
      bitOffset: 8,
      bitLength: 32,
      resolution: 0.01, // meters
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'offset',
      bitOffset: 40,
      bitLength: 16,
      resolution: 0.001, // meters
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'maxRange',
      bitOffset: 56,
      bitLength: 8,
      resolution: 10, // meters
      type: FieldType.unsigned,
    ),
  ],
);

const speedWaterReferencedPgn = PgnDefinition(
  pgn: 128259,
  name: 'Speed, Water Referenced',
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
      name: 'speedWaterRef',
      bitOffset: 8,
      bitLength: 16,
      resolution: 0.01, // m/s
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'speedGroundRef',
      bitOffset: 24,
      bitLength: 16,
      resolution: 0.01, // m/s
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'speedWaterRefType',
      bitOffset: 40,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {
        0: 'paddleWheel',
        1: 'pitotTube',
        2: 'doppler',
        3: 'ultrasound',
        4: 'electromagneticCorrelation',
      },
    ),
    FieldDefinition(
      name: 'speedDirection',
      bitOffset: 44,
      bitLength: 4,
      type: FieldType.unsigned,
    ),
  ],
);

/// All depth and speed PGN definitions.
const depthSpeedPgns = [
  waterDepthPgn,
  speedWaterReferencedPgn,
];
