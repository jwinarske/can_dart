// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:can_codec/can_codec.dart';
import 'package:nmea2000/src/nmea2000_registry.dart';
import 'package:test/test.dart';

void main() {
  group('Nmea2000Registry.standard()', () {
    late Nmea2000Registry registry;

    setUp(() {
      registry = Nmea2000Registry.standard();
    });

    test('contains mandatory PGNs', () {
      expect(registry.lookup(126993), isNotNull); // Heartbeat
      expect(registry.lookup(126996), isNotNull); // Product Information
      expect(registry.lookup(126998), isNotNull); // Configuration Information
      expect(registry.lookup(59392), isNotNull); // ISO Acknowledgment
      expect(registry.lookup(59904), isNotNull); // ISO Request
    });

    test('contains navigation PGNs', () {
      expect(registry.lookup(129025), isNotNull); // Position Rapid Update
      expect(registry.lookup(129026), isNotNull); // COG & SOG
      expect(registry.lookup(129029), isNotNull); // GNSS Position Data
      expect(registry.lookup(129033), isNotNull); // Time & Date
      expect(registry.lookup(128275), isNotNull); // Distance Log
    });

    test('contains wind PGNs', () {
      expect(registry.lookup(130306), isNotNull); // Wind Data
    });

    test('contains heading PGNs', () {
      expect(registry.lookup(127250), isNotNull); // Vessel Heading
      expect(registry.lookup(127251), isNotNull); // Rate of Turn
      expect(registry.lookup(127258), isNotNull); // Magnetic Variation
    });

    test('contains depth/speed PGNs', () {
      expect(registry.lookup(128267), isNotNull); // Water Depth
      expect(registry.lookup(128259), isNotNull); // Speed Water Referenced
    });

    test('contains engine PGNs', () {
      expect(registry.lookup(127488), isNotNull); // Engine Params Rapid
      expect(registry.lookup(127489), isNotNull); // Engine Params Dynamic
      expect(registry.lookup(127493), isNotNull); // Transmission Params
    });

    test('contains electrical PGNs', () {
      expect(registry.lookup(127508), isNotNull); // Battery Status
      expect(registry.lookup(127505), isNotNull); // Fluid Level
    });

    test('contains rudder PGN', () {
      expect(registry.lookup(127245), isNotNull);
    });

    test('contains set & drift PGN', () {
      expect(registry.lookup(128281), isNotNull);
    });

    test('lookup returns correct PGN name', () {
      expect(registry.lookup(130306)!.name, 'Wind Data');
      expect(registry.lookup(129025)!.name, 'Position, Rapid Update');
    });

    test('allPgns and pgnNumbers have consistent counts', () {
      expect(registry.allPgns.length, registry.pgnNumbers.length);
      expect(registry.allPgns.length, greaterThanOrEqualTo(20));
    });
  });

  group('Nmea2000Registry.empty()', () {
    test('starts with zero PGNs', () {
      final registry = Nmea2000Registry.empty();
      expect(registry.allPgns, isEmpty);
      expect(registry.pgnNumbers, isEmpty);
    });

    test('lookup returns null on empty registry', () {
      final registry = Nmea2000Registry.empty();
      expect(registry.lookup(130306), isNull);
    });
  });

  group('register and lookup', () {
    test('register adds PGNs', () {
      final registry = Nmea2000Registry.empty();
      registry.register([
        const PgnDefinition(
          pgn: 99999,
          name: 'Custom',
          transport: 0,
          dataLength: 8,
          fields: [],
        ),
      ]);

      expect(registry.lookup(99999), isNotNull);
      expect(registry.lookup(99999)!.name, 'Custom');
      expect(registry.pgnNumbers, contains(99999));
    });

    test('register overwrites existing PGN', () {
      final registry = Nmea2000Registry.empty();
      registry.register([
        const PgnDefinition(
          pgn: 100,
          name: 'Original',
          transport: 0,
          dataLength: 8,
          fields: [],
        ),
      ]);
      expect(registry.lookup(100)!.name, 'Original');

      registry.register([
        const PgnDefinition(
          pgn: 100,
          name: 'Replaced',
          transport: 0,
          dataLength: 8,
          fields: [],
        ),
      ]);
      expect(registry.lookup(100)!.name, 'Replaced');
      // Count should not increase
      expect(registry.allPgns.length, 1);
    });

    test('register multiple PGNs at once', () {
      final registry = Nmea2000Registry.empty();
      registry.register([
        const PgnDefinition(
          pgn: 1,
          name: 'A',
          transport: 0,
          dataLength: 8,
          fields: [],
        ),
        const PgnDefinition(
          pgn: 2,
          name: 'B',
          transport: 1,
          dataLength: 16,
          fields: [],
        ),
      ]);
      expect(registry.allPgns.length, 2);
    });
  });

  group('fastPacketPgns', () {
    test('returns only PGNs with transport == 1', () {
      final registry = Nmea2000Registry.empty();
      registry.register([
        const PgnDefinition(
          pgn: 1,
          name: 'Single',
          transport: 0,
          dataLength: 8,
          fields: [],
        ),
        const PgnDefinition(
          pgn: 2,
          name: 'FastPacket',
          transport: 1,
          dataLength: 16,
          fields: [],
        ),
        const PgnDefinition(
          pgn: 3,
          name: 'IsoTp',
          transport: 2,
          dataLength: 32,
          fields: [],
        ),
      ]);

      final fp = registry.fastPacketPgns;
      expect(fp, [2]);
    });

    test('standard registry has fast packet PGNs', () {
      final registry = Nmea2000Registry.standard();
      final fp = registry.fastPacketPgns;
      expect(fp, isNotEmpty);
      // Position Rapid Update (129025) is fast_packet
      expect(fp, contains(129025));
      // Wind Data (130306) is single frame
      expect(fp, isNot(contains(130306)));
    });

    test('empty registry returns empty list', () {
      final registry = Nmea2000Registry.empty();
      expect(registry.fastPacketPgns, isEmpty);
    });
  });
}
