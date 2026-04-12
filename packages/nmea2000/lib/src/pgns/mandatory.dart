// Copyright 2024 can_dart Contributors
// SPDX-License-Identifier: Apache-2.0

import '../pgn_definition.dart';

/// Mandatory NMEA 2000 PGN definitions — the core set every compliant device
/// must respond to or transmit.

const heartbeatPgn = PgnDefinition(
  pgn: 126993,
  name: 'Heartbeat',
  transport: 1, // fast_packet
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'dataTransmitOffset',
      bitOffset: 0,
      bitLength: 16,
      resolution: 10, // milliseconds × 10
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'sequenceCounter',
      bitOffset: 16,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'class1CanState',
      bitOffset: 24,
      bitLength: 2,
      type: FieldType.lookup,
    ),
    FieldDefinition(
      name: 'class2CanState',
      bitOffset: 26,
      bitLength: 2,
      type: FieldType.lookup,
    ),
    FieldDefinition(
      name: 'noProductInfoYet',
      bitOffset: 28,
      bitLength: 1,
      type: FieldType.unsigned,
    ),
    // Bits 29..63 reserved.
  ],
);

const productInformationPgn = PgnDefinition(
  pgn: 126996,
  name: 'Product Information',
  transport: 1, // fast_packet
  dataLength: 134,
  fields: [
    FieldDefinition(
      name: 'nmea2000Version',
      bitOffset: 0,
      bitLength: 16,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'productCode',
      bitOffset: 16,
      bitLength: 16,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'modelId',
      bitOffset: 32,
      bitLength: 256, // 32 bytes
      type: FieldType.string,
    ),
    FieldDefinition(
      name: 'softwareVersionCode',
      bitOffset: 288,
      bitLength: 256, // 32 bytes
      type: FieldType.string,
    ),
    FieldDefinition(
      name: 'modelVersion',
      bitOffset: 544,
      bitLength: 256, // 32 bytes
      type: FieldType.string,
    ),
    FieldDefinition(
      name: 'modelSerialCode',
      bitOffset: 800,
      bitLength: 256, // 32 bytes
      type: FieldType.string,
    ),
    FieldDefinition(
      name: 'certificationLevel',
      bitOffset: 1056,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'loadEquivalency',
      bitOffset: 1064,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
  ],
);

const configurationInformationPgn = PgnDefinition(
  pgn: 126998,
  name: 'Configuration Information',
  transport: 1, // fast_packet
  dataLength: 70, // minimum; variable length with string fields
  fields: [
    // Variable-length LAU strings — simplified as fixed fields for now.
    // Full LAU string parsing (length + encoding + payload) is a Phase 2 item.
    FieldDefinition(
      name: 'installationDescription1Length',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'installationDescription1',
      bitOffset: 8,
      bitLength: 256, // 32 bytes — truncated placeholder
      type: FieldType.string,
    ),
    FieldDefinition(
      name: 'installationDescription2Length',
      bitOffset: 264,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'installationDescription2',
      bitOffset: 272,
      bitLength: 256, // 32 bytes — truncated placeholder
      type: FieldType.string,
    ),
  ],
);

const isoAcknowledgmentPgn = PgnDefinition(
  pgn: 59392,
  name: 'ISO Acknowledgment',
  transport: 0, // single
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'control',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.lookup,
      lookupTable: {0: 'ack', 1: 'nak', 2: 'accessDenied', 3: 'addressBusy'},
    ),
    FieldDefinition(
      name: 'groupFunction',
      bitOffset: 8,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    // Bytes 2-4: reserved (0xFF)
    FieldDefinition(
      name: 'addressAcknowledged',
      bitOffset: 40,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'pgnAcknowledged',
      bitOffset: 48,
      bitLength: 24,
      type: FieldType.unsigned,
    ),
  ],
);

const isoRequestPgn = PgnDefinition(
  pgn: 59904,
  name: 'ISO Request',
  transport: 0, // single
  dataLength: 3,
  fields: [
    FieldDefinition(
      name: 'requestedPgn',
      bitOffset: 0,
      bitLength: 24,
      type: FieldType.unsigned,
    ),
  ],
);

/// All mandatory PGN definitions.
const mandatoryPgns = [
  heartbeatPgn,
  productInformationPgn,
  configurationInformationPgn,
  isoAcknowledgmentPgn,
  isoRequestPgn,
];
