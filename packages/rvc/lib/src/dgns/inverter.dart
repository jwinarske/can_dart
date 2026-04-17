// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// Inverter DGN definitions for RV-C.

const inverterStatusDgn = MessageDefinition(
  pgn: 0x1FFC4,
  name: 'Inverter Status',
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
      name: 'operatingStatus',
      bitOffset: 8,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {0: 'disabled', 1: 'enabled', 2: 'fault'},
    ),
    FieldDefinition(
      name: 'inverterEnable',
      bitOffset: 12,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'disabled', 1: 'enabled'},
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 14,
      bitLength: 2,
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
      name: 'reserved2',
      bitOffset: 32,
      bitLength: 32,
      type: FieldType.reserved,
    ),
  ],
);

const inverterCommandDgn = MessageDefinition(
  pgn: 0x1FE9D,
  name: 'Inverter Command',
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
      name: 'enable',
      bitOffset: 8,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'disable', 1: 'enable', 3: 'noAction'},
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 10,
      bitLength: 54,
      type: FieldType.reserved,
    ),
  ],
);

/// All inverter DGN definitions.
const inverterDgns = [
  inverterStatusDgn,
  inverterCommandDgn,
];
