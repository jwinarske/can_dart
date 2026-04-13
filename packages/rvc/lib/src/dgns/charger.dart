// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// Charger DGN definitions for RV-C.

const chargerStatusDgn = MessageDefinition(
  pgn: 0x1FFC7,
  name: 'Charger Status',
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
      name: 'chargeVoltage',
      bitOffset: 8,
      bitLength: 16,
      resolution: 0.05,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'chargeCurrent',
      bitOffset: 24,
      bitLength: 16,
      resolution: 0.05,
      offset: -1600.0,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'chargePercentCurrent',
      bitOffset: 40,
      bitLength: 8,
      resolution: 0.5,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'operatingState',
      bitOffset: 48,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {
        0: 'disabled',
        1: 'enabled',
        2: 'fault',
        3: 'bulkCharge',
        4: 'absorptionCharge',
        5: 'floatCharge',
        6: 'equalize',
      },
    ),
    FieldDefinition(
      name: 'defaultState',
      bitOffset: 52,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'disabled', 1: 'enabled'},
    ),
    FieldDefinition(
      name: 'autoRechargeEnable',
      bitOffset: 54,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'disabled', 1: 'enabled'},
    ),
    FieldDefinition(
      name: 'forceCharge',
      bitOffset: 56,
      bitLength: 2,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 58,
      bitLength: 6,
      type: FieldType.reserved,
    ),
  ],
);

const chargerCommandDgn = MessageDefinition(
  pgn: 0x1FEA0,
  name: 'Charger Command',
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
      name: 'reserved1',
      bitOffset: 8,
      bitLength: 4,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'chargeEnable',
      bitOffset: 12,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'disable', 1: 'enable', 3: 'noAction'},
    ),
    FieldDefinition(
      name: 'reserved2',
      bitOffset: 14,
      bitLength: 2,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'defaultState',
      bitOffset: 16,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'disable', 1: 'enable', 3: 'noAction'},
    ),
    FieldDefinition(
      name: 'autoRechargeEnable',
      bitOffset: 18,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'disable', 1: 'enable', 3: 'noAction'},
    ),
    FieldDefinition(
      name: 'forceCharge',
      bitOffset: 20,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'cancel', 1: 'force', 3: 'noAction'},
    ),
    FieldDefinition(
      name: 'reserved3',
      bitOffset: 22,
      bitLength: 42,
      type: FieldType.reserved,
    ),
  ],
);

/// All charger DGN definitions.
const chargerDgns = [
  chargerStatusDgn,
  chargerCommandDgn,
];
