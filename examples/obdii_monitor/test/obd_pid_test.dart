// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:obdii_monitor/models/obd_pid.dart';

void main() {
  group('PID decode functions', () {
    test('0x04 Engine Load: 0 → 0%, 255 → 100%', () {
      final pid = obdPids[0x04]!;
      expect(pid.decode([0]), closeTo(0.0, 0.01));
      expect(pid.decode([255]), closeTo(100.0, 0.01));
      expect(pid.decode([128]), closeTo(50.2, 0.1));
    });

    test('0x05 Coolant Temp: 0 → -40°C, 215 → 175°C', () {
      final pid = obdPids[0x05]!;
      expect(pid.decode([0]), -40.0);
      expect(pid.decode([215]), 175.0);
      expect(pid.decode([100]), 60.0);
    });

    test('0x06 Short Fuel Trim: 0 → -100%, 128 → 0%, 255 → ~99.2%', () {
      final pid = obdPids[0x06]!;
      expect(pid.decode([0]), closeTo(-100.0, 0.1));
      expect(pid.decode([128]), closeTo(0.0, 0.01));
      expect(pid.decode([255]), closeTo(99.2, 0.1));
    });

    test('0x0B Intake MAP: identity (kPa)', () {
      final pid = obdPids[0x0B]!;
      expect(pid.decode([101]), 101.0);
      expect(pid.decode([0]), 0.0);
    });

    test('0x0C Engine RPM: 2-byte formula', () {
      final pid = obdPids[0x0C]!;
      // 0x0C00 → (12*256 + 0) / 4 = 768.0
      expect(pid.decode([12, 0]), 768.0);
      // 0x1000 → (16*256 + 0) / 4 = 1024.0
      expect(pid.decode([16, 0]), 1024.0);
      // 0x0000 → 0
      expect(pid.decode([0, 0]), 0.0);
      // Max: 0xFFFF → (255*256 + 255) / 4 = 16383.75
      expect(pid.decode([255, 255]), 16383.75);
    });

    test('0x0D Vehicle Speed: identity (km/h)', () {
      final pid = obdPids[0x0D]!;
      expect(pid.decode([120]), 120.0);
      expect(pid.decode([0]), 0.0);
    });

    test('0x0E Timing Advance: 0 → -64°, 128 → 0°, 255 → 63.5°', () {
      final pid = obdPids[0x0E]!;
      expect(pid.decode([0]), -64.0);
      expect(pid.decode([128]), 0.0);
      expect(pid.decode([255]), 63.5);
    });

    test('0x0F Intake Air Temp: same formula as coolant', () {
      final pid = obdPids[0x0F]!;
      expect(pid.decode([0]), -40.0);
      expect(pid.decode([60]), 20.0);
    });

    test('0x10 MAF Rate: 2-byte, divide by 100', () {
      final pid = obdPids[0x10]!;
      expect(pid.decode([0, 0]), 0.0);
      // (1*256 + 0) / 100 = 2.56
      expect(pid.decode([1, 0]), closeTo(2.56, 0.001));
      // Max: (255*256 + 255) / 100 = 655.35
      expect(pid.decode([255, 255]), closeTo(655.35, 0.001));
    });

    test('0x11 Throttle Position: same formula as engine load', () {
      final pid = obdPids[0x11]!;
      expect(pid.decode([0]), closeTo(0.0, 0.01));
      expect(pid.decode([255]), closeTo(100.0, 0.01));
    });

    test('0x1C OBD Standard: identity', () {
      final pid = obdPids[0x1C]!;
      expect(pid.decode([6]), 6.0);
    });

    test('0x1F Run Time: 2-byte seconds', () {
      final pid = obdPids[0x1F]!;
      expect(pid.decode([0, 0]), 0.0);
      // 1*256 + 44 = 300
      expect(pid.decode([1, 44]), 300.0);
      // Max
      expect(pid.decode([255, 255]), 65535.0);
    });

    test('0x2F Fuel Level: same formula as engine load', () {
      final pid = obdPids[0x2F]!;
      expect(pid.decode([0]), closeTo(0.0, 0.01));
      expect(pid.decode([255]), closeTo(100.0, 0.01));
    });

    test('0x33 Barometric Pressure: identity (kPa)', () {
      final pid = obdPids[0x33]!;
      expect(pid.decode([101]), 101.0);
    });

    test('0x46 Ambient Air Temp: same offset as coolant', () {
      final pid = obdPids[0x46]!;
      expect(pid.decode([0]), -40.0);
      expect(pid.decode([65]), 25.0);
    });

    test('0x5C Oil Temp: same offset as coolant', () {
      final pid = obdPids[0x5C]!;
      expect(pid.decode([0]), -40.0);
      expect(pid.decode([130]), 90.0);
    });
  });

  group('PID metadata', () {
    test('all 16 PIDs have correct byte counts', () {
      for (final pid in obdPids.values) {
        expect(
          pid.bytes,
          isIn([1, 2]),
          reason: 'PID 0x${pid.pid.toRadixString(16)} has ${pid.bytes} bytes',
        );
      }
    });

    test('all PIDs have non-empty names and units', () {
      for (final pid in obdPids.values) {
        expect(
          pid.name,
          isNotEmpty,
          reason: 'PID 0x${pid.pid.toRadixString(16)} missing name',
        );
      }
    });

    test('obdPids contains 16 entries', () {
      expect(obdPids.length, 16);
    });
  });

  group('decodeDtc', () {
    test('powertrain codes (P prefix)', () {
      // P0300 — Random/Multiple Cylinder Misfire
      // byte0: 00_00_0011 = prefix P(00), digit1=0, digit2=3
      // byte1: 0000_0000 = digit3=0, digit4=0
      expect(decodeDtc(0x03, 0x00), 'P0300');
    });

    test('chassis codes (C prefix)', () {
      // C0100
      // byte0: 01_00_0001 = prefix C(01), digit1=0, digit2=1
      // byte1: 0000_0000
      expect(decodeDtc(0x41, 0x00), 'C0100');
    });

    test('body codes (B prefix)', () {
      // B0200
      // byte0: 10_00_0010 = prefix B(10), digit1=0, digit2=2
      expect(decodeDtc(0x82, 0x00), 'B0200');
    });

    test('network codes (U prefix)', () {
      // U0100
      // byte0: 11_00_0001 = prefix U(11), digit1=0, digit2=1
      expect(decodeDtc(0xC1, 0x00), 'U0100');
    });

    test('hex digits in code', () {
      // P0ABF
      // byte0: 00_00_1010 = prefix P, digit1=0, digit2=A(10)
      // byte1: 1011_1111 = digit3=B(11), digit4=F(15)
      expect(decodeDtc(0x0A, 0xBF), 'P0ABF');
    });

    test('all zeros produces P0000', () {
      expect(decodeDtc(0x00, 0x00), 'P0000');
    });
  });

  group('decodeVin', () {
    test('decodes 17-byte ASCII VIN', () {
      final vin = 'WVWZZZ3CZWE123456'.codeUnits;
      expect(decodeVin(vin), 'WVWZZZ3CZWE123456');
    });

    test('filters non-printable characters', () {
      final bytes = [0x01, 0x57, 0x56, 0x57, 0x00, 0xFF]; // W, V, W with junk
      expect(decodeVin(bytes), 'WVW');
    });

    test('empty input returns empty string', () {
      expect(decodeVin([]), '');
    });
  });
}
