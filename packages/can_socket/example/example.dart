// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Minimal SocketCAN example -- send and receive a CAN frame on vcan0.
///
/// Setup:
///   sudo modprobe vcan
///   sudo ip link add dev vcan0 type vcan
///   sudo ip link set up vcan0
library;

import 'dart:typed_data';

import 'package:can_socket/can_socket.dart';

void main() {
  final socket = CanSocket('vcan0');

  // Send a standard CAN frame.
  socket.send(
    CanFrame(id: 0x123, data: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])),
  );

  // Blocking receive with 1-second timeout.
  final frame = socket.receive(timeoutMs: 1000);
  if (frame != null) {
    print('Received: $frame');
  } else {
    print('No frame received within timeout.');
  }

  socket.close();
}
