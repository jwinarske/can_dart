// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Minimal NMEA 2000 example -- create a display node on vcan0,
/// listen for wind data, and print decoded fields.
///
/// Setup:
///   sudo modprobe vcan
///   sudo ip link add dev vcan0 type vcan
///   sudo ip link set up vcan0
library;

import 'dart:async';

import 'package:nmea2000/nmea2000.dart';

Future<void> main() async {
  final ecu = await Nmea2000Ecu.create(
    ifname: 'vcan0',
    address: 0x80,
    modelId: 'Example Display',
    softwareVersion: '0.1.0',
  );

  print('Claimed address: 0x${ecu.address.toRadixString(16)}');

  // Listen for Wind Data PGN (130306) and decode fields.
  final sub = ecu.framesForPgn(130306).listen((frame) {
    final registry = ecu.registry;
    final def = registry.lookup(130306);
    if (def == null) return;

    final fields = decode(frame.data, def);
    if (fields != null) {
      print('Wind speed: ${fields['windSpeed']} m/s, '
          'angle: ${fields['windAngle']} rad');
    }
  });

  // Run for 30 seconds then clean up.
  await Future<void>.delayed(const Duration(seconds: 30));
  await sub.cancel();
  ecu.dispose();
}
