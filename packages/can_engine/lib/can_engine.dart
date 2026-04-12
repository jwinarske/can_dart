// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Zero-copy CAN engine with C++ Asio event loop.
///
/// Dart reads the DisplaySnapshot via Pointer.ref — no copies, no GC.
/// The native thread owns the entire pipeline: socket I/O, signal decode,
/// filter chain, and snapshot publish.
library;

export 'src/can_engine.dart';
export 'src/native_structs.dart';
