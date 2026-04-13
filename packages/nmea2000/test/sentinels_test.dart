// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:nmea2000/src/sentinels.dart';
import 'package:test/test.dart';

void main() {
  group('naSentinel', () {
    test('common bit widths', () {
      expect(naSentinel(1), 1);
      expect(naSentinel(2), 3);
      expect(naSentinel(3), 7);
      expect(naSentinel(8), 0xFF);
      expect(naSentinel(16), 0xFFFF);
      expect(naSentinel(32), 0xFFFFFFFF);
    });

    test('bitLength >= 64 returns -1', () {
      expect(naSentinel(64), -1);
      expect(naSentinel(128), -1);
    });
  });

  group('isNa', () {
    test('all bits set is NA', () {
      expect(isNa(0x01, 1), isTrue);
      expect(isNa(0x03, 2), isTrue);
      expect(isNa(0x07, 3), isTrue);
      expect(isNa(0xFF, 8), isTrue);
      expect(isNa(0xFFFF, 16), isTrue);
      expect(isNa(0xFFFFFFFF, 32), isTrue);
    });

    test('all bits set minus 1 is not NA', () {
      expect(isNa(0x00, 1), isFalse);
      expect(isNa(0x02, 2), isFalse);
      expect(isNa(0xFE, 8), isFalse);
      expect(isNa(0xFFFE, 16), isFalse);
      expect(isNa(0xFFFFFFFE, 32), isFalse);
    });

    test('zero is not NA', () {
      expect(isNa(0, 8), isFalse);
      expect(isNa(0, 16), isFalse);
    });

    test('bitLength >= 64 always returns false', () {
      expect(isNa(0xFFFFFFFF, 64), isFalse);
      expect(isNa(-1, 64), isFalse);
    });
  });

  group('isOor', () {
    test('all bits set minus 1 is OOR', () {
      expect(isOor(0x00, 1), isTrue); // 1-bit: NA=1, OOR=0
      expect(isOor(0x02, 2), isTrue); // 2-bit: NA=3, OOR=2
      expect(isOor(0xFE, 8), isTrue);
      expect(isOor(0xFFFE, 16), isTrue);
      expect(isOor(0xFFFFFFFE, 32), isTrue);
    });

    test('all bits set (NA) is not OOR', () {
      expect(isOor(0xFF, 8), isFalse);
      expect(isOor(0xFFFF, 16), isFalse);
    });

    test('normal values are not OOR', () {
      expect(isOor(0, 8), isFalse);
      expect(isOor(100, 16), isFalse);
    });

    test('bitLength >= 64 always returns false', () {
      expect(isOor(0xFFFFFFFE, 64), isFalse);
    });
  });

  group('isReserved', () {
    test('all bits set minus 2 is reserved', () {
      expect(isReserved(0xFD, 8), isTrue);
      expect(isReserved(0xFFFD, 16), isTrue);
      expect(isReserved(0xFFFFFFFD, 32), isTrue);
    });

    test('NA and OOR are not reserved', () {
      expect(isReserved(0xFF, 8), isFalse);
      expect(isReserved(0xFE, 8), isFalse);
    });

    test('normal values are not reserved', () {
      expect(isReserved(0, 8), isFalse);
      expect(isReserved(100, 16), isFalse);
    });

    test('bitLength >= 64 always returns false', () {
      expect(isReserved(0xFFFFFFFD, 64), isFalse);
    });
  });
}
