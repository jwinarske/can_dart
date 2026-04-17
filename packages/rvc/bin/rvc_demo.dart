// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// bin/rvc_demo.dart — RV-C node demo on vcan0.
//
// Creates one RvcEcu with RV-C NAME defaults, waits for address claim,
// then prints all received events decoded to named fields until Ctrl-C.
//
// Setup:
//   sudo modprobe vcan
//   sudo ip link add dev vcan0 type vcan
//   sudo ip link set up vcan0
//
// Run:
//   cd packages/rvc && dart run rvc:rvc_demo

import 'dart:async';
import 'dart:io';

import 'package:rvc/rvc.dart';

Future<void> main() async {
  final shutdown = Completer<void>();
  unawaited(ProcessSignal.sigint.watch().first.then((_) {
    if (!shutdown.isCompleted) shutdown.complete();
  }));
  unawaited(ProcessSignal.sigterm.watch().first.then((_) {
    if (!shutdown.isCompleted) shutdown.complete();
  }));

  final registry = RvcRegistry.standard();

  late final RvcEcu ecu;
  try {
    ecu = await RvcEcu.create(
      ifname: 'vcan0',
      address: 0x80,
      identityNumber: 42,
      registry: registry,
    );
  } on StateError catch (e) {
    stderr.writeln('create failed: $e');
    exit(1);
  } on TimeoutException catch (e) {
    stderr.writeln('address claim failed: $e');
    exit(2);
  }

  final sa = ecu.address.toRadixString(16).padLeft(2, '0').toUpperCase();
  print('RV-C node active on vcan0');
  print('  Address: 0x$sa');
  print('');
  print('Listening for events... (Ctrl-C to stop)');
  print('');

  final sub = ecu.events.listen((e) {
    switch (e) {
      case FrameReceived(:final pgn, :final source, :final data):
        final p = pgn.toRadixString(16).padLeft(5, '0').toUpperCase();
        final s = source.toRadixString(16).padLeft(2, '0').toUpperCase();
        final def = registry.lookup(pgn);
        if (def != null) {
          final fields = decode(data, def);
          print('  RX DGN=0x$p (${def.name}) SA=0x$s $fields');
        } else {
          print('  RX DGN=0x$p SA=0x$s len=${data.length}');
        }
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
