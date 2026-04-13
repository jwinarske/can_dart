// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Integration test: exercises Nmea2000Ecu against vcan0.
//
// Skipped automatically when vcan0 is not up. Locally:
//
//   sudo modprobe vcan
//   sudo ip link add dev vcan0 type vcan
//   sudo ip link set up vcan0
//   dart test test/nmea2000_ecu_vcan_test.dart

@TestOn('linux')
library;

import 'dart:io';

import 'package:nmea2000/nmea2000.dart';
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

  group('Nmea2000Ecu (vcan0)', skip: skipReason, () {
    test('create claims an address', () async {
      final ecu = await Nmea2000Ecu.create(
        ifname: _vcan,
        address: 0x80,
        identityNumber: 0xA001,
        modelId: 'Test Display',
        softwareVersion: '0.1.0',
      );
      addTearDown(ecu.dispose);

      expect(ecu.addressClaimed, isTrue);
      expect(ecu.address, 0x80);
      expect(ecu.modelId, 'Test Display');
    });

    test('auto-responds to Product Information request', () async {
      final display = await Nmea2000Ecu.create(
        ifname: _vcan,
        address: 0x80,
        identityNumber: 0xA002,
        modelId: 'My Display',
        softwareVersion: '2.0.0',
      );
      addTearDown(display.dispose);

      // Create a raw J1939 ECU to send requests and receive responses.
      final requester = J1939Ecu.create(
        ifname: _vcan,
        address: 0x90,
        identityNumber: 0xB001,
      );
      addTearDown(requester.dispose);

      await requester.events
          .where((e) => e is AddressClaimed)
          .first
          .timeout(const Duration(milliseconds: 400));

      // Listen for Product Information (PGN 126996) response.
      final prodInfoFuture = requester.frames
          .where((f) => f.pgn == 126996)
          .first
          .timeout(const Duration(seconds: 3));

      // Send ISO Request for Product Information.
      requester.sendRequest(0x80, 126996);

      final frame = await prodInfoFuture;
      expect(frame.data.length, greaterThanOrEqualTo(6));

      // Decode the response using our codec.
      final decoded = decode(frame.data, productInformationPgn);
      expect(decoded, isNotNull);
      expect(decoded!['modelId'], 'My Display');
      expect(decoded['softwareVersionCode'], '2.0.0');
    });

    test('auto-responds to PGN List request', () async {
      final display = await Nmea2000Ecu.create(
        ifname: _vcan,
        address: 0x81,
        identityNumber: 0xA003,
      );
      addTearDown(display.dispose);

      final requester = J1939Ecu.create(
        ifname: _vcan,
        address: 0x91,
        identityNumber: 0xB002,
      );
      addTearDown(requester.dispose);

      await requester.events
          .where((e) => e is AddressClaimed)
          .first
          .timeout(const Duration(milliseconds: 400));

      final pgnListFuture = requester.frames
          .where((f) => f.pgn == 126464)
          .first
          .timeout(const Duration(seconds: 3));

      requester.sendRequest(0x81, 126464);

      final frame = await pgnListFuture;
      // First byte is 0 (transmit list), then 3-byte LE PGN entries.
      expect(frame.data[0], 0);
      expect(frame.data.length, greaterThan(3));

      // Parse the PGN list.
      final numPgns = (frame.data.length - 1) ~/ 3;
      expect(numPgns, greaterThanOrEqualTo(5)); // at least the mandatory PGNs

      final pgns = <int>[];
      for (var i = 0; i < numPgns; i++) {
        final pgn = frame.data[1 + i * 3] |
            (frame.data[2 + i * 3] << 8) |
            (frame.data[3 + i * 3] << 16);
        pgns.add(pgn);
      }
      // Should include the mandatory PGNs.
      expect(pgns, contains(126993)); // Heartbeat
      expect(pgns, contains(126996)); // Product Information
    });

    test('NACKs unknown PGN request', () async {
      final display = await Nmea2000Ecu.create(
        ifname: _vcan,
        address: 0x82,
        identityNumber: 0xA004,
      );
      addTearDown(display.dispose);

      final requester = J1939Ecu.create(
        ifname: _vcan,
        address: 0x92,
        identityNumber: 0xB003,
      );
      addTearDown(requester.dispose);

      await requester.events
          .where((e) => e is AddressClaimed)
          .first
          .timeout(const Duration(milliseconds: 400));

      // Listen for ISO Acknowledgment (PGN 59392).
      final ackFuture = requester.frames
          .where((f) => f.pgn == 59392)
          .first
          .timeout(const Duration(seconds: 3));

      // Request an unknown PGN.
      requester.sendRequest(0x82, 99999);

      final frame = await ackFuture;
      // control byte: 1 = NAK
      final decoded = decode(frame.data, isoAcknowledgmentPgn);
      expect(decoded, isNotNull);
      expect(decoded!['control'], 1); // NAK
    });

    test('heartbeat is sent on create', () async {
      // Create a listener first so we catch the heartbeat.
      final listener = J1939Ecu.create(
        ifname: _vcan,
        address: 0x93,
        identityNumber: 0xB004,
      );
      addTearDown(listener.dispose);

      await listener.events
          .where((e) => e is AddressClaimed)
          .first
          .timeout(const Duration(milliseconds: 400));

      // Set up heartbeat listener before creating the N2K ECU.
      final heartbeatFuture = listener.frames
          .where((f) => f.pgn == 126993)
          .first
          .timeout(const Duration(seconds: 5));

      final display = await Nmea2000Ecu.create(
        ifname: _vcan,
        address: 0x83,
        identityNumber: 0xA005,
        heartbeatPeriod: const Duration(seconds: 1),
      );
      addTearDown(display.dispose);

      final frame = await heartbeatFuture;
      expect(frame.data.length, greaterThanOrEqualTo(3));
    });

    test('dispose is idempotent', () async {
      final ecu = await Nmea2000Ecu.create(
        ifname: _vcan,
        address: 0x84,
        identityNumber: 0xA006,
      );
      ecu.dispose();
      ecu.dispose(); // should not throw
    });

    test('send and receive a frame between two N2K ECUs', () async {
      final a = await Nmea2000Ecu.create(
        ifname: _vcan,
        address: 0x85,
        identityNumber: 0xA007,
      );
      addTearDown(a.dispose);

      final b = await Nmea2000Ecu.create(
        ifname: _vcan,
        address: 0x86,
        identityNumber: 0xA008,
      );
      addTearDown(b.dispose);

      // B listens for Wind Data from A.
      final windFuture = b.framesForPgn(130306).first.timeout(
            const Duration(seconds: 2),
          );

      // A sends Wind Data.
      final windPayload = encode({
        'sid': 1,
        'windSpeed': 5.5,
        'windAngle': 0.785,
        'reference': 2,
      }, windDataPgn);
      await a.send(130306, priority: 6, dest: kBroadcast, data: windPayload);

      final frame = await windFuture;
      final decoded = decode(frame.data, windDataPgn);
      expect(decoded, isNotNull);
      expect(decoded!['windSpeed'], closeTo(5.5, 0.01));
      expect(decoded['windAngle'], closeTo(0.785, 0.001));
    });
  });
}
