// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// DC power DGN definitions for RV-C.

const dcSourceStatus1Dgn = MessageDefinition(
  pgn: 0x1FFFD,
  name: 'DC Source Status 1',
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
      name: 'devicePriority',
      bitOffset: 8,
      bitLength: 4,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 12,
      bitLength: 4,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'dcVoltage',
      bitOffset: 16,
      bitLength: 16,
      resolution: 0.05,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'dcCurrent',
      bitOffset: 32,
      bitLength: 32,
      resolution: 0.001,
      offset: -2000000.0,
      type: FieldType.unsigned,
    ),
  ],
);

const dcSourceStatus2Dgn = MessageDefinition(
  pgn: 0x1FFFC,
  name: 'DC Source Status 2',
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
      name: 'devicePriority',
      bitOffset: 8,
      bitLength: 4,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 12,
      bitLength: 4,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'sourceTemperature',
      bitOffset: 16,
      bitLength: 16,
      resolution: 0.03125,
      offset: -273.0,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'stateOfCharge',
      bitOffset: 32,
      bitLength: 8,
      resolution: 0.5,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'timeRemaining',
      bitOffset: 40,
      bitLength: 16,
      resolution: 1.0,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved2',
      bitOffset: 56,
      bitLength: 8,
      type: FieldType.reserved,
    ),
  ],
);

const dcSourceStatus3Dgn = MessageDefinition(
  pgn: 0x1FFFB,
  name: 'DC Source Status 3',
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
      name: 'devicePriority',
      bitOffset: 8,
      bitLength: 4,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 12,
      bitLength: 4,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'stateOfHealth',
      bitOffset: 16,
      bitLength: 8,
      resolution: 0.5,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'capacity',
      bitOffset: 24,
      bitLength: 16,
      resolution: 1.0,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved2',
      bitOffset: 40,
      bitLength: 24,
      type: FieldType.reserved,
    ),
  ],
);

/// All DC power DGN definitions.
const dcPowerDgns = [
  dcSourceStatus1Dgn,
  dcSourceStatus2Dgn,
  dcSourceStatus3Dgn,
];
