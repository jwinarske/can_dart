// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:nmea2000_bus/src/bus_event.dart';
import 'package:nmea2000_bus/src/device_info.dart';
import 'package:test/test.dart';

void main() {
  // Shared test device.
  final device = DeviceInfo(
    address: 0x42,
    name: const N2kName(
      manufacturerCode: 0x1AB,
      identityNumber: 12345,
      industryGroup: 4,
    ),
  );

  group('sealed hierarchy exhaustive switch', () {
    test('all 6 event types are reachable', () {
      final events = <BusEvent>[
        DeviceAppeared(device),
        const DeviceDisappeared(0x42),
        DeviceInfoUpdated(device),
        const DeviceWentOffline(0x42),
        DeviceCameOnline(device),
        const ClaimConflict(
          address: 0x42,
          winner: N2kName(identityNumber: 1),
          loser: N2kName(identityNumber: 2),
        ),
      ];

      // Exhaustive switch — compiler verifies all cases covered.
      for (final e in events) {
        final label = switch (e) {
          DeviceAppeared() => 'appeared',
          DeviceDisappeared() => 'disappeared',
          DeviceInfoUpdated() => 'updated',
          DeviceWentOffline() => 'offline',
          DeviceCameOnline() => 'online',
          ClaimConflict() => 'conflict',
        };
        expect(label, isNotEmpty);
      }

      expect(events.length, 6);
    });
  });

  group('DeviceAppeared', () {
    test('stores device', () {
      final event = DeviceAppeared(device);
      expect(event.device.address, 0x42);
    });

    test('toString contains device info', () {
      final event = DeviceAppeared(device);
      expect(event.toString(), contains('DeviceAppeared'));
      expect(event.toString(), contains('0x42'));
    });
  });

  group('DeviceDisappeared', () {
    test('stores address', () {
      const event = DeviceDisappeared(0xA0);
      expect(event.address, 0xA0);
    });

    test('toString formats address as hex', () {
      const event = DeviceDisappeared(0x0A);
      expect(event.toString(), contains('0a'));
    });
  });

  group('DeviceInfoUpdated', () {
    test('stores device', () {
      final event = DeviceInfoUpdated(device);
      expect(event.device.address, 0x42);
    });

    test('toString contains DeviceInfoUpdated', () {
      final event = DeviceInfoUpdated(device);
      expect(event.toString(), contains('DeviceInfoUpdated'));
    });
  });

  group('DeviceWentOffline', () {
    test('stores address', () {
      const event = DeviceWentOffline(0xB0);
      expect(event.address, 0xB0);
    });

    test('toString formats address as hex', () {
      const event = DeviceWentOffline(0xB0);
      expect(event.toString(), contains('b0'));
    });
  });

  group('DeviceCameOnline', () {
    test('stores device', () {
      final event = DeviceCameOnline(device);
      expect(event.device.address, 0x42);
    });

    test('toString contains DeviceCameOnline', () {
      final event = DeviceCameOnline(device);
      expect(event.toString(), contains('DeviceCameOnline'));
    });
  });

  group('ClaimConflict', () {
    test('stores address, winner, and loser', () {
      const winner = N2kName(identityNumber: 1, manufacturerCode: 100);
      const loser = N2kName(identityNumber: 2, manufacturerCode: 200);
      const event = ClaimConflict(
        address: 0x50,
        winner: winner,
        loser: loser,
      );
      expect(event.address, 0x50);
      expect(event.winner.identityNumber, 1);
      expect(event.loser.manufacturerCode, 200);
    });

    test('toString includes address and winner/loser', () {
      const event = ClaimConflict(
        address: 0x50,
        winner: N2kName(identityNumber: 1),
        loser: N2kName(identityNumber: 2),
      );
      final s = event.toString();
      expect(s, contains('ClaimConflict'));
      expect(s, contains('50'));
      expect(s, contains('winner'));
      expect(s, contains('loser'));
    });
  });
}
