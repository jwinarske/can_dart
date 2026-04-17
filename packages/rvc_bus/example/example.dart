// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Minimal rvc_bus example -- demonstrate RvcName decoding.
library;

import 'dart:typed_data';

import 'package:rvc_bus/src/rvc_device_info.dart';

void main() {
  // Decode a J1939 NAME from 8 bytes (as received in AddressClaimed PGN).
  const name = RvcName(
    identityNumber: 12345,
    manufacturerCode: 0x1AB,
    deviceFunction: 30, // Generator
    industryGroup: 1, // Highway (RV-C)
  );

  // Encode to raw 64-bit integer and back.
  final raw = name.raw;
  final decoded = RvcName.fromRaw(raw);
  print('Device: ${decoded.deviceTypeName}'); // Generator
  print('Manufacturer: 0x${decoded.manufacturerCode.toRadixString(16)}');

  // Decode from bytes.
  final data = Uint8List(8);
  for (var i = 0; i < 8; i++) {
    data[i] = (raw >> (i * 8)) & 0xFF;
  }
  final fromBytes = RvcName.decode(data);
  print('From bytes: ${fromBytes.deviceTypeName}');
}
