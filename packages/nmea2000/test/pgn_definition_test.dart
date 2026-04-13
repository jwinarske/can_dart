// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';
import 'package:test/test.dart';

void main() {
  group('FieldDefinition sentinels', () {
    test('naSentinel matches expected values', () {
      expect(
        const FieldDefinition(name: 'a', bitOffset: 0, bitLength: 1).naSentinel,
        1,
      );
      expect(
        const FieldDefinition(name: 'a', bitOffset: 0, bitLength: 2).naSentinel,
        3,
      );
      expect(
        const FieldDefinition(name: 'a', bitOffset: 0, bitLength: 8).naSentinel,
        0xFF,
      );
      expect(
        const FieldDefinition(name: 'a', bitOffset: 0, bitLength: 16)
            .naSentinel,
        0xFFFF,
      );
      expect(
        const FieldDefinition(name: 'a', bitOffset: 0, bitLength: 32)
            .naSentinel,
        0xFFFFFFFF,
      );
    });

    test('naSentinel returns -1 for bitLength >= 64', () {
      expect(
        const FieldDefinition(name: 'a', bitOffset: 0, bitLength: 64)
            .naSentinel,
        -1,
      );
    });

    test('oorSentinel is naSentinel - 1', () {
      const f = FieldDefinition(name: 'a', bitOffset: 0, bitLength: 8);
      expect(f.oorSentinel, f.naSentinel - 1);
      expect(f.oorSentinel, 0xFE);
    });

    test('reservedSentinel is naSentinel - 2', () {
      const f = FieldDefinition(name: 'a', bitOffset: 0, bitLength: 16);
      expect(f.reservedSentinel, f.naSentinel - 2);
      expect(f.reservedSentinel, 0xFFFD);
    });
  });

  group('FieldDefinition construction', () {
    test('defaults', () {
      const f = FieldDefinition(name: 'test', bitOffset: 8, bitLength: 16);
      expect(f.resolution, 1.0);
      expect(f.offset, 0.0);
      expect(f.type, FieldType.unsigned);
      expect(f.lookupTable, isNull);
    });

    test('all parameters stored', () {
      const f = FieldDefinition(
        name: 'speed',
        bitOffset: 24,
        bitLength: 16,
        resolution: 0.01,
        offset: -10.0,
        type: FieldType.signed,
        lookupTable: {0: 'off', 1: 'on'},
      );
      expect(f.name, 'speed');
      expect(f.bitOffset, 24);
      expect(f.bitLength, 16);
      expect(f.resolution, 0.01);
      expect(f.offset, -10.0);
      expect(f.type, FieldType.signed);
      expect(f.lookupTable, {0: 'off', 1: 'on'});
    });
  });

  group('PgnDefinition construction', () {
    test('all fields stored', () {
      const def = PgnDefinition(
        pgn: 130306,
        name: 'Wind Data',
        transport: 0,
        dataLength: 6,
        fields: [
          FieldDefinition(name: 'sid', bitOffset: 0, bitLength: 8),
        ],
      );
      expect(def.pgn, 130306);
      expect(def.name, 'Wind Data');
      expect(def.transport, 0);
      expect(def.dataLength, 6);
      expect(def.fields.length, 1);
      expect(def.repeating, isFalse);
    });

    test('repeating defaults to false', () {
      const def = PgnDefinition(
        pgn: 1,
        name: 'Test',
        transport: 0,
        dataLength: 8,
        fields: [],
      );
      expect(def.repeating, isFalse);
    });

    test('repeating can be set to true', () {
      const def = PgnDefinition(
        pgn: 1,
        name: 'Test',
        transport: 0,
        dataLength: 8,
        fields: [],
        repeating: true,
      );
      expect(def.repeating, isTrue);
    });
  });

  group('FieldType enum', () {
    test('all values exist', () {
      expect(
          FieldType.values,
          containsAll([
            FieldType.unsigned,
            FieldType.signed,
            FieldType.float32,
            FieldType.float64,
            FieldType.string,
            FieldType.lookup,
            FieldType.reserved,
          ]));
      expect(FieldType.values.length, 7);
    });
  });
}
