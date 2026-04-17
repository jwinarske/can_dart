// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// Heading and magnetic variation NMEA 2000 PGN definitions.

const vesselHeadingPgn = PgnDefinition(
  pgn: 127250,
  name: 'Vessel Heading',
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
      name: 'heading',
      bitOffset: 8,
      bitLength: 16,
      resolution: 0.0001, // radians
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'deviation',
      bitOffset: 24,
      bitLength: 16,
      resolution: 0.0001, // radians
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'variation',
      bitOffset: 40,
      bitLength: 16,
      resolution: 0.0001, // radians
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'reference',
      bitOffset: 56,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'true', 1: 'magnetic'},
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 58,
      bitLength: 6,
      type: FieldType.reserved,
    ),
  ],
);

const rateOfTurnPgn = PgnDefinition(
  pgn: 127251,
  name: 'Rate of Turn',
  transport: 0, // single
  dataLength: 5,
  fields: [
    FieldDefinition(
      name: 'sid',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'rate',
      bitOffset: 8,
      bitLength: 32,
      resolution: 3.125e-8, // rad/s
      type: FieldType.signed,
    ),
  ],
);

const magneticVariationPgn = PgnDefinition(
  pgn: 127258,
  name: 'Magnetic Variation',
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
      name: 'source',
      bitOffset: 8,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {
        0: 'manual',
        1: 'chart',
        2: 'table',
        3: 'calculated',
        4: 'wmm2000',
        5: 'wmm2005',
        6: 'wmm2010',
        7: 'wmm2015',
        8: 'wmm2020',
      },
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 12,
      bitLength: 4,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'daysSince1970',
      bitOffset: 16,
      bitLength: 16,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'variation',
      bitOffset: 32,
      bitLength: 16,
      resolution: 0.0001, // radians
      type: FieldType.signed,
    ),
  ],
);

/// All heading PGN definitions.
const headingPgns = [
  vesselHeadingPgn,
  rateOfTurnPgn,
  magneticVariationPgn,
];
