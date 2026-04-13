// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';

/// Date/time and alarm DGN definitions for RV-C.

const dateTimeStatusDgn = MessageDefinition(
  pgn: 0x1FFFF,
  name: 'Date/Time Status',
  transport: 0,
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'year',
      bitOffset: 0,
      bitLength: 8,
      offset: 2000.0,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'month',
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
      name: 'day',
      bitOffset: 16,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'dayOfWeek',
      bitOffset: 24,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {
        0: 'sunday',
        1: 'monday',
        2: 'tuesday',
        3: 'wednesday',
        4: 'thursday',
        5: 'friday',
        6: 'saturday',
      },
    ),
    FieldDefinition(
      name: 'reserved2',
      bitOffset: 28,
      bitLength: 4,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'hour',
      bitOffset: 32,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'minute',
      bitOffset: 40,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'second',
      bitOffset: 48,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved3',
      bitOffset: 56,
      bitLength: 8,
      type: FieldType.reserved,
    ),
  ],
);

const genericAlarmStatusDgn = MessageDefinition(
  pgn: 0x1FED9,
  name: 'Generic Alarm Status',
  transport: 0,
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'operatingStatus',
      bitOffset: 0,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'ok', 1: 'warning', 2: 'alarm'},
    ),
    FieldDefinition(
      name: 'sourceType',
      bitOffset: 2,
      bitLength: 6,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'sourceInstance',
      bitOffset: 8,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'alarmType',
      bitOffset: 16,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 24,
      bitLength: 40,
      type: FieldType.reserved,
    ),
  ],
);

/// All date/time and alarm DGN definitions.
const dateTimeAlarmDgns = [
  dateTimeStatusDgn,
  genericAlarmStatusDgn,
];
