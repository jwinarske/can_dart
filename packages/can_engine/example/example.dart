// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Minimal can_engine example -- start the engine on vcan0, read bus stats.
///
/// Setup:
///   sudo modprobe vcan
///   sudo ip link add dev vcan0 type vcan
///   sudo ip link set up vcan0
library;

import 'dart:typed_data';

import 'package:can_engine/can_engine.dart';

void main() async {
  final engine = CanEngine();

  final rc = engine.start('vcan0');
  if (rc != 0) {
    print('Failed to start: ${engine.lastError}');
    return;
  }

  print('Engine running on vcan0');
  print('Connected: ${engine.isConnected}');

  // Send a test frame.
  engine.sendFrame(0x123, Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]));

  // Let the engine process for a moment.
  await Future<void>.delayed(const Duration(milliseconds: 500));

  // Read bus statistics from the zero-copy snapshot.
  print('Bus load: ${engine.busLoadPercent}%');
  print('Frames/sec: ${engine.framesPerSecond}');

  engine.stop();
  engine.dispose();
}
