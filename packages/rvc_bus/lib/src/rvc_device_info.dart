// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

/// Device online/offline status.
enum RvcDeviceStatus { online, offline }

/// Decoded J1939/RV-C 64-bit NAME field with RV-C device function lookup.
///
/// The NAME is broadcast in the AddressClaimed PGN (0xEE00) as 8 bytes
/// little-endian. Lower numeric value = higher priority in claim arbitration.
class RvcName {
  const RvcName({
    this.identityNumber = 0,
    this.manufacturerCode = 0x7FF,
    this.functionInstance = 0,
    this.ecuInstance = 0,
    this.deviceFunction = 0,
    this.deviceClass = 0,
    this.arbitraryAddress = true,
    this.industryGroup = 0,
    this.systemInstance = 0,
  });

  final int identityNumber; // 21 bits
  final int manufacturerCode; // 11 bits
  final int functionInstance; // 5 bits
  final int ecuInstance; // 3 bits
  final int deviceFunction; // 8 bits
  final int deviceClass; // 7 bits
  final bool arbitraryAddress; // 1 bit
  final int industryGroup; // 3 bits
  final int systemInstance; // 4 bits

  /// Decode from 8 bytes little-endian (as received in AddressClaimed PGN).
  factory RvcName.decode(Uint8List data) {
    if (data.length < 8) return const RvcName();
    int raw = 0;
    for (var i = 0; i < 8; i++) {
      raw |= data[i] << (i * 8);
    }
    return RvcName.fromRaw(raw);
  }

  /// Decode from a 64-bit raw integer.
  factory RvcName.fromRaw(int raw) {
    return RvcName(
      identityNumber: raw & 0x1FFFFF,
      manufacturerCode: (raw >> 21) & 0x7FF,
      functionInstance: (raw >> 32) & 0x1F,
      ecuInstance: (raw >> 37) & 0x07,
      deviceFunction: (raw >> 40) & 0xFF,
      deviceClass: (raw >> 49) & 0x7F,
      arbitraryAddress: ((raw >> 56) & 0x1) == 1,
      industryGroup: (raw >> 57) & 0x07,
      systemInstance: (raw >> 60) & 0x0F,
    );
  }

  /// Encode to 64-bit raw integer.
  int get raw =>
      (identityNumber & 0x1FFFFF) |
      ((manufacturerCode & 0x7FF) << 21) |
      ((functionInstance & 0x1F) << 32) |
      ((ecuInstance & 0x07) << 37) |
      (deviceFunction << 40) |
      ((deviceClass & 0x7F) << 49) |
      ((arbitraryAddress ? 1 : 0) << 56) |
      ((industryGroup & 0x07) << 57) |
      ((systemInstance & 0x0F) << 60);

  /// Human-readable device type from the RV-C device function table.
  String get deviceTypeName =>
      _rvcDeviceFunctions[deviceFunction] ?? 'Unknown ($deviceFunction)';

  @override
  String toString() => 'RvcName(mfr=$manufacturerCode id=$identityNumber '
      'fn=$deviceFunction "$deviceTypeName" cls=$deviceClass)';
}

/// Information about a single device on the RV-C bus.
class RvcDeviceInfo {
  RvcDeviceInfo({
    required this.address,
    RvcName? name,
    DateTime? lastHeard,
    this.status = RvcDeviceStatus.online,
  })  : name = name ?? const RvcName(),
        lastHeard = lastHeard ?? DateTime.now();

  final int address;
  RvcName name;
  DateTime lastHeard;
  RvcDeviceStatus status;

  @override
  String toString() {
    final sa = address.toRadixString(16).padLeft(2, '0').toUpperCase();
    return 'RvcDevice(0x$sa "${name.deviceTypeName}" $status $name)';
  }
}

// -- RV-C device function lookup table ----------------------------------------

/// Common RV-C device function codes mapped to human-readable names.
///
/// See RV-C specification Appendix B — Device Function Codes.
const _rvcDeviceFunctions = <int, String>{
  0: 'Generic',
  1: 'Main Controller',
  10: 'Display',
  17: 'Furnace',
  19: 'Air Conditioner',
  20: 'Thermostat',
  25: 'Water Heater',
  30: 'Generator',
  32: 'Battery Charger',
  33: 'Inverter',
  34: 'Battery Monitor',
  35: 'AC Source',
  36: 'DC Source',
  37: 'Water Pump',
  38: 'Tank Sensor',
  40: 'DC Dimmer',
  42: 'Transfer Switch',
  44: 'Slide-out',
  45: 'Leveling Jack',
  46: 'Awning',
  50: 'GPS Receiver',
  60: 'Solar Controller',
};
