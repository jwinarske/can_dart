// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// bin/j1939.dart — J1939 two-ECU demo on vcan0.
//
// Setup:
//   sudo modprobe vcan
//   sudo ip link add dev vcan0 type vcan
//   sudo ip link set up vcan0
//
// Run:
//   dart run j1939

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:j1939/j1939.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<AddressClaimed> waitForClaim(
  J1939Ecu ecu, {
  Duration timeout = const Duration(milliseconds: 400),
}) =>
    ecu.events
        .where((e) => e is AddressClaimed)
        .cast<AddressClaimed>()
        .first
        .timeout(timeout,
            onTimeout: () => throw TimeoutException('address claim timed out'));

void logFrame(String tag, FrameReceived f) {
  final hex = f.data
      .map((int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
  final pgn = f.pgn.toRadixString(16).toUpperCase().padLeft(5, '0');
  final sa = f.source.toRadixString(16).padLeft(2, '0').toUpperCase();
  final da = f.destination.toRadixString(16).padLeft(2, '0').toUpperCase();
  print('$tag: PGN=0x$pgn  SA=0x$sa  DA=0x$da  data=[$hex]');
}

// ── main ──────────────────────────────────────────────────────────────────────

Future<void> main() async {
  final shutdown = Completer<void>();

  // unawaited: these futures intentionally run for the lifetime of the process.
  unawaited(ProcessSignal.sigint.watch().first.then((_) {
    print('\n[main] shutting down');
    shutdown.complete();
  }));
  unawaited(ProcessSignal.sigterm.watch().first.then(
    (_) {
      if (!shutdown.isCompleted) shutdown.complete();
    },
  ));

  // ── 1. Create two ECU instances ────────────────────────────────────────

  late final J1939Ecu ecuA;
  late final J1939Ecu ecuB;
  try {
    ecuA = J1939Ecu.create(
        ifname: 'vcan0',
        address: 0xA0,
        identityNumber: 0x0001,
        manufacturerCode: 0x7FF);
    ecuB = J1939Ecu.create(
        ifname: 'vcan0',
        address: 0xB0,
        identityNumber: 0x0002,
        manufacturerCode: 0x7FF);
  } on StateError catch (e) {
    stderr.writeln('[main] create failed: $e');
    exit(1);
  }

  // ── 2. Register frame handlers ─────────────────────────────────────────

  ecuA.frames.listen((f) => logFrame('[ECU A RX]', f));
  ecuB.frames.listen((f) => logFrame('[ECU B RX]', f));

  for (final ecu in [ecuA, ecuB]) {
    ecu.events
        .where((e) => e is EcuError || e is AddressClaimFailed)
        .listen((e) => stderr.writeln('[main] event: $e'));
  }

  // ── 3. Wait for address claims ─────────────────────────────────────────

  print('[main] waiting for address claims (400 ms)...');
  final AddressClaimed claimA;
  final AddressClaimed claimB;
  try {
    // Record destructuring + (Future, Future).wait requires Dart 3.0+.
    (claimA, claimB) = await (waitForClaim(ecuA), waitForClaim(ecuB)).wait;
  } on TimeoutException catch (e) {
    stderr.writeln('[main] $e');
    ecuA.dispose();
    ecuB.dispose();
    exit(1);
  }

  final addrA = claimA.address.toRadixString(16).padLeft(2, '0').toUpperCase();
  final addrB = claimB.address.toRadixString(16).padLeft(2, '0').toUpperCase();
  print('[main] ECU A claimed 0x$addrA, ECU B claimed 0x$addrB');

  // ── 4. Single-frame proprietary-A: ECU A → ECU B (7 bytes) ────────────

  print('[main] ECU A → ECU B: proprietary-A');
  try {
    await ecuA.send(Pgn.proprietaryA,
        priority: 6,
        dest: claimB.address,
        data: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03]));
  } on StateError catch (e) {
    stderr.writeln('[main] send failed: $e');
  }
  await Future<void>.delayed(const Duration(milliseconds: 50));

  // ── 5. Multi-packet BAM: ECU B → broadcast (25 bytes) ─────────────────
  //
  // Returns immediately; resolves when the last DT packet is sent
  // (~4 × 50 ms on the C++ ASIO thread). Dart event loop is free throughout.

  final swId = Uint8List.fromList(List<int>.generate(25, (i) => 0x20 + i));
  print('[main] ECU B → broadcast: BAM ${swId.length} bytes (SoftwareId)');
  try {
    await ecuB.send(Pgn.softwareId, priority: 6, dest: kBroadcast, data: swId);
  } on StateError catch (e) {
    stderr.writeln('[main] BAM failed: $e');
  }

  // ── 6. DM1 fault on ECU A; ECU B requests it ──────────────────────────

  print('[main] ECU A: add DM1 fault — SPN 100 (engine oil pressure), FMI 1');
  ecuA.addDm1Fault(spn: 100, fmi: 1, occurrence: 1);

  print('[main] ECU B → ECU A: request DM1');
  try {
    ecuB.sendRequest(claimA.address, Pgn.dm1);
  } on StateError catch (e) {
    stderr.writeln('[main] DM1 request failed: $e');
  }
  await Future<void>.delayed(const Duration(milliseconds: 150));

  // ── 7. Request all address claims ─────────────────────────────────────

  print('[main] ECU A: requesting all address claims');
  try {
    ecuA.sendRequest(kBroadcast, Pgn.addressClaimed);
  } on StateError catch (e) {
    stderr.writeln('[main] address request failed: $e');
  }
  await Future<void>.delayed(const Duration(milliseconds: 50));

  // ── 8. Run until Ctrl-C ───────────────────────────────────────────────

  print('\n[main] both ECUs active on vcan0 — Ctrl-C to stop');
  print(
      '       try: cansend vcan0 18EAFFA0#CAFECA00  (DM1 request to ECU A)\n');
  await shutdown.future;

  ecuA.dispose();
  ecuB.dispose();
}
