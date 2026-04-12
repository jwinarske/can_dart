// Copyright 2024 can_dart Contributors
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'pgn_definition.dart';
import 'sentinels.dart';

/// Encode named field values into an NMEA 2000 payload.
///
/// Fields not present in [values] are filled with their NA sentinel.
/// Returns a [Uint8List] of [def.dataLength] bytes, little-endian.
Uint8List encode(Map<String, dynamic> values, PgnDefinition def) {
  final data = Uint8List(def.dataLength);
  // Initialize to all 0xFF (NA for all field widths).
  data.fillRange(0, data.length, 0xFF);

  for (final field in def.fields) {
    if (field.type == FieldType.reserved) continue;

    final value = values[field.name];
    if (value == null) continue; // leave as NA

    int rawValue;
    switch (field.type) {
      case FieldType.string:
        _writeString(data, field.bitOffset, field.bitLength, value as String);
        continue;
      case FieldType.lookup:
        rawValue = (value as num).toInt();
      case FieldType.signed:
        final physical = (value as num).toDouble();
        var intVal = ((physical - field.offset) / field.resolution).round();
        // Clamp to signed range and convert to unsigned for bit packing.
        if (intVal < 0) {
          intVal = intVal + (1 << field.bitLength);
        }
        rawValue = intVal & naSentinel(field.bitLength);
      case FieldType.unsigned || FieldType.float32 || FieldType.float64:
        final physical = (value as num).toDouble();
        rawValue = ((physical - field.offset) / field.resolution).round();
      case FieldType.reserved:
        continue;
    }

    _writeBits(data, field.bitOffset, field.bitLength, rawValue);
  }

  return data;
}

/// Write [bitLength] bits starting at [bitOffset] into a little-endian
/// byte array.
void _writeBits(Uint8List data, int bitOffset, int bitLength, int value) {
  for (var i = 0; i < bitLength; i++) {
    final byteIndex = (bitOffset + i) >> 3;
    final bitIndex = (bitOffset + i) & 7;
    if (byteIndex >= data.length) break;
    if ((value >> i) & 1 == 1) {
      data[byteIndex] |= (1 << bitIndex);
    } else {
      data[byteIndex] &= ~(1 << bitIndex);
    }
  }
}

/// Write a fixed-length ASCII string into the payload, padded with 0xFF.
void _writeString(
    Uint8List data, int bitOffset, int bitLength, String value) {
  final byteOffset = bitOffset >> 3;
  final byteLength = bitLength >> 3;
  final codeUnits = value.codeUnits;
  for (var i = 0; i < byteLength; i++) {
    if (byteOffset + i >= data.length) break;
    data[byteOffset + i] = (i < codeUnits.length) ? codeUnits[i] : 0xFF;
  }
}
