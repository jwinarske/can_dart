// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// HVAC / thermostat DGN definitions for RV-C.

const thermostatStatus1Dgn = MessageDefinition(
  pgn: 0x1FFE2,
  name: 'Thermostat Status 1',
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
      name: 'operatingMode',
      bitOffset: 8,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {
        0: 'off',
        1: 'cool',
        2: 'heat',
        3: 'autoHeatCool',
        4: 'fanOnly',
        5: 'auxHeat',
      },
    ),
    FieldDefinition(
      name: 'fanMode',
      bitOffset: 12,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {0: 'auto', 1: 'on'},
    ),
    FieldDefinition(
      name: 'scheduleMode',
      bitOffset: 16,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {0: 'disabled', 1: 'enabled'},
    ),
    FieldDefinition(
      name: 'fanSpeed',
      bitOffset: 20,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {0: 'auto', 1: 'low', 2: 'medium', 3: 'high'},
    ),
    FieldDefinition(
      name: 'setpointHeat',
      bitOffset: 24,
      bitLength: 16,
      resolution: 0.03125,
      offset: -273.0,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'setpointCool',
      bitOffset: 40,
      bitLength: 16,
      resolution: 0.03125,
      offset: -273.0,
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

const thermostatCommand1Dgn = MessageDefinition(
  pgn: 0x1FEF9,
  name: 'Thermostat Command 1',
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
      name: 'operatingMode',
      bitOffset: 8,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {
        0: 'off',
        1: 'cool',
        2: 'heat',
        3: 'autoHeatCool',
        4: 'fanOnly',
        5: 'auxHeat',
      },
    ),
    FieldDefinition(
      name: 'fanMode',
      bitOffset: 12,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {0: 'auto', 1: 'on'},
    ),
    FieldDefinition(
      name: 'scheduleMode',
      bitOffset: 16,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {0: 'disabled', 1: 'enabled'},
    ),
    FieldDefinition(
      name: 'fanSpeed',
      bitOffset: 20,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {0: 'auto', 1: 'low', 2: 'medium', 3: 'high'},
    ),
    FieldDefinition(
      name: 'setpointHeat',
      bitOffset: 24,
      bitLength: 16,
      resolution: 0.03125,
      offset: -273.0,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'setpointCool',
      bitOffset: 40,
      bitLength: 16,
      resolution: 0.03125,
      offset: -273.0,
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

/// All HVAC DGN definitions.
const hvacDgns = [
  thermostatStatus1Dgn,
  thermostatCommand1Dgn,
];
