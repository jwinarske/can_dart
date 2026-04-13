// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import '../pgn_definition.dart';

/// Navigation-related NMEA 2000 PGN definitions.

const positionRapidUpdatePgn = PgnDefinition(
  pgn: 129025,
  name: 'Position, Rapid Update',
  transport: 1, // fast_packet
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'latitude',
      bitOffset: 0,
      bitLength: 32,
      resolution: 1e-7, // degrees
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'longitude',
      bitOffset: 32,
      bitLength: 32,
      resolution: 1e-7, // degrees
      type: FieldType.signed,
    ),
  ],
);

const cogSogRapidUpdatePgn = PgnDefinition(
  pgn: 129026,
  name: 'COG & SOG, Rapid Update',
  transport: 1, // fast_packet
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'sid',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'cogReference',
      bitOffset: 8,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'true', 1: 'magnetic'},
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 10,
      bitLength: 6,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'cog',
      bitOffset: 16,
      bitLength: 16,
      resolution: 0.0001, // radians
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'sog',
      bitOffset: 32,
      bitLength: 16,
      resolution: 0.01, // m/s
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

const gnssPositionDataPgn = PgnDefinition(
  pgn: 129029,
  name: 'GNSS Position Data',
  transport: 1, // fast_packet
  dataLength: 43,
  fields: [
    FieldDefinition(
      name: 'sid',
      bitOffset: 0,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'daysSince1970',
      bitOffset: 8,
      bitLength: 16,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'secondsSinceMidnight',
      bitOffset: 24,
      bitLength: 32,
      resolution: 0.0001,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'latitude',
      bitOffset: 56,
      bitLength: 64,
      resolution: 1e-16, // degrees
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'longitude',
      bitOffset: 120,
      bitLength: 64,
      resolution: 1e-16, // degrees
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'altitude',
      bitOffset: 184,
      bitLength: 64,
      resolution: 1e-6, // meters
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'gnssType',
      bitOffset: 248,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {
        0: 'gps',
        1: 'glonass',
        2: 'gpsGlonass',
        3: 'gpsSbas',
        4: 'gpsSbasGlonass',
      },
    ),
    FieldDefinition(
      name: 'method',
      bitOffset: 252,
      bitLength: 4,
      type: FieldType.lookup,
      lookupTable: {
        0: 'noGnss',
        1: 'gnssFixNoIntegrity',
        2: 'dgnss',
        3: 'precisePps',
        4: 'rtk',
        5: 'floatRtk',
      },
    ),
    FieldDefinition(
      name: 'integrity',
      bitOffset: 256,
      bitLength: 2,
      type: FieldType.lookup,
      lookupTable: {0: 'noCheck', 1: 'safe', 2: 'caution'},
    ),
    FieldDefinition(
      name: 'reserved3',
      bitOffset: 258,
      bitLength: 6,
      type: FieldType.reserved,
    ),
    FieldDefinition(
      name: 'numberOfSvs',
      bitOffset: 264,
      bitLength: 8,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'hdop',
      bitOffset: 272,
      bitLength: 16,
      resolution: 0.01,
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'pdop',
      bitOffset: 288,
      bitLength: 16,
      resolution: 0.01,
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'geoidalSeparation',
      bitOffset: 304,
      bitLength: 32,
      resolution: 0.01, // meters
      type: FieldType.signed,
    ),
  ],
);

const timeDatePgn = PgnDefinition(
  pgn: 129033,
  name: 'Time & Date',
  transport: 1, // fast_packet
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'daysSince1970',
      bitOffset: 0,
      bitLength: 16,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'secondsSinceMidnight',
      bitOffset: 16,
      bitLength: 32,
      resolution: 0.0001,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'localOffset',
      bitOffset: 48,
      bitLength: 16,
      resolution: 1, // minutes
      type: FieldType.signed,
    ),
  ],
);

const distanceLogPgn = PgnDefinition(
  pgn: 128275,
  name: 'Distance Log',
  transport: 1, // fast_packet
  dataLength: 14,
  fields: [
    FieldDefinition(
      name: 'daysSince1970',
      bitOffset: 0,
      bitLength: 16,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'secondsSinceMidnight',
      bitOffset: 16,
      bitLength: 32,
      resolution: 0.0001,
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'log',
      bitOffset: 48,
      bitLength: 32,
      resolution: 1, // meters, cumulative
      type: FieldType.unsigned,
    ),
    FieldDefinition(
      name: 'tripLog',
      bitOffset: 80,
      bitLength: 32,
      resolution: 1, // meters
      type: FieldType.unsigned,
    ),
  ],
);

/// All navigation PGN definitions.
const navigationPgns = [
  positionRapidUpdatePgn,
  cogSogRapidUpdatePgn,
  gnssPositionDataPgn,
  timeDatePgn,
  distanceLogPgn,
];
