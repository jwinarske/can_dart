// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// j1939_types.dart — Value types and sealed event hierarchy for the J1939 API.
// No FFI imports; safe to use from any isolate.

import 'dart:typed_data';

// ── Constants ─────────────────────────────────────────────────────────────────

const int kBroadcast = 0xFF;
const int kNullAddress = 0xFE;

// ── PGN constants (mirrors j1939/Types.hpp enum class Pgn) ───────────────────

abstract final class Pgn {
  static const int proprietaryA = 0xEF00;
  static const int proprietaryB = 0xFF00;
  static const int addressClaimed = 0xEE00;
  static const int requestPgn = 0xEA00;
  static const int dm1 = 0xFECA;
  static const int softwareId = 0xFEDA;
}

// ── Sealed event hierarchy ────────────────────────────────────────────────────
//
// C++ posts these via Dart_PostCObject_DL; dispatched in J1939Ecu._port.handler.
//
// The `const J1939Event()` base constructor lets subclasses declare their
// own const constructors.
//
// Exhaustive switch example:
//   ecu.events.listen((e) => switch (e) {
//     FrameReceived(:final pgn, :final data) => handleFrame(pgn, data),
//     AddressClaimed(:final address)         => print('claimed $address'),
//     AddressClaimFailed()                   => print('claim failed'),
//     EcuError(:final errorCode)             => print('errno $errorCode'),
//     Dm1Received(:final spn, :final fmi)    => handleFault(spn, fmi),
//   });

sealed class J1939Event {
  const J1939Event();
}

// ── type 0 — frame received ───────────────────────────────────────────────────

final class FrameReceived extends J1939Event {
  const FrameReceived({
    required this.pgn,
    required this.source,
    required this.destination,
    required this.data,
  });

  final int pgn;
  final int source;
  final int destination;

  /// Zero-copy view backed by the C++ FrameBufferPool.
  ///
  /// Points directly into native memory. The C++ finalizer reclaims the buffer
  /// when the GC collects this Uint8List. Copy if you need the bytes to
  /// outlive the current event-loop turn:
  ///   final safe = Uint8List.fromList(frame.data);
  final Uint8List data;

  @override
  String toString() {
    final p = pgn.toRadixString(16).padLeft(5, '0').toUpperCase();
    final s = source.toRadixString(16).padLeft(2, '0').toUpperCase();
    final d = destination.toRadixString(16).padLeft(2, '0').toUpperCase();
    return 'FrameReceived(pgn=0x$p sa=0x$s da=0x$d len=${data.length})';
  }
}

// ── type 1 — address claimed ──────────────────────────────────────────────────

final class AddressClaimed extends J1939Event {
  const AddressClaimed(this.address);
  final int address;

  @override
  String toString() =>
      'AddressClaimed(0x${address.toRadixString(16).padLeft(2, '0').toUpperCase()})';
}

// ── type 2 — address claim failed ────────────────────────────────────────────

final class AddressClaimFailed extends J1939Event {
  const AddressClaimFailed();

  @override
  String toString() => 'AddressClaimFailed()';
}

// ── type 3 — OS / transport error ────────────────────────────────────────────

final class EcuError extends J1939Event {
  const EcuError(this.errorCode);
  final int errorCode;

  @override
  String toString() => 'EcuError(errno=$errorCode)';
}

// ── type 4 — DM1 active fault received ───────────────────────────────────────

final class Dm1Received extends J1939Event {
  const Dm1Received({
    required this.source,
    required this.spn,
    required this.fmi,
    required this.occurrence,
  });

  /// Source address of the ECU that broadcast this fault.
  final int source;

  /// Suspect Parameter Number (19-bit).
  final int spn;

  /// Failure Mode Identifier (5-bit).
  final int fmi;

  /// Occurrence count (7-bit; 0x7F = not available).
  final int occurrence;

  @override
  String toString() =>
      'Dm1Received(sa=0x${source.toRadixString(16).padLeft(2, '0')}'
      ' spn=$spn fmi=$fmi occ=$occurrence)';
}
