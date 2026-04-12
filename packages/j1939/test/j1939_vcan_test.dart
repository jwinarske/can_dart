// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Integration test: exercises the full J1939Ecu lifecycle against vcan0.
//
// Skipped automatically when vcan0 is not up. In CI, `.github/workflows/ci.yml`
// brings vcan0 up before the test job. Locally:
//
//   sudo modprobe vcan
//   sudo ip link add dev vcan0 type vcan
//   sudo ip link set up vcan0
//   dart test test/j1939_vcan_test.dart
//
// This test imports the full package barrel (`package:j1939/j1939.dart`),
// which eagerly loads libj1939_plugin.so via src/j1939_native.dart's
// multi-stage resolver. The library is expected to be built by
// hook/build.dart before `dart test` runs.

@TestOn('linux')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:j1939/j1939.dart';
import 'package:test/test.dart';

const _vcan = 'vcan0';

bool _vcanAvailable() {
  try {
    final r = Process.runSync('ip', ['link', 'show', _vcan]);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  final hasVcan = _vcanAvailable();
  final skipReason = hasVcan ? null : 'vcan0 not available';

  group('J1939Ecu (vcan0)', skip: skipReason, () {
    test('create claims an address and exposes it', () async {
      final ecu = J1939Ecu.create(
        ifname: _vcan,
        address: 0xA0,
        identityNumber: 0x1234,
      );
      addTearDown(ecu.dispose);

      // Wait up to 400 ms for the claim event. Normally fires within
      // ~5 ms once the contention timer expires.
      final claim = await ecu.events
          .where((e) => e is AddressClaimed)
          .cast<AddressClaimed>()
          .first
          .timeout(const Duration(milliseconds: 400));

      expect(claim.address, 0xA0);
      expect(ecu.addressClaimed, isTrue);
      expect(ecu.address, 0xA0);
    });

    test('two ECUs on the same interface claim distinct addresses', () async {
      final a = J1939Ecu.create(
        ifname: _vcan,
        address: 0xB0,
        identityNumber: 0x1111,
      );
      final b = J1939Ecu.create(
        ifname: _vcan,
        address: 0xB1,
        identityNumber: 0x2222,
      );
      addTearDown(() {
        a.dispose();
        b.dispose();
      });

      Future<AddressClaimed> claimFor(J1939Ecu e) => e.events
          .where((ev) => ev is AddressClaimed)
          .cast<AddressClaimed>()
          .first
          .timeout(const Duration(milliseconds: 400));

      final (ca, cb) = await (claimFor(a), claimFor(b)).wait;
      expect(ca.address, 0xB0);
      expect(cb.address, 0xB1);
    });

    test('single-frame send round-trips between two ECUs', () async {
      final tx = J1939Ecu.create(
        ifname: _vcan,
        address: 0xC0,
        identityNumber: 0x3333,
      );
      final rx = J1939Ecu.create(
        ifname: _vcan,
        address: 0xC1,
        identityNumber: 0x4444,
      );
      addTearDown(() {
        tx.dispose();
        rx.dispose();
      });

      // Collect the first frame received by rx with a short deadline.
      final receivedFuture = rx.frames
          .where((f) => f.pgn == Pgn.proprietaryA)
          .first
          .timeout(const Duration(milliseconds: 400));

      // Wait for both to claim.
      await Future.wait([
        tx.events.where((e) => e is AddressClaimed).first,
        rx.events.where((e) => e is AddressClaimed).first,
      ]).timeout(const Duration(milliseconds: 400));

      final payload = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      await tx.send(
        Pgn.proprietaryA,
        priority: 6,
        dest: 0xC1,
        data: payload,
      );

      final frame = await receivedFuture;
      expect(frame.source, 0xC0);
      expect(frame.destination, 0xC1);
      // The data is a zero-copy view into a C++ pool buffer; copy first
      // so the subsequent expect() operates on a stable Dart list.
      expect(Uint8List.fromList(frame.data), payload);
    });

    test('DM1 fault add + request round-trips', () async {
      final a = J1939Ecu.create(
        ifname: _vcan,
        address: 0xD0,
        identityNumber: 0x5555,
      );
      final b = J1939Ecu.create(
        ifname: _vcan,
        address: 0xD1,
        identityNumber: 0x6666,
      );
      addTearDown(() {
        a.dispose();
        b.dispose();
      });

      // Wait for claims.
      await Future.wait([
        a.events.where((e) => e is AddressClaimed).first,
        b.events.where((e) => e is AddressClaimed).first,
      ]).timeout(const Duration(milliseconds: 400));

      // B will listen for DM1 events posted by A.
      final dm1Future = b.events
          .where((e) => e is Dm1Received)
          .cast<Dm1Received>()
          .first
          .timeout(const Duration(seconds: 2));

      a.addDm1Fault(spn: 100, fmi: 1, occurrence: 1);
      // The fault is registered synchronously in the C++ vector, but allow
      // the RX threads time to settle on slow CI runners before requesting.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      b.sendRequest(0xD0, Pgn.dm1);

      final dm1 = await dm1Future;
      expect(dm1.source, 0xD0);
      expect(dm1.spn, 100);
      expect(dm1.fmi, 1);
      expect(dm1.occurrence, 1);

      a.clearDm1Faults();
    });

    test('dispose is idempotent', () {
      final ecu = J1939Ecu.create(
        ifname: _vcan,
        address: 0xE0,
        identityNumber: 0x7777,
      );
      expect(ecu.dispose, returnsNormally);
      // Second call must not throw.
      expect(ecu.dispose, returnsNormally);
    });

    test('create throws on invalid interface', () {
      expect(
        () => J1939Ecu.create(
          ifname: 'nosuch_iface_42',
          address: 0xF0,
          identityNumber: 0x8888,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
