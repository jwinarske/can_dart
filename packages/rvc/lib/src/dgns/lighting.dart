// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// Lighting DGN definitions for RV-C.

const dcDimmerStatus3Dgn = MessageDefinition(
  pgn: 0x1FEDE,
  name: 'DC Dimmer Status 3',
  transport: 0,
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'instance',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'group',
      bitOffset: 8,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'brightness',
      bitOffset: 16,
      bitLength: 8,
      resolution: 0.5,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'enable',
      bitOffset: 24,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'off', 1: 'on', 2: 'reserved', 3: 'noAction'},
    ),
    FieldDefinition(
      name: 'delayDuration',
      bitOffset: 26,
      bitLength: 6,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 32,
      bitLength: 32,
      type: FieldType.reserved,
    ),
  ],
);

const dcDimmerCommand2Dgn = MessageDefinition(
  pgn: 0x1FEDB,
  name: 'DC Dimmer Command 2',
  transport: 0,
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'instance',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'group',
      bitOffset: 8,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'brightness',
      bitOffset: 16,
      bitLength: 8,
      resolution: 0.5,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'command',
      bitOffset: 24,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'off', 1: 'on', 2: 'toggle', 3: 'noAction'},
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 26,
      bitLength: 38,
      type: FieldType.reserved,
    ),
  ],
);

/// All lighting DGN definitions.
const lightingDgns = [
  dcDimmerStatus3Dgn,
  dcDimmerCommand2Dgn,
];
