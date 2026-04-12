// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// bin/demo.dart — NMEA 2000 display node demo on vcan0.
//
// Creates one Nmea2000Ecu with marine NAME defaults, waits for address
// claim, starts heartbeat and mandatory PGN auto-responder, then prints
// all received events until Ctrl-C.
//
// Setup:
//   sudo modprobe vcan
//   sudo ip link add dev vcan0 type vcan
//   sudo ip link set up vcan0
//
// Run:
//   cd packages/nmea2000 && dart run nmea2000:demo
//
// Test Product Info request (from another terminal):
//   cansend vcan0 18EAFF80#14F001
//   (PGN 0xEA00 = Request, dest=0xFF broadcast, data = LE PGN 126996 = 0x01F014)

import 'dart:async';
import 'dart:io';

import 'package:nmea2000/nmea2000.dart';

Future<void> main() async {
  final shutdown = Completer<void>();
  unawaited(ProcessSignal.sigint.watch().first.then((_) {
    if (!shutdown.isCompleted) shutdown.complete();
  }));
  unawaited(ProcessSignal.sigterm.watch().first.then((_) {
    if (!shutdown.isCompleted) shutdown.complete();
  }));

  late final Nmea2000Ecu ecu;
  try {
    ecu = await Nmea2000Ecu.create(
      ifname: 'vcan0',
      address: 0x80,
      identityNumber: 42,
      modelId: 'Dart N2K Demo',
      softwareVersion: '0.1.0',
      modelVersion: '1.0',
      modelSerialCode: 'DEMO-001',
    );
  } on StateError catch (e) {
    stderr.writeln('create failed: $e');
    exit(1);
  } on TimeoutException catch (e) {
    stderr.writeln('address claim failed: $e');
    exit(2);
  }

  final sa = ecu.address.toRadixString(16).padLeft(2, '0').toUpperCase();
  print('NMEA 2000 display node active on vcan0');
  print('  Address: 0x$sa');
  print('  Heartbeat: every 60s (PGN 126993)');
  print('  Auto-responds to: Product Info (126996), Config Info (126998),');
  print('                     PGN List (126464), ISO Request (59904)');
  print('');
  print('Test commands (from another terminal):');
  print('  # Request Product Information:');
  print('  cansend vcan0 18EAFF80#14F001');
  print('  # Request PGN List:');
  print('  cansend vcan0 18EAFF80#00F801');
  print('');
  print('Listening for events... (Ctrl-C to stop)');
  print('');

  final sub = ecu.events.listen((e) {
    switch (e) {
      case FrameReceived(:final pgn, :final source, :final data):
        final p = pgn.toRadixString(16).padLeft(5, '0').toUpperCase();
        final s = source.toRadixString(16).padLeft(2, '0').toUpperCase();
        print('  RX PGN=0x$p SA=0x$s len=${data.length}');
      case AddressClaimed(:final address):
        print('  AddressClaimed(0x'
            '${address.toRadixString(16).padLeft(2, '0').toUpperCase()})');
      case AddressClaimFailed():
        print('  AddressClaimFailed');
      case EcuError(:final errorCode):
        print('  EcuError(errno=$errorCode)');
      case Dm1Received(:final source, :final spn, :final fmi):
        print('  DM1 from 0x${source.toRadixString(16)} spn=$spn fmi=$fmi');
    }
  });

  await shutdown.future;
  print('\nshutting down');
  await sub.cancel();
  ecu.dispose();
}
