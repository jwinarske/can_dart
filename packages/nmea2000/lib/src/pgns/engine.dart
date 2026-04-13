// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import '../pgn_definition.dart';

/// Engine and transmission NMEA 2000 PGN definitions.

const engineParametersRapidUpdatePgn = PgnDefinition(
  pgn: 127488,
  name: 'Engine Parameters, Rapid Update',
  transport: 0, // single
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'engineInstance',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'engineSpeed',
      bitOffset: 8,
      bitLength: 16,
      resolution: 0.25, // RPM
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'engineBoostPressure',
      bitOffset: 24,
      bitLength: 16,
      resolution: 100, // Pa
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'engineTiltTrim',
      bitOffset: 40,
      bitLength: 8,
      resolution: 1, // %
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 48,
      bitLength: 16,
      type: FieldType.reserved,
    ),
  ],
);

const engineParametersDynamicPgn = PgnDefinition(
  pgn: 127489,
  name: 'Engine Parameters, Dynamic',
  transport: 1, // fast_packet
  dataLength: 26,
  fields: [
    FieldDefinition(
      name: 'engineInstance',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'oilPressure',
      bitOffset: 8,
      bitLength: 16,
      resolution: 100, // Pa (hPa)
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'oilTemperature',
      bitOffset: 24,
      bitLength: 16,
      resolution: 0.1, // K
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'temperature',
      bitOffset: 40,
      bitLength: 16,
      resolution: 0.01, // K (coolant temp)
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'alternatorPotential',
      bitOffset: 56,
      bitLength: 16,
      resolution: 0.01, // V
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'fuelRate',
      bitOffset: 72,
      bitLength: 16,
      resolution: 0.0001, // m³/h (= 0.1 L/h)
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'totalEngineHours',
      bitOffset: 88,
      bitLength: 32,
      resolution: 1, // seconds
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'coolantPressure',
      bitOffset: 120,
      bitLength: 16,
      resolution: 100, // Pa
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'fuelPressure',
      bitOffset: 136,
      bitLength: 16,
      resolution: 1000, // Pa
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 152,
      bitLength: 8,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'discreteStatus1',
      bitOffset: 160,
      bitLength: 16,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'discreteStatus2',
      bitOffset: 176,
      bitLength: 16,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'percentEngineLoad',
      bitOffset: 192,
      bitLength: 8,
      resolution: 1, // %
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'percentEngineTorque',
      bitOffset: 200,
      bitLength: 8,
      resolution: 1, // %
      type: FieldType.signed,
    ),
  ],
);

const transmissionParametersDynamicPgn = PgnDefinition(
  pgn: 127493,
  name: 'Transmission Parameters, Dynamic',
  transport: 0, // single
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'engineInstance',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'transmissionGear',
      bitOffset: 8,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'forward', 1: 'neutral', 2: 'reverse'},
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 10,
      bitLength: 6,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'oilPressure',
      bitOffset: 16,
      bitLength: 16,
      resolution: 100, // Pa
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'oilTemperature',
      bitOffset: 32,
      bitLength: 16,
      resolution: 0.1, // K
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'discreteStatus1',
      bitOffset: 48,
      bitLength: 8,
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

/// All engine PGN definitions.
const enginePgns = [
  engineParametersRapidUpdatePgn,
  engineParametersDynamicPgn,
  transmissionParametersDynamicPgn,
];
