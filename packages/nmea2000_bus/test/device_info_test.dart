// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Import source files directly to avoid triggering native library loads.

import 'dart:typed_data';

import 'package:nmea2000_bus/src/device_info.dart';
import 'package:test/test.dart';

void main() {
  group('N2kName defaults', () {
    test('default constructor values', () {
      const name = N2kName();
      expect(name.identityNumber, 0);
      expect(name.manufacturerCode, 0x7FF);
      expect(name.functionInstance, 0);
      expect(name.ecuInstance, 0);
      expect(name.deviceFunction, 0);
      expect(name.deviceClass, 0);
      expect(name.arbitraryAddress, isTrue);
      expect(name.industryGroup, 0);
      expect(name.systemInstance, 0);
    });
  });

  group('N2kName.decode', () {
    test('decodes all 9 fields from 8-byte LE payload', () {
      // Build a known NAME:
      //   identityNumber   = 0x12345  (21 bits)
      //   manufacturerCode = 0x1AB    (11 bits)
      //   functionInstance  = 5       (5 bits)
      //   ecuInstance       = 3       (3 bits)
      //   deviceFunction    = 130     (8 bits)
      //   deviceClass       = 120     (7 bits, bit 48 reserved)
      //   arbitraryAddress  = true    (1 bit)
      //   industryGroup     = 4       (3 bits)
      //   systemInstance    = 2       (4 bits)
      const name = N2kName(
        identityNumber: 0x12345,
        manufacturerCode: 0x1AB,
        functionInstance: 5,
        ecuInstance: 3,
        deviceFunction: 130,
        deviceClass: 120,
        arbitraryAddress: true,
        industryGroup: 4,
        systemInstance: 2,
      );

      // Encode to raw then to 8 bytes LE.
      final raw = name.raw;
      final data = Uint8List(8);
      for (var i = 0; i < 8; i++) {
        data[i] = (raw >> (i * 8)) & 0xFF;
      }

      final decoded = N2kName.decode(data);
      expect(decoded.identityNumber, 0x12345);
      expect(decoded.manufacturerCode, 0x1AB);
      expect(decoded.functionInstance, 5);
      expect(decoded.ecuInstance, 3);
      expect(decoded.deviceFunction, 130);
      expect(decoded.deviceClass, 120);
      expect(decoded.arbitraryAddress, isTrue);
      expect(decoded.industryGroup, 4);
      expect(decoded.systemInstance, 2);
    });

    test('short data returns default', () {
      final decoded = N2kName.decode(Uint8List(4));
      expect(decoded.identityNumber, 0);
      expect(decoded.manufacturerCode, 0x7FF);
    });

    test('empty data returns default', () {
      final decoded = N2kName.decode(Uint8List(0));
      expect(decoded.manufacturerCode, 0x7FF);
    });
  });

  group('N2kName.fromRaw round trip', () {
    test('construct → raw → fromRaw preserves all fields', () {
      const original = N2kName(
        identityNumber: 0x1FFFFF, // max 21 bits
        manufacturerCode: 0x7FF, // max 11 bits
        functionInstance: 0x1F, // max 5 bits
        ecuInstance: 0x07, // max 3 bits
        deviceFunction: 0xFF, // max 8 bits
        deviceClass: 0x7F, // max 7 bits
        arbitraryAddress: true,
        industryGroup: 0x07, // max 3 bits
        systemInstance: 0x0F, // max 4 bits
      );

      final roundTripped = N2kName.fromRaw(original.raw);
      expect(roundTripped.identityNumber, original.identityNumber);
      expect(roundTripped.manufacturerCode, original.manufacturerCode);
      expect(roundTripped.functionInstance, original.functionInstance);
      expect(roundTripped.ecuInstance, original.ecuInstance);
      expect(roundTripped.deviceFunction, original.deviceFunction);
      expect(roundTripped.deviceClass, original.deviceClass);
      expect(roundTripped.arbitraryAddress, original.arbitraryAddress);
      expect(roundTripped.industryGroup, original.industryGroup);
      expect(roundTripped.systemInstance, original.systemInstance);
    });

    test('arbitraryAddress false round trips', () {
      const name = N2kName(arbitraryAddress: false);
      final rt = N2kName.fromRaw(name.raw);
      expect(rt.arbitraryAddress, isFalse);
    });

    test('zero NAME round trips', () {
      const name = N2kName(
        identityNumber: 0,
        manufacturerCode: 0,
        functionInstance: 0,
        ecuInstance: 0,
        deviceFunction: 0,
        deviceClass: 0,
        arbitraryAddress: false,
        industryGroup: 0,
        systemInstance: 0,
      );
      expect(name.raw, 0);
      final rt = N2kName.fromRaw(0);
      expect(rt.identityNumber, 0);
      expect(rt.arbitraryAddress, isFalse);
    });
  });

  group('N2kName.raw encoding bit positions', () {
    test('identityNumber at bits 0-20', () {
      const name = N2kName(
        identityNumber: 1,
        manufacturerCode: 0,
        arbitraryAddress: false,
      );
      expect(name.raw, 1);
    });

    test('manufacturerCode at bits 21-31', () {
      const name = N2kName(
        identityNumber: 0,
        manufacturerCode: 1,
        arbitraryAddress: false,
      );
      expect(name.raw, 1 << 21);
    });

    test('functionInstance at bits 32-36', () {
      const name = N2kName(
        identityNumber: 0,
        manufacturerCode: 0,
        functionInstance: 1,
        arbitraryAddress: false,
      );
      expect(name.raw, 1 << 32);
    });

    test('ecuInstance at bits 37-39', () {
      const name = N2kName(
        identityNumber: 0,
        manufacturerCode: 0,
        ecuInstance: 1,
        arbitraryAddress: false,
      );
      expect(name.raw, 1 << 37);
    });

    test('deviceFunction at bits 40-47', () {
      const name = N2kName(
        identityNumber: 0,
        manufacturerCode: 0,
        deviceFunction: 1,
        arbitraryAddress: false,
      );
      expect(name.raw, 1 << 40);
    });

    test('deviceClass at bits 49-55', () {
      const name = N2kName(
        identityNumber: 0,
        manufacturerCode: 0,
        deviceClass: 1,
        arbitraryAddress: false,
      );
      expect(name.raw, 1 << 49);
    });

    test('arbitraryAddress at bit 56', () {
      const name = N2kName(
        identityNumber: 0,
        manufacturerCode: 0,
        arbitraryAddress: true,
      );
      expect(name.raw, 1 << 56);
    });

    test('industryGroup at bits 57-59', () {
      const name = N2kName(
        identityNumber: 0,
        manufacturerCode: 0,
        industryGroup: 1,
        arbitraryAddress: false,
      );
      expect(name.raw, 1 << 57);
    });

    test('systemInstance at bits 60-63', () {
      const name = N2kName(
        identityNumber: 0,
        manufacturerCode: 0,
        systemInstance: 1,
        arbitraryAddress: false,
      );
      expect(name.raw, 1 << 60);
    });
  });

  group('N2kName.industryGroupName', () {
    test('all named groups', () {
      expect(const N2kName(industryGroup: 0).industryGroupName, 'Global');
      expect(const N2kName(industryGroup: 1).industryGroupName, 'Highway');
      expect(const N2kName(industryGroup: 2).industryGroupName, 'Agriculture');
      expect(const N2kName(industryGroup: 3).industryGroupName, 'Construction');
      expect(const N2kName(industryGroup: 4).industryGroupName, 'Marine');
      expect(const N2kName(industryGroup: 5).industryGroupName, 'Industrial');
    });

    test('unknown group', () {
      expect(const N2kName(industryGroup: 6).industryGroupName, 'Unknown(6)');
      expect(const N2kName(industryGroup: 7).industryGroupName, 'Unknown(7)');
    });
  });

  group('N2kName.toString', () {
    test('format includes key fields', () {
      const name = N2kName(
        manufacturerCode: 0x1AB,
        identityNumber: 12345,
        deviceFunction: 130,
        deviceClass: 120,
        industryGroup: 4,
      );
      final s = name.toString();
      expect(s, contains('mfr='));
      expect(s, contains('id=12345'));
      expect(s, contains('fn=130'));
      expect(s, contains('cls=120'));
      expect(s, contains('marine'));
    });
  });

  group('ProductInfo.decode', () {
    test('decodes 134-byte payload', () {
      final data = Uint8List(134);
      final view = ByteData.sublistView(data);
      view.setUint16(0, 2100, Endian.little);
      view.setUint16(2, 42, Endian.little);

      // modelId at bytes 4..35
      final model = 'GPS Module'.codeUnits;
      data.setRange(4, 4 + model.length, model);
      data.fillRange(4 + model.length, 36, 0xFF);

      // softwareVersion at bytes 36..67
      final sw = '3.2.1'.codeUnits;
      data.setRange(36, 36 + sw.length, sw);
      data.fillRange(36 + sw.length, 68, 0xFF);

      // modelVersion at bytes 68..99
      final mv = 'Rev C'.codeUnits;
      data.setRange(68, 68 + mv.length, mv);
      data.fillRange(68 + mv.length, 100, 0xFF);

      // modelSerialCode at bytes 100..131
      final sn = 'SN99'.codeUnits;
      data.setRange(100, 100 + sn.length, sn);
      data.fillRange(100 + sn.length, 132, 0xFF);

      data[132] = 2; // certificationLevel
      data[133] = 5; // loadEquivalency

      final info = ProductInfo.decode(data);
      expect(info.nmea2000Version, 2100);
      expect(info.productCode, 42);
      expect(info.modelId, 'GPS Module');
      expect(info.softwareVersion, '3.2.1');
      expect(info.modelVersion, 'Rev C');
      expect(info.modelSerialCode, 'SN99');
      expect(info.certificationLevel, 2);
      expect(info.loadEquivalency, 5);
    });

    test('short data returns empty defaults', () {
      final info = ProductInfo.decode(Uint8List(10));
      expect(info.nmea2000Version, 0);
      expect(info.productCode, 0);
      expect(info.modelId, '');
    });

    test('toString format', () {
      const info = ProductInfo(modelId: 'Test', softwareVersion: '1.0');
      expect(info.toString(), contains('Test'));
      expect(info.toString(), contains('1.0'));
    });
  });

  group('DeviceInfo', () {
    test('defaults', () {
      final device = DeviceInfo(address: 0x42);
      expect(device.address, 0x42);
      expect(device.name.manufacturerCode, 0x7FF);
      expect(device.productInfo, isNull);
      expect(device.transmitPgns, isEmpty);
      expect(device.receivePgns, isEmpty);
      expect(device.status, DeviceStatus.online);
    });

    test('toString includes hex address', () {
      final device = DeviceInfo(address: 0x42);
      expect(device.toString(), contains('0x42'));
    });

    test('toString includes model when available', () {
      final device = DeviceInfo(
        address: 0x10,
        productInfo: const ProductInfo(modelId: 'Wind Sensor'),
      );
      expect(device.toString(), contains('Wind Sensor'));
    });

    test('status can be changed', () {
      final device = DeviceInfo(address: 0x10);
      expect(device.status, DeviceStatus.online);
      device.status = DeviceStatus.offline;
      expect(device.status, DeviceStatus.offline);
    });
  });

  group('DeviceStatus', () {
    test('has two values', () {
      expect(DeviceStatus.values.length, 2);
      expect(DeviceStatus.values, contains(DeviceStatus.online));
      expect(DeviceStatus.values, contains(DeviceStatus.offline));
    });
  });
}
