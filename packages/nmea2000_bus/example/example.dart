// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Minimal bus discovery example -- list NMEA 2000 devices on vcan0.
///
/// Setup:
///   sudo modprobe vcan
///   sudo ip link add dev vcan0 type vcan
///   sudo ip link set up vcan0
library;

import 'dart:async';

import 'package:nmea2000/nmea2000.dart';
import 'package:nmea2000_bus/nmea2000_bus.dart';

Future<void> main() async {
  final ecu = await Nmea2000Ecu.create(
    ifname: 'vcan0',
    address: 0x20,
    modelId: 'Bus Monitor',
    softwareVersion: '0.1.0',
  );

  final registry = BusRegistry(ecu);

  // Print every bus topology change.
  final sub = registry.events.listen((event) => switch (event) {
        DeviceAppeared(:final device) =>
          print('New device at 0x${device.address.toRadixString(16)}'),
        DeviceInfoUpdated(:final device) =>
          print('Updated: ${device.productInfo?.modelId}'),
        DeviceWentOffline(:final address) =>
          print('Offline: 0x${address.toRadixString(16)}'),
        DeviceCameOnline(:final device) =>
          print('Online: 0x${device.address.toRadixString(16)}'),
        DeviceDisappeared(:final address) =>
          print('Removed: 0x${address.toRadixString(16)}'),
        ClaimConflict(:final address, :final winner, :final loser) =>
          print('Conflict at 0x${address.toRadixString(16)}: '
              '$winner vs $loser'),
      });

  // Run for 30 seconds, then print a summary.
  await Future<void>.delayed(const Duration(seconds: 30));

  print('\n--- Online devices ---');
  for (final d in registry.onlineDevices) {
    print('  0x${d.address.toRadixString(16)}: '
        '${d.productInfo?.modelId ?? "unknown"} '
        '(${d.name.industryGroupName})');
  }

  await sub.cancel();
  registry.dispose();
  ecu.dispose();
}
