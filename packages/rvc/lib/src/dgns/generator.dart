// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// Generator DGN definitions for RV-C.

const generatorStatus1Dgn = MessageDefinition(
  pgn: 0x1FFDC,
  name: 'Generator Status 1',
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
      lookupTable: {
        0: 'stopped',
        1: 'running',
        2: 'warmup',
        3: 'cooldown',
        4: 'priming',
      },
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 12,
      bitLength: 4,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'engineSpeed',
      bitOffset: 16,
      bitLength: 16,
      resolution: 0.125,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'engineHours',
      bitOffset: 32,
      bitLength: 32,
      resolution: 0.05,
      type: FieldType.unsigned,
    ),
  ],
);

const generatorCommandDgn = MessageDefinition(
  pgn: 0x1FE97,
  name: 'Generator Command',
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
      name: 'command',
      bitOffset: 8,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {
        0: 'stop',
        1: 'start',
        2: 'emergencyStop',
        3: 'noAction',
      },
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 12,
      bitLength: 52,
      type: FieldType.reserved,
    ),
  ],
);

/// All generator DGN definitions.
const generatorDgns = [
  generatorStatus1Dgn,
  generatorCommandDgn,
];
