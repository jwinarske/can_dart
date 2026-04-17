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
  group('decode unsigned fields', () {
    test('wind data: speed, angle, sid', () {
      // sid=42, windSpeed=550 (5.50 m/s), windAngle=7850 (0.7850 rad)
      final data = Uint8List(6);
      data[0] = 42; // sid
      data[1] = 550 & 0xFF; // windSpeed low
      data[2] = (550 >> 8) & 0xFF; // windSpeed high
      data[3] = 7850 & 0xFF; // windAngle low
      data[4] = (7850 >> 8) & 0xFF; // windAngle high
      data[5] = 2; // reference = apparent

      final result = decode(data, windDataPgn)!;
      expect(result['sid'], 42);
      expect(result['windSpeed'], closeTo(5.50, 0.001));
      expect(result['windAngle'], closeTo(0.7850, 0.00001));
      expect(result['reference'], 2);
    });

    test('zero values decode correctly', () {
      final data = Uint8List(6); // all zeros
      final result = decode(data, windDataPgn)!;
      expect(result['sid'], 0);
      expect(result['windSpeed'], closeTo(0.0, 0.001));
      expect(result['windAngle'], closeTo(0.0, 0.00001));
      expect(result['reference'], 0);
    });
  });

  group('decode signed fields', () {
    test('positive latitude and longitude', () {
      // lat = 47.6062° → raw = 476062000, lon = -122.3321° → raw = -1223321000
      final data = Uint8List(8);
      final bd = ByteData.sublistView(data);
      bd.setInt32(0, 476062000, Endian.little);
      bd.setInt32(4, -1223321000, Endian.little);

      final result = decode(data, positionRapidUpdatePgn)!;
      expect(result['latitude'], closeTo(47.6062, 0.0001));
      expect(result['longitude'], closeTo(-122.3321, 0.0001));
    });

    test('negative latitude (southern hemisphere)', () {
      // lat = -33.8688° → raw = -338688000
      final data = Uint8List(8);
      final bd = ByteData.sublistView(data);
      bd.setInt32(0, -338688000, Endian.little);
      bd.setInt32(4, 1512093000, Endian.little); // lon = 151.2093°

      final result = decode(data, positionRapidUpdatePgn)!;
      expect(result['latitude'], closeTo(-33.8688, 0.0001));
      expect(result['longitude'], closeTo(151.2093, 0.0001));
    });

    test('zero position (null island)', () {
      final data = Uint8List(8); // all zeros
      final result = decode(data, positionRapidUpdatePgn)!;
      expect(result['latitude'], closeTo(0.0, 1e-7));
      expect(result['longitude'], closeTo(0.0, 1e-7));
    });
  });

  group('decode string fields', () {
    test('product information with ASCII strings', () {
      final data = Uint8List(134);
      // nmea2000Version = 2100
      data[0] = 2100 & 0xFF;
      data[1] = (2100 >> 8) & 0xFF;
      // productCode = 42
      data[2] = 42;
      data[3] = 0;
      // modelId at byte 4, 32 bytes
      final modelBytes = 'Test Display'.codeUnits;
      data.setRange(4, 4 + modelBytes.length, modelBytes);
      // Pad rest of modelId with 0xFF
      data.fillRange(4 + modelBytes.length, 36, 0xFF);
      // softwareVersionCode at byte 36, 32 bytes
      final swBytes = '1.2.3'.codeUnits;
      data.setRange(36, 36 + swBytes.length, swBytes);
      data.fillRange(36 + swBytes.length, 68, 0xFF);
      // modelVersion at byte 68, 32 bytes
      final mvBytes = 'Rev A'.codeUnits;
      data.setRange(68, 68 + mvBytes.length, mvBytes);
      data.fillRange(68 + mvBytes.length, 100, 0xFF);
      // modelSerialCode at byte 100, 32 bytes
      final snBytes = 'SN001'.codeUnits;
      data.setRange(100, 100 + snBytes.length, snBytes);
      data.fillRange(100 + snBytes.length, 132, 0xFF);
      // certificationLevel and loadEquivalency
      data[132] = 1;
      data[133] = 2;

      final result = decode(data, productInformationPgn)!;
      expect(result['nmea2000Version'], 2100);
      expect(result['productCode'], 42);
      expect(result['modelId'], 'Test Display');
      expect(result['softwareVersionCode'], '1.2.3');
      expect(result['modelVersion'], 'Rev A');
      expect(result['modelSerialCode'], 'SN001');
      expect(result['certificationLevel'], 1);
      expect(result['loadEquivalency'], 2);
    });

    test('strings with null padding are trimmed', () {
      final data = Uint8List(134);
      data.fillRange(0, 134, 0xFF);
      data[0] = 0;
      data[1] = 0;
      data[2] = 0;
      data[3] = 0;
      // modelId: "Hi" followed by 0x00 padding
      data[4] = 0x48; // H
      data[5] = 0x69; // i
      data.fillRange(6, 36, 0x00); // null padding

      final result = decode(data, productInformationPgn)!;
      expect(result['modelId'], 'Hi');
    });
  });

  group('decode lookup fields', () {
    test('COG reference lookup returns raw integer', () {
      final data = Uint8List(8);
      data[0] = 5; // sid
      data[1] = 1; // cogReference = 1 (magnetic), bits 8-9
      // Remaining bytes as 0xFF (NA)
      data.fillRange(2, 8, 0xFF);

      final result = decode(data, cogSogRapidUpdatePgn)!;
      expect(result['sid'], 5);
      expect(result['cogReference'], 1);
    });
  });

  group('reserved fields', () {
    test('reserved fields are not included in result', () {
      final data = Uint8List(8);
      data.fillRange(0, 8, 0x00);

      final result = decode(data, cogSogRapidUpdatePgn)!;
      expect(result.containsKey('reserved1'), isFalse);
      expect(result.containsKey('reserved2'), isFalse);
    });
  });

  group('NA sentinel handling', () {
    test('all-bits-set field is omitted from result', () {
      final data = Uint8List(6);
      data.fillRange(0, 6, 0xFF); // all NA

      final result = decode(data, windDataPgn)!;
      expect(result.containsKey('sid'), isFalse);
      expect(result.containsKey('windSpeed'), isFalse);
      expect(result.containsKey('windAngle'), isFalse);
      expect(result.containsKey('reference'), isFalse);
    });

    test('individual NA field is omitted while others decode', () {
      final data = Uint8List(6);
      data[0] = 42; // sid = 42
      data[1] = 0xFF; // windSpeed = NA (all bits set for 16-bit)
      data[2] = 0xFF;
      data[3] = 100 & 0xFF; // windAngle = 100
      data[4] = (100 >> 8) & 0xFF;
      data[5] = 2; // reference = 2

      final result = decode(data, windDataPgn)!;
      expect(result['sid'], 42);
      expect(result.containsKey('windSpeed'), isFalse);
      expect(result['windAngle'], closeTo(0.01, 0.00001));
      expect(result['reference'], 2);
    });
  });

  group('OOR sentinel handling', () {
    test('all-bits-set-minus-1 decodes as NaN', () {
      final data = Uint8List(6);
      data[0] = 0xFE; // sid = OOR (8-bit: 0xFF - 1)
      data[1] = 0xFE; // windSpeed low = 0xFFFE (16-bit OOR)
      data[2] = 0xFF;
      data[3] = 0x00;
      data[4] = 0x00;
      data[5] = 0x00;

      final result = decode(data, windDataPgn)!;
      expect((result['sid'] as double).isNaN, isTrue);
      expect((result['windSpeed'] as double).isNaN, isTrue);
    });
  });

  group('short payload', () {
    test('returns null when payload shorter than dataLength', () {
      final data = Uint8List(3); // windDataPgn expects 6
      expect(decode(data, windDataPgn), isNull);
    });

    test('returns null for empty payload', () {
      expect(decode(Uint8List(0), windDataPgn), isNull);
    });
  });

  group('repeating PGN', () {
    test('short payload still decodes when repeating is true', () {
      final repeatingDef = PgnDefinition(
        pgn: 99999,
        name: 'Test Repeating',
        transport: 0,
        dataLength: 16,
        repeating: true,
        fields: [
          const FieldDefinition(
            name: 'counter',
            bitOffset: 0,
            bitLength: 8,
            type: FieldType.unsigned,
          ),
        ],
      );

      final data = Uint8List(4); // shorter than dataLength of 16
      data[0] = 7;

      final result = decode(data, repeatingDef);
      expect(result, isNotNull);
      expect(result!['counter'], 7);
    });
  });

  group('encode-decode round trip', () {
    test('wind data round trip', () {
      final original = <String, dynamic>{
        'sid': 42,
        'windSpeed': 5.50,
        'windAngle': 0.7850,
        'reference': 2,
      };

      final encoded = encode(original, windDataPgn);
      final decoded = decode(encoded, windDataPgn)!;

      expect(decoded['sid'], 42);
      expect(decoded['windSpeed'], closeTo(5.50, 0.01));
      expect(decoded['windAngle'], closeTo(0.7850, 0.0001));
      expect(decoded['reference'], 2);
    });

    test('position rapid update round trip with signed values', () {
      final original = <String, dynamic>{
        'latitude': 47.6062,
        'longitude': -122.3321,
      };

      final encoded = encode(original, positionRapidUpdatePgn);
      final decoded = decode(encoded, positionRapidUpdatePgn)!;

      expect(decoded['latitude'], closeTo(47.6062, 1e-6));
      expect(decoded['longitude'], closeTo(-122.3321, 1e-6));
    });

    test('heartbeat round trip', () {
      final original = <String, dynamic>{
        'dataTransmitOffset': 600000.0, // 60s × 10ms resolution
        'sequenceCounter': 99,
        'class1CanState': 0,
        'class2CanState': 0,
        'noProductInfoYet': 0,
      };

      final encoded = encode(original, heartbeatPgn);
      final decoded = decode(encoded, heartbeatPgn)!;

      expect(decoded['dataTransmitOffset'], closeTo(600000.0, 10));
      expect(decoded['sequenceCounter'], 99);
    });

    test('product information string round trip', () {
      final original = <String, dynamic>{
        'nmea2000Version': 2100,
        'productCode': 42,
        'modelId': 'Marine Display',
        'softwareVersionCode': '2.1.0',
        'modelVersion': 'Rev B',
        'modelSerialCode': 'SN12345',
        'certificationLevel': 1,
        'loadEquivalency': 3,
      };

      final encoded = encode(original, productInformationPgn);
      final decoded = decode(encoded, productInformationPgn)!;

      expect(decoded['nmea2000Version'], 2100);
      expect(decoded['productCode'], 42);
      expect(decoded['modelId'], 'Marine Display');
      expect(decoded['softwareVersionCode'], '2.1.0');
      expect(decoded['modelVersion'], 'Rev B');
      expect(decoded['modelSerialCode'], 'SN12345');
      expect(decoded['certificationLevel'], 1);
      expect(decoded['loadEquivalency'], 3);
    });
  });
}
