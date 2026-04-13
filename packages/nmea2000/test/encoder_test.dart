// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Import source files directly — NOT the barrel nmea2000.dart — to avoid
// triggering the j1939 native library load.

import 'dart:typed_data';

import 'package:can_codec/can_codec.dart';
import 'package:nmea2000/src/pgns/mandatory.dart';
import 'package:nmea2000/src/pgns/navigation.dart';
import 'package:nmea2000/src/pgns/wind.dart';
import 'package:test/test.dart';

void main() {
  group('encode unsigned fields', () {
    test('wind data encodes speed and angle correctly', () {
      final values = <String, dynamic>{
        'sid': 42,
        'windSpeed': 5.50,
        'windAngle': 0.7850,
        'reference': 2,
      };

      final data = encode(values, windDataPgn);
      expect(data.length, 6);

      // sid = 42 at byte 0
      expect(data[0], 42);
      // windSpeed: 5.50 / 0.01 = 550 = 0x0226
      expect(data[1], 0x26);
      expect(data[2], 0x02);
      // windAngle: 0.7850 / 0.0001 = 7850 = 0x1EAA
      expect(data[3], 0xAA);
      expect(data[4], 0x1E);
      // reference = 2 at bits 40-42 (3 bits)
      // Byte 5: bits 0-2 = reference(2), bits 3-7 = reserved(0xFF fill → 0x1F)
      // reserved fills as 0xFF initially; encoder clears reference bits and
      // writes 2 = 0b010 into bits 0-2.
      expect(data[5] & 0x07, 2); // lower 3 bits
    });

    test('zero values encode as zero bytes', () {
      final values = <String, dynamic>{
        'sid': 0,
        'windSpeed': 0.0,
        'windAngle': 0.0,
        'reference': 0,
      };

      final data = encode(values, windDataPgn);
      expect(data[0], 0);
      expect(data[1], 0);
      expect(data[2], 0);
      expect(data[3], 0);
      expect(data[4], 0);
      expect(data[5] & 0x07, 0);
    });
  });

  group('encode signed fields', () {
    test('positive latitude encodes correctly', () {
      final values = <String, dynamic>{
        'latitude': 47.6062,
        'longitude': 0.0,
      };

      final data = encode(values, positionRapidUpdatePgn);
      final bd = ByteData.sublistView(data);
      // lat: 47.6062 / 1e-7 = 476062000
      final raw = bd.getInt32(0, Endian.little);
      expect(raw, closeTo(476062000, 1));
    });

    test('negative longitude encodes as twos complement', () {
      final values = <String, dynamic>{
        'latitude': 0.0,
        'longitude': -122.3321,
      };

      final data = encode(values, positionRapidUpdatePgn);
      final bd = ByteData.sublistView(data);
      final raw = bd.getInt32(4, Endian.little);
      expect(raw, closeTo(-1223321000, 1));
    });
  });

  group('encode lookup fields', () {
    test('COG reference lookup encodes at correct bit offset', () {
      final values = <String, dynamic>{
        'sid': 5,
        'cogReference': 1, // magnetic
        'cog': 1.5708, // ~90° in radians
        'sog': 3.0, // m/s
      };

      final data = encode(values, cogSogRapidUpdatePgn);
      expect(data[0], 5); // sid
      // cogReference at bits 8-9 (2 bits in byte 1, lower 2 bits)
      expect(data[1] & 0x03, 1);
    });
  });

  group('encode string fields', () {
    test('short string is padded with 0xFF', () {
      final values = <String, dynamic>{
        'nmea2000Version': 2100,
        'productCode': 42,
        'modelId': 'Hi',
        'softwareVersionCode': 'v1',
        'modelVersion': 'A',
        'modelSerialCode': 'S1',
        'certificationLevel': 1,
        'loadEquivalency': 1,
      };

      final data = encode(values, productInformationPgn);
      expect(data.length, 134);

      // modelId at bytes 4..35 (32 bytes)
      expect(data[4], 0x48); // 'H'
      expect(data[5], 0x69); // 'i'
      // Remaining bytes should be 0xFF (padding)
      for (var i = 6; i < 36; i++) {
        expect(data[i], 0xFF, reason: 'byte $i should be 0xFF padding');
      }
    });
  });

  group('missing fields encode as NA', () {
    test('omitted wind fields fill with 0xFF', () {
      final data = encode(<String, dynamic>{}, windDataPgn);
      expect(data.length, 6);
      // All bytes should be 0xFF (NA fill)
      for (var i = 0; i < 6; i++) {
        expect(data[i], 0xFF, reason: 'byte $i should be 0xFF');
      }
    });

    test('partial values: only provided fields are encoded', () {
      final data = encode({'sid': 10}, windDataPgn);
      expect(data[0], 10); // sid encoded
      // windSpeed (bytes 1-2) should remain 0xFF
      expect(data[1], 0xFF);
      expect(data[2], 0xFF);
      // windAngle (bytes 3-4) should remain 0xFF
      expect(data[3], 0xFF);
      expect(data[4], 0xFF);
    });
  });

  group('output size', () {
    test('output matches PGN dataLength', () {
      expect(encode({}, windDataPgn).length, 6);
      expect(encode({}, positionRapidUpdatePgn).length, 8);
      expect(encode({}, productInformationPgn).length, 134);
      expect(encode({}, heartbeatPgn).length, 8);
      expect(encode({}, isoRequestPgn).length, 3);
    });
  });

  group('encode-decode consistency', () {
    test('all wind data fields survive round trip', () {
      final original = <String, dynamic>{
        'sid': 255 - 2, // avoid NA/OOR
        'windSpeed': 12.34,
        'windAngle': 3.1415,
        'reference': 4,
      };

      final encoded = encode(original, windDataPgn);
      final decoded = decode(encoded, windDataPgn)!;

      expect(decoded['sid'], original['sid']);
      expect(
          decoded['windSpeed'], closeTo(original['windSpeed'] as double, 0.01));
      expect(decoded['windAngle'],
          closeTo(original['windAngle'] as double, 0.0001));
      expect(decoded['reference'], original['reference']);
    });

    test('COG/SOG fields survive round trip', () {
      final original = <String, dynamic>{
        'sid': 10,
        'cogReference': 0,
        'cog': 1.5708,
        'sog': 5.25,
      };

      final encoded = encode(original, cogSogRapidUpdatePgn);
      final decoded = decode(encoded, cogSogRapidUpdatePgn)!;

      expect(decoded['sid'], 10);
      expect(decoded['cogReference'], 0);
      expect(decoded['cog'], closeTo(1.5708, 0.0001));
      expect(decoded['sog'], closeTo(5.25, 0.01));
    });
  });
}
