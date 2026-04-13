// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import '../pgn_definition.dart';

/// Set & Drift NMEA 2000 PGN definitions.

const setDriftRapidUpdatePgn = PgnDefinition(
  pgn: 128281,
  name: 'Set & Drift, Rapid Update',
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
      name: 'setReference',
      bitOffset: 8,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'true', 1: 'magnetic'},
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 10,
      bitLength: 6,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'set_',
      bitOffset: 16,
      bitLength: 16,
      resolution: 0.0001, // radians
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'drift',
      bitOffset: 32,
      bitLength: 16,
      resolution: 0.01, // m/s
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved2',
      bitOffset: 48,
      bitLength: 16,
      type: FieldType.reserved,
    ),
  ],
);

/// All set & drift PGN definitions.
const setDriftPgns = [
  setDriftRapidUpdatePgn,
];
