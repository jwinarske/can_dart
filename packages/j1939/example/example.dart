// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Minimal J1939 example — create an ECU on vcan0, claim an address,
/// send a frame, and listen for incoming traffic.
///
/// Setup:
///   sudo modprobe vcan
///   sudo ip link add dev vcan0 type vcan
///   sudo ip link set up vcan0
///
/// Run:
///   dart run example/example.dart
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:j1939/j1939.dart';

Future<void> main() async {
  // Create an ECU on the virtual CAN interface.
  final ecu = J1939Ecu.create(
    ifname: 'vcan0',
    address: 0x80,
    identityNumber: 0x1234,
  );

  // Wait for the J1939/81 address claim to settle.
  final claim = await ecu.events
      .where((e) => e is AddressClaimed)
      .cast<AddressClaimed>()
      .first
      .timeout(const Duration(milliseconds: 400));
  print('Claimed address: 0x${claim.address.toRadixString(16)}');

  // Handle every event type with an exhaustive switch.
  final sub = ecu.events.listen((event) => switch (event) {
        FrameReceived(:final pgn, :final source, :final data) =>
          print('RX: PGN=0x${pgn.toRadixString(16)} '
              'from=0x${source.toRadixString(16)} '
              'len=${data.length}'),
        AddressClaimed(:final address) =>
          print('Address claimed: 0x${address.toRadixString(16)}'),
        AddressClaimFailed() => print('Address claim failed'),
        EcuError(:final errorCode) => print('Error: errno=$errorCode'),
        Dm1Received(:final spn, :final fmi) =>
          print('DM1 fault: SPN=$spn FMI=$fmi'),
      });

  // Send a single-frame proprietary-A message (broadcast).
  await ecu.send(
    Pgn.proprietaryA,
    priority: 6,
    dest: kBroadcast,
    data: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
  );

  // Send a multi-packet BAM (> 8 bytes, non-blocking).
  await ecu.send(
    Pgn.softwareId,
    priority: 6,
    dest: kBroadcast,
    data: Uint8List.fromList(List.generate(25, (i) => i)),
  );

  // Inject a DM1 fault so other ECUs can request it.
  ecu.addDm1Fault(spn: 100, fmi: 1, occurrence: 1);

  // Let the ECU run for a few seconds to receive traffic.
  await Future<void>.delayed(const Duration(seconds: 3));

  await sub.cancel();
  ecu.dispose();
}
