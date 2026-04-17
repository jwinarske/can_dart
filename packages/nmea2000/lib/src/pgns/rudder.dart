// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// Rudder NMEA 2000 PGN definitions.

const rudderPgn = PgnDefinition(
  pgn: 127245,
  name: 'Rudder',
  transport: 0, // single
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'instance',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'directionOrder',
      bitOffset: 8,
      bitLength: 3,
      type: FieldType.lookup,
      lookupTable: {
        0: 'noOrder',
        1: 'moveToStarboard',
        2: 'moveToPort',
      },
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 11,
      bitLength: 5,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'angleOrder',
      bitOffset: 16,
      bitLength: 16,
      resolution: 0.0001, // radians
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'position',
      bitOffset: 32,
      bitLength: 16,
      resolution: 0.0001, // radians
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'reserved2',
      bitOffset: 48,
      bitLength: 16,
      type: FieldType.reserved,
    ),
  ],
);

/// All rudder PGN definitions.
const rudderPgns = [
  rudderPgn,
];
