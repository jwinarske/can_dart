// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'pgn_definition.dart';
import 'sentinels.dart';

/// Decode a raw NMEA 2000 payload into named field values.
///
/// Returns a map of field name → physical value. Fields whose raw value
/// matches the NA sentinel are omitted. Fields matching OOR are set to
/// [double.nan].
///
/// The payload bytes are little-endian per the NMEA 2000 / J1939 convention.
Map<String, dynamic>? decode(Uint8List data, PgnDefinition def) {
  if (data.length < def.dataLength && !def.repeating) return null;

  final result = <String, dynamic>{};

  for (final field in def.fields) {
    if (field.type == FieldType.reserved) continue;

    final rawValue = _extractBits(data, field.bitOffset, field.bitLength);

    final isSigned = field.type == FieldType.signed;

    if (isNa(rawValue, field.bitLength, isSigned: isSigned)) continue;

    if (isOor(rawValue, field.bitLength, isSigned: isSigned)) {
      result[field.name] = double.nan;
      continue;
    }

    switch (field.type) {
      case FieldType.string:
        result[field.name] =
            _extractString(data, field.bitOffset, field.bitLength);
      case FieldType.lookup:
        result[field.name] = rawValue;
      case FieldType.float32 || FieldType.float64:
        result[field.name] = _toDouble(rawValue, field);
      case FieldType.signed:
        final signed = _toSigned(rawValue, field.bitLength);
        result[field.name] = signed * field.resolution + field.offset;
      case FieldType.unsigned:
        result[field.name] = rawValue * field.resolution + field.offset;
      case FieldType.reserved:
        break; // already skipped above
    }
  }

  return result;
}

/// Extract [bitLength] bits starting at [bitOffset] from a little-endian
/// byte array. Returns an unsigned integer.
int _extractBits(Uint8List data, int bitOffset, int bitLength) {
  var value = 0;
  for (var i = 0; i < bitLength; i++) {
    final byteIndex = (bitOffset + i) >> 3;
    final bitIndex = (bitOffset + i) & 7;
    if (byteIndex >= data.length) break;
    if ((data[byteIndex] >> bitIndex) & 1 == 1) {
      value |= (1 << i);
    }
  }
  return value;
}

/// Convert an unsigned raw value to a signed value via two's complement.
double _toSigned(int rawValue, int bitLength) {
  final signBit = 1 << (bitLength - 1);
  if (rawValue >= signBit) {
    return (rawValue - (1 << bitLength)).toDouble();
  }
  return rawValue.toDouble();
}

/// Apply resolution and offset to produce a physical double value.
double _toDouble(int rawValue, FieldDefinition field) {
  return rawValue * field.resolution + field.offset;
}

/// Extract a fixed-length ASCII string from the payload.
String _extractString(Uint8List data, int bitOffset, int bitLength) {
  final byteOffset = bitOffset >> 3;
  final byteLength = bitLength >> 3;
  if (byteOffset + byteLength > data.length) return '';

  final bytes = data.sublist(byteOffset, byteOffset + byteLength);
  // Trim trailing 0xFF (NA) and 0x00 (null padding).
  var end = bytes.length;
  while (end > 0 && (bytes[end - 1] == 0xFF || bytes[end - 1] == 0x00)) {
    end--;
  }
  return String.fromCharCodes(bytes, 0, end);
}
