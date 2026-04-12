// Copyright 2024 can_dart Contributors
// SPDX-License-Identifier: Apache-2.0

/// NMEA 2000 data-not-available / out-of-range sentinel helpers.
///
/// Per the NMEA 2000 convention, reserved bit patterns for each field width:
///   - NA (data not available): all bits set
///   - OOR (out of range): all bits set minus 1
///   - Reserved: all bits set minus 2
///
/// For signed fields, NA is the most-positive value, OOR is most-positive - 1.
/// For floats, NaN indicates NA.
library;

/// Returns true if [rawValue] matches the NA sentinel for a field of
/// [bitLength] bits with the given [type].
bool isNa(int rawValue, int bitLength, {bool isSigned = false}) {
  if (bitLength >= 64) return false;
  final mask = (1 << bitLength) - 1;
  return (rawValue & mask) == mask;
}

/// Returns true if [rawValue] matches the OOR sentinel.
bool isOor(int rawValue, int bitLength, {bool isSigned = false}) {
  if (bitLength >= 64) return false;
  final mask = (1 << bitLength) - 1;
  return (rawValue & mask) == (mask - 1);
}

/// Returns true if [rawValue] matches the reserved sentinel.
bool isReserved(int rawValue, int bitLength) {
  if (bitLength >= 64) return false;
  final mask = (1 << bitLength) - 1;
  return (rawValue & mask) == (mask - 2);
}

/// Write the NA sentinel for a given bit length.
int naSentinel(int bitLength) {
  if (bitLength >= 64) return -1;
  return (1 << bitLength) - 1;
}
