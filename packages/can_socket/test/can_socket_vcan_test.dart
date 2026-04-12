// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

@TestOn('linux')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:can_socket/can_socket.dart';
import 'package:test/test.dart';

/// These tests require a vcan interface. Set up with:
///   sudo modprobe vcan
///   sudo ip link add dev vcan0 type vcan
///   sudo ip link set up vcan0
///
/// Run with: dart test test/can_socket_vcan_test.dart
const vcanInterface = 'vcan0';

bool _vcanAvailable() {
  try {
    final result = Process.runSync('ip', ['link', 'show', vcanInterface]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  final hasVcan = _vcanAvailable();

  group('CanSocket vcan', skip: hasVcan ? null : 'vcan0 not available', () {
    test('send and receive standard frame', () {
      final sender = CanSocket(vcanInterface);
      final receiver = CanSocket(vcanInterface);

      addTearDown(() {
        sender.close();
        receiver.close();
      });

      final frame = CanFrame(
        id: 0x123,
        data: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
      );

      sender.send(frame);
      final received = receiver.receive(timeoutMs: 1000);

      expect(received, isNotNull);
      expect(received!.id, 0x123);
      expect(received.data, [0xDE, 0xAD, 0xBE, 0xEF]);
      expect(received.dlc, 4);
    });

    test('send and receive extended frame', () {
      final sender = CanSocket(vcanInterface);
      final receiver = CanSocket(vcanInterface);

      addTearDown(() {
        sender.close();
        receiver.close();
      });

      final frame = CanFrame(
        id: 0x1ABCDEF0,
        isExtended: true,
        data: Uint8List.fromList([
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
          0x08,
        ]),
      );

      sender.send(frame);
      final received = receiver.receive(timeoutMs: 1000);

      expect(received, isNotNull);
      expect(received!.id, 0x1ABCDEF0);
      expect(received.isExtended, true);
      expect(received.dlc, 8);
    });

    test('receive returns null on timeout', () {
      final socket = CanSocket(vcanInterface);
      addTearDown(socket.close);

      // Set filters to block everything so we don't receive stray frames
      socket.setFilters([]);

      final received = socket.receive(timeoutMs: 50);
      expect(received, isNull);
    });

    test('hardware filter blocks non-matching frames', () {
      final sender = CanSocket(vcanInterface);
      final receiver = CanSocket(vcanInterface);

      addTearDown(() {
        sender.close();
        receiver.close();
      });

      // Only accept ID 0x200
      receiver.setFilters([CanFilter.exact(0x200)]);

      // Send a non-matching frame first
      sender.send(CanFrame(id: 0x100, data: Uint8List.fromList([0xFF])));
      // Then the matching one
      sender.send(CanFrame(id: 0x200, data: Uint8List.fromList([0xAA])));

      final received = receiver.receive(timeoutMs: 1000);
      expect(received, isNotNull);
      expect(received!.id, 0x200);
      expect(received.data, [0xAA]);
    });

    test('frameStream delivers frames asynchronously', () async {
      final sender = CanSocket(vcanInterface);
      final receiver = CanSocket(vcanInterface);

      addTearDown(() {
        sender.close();
        receiver.close();
      });

      final stream = receiver.frameStream;
      final completer = Completer<CanFrame>();
      final sub = stream.listen((frame) {
        if (!completer.isCompleted) completer.complete(frame);
      });

      // Give the isolate time to start
      await Future<void>.delayed(const Duration(milliseconds: 100));

      sender.send(CanFrame(id: 0x333, data: Uint8List.fromList([0x11, 0x22])));

      final received = await completer.future.timeout(
        const Duration(seconds: 2),
      );

      expect(received.id, 0x333);
      expect(received.data, [0x11, 0x22]);

      await sub.cancel();
    });

    test('CAN FD send and receive', () {
      final sender = CanSocket(vcanInterface, canFd: true);
      final receiver = CanSocket(vcanInterface, canFd: true);

      addTearDown(() {
        sender.close();
        receiver.close();
      });

      final data = Uint8List(64);
      for (var i = 0; i < 64; i++) {
        data[i] = i;
      }

      final frame = CanFrame(id: 0x456, isFd: true, isBrs: true, data: data);

      sender.send(frame);
      final received = receiver.receive(timeoutMs: 1000);

      expect(received, isNotNull);
      expect(received!.id, 0x456);
      expect(received.isFd, true);
      expect(received.data.length, 64);
      expect(received.data, data);
    });

    test('setLoopback and setRecvOwnMsgs', () {
      final socket = CanSocket(vcanInterface);
      addTearDown(socket.close);

      // These should not throw
      socket.setLoopback(true);
      socket.setLoopback(false);
      socket.setRecvOwnMsgs(true);
      socket.setRecvOwnMsgs(false);
    });

    test('setErrorMask does not throw', () {
      final socket = CanSocket(vcanInterface);
      addTearDown(socket.close);

      socket.setErrorMask(canErrBusError | canErrCrtl);
    });

    test('close prevents further operations', () {
      final socket = CanSocket(vcanInterface);
      socket.close();

      expect(
        () => socket.send(CanFrame(id: 0, data: Uint8List(0))),
        throwsStateError,
      );
      expect(() => socket.receive(), throwsStateError);
    });

    test('multiple frames in sequence', () {
      final sender = CanSocket(vcanInterface);
      final receiver = CanSocket(vcanInterface);

      addTearDown(() {
        sender.close();
        receiver.close();
      });

      const count = 10;
      for (var i = 0; i < count; i++) {
        sender.send(CanFrame(id: 0x100 + i, data: Uint8List.fromList([i])));
      }

      for (var i = 0; i < count; i++) {
        final received = receiver.receive(timeoutMs: 1000);
        expect(received, isNotNull);
        expect(received!.id, 0x100 + i);
        expect(received.data, [i]);
      }
    });
  });
}
