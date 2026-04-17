// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:can_codec/can_codec.dart';
import 'package:test/test.dart';

// A simple test message definition for wind data.
const _windDef = MessageDefinition(
  pgn: 130306,
  name: 'Wind Data',
  transport: 0,
  dataLength: 6,
  fields: [
    FieldDefinition(name: 'sid', bitOffset: 0, bitLength: 8),
    FieldDefinition(
      name: 'windSpeed',
      bitOffset: 8,
      bitLength: 16,
      resolution: 0.01,
    ),
    FieldDefinition(
      name: 'windAngle',
      bitOffset: 24,
      bitLength: 16,
      resolution: 0.0001,
    ),
    FieldDefinition(
      name: 'reference',
      bitOffset: 40,
      bitLength: 3,
      type: FieldType.lookup,
    ),
    FieldDefinition(
      name: 'reserved1',
      bitOffset: 43,
      bitLength: 5,
      type: FieldType.reserved,
    ),
  ],
);

// Signed fields for position testing.
const _positionDef = MessageDefinition(
  pgn: 129025,
  name: 'Position',
  transport: 0,
  dataLength: 8,
  fields: [
    FieldDefinition(
      name: 'latitude',
      bitOffset: 0,
      bitLength: 32,
      resolution: 1e-7,
      type: FieldType.signed,
    ),
    FieldDefinition(
      name: 'longitude',
      bitOffset: 32,
      bitLength: 32,
      resolution: 1e-7,
      type: FieldType.signed,
    ),
  ],
);

