// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// Tank DGN definitions for RV-C.

const tankStatusDgn = MessageDefinition(
  pgn: 0x1FFB7,
  name: 'Tank Status',
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
      bitLength: 8,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'level',
      bitOffset: 16,
      bitLength: 16,
      resolution: 0.5,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'capacity',
      bitOffset: 32,
      bitLength: 16,
      resolution: 0.1,
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

/// All tank DGN definitions.
const tankDgns = [
  tankStatusDgn,
];
