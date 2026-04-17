// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Import source files directly to avoid triggering j1939 native library load.

import 'dart:typed_data';

import 'package:rvc_bus/src/rvc_bus_event.dart';
import 'package:rvc_bus/src/rvc_device_info.dart';
import 'package:test/test.dart';

void main() {
  group('RvcName defaults', () {
    test('default constructor values', () {
      const name = RvcName();
      expect(name.identityNumber, 0);
      expect(name.manufacturerCode, 0x7FF);
      expect(name.arbitraryAddress, isTrue);
      expect(name.deviceFunction, 0);
    });
  });

  group('RvcName.decode', () {
    test('decodes all 9 fields from 8-byte LE payload', () {
      const name = RvcName(
        identityNumber: 0x12345,
        manufacturerCode: 0x1AB,
        functionInstance: 5,
        ecuInstance: 3,
        deviceFunction: 30, // Generator
        deviceClass: 10,
        arbitraryAddress: true,
        industryGroup: 5, // Industrial
        systemInstance: 2,
      );

      final raw = name.raw;
      final data = Uint8List(8);
      for (var i = 0; i < 8; i++) {
        data[i] = (raw >> (i * 8)) & 0xFF;
      }

      final decoded = RvcName.decode(data);
      expect(decoded.identityNumber, 0x12345);
      expect(decoded.manufacturerCode, 0x1AB);
      expect(decoded.functionInstance, 5);
      expect(decoded.ecuInstance, 3);
      expect(decoded.deviceFunction, 30);
      expect(decoded.deviceClass, 10);
      expect(decoded.arbitraryAddress, isTrue);
      expect(decoded.industryGroup, 5);
      expect(decoded.systemInstance, 2);
    });

    test('short data returns default', () {
      final decoded = RvcName.decode(Uint8List(4));
      expect(decoded.manufacturerCode, 0x7FF);
    });
  });

  group('RvcName.fromRaw round trip', () {
    test('max values round trip', () {
      const original = RvcName(
        identityNumber: 0x1FFFFF,
        manufacturerCode: 0x7FF,
        functionInstance: 0x1F,
        ecuInstance: 0x07,
        deviceFunction: 0xFF,
        deviceClass: 0x7F,
        arbitraryAddress: true,
        industryGroup: 0x07,
        systemInstance: 0x0F,
      );
      final rt = RvcName.fromRaw(original.raw);
      expect(rt.identityNumber, original.identityNumber);
      expect(rt.manufacturerCode, original.manufacturerCode);
      expect(rt.deviceFunction, original.deviceFunction);
      expect(rt.arbitraryAddress, original.arbitraryAddress);
    });

    test('zero NAME round trips', () {
      const name = RvcName(
        identityNumber: 0,
        manufacturerCode: 0,
        arbitraryAddress: false,
      );
      expect(name.raw, 0);
      final rt = RvcName.fromRaw(0);
      expect(rt.identityNumber, 0);
      expect(rt.arbitraryAddress, isFalse);
    });
  });

  group('RvcName.raw bit positions', () {
    test('identityNumber at bits 0-20', () {
      const name = RvcName(
          identityNumber: 1, manufacturerCode: 0, arbitraryAddress: false);
      expect(name.raw, 1);
    });

    test('manufacturerCode at bits 21-31', () {
      const name = RvcName(
          identityNumber: 0, manufacturerCode: 1, arbitraryAddress: false);
      expect(name.raw, 1 << 21);
    });

    test('deviceFunction at bits 40-47', () {
      const name = RvcName(
          identityNumber: 0,
          manufacturerCode: 0,
          deviceFunction: 1,
          arbitraryAddress: false);
      expect(name.raw, 1 << 40);
    });

    test('arbitraryAddress at bit 56', () {
      const name = RvcName(
          identityNumber: 0, manufacturerCode: 0, arbitraryAddress: true);
      expect(name.raw, 1 << 56);
    });
  });

  group('RvcName.deviceTypeName', () {
    test('known device functions', () {
      expect(const RvcName(deviceFunction: 0).deviceTypeName, 'Generic');
      expect(
          const RvcName(deviceFunction: 1).deviceTypeName, 'Main Controller');
      expect(const RvcName(deviceFunction: 10).deviceTypeName, 'Display');
      expect(const RvcName(deviceFunction: 30).deviceTypeName, 'Generator');
      expect(
          const RvcName(deviceFunction: 32).deviceTypeName, 'Battery Charger');
      expect(const RvcName(deviceFunction: 33).deviceTypeName, 'Inverter');
      expect(const RvcName(deviceFunction: 38).deviceTypeName, 'Tank Sensor');
      expect(
          const RvcName(deviceFunction: 60).deviceTypeName, 'Solar Controller');
    });

    test('unknown device function', () {
      expect(const RvcName(deviceFunction: 255).deviceTypeName,
          contains('Unknown'));
    });
  });

  group('RvcName.toString', () {
    test('includes key fields', () {
      const name = RvcName(
        manufacturerCode: 0x1AB,
        identityNumber: 12345,
        deviceFunction: 30,
      );
      final s = name.toString();
      expect(s, contains('mfr='));
      expect(s, contains('12345'));
      expect(s, contains('Generator'));
    });
  });

  group('RvcDeviceInfo', () {
    test('defaults', () {
      final device = RvcDeviceInfo(address: 0x42);
      expect(device.address, 0x42);
      expect(device.name.manufacturerCode, 0x7FF);
      expect(device.status, RvcDeviceStatus.online);
    });

    test('toString includes hex address', () {
      final device = RvcDeviceInfo(address: 0x42);
      expect(device.toString(), contains('0x42'));
    });

    test('status can be changed', () {
      final device = RvcDeviceInfo(address: 0x10);
      device.status = RvcDeviceStatus.offline;
      expect(device.status, RvcDeviceStatus.offline);
    });
  });

  group('RvcDeviceStatus', () {
    test('has two values', () {
      expect(RvcDeviceStatus.values.length, 2);
    });
  });

  group('sealed RvcBusEvent hierarchy', () {
    test('all 4 event types are reachable', () {
      final device = RvcDeviceInfo(address: 0x42);
      final events = <RvcBusEvent>[
        RvcDeviceAppeared(device),
        const RvcDeviceDisappeared(0x42),
        const RvcDeviceWentOffline(0x42),
        RvcDeviceCameOnline(device),
      ];

      for (final e in events) {
        final label = switch (e) {
          RvcDeviceAppeared() => 'appeared',
          RvcDeviceDisappeared() => 'disappeared',
          RvcDeviceWentOffline() => 'offline',
          RvcDeviceCameOnline() => 'online',
        };
        expect(label, isNotEmpty);
      }
      expect(events.length, 4);
    });

    test('RvcDeviceAppeared stores device', () {
      final device = RvcDeviceInfo(address: 0xA0);
      final event = RvcDeviceAppeared(device);
      expect(event.device.address, 0xA0);
      expect(event.toString(), contains('RvcDeviceAppeared'));
    });

    test('RvcDeviceDisappeared stores address', () {
      const event = RvcDeviceDisappeared(0xB0);
      expect(event.address, 0xB0);
      expect(event.toString(), contains('b0'));
    });

    test('RvcDeviceWentOffline stores address', () {
      const event = RvcDeviceWentOffline(0xC0);
      expect(event.address, 0xC0);
    });

    test('RvcDeviceCameOnline stores device', () {
      final device = RvcDeviceInfo(address: 0xD0);
      final event = RvcDeviceCameOnline(device);
      expect(event.device.address, 0xD0);
    });
  });
}