void main() {
  group('decode', () {
    test('unsigned fields with resolution', () {
      final data = Uint8List(6);
      data[0] = 42;
      data[1] = 550 & 0xFF;
      data[2] = (550 >> 8) & 0xFF;
      data[3] = 7850 & 0xFF;
      data[4] = (7850 >> 8) & 0xFF;
      data[5] = 2;

      final result = decode(data, _windDef)!;
      expect(result['sid'], 42);
      expect(result['windSpeed'], closeTo(5.50, 0.001));
      expect(result['windAngle'], closeTo(0.7850, 0.00001));
      expect(result['reference'], 2);
    });

    test('signed fields', () {
      final data = Uint8List(8);
      final bd = ByteData.sublistView(data);
      bd.setInt32(0, 476062000, Endian.little);
      bd.setInt32(4, -1223321000, Endian.little);

      final result = decode(data, _positionDef)!;
      expect(result['latitude'], closeTo(47.6062, 0.0001));
      expect(result['longitude'], closeTo(-122.3321, 0.0001));
    });

    test('reserved fields are skipped', () {
      final data = Uint8List(6);
      final result = decode(data, _windDef)!;
      expect(result.containsKey('reserved1'), isFalse);
    });

    test('NA sentinel fields are omitted', () {
      final data = Uint8List(6)..fillRange(0, 6, 0xFF);
      final result = decode(data, _windDef)!;
      expect(result, isEmpty);
    });

    test('OOR sentinel decodes as NaN', () {
      final data = Uint8List(6);
      data[0] = 0xFE; // 8-bit OOR
      data.fillRange(1, 6, 0x00);
      final result = decode(data, _windDef)!;
      expect((result['sid'] as double).isNaN, isTrue);
    });

    test('short payload returns null', () {
      expect(decode(Uint8List(3), _windDef), isNull);
    });

    test('repeating PGN with short payload still decodes', () {
      final def = MessageDefinition(
        pgn: 99999,
        name: 'Repeating',
        transport: 0,
        dataLength: 16,
        repeating: true,
        fields: [
          const FieldDefinition(name: 'x', bitOffset: 0, bitLength: 8),
        ],
      );
      final data = Uint8List(4)..first = 7;
      expect(decode(data, def)!['x'], 7);
    });
  });

  group('encode', () {
    test('unsigned fields', () {
      final data =
          encode({'sid': 42, 'windSpeed': 5.50, 'reference': 2}, _windDef);
      expect(data.length, 6);
      expect(data[0], 42);
      expect(data[1], 0x26); // 550 low
      expect(data[2], 0x02); // 550 high
      expect(data[5] & 0x07, 2);
    });

    test('missing fields fill with NA (0xFF)', () {
      final data = encode(<String, dynamic>{}, _windDef);
      for (var i = 0; i < 6; i++) {
        expect(data[i], 0xFF);
      }
    });

    test('signed fields encode twos complement', () {
      final data = encode({
        'latitude': -33.8688,
        'longitude': 151.2093,
      }, _positionDef);
      final bd = ByteData.sublistView(data);
      expect(bd.getInt32(0, Endian.little), closeTo(-338688000, 1));
      expect(bd.getInt32(4, Endian.little), closeTo(1512093000, 1));
    });
  });

  group('encode-decode round trip', () {
    test('wind data', () {
      final original = <String, dynamic>{
        'sid': 42,
        'windSpeed': 5.50,
        'windAngle': 0.7850,
        'reference': 2,
      };
      final decoded = decode(encode(original, _windDef), _windDef)!;
      expect(decoded['sid'], 42);
      expect(decoded['windSpeed'], closeTo(5.50, 0.01));
      expect(decoded['windAngle'], closeTo(0.7850, 0.0001));
      expect(decoded['reference'], 2);
    });

    test('signed position', () {
      final original = <String, dynamic>{
        'latitude': 47.6062,
        'longitude': -122.3321,
      };
      final decoded = decode(encode(original, _positionDef), _positionDef)!;
      expect(decoded['latitude'], closeTo(47.6062, 1e-6));
      expect(decoded['longitude'], closeTo(-122.3321, 1e-6));
    });
  });

  group('sentinels', () {
    test('naSentinel values', () {
      expect(naSentinel(1), 1);
      expect(naSentinel(8), 0xFF);
      expect(naSentinel(16), 0xFFFF);
      expect(naSentinel(32), 0xFFFFFFFF);
      expect(naSentinel(64), -1);
    });

    test('isNa', () {
      expect(isNa(0xFF, 8), isTrue);
      expect(isNa(0xFE, 8), isFalse);
      expect(isNa(0, 8), isFalse);
    });

    test('isOor', () {
      expect(isOor(0xFE, 8), isTrue);
      expect(isOor(0xFF, 8), isFalse);
    });

    test('isReserved', () {
      expect(isReserved(0xFD, 8), isTrue);
      expect(isReserved(0xFE, 8), isFalse);
    });
  });

  group('MessageDefinition', () {
    test('construction', () {
      expect(_windDef.pgn, 130306);
      expect(_windDef.name, 'Wind Data');
      expect(_windDef.dataLength, 6);
      expect(_windDef.fields.length, 5);
      expect(_windDef.repeating, isFalse);
    });
  });

  group('FieldDefinition sentinels', () {
    test('sentinel values', () {
      const f = FieldDefinition(name: 'a', bitOffset: 0, bitLength: 8);
      expect(f.naSentinel, 0xFF);
      expect(f.oorSentinel, 0xFE);
      expect(f.reservedSentinel, 0xFD);
    });
  });

  group('TransportType', () {
    test('values', () {
      expect(TransportType.single.value, 0);
      expect(TransportType.fastPacket.value, 1);
      expect(TransportType.isoTp.value, 2);
      expect(TransportType.values.length, 3);
    });
  });

  group('FieldType', () {
    test('all values exist', () {
      expect(FieldType.values.length, 7);
    });
  });

  group('backward-compatible aliases', () {
    test('PgnDefinition is MessageDefinition', () {
      // ignore: unnecessary_type_check
      expect(_windDef is PgnDefinition, isTrue);
    });

    test('PgnTransport is TransportType', () {
      expect(PgnTransport.single, TransportType.single);
    });
  });
}
