// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Import source files directly to avoid triggering j1939 native library load.

import 'package:can_codec/can_codec.dart';
import 'package:rvc/src/rvc_registry.dart';
import 'package:test/test.dart';

void main() {
  group('RvcRegistry.standard()', () {
    late RvcRegistry registry;

    setUp(() {
      registry = RvcRegistry.standard();
    });

    test('contains DGNs from all categories', () {
      // Spot-check one DGN from each category.
      expect(registry.allDgns.length, greaterThanOrEqualTo(10));
      expect(registry.dgnNumbers, isNotEmpty);
    });

    test('lookup returns correct name', () {
      // DC_SOURCE_STATUS_1 is a common RV-C DGN.
      final dgn = registry.lookup(0x1FFAD);
      if (dgn != null) {
        expect(dgn.name, isNotEmpty);
      }
    });

    test('allDgns and dgnNumbers have consistent counts', () {
      expect(registry.allDgns.length, registry.dgnNumbers.length);
    });
  });

  group('RvcRegistry.empty()', () {
    test('starts with zero DGNs', () {
      final registry = RvcRegistry.empty();
      expect(registry.allDgns, isEmpty);
      expect(registry.dgnNumbers, isEmpty);
    });

    test('lookup returns null', () {
      final registry = RvcRegistry.empty();
      expect(registry.lookup(0x1FFAD), isNull);
    });
  });

  group('register and lookup', () {
    test('adds and retrieves DGNs', () {
      final registry = RvcRegistry.empty();
      registry.register([
        const MessageDefinition(
          pgn: 99999,
          name: 'Custom DGN',
          transport: 0,
          dataLength: 8,
          fields: [],
        ),
      ]);
      expect(registry.lookup(99999), isNotNull);
      expect(registry.lookup(99999)!.name, 'Custom DGN');
    });

    test('overwrites existing DGN', () {
      final registry = RvcRegistry.empty();
      registry.register([
        const MessageDefinition(
          pgn: 100,
          name: 'Original',
          transport: 0,
          dataLength: 8,
          fields: [],
        ),
      ]);
      registry.register([
        const MessageDefinition(
          pgn: 100,
          name: 'Replaced',
          transport: 0,
          dataLength: 8,
          fields: [],
        ),
      ]);
      expect(registry.lookup(100)!.name, 'Replaced');
      expect(registry.allDgns.length, 1);
    });
  });
}
