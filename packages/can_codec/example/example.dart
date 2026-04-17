// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Minimal can_codec example -- decode and encode a CAN message.
library;

import 'dart:typed_data';

import 'package:can_codec/can_codec.dart';

const windDef = MessageDefinition(
  pgn: 130306,
  name: 'Wind Data',
  transport: 0,
  dataLength: 6,
  fields: [
    FieldDefinition(name: 'sid', bitOffset: 0, bitLength: 8),
    FieldDefinition(
        name: 'windSpeed', bitOffset: 8, bitLength: 16, resolution: 0.01),
    FieldDefinition(
        name: 'windAngle', bitOffset: 24, bitLength: 16, resolution: 0.0001),
    FieldDefinition(
        name: 'reference', bitOffset: 40, bitLength: 3, type: FieldType.lookup),
  ],
);

void main() {
  // Encode field values to a CAN payload.
  final payload = encode({
    'sid': 42,
    'windSpeed': 5.50,
    'windAngle': 0.7850,
    'reference': 2,
  }, windDef);

  print('Encoded ${payload.length} bytes');

  // Decode the payload back to field values.
  final fields = decode(payload, windDef)!;
  print('Speed: ${fields['windSpeed']} m/s');
  print('Angle: ${fields['windAngle']} rad');
  print('Ref: ${fields['reference']}');

  // Sentinel detection.
  final naPayload = Uint8List(6)..fillRange(0, 6, 0xFF);
  final naFields = decode(naPayload, windDef)!;
  print('All-NA payload decodes to: $naFields'); // empty map
}
