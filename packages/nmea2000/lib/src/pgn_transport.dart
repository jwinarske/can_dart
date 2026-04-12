// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Mirrors the C++ `j1939::PgnTransport` enum.
/// Integer values 0/1/2 match the C++ side for FFI calls.
enum PgnTransport {
  single(0),
  fastPacket(1),
  isoTp(2);

  const PgnTransport(this.value);
  final int value;
}
