// Dart-side encode/decode helpers for can_dbc signals.
//
// can_dbc parses a .dbc into a structured [DbcDatabase], and the native
// can_engine pipeline knows how to decode signals from raw CAN frames via
// the compiled signal table. But the Flutter app layer still needs to
// (a) *decode* frames itself when the engine is running — because we read
// the raw `messages[]` rows out of the zero-copy snapshot, not the
// engine's signals[] array, to keep the UI decoupled from signal indices —
// and (b) *encode* outbound frames like HELM_CMD from user input.
//
// This file stays pure Dart and depends only on can_dbc. Everything is
// keyed off the [DbcSignal] definitions, so a DBC schema change cascades
// into the app purely through the parsed model — no regenerated code.

import 'dart:typed_data';

import 'package:can_dbc/can_dbc.dart';

/// Decodes [signal] out of the little-endian byte sequence [payload] and
/// returns the *physical* value (factor/offset already applied).
///
/// Returns `null` if the payload is too short for the signal's bit range.
double? decodeSignal(DbcSignal signal, Uint8List payload) {
  final raw = _readBits(
    payload,
    startBit: signal.startBit,
    length: signal.length,
    bigEndian: signal.byteOrder == ByteOrder.bigEndian,
  );
  if (raw == null) return null;

  var value = raw;
  if (signal.valueType == ValueType.signed) {
    final signBit = 1 << (signal.length - 1);
    if ((raw & signBit) != 0) {
      // Sign-extend.
      value = raw - (1 << signal.length);
    }
  }
  return value * signal.factor + signal.offset;
}

/// Encodes the *physical* value [value] into [payload] at [signal]'s
/// bit range. Throws [ArgumentError] if [payload] is too short.
///
/// The caller is responsible for pre-sizing [payload] (typically to
/// the parent DbcMessage's `length`) and for calling this multiple
/// times when packing several signals into one frame.
void encodeSignal(DbcSignal signal, double value, Uint8List payload) {
  final scaled = ((value - signal.offset) / signal.factor).round();
  final mask = signal.length >= 64 ? ~0 : ((1 << signal.length) - 1);
  final raw = scaled & mask;
  _writeBits(
    payload,
    startBit: signal.startBit,
    length: signal.length,
    value: raw,
    bigEndian: signal.byteOrder == ByteOrder.bigEndian,
  );
}

// ── Bit helpers ──
//
// DBC defines two bit numberings:
//
// * Intel (little endian @1): bits are numbered LSB-first within each byte
//   and consecutive bits walk "upward" through the byte stream. Signal
//   start bit is the LSB of the signal.
// * Motorola (big endian @0): bits are numbered MSB-first within each byte
//   but bytes run in their natural order. Signal start bit is the MSB
//   of the signal. Cantools-compatible "Motorola forward LSB" numbering.
//
// The DBC only ever encodes unsigned up to 32 bits for the Throttle file,
// but the helpers below work for up to 63-bit values regardless. We keep
// intermediate math in plain ints — JIT on VM/desktop is 64-bit so this
// is safe.

int? _readBits(
  Uint8List buf, {
  required int startBit,
  required int length,
  required bool bigEndian,
}) {
  if (length <= 0 || length > 63) return 0;

  var raw = 0;
  for (var i = 0; i < length; i++) {
    final int bitPos;
    if (bigEndian) {
      // Motorola: start bit is the MSB of the signal. Walk backwards
      // through the forward bit ordering.
      final startByte = startBit ~/ 8;
      final startBitInByte = startBit % 8;
      final linear = startByte * 8 + (7 - startBitInByte) + i;
      final byte = linear ~/ 8;
      final bit = 7 - (linear % 8);
      if (byte >= buf.length) return null;
      bitPos = (buf[byte] >> bit) & 1;
    } else {
      // Intel: straightforward linear bit ordering.
      final pos = startBit + i;
      final byte = pos ~/ 8;
      final bit = pos % 8;
      if (byte >= buf.length) return null;
      bitPos = (buf[byte] >> bit) & 1;
    }
    raw |= bitPos << i;
  }
  return raw;
}

void _writeBits(
  Uint8List buf, {
  required int startBit,
  required int length,
  required int value,
  required bool bigEndian,
}) {
  for (var i = 0; i < length; i++) {
    final bitVal = (value >> i) & 1;
    if (bigEndian) {
      final startByte = startBit ~/ 8;
      final startBitInByte = startBit % 8;
      final linear = startByte * 8 + (7 - startBitInByte) + i;
      final byte = linear ~/ 8;
      final bit = 7 - (linear % 8);
      if (byte >= buf.length) {
        throw ArgumentError(
          'encodeSignal: buffer too short (byte $byte >= ${buf.length})',
        );
      }
      buf[byte] = (buf[byte] & ~(1 << bit)) | (bitVal << bit);
    } else {
      final pos = startBit + i;
      final byte = pos ~/ 8;
      final bit = pos % 8;
      if (byte >= buf.length) {
        throw ArgumentError(
          'encodeSignal: buffer too short (byte $byte >= ${buf.length})',
        );
      }
      buf[byte] = (buf[byte] & ~(1 << bit)) | (bitVal << bit);
    }
  }
}
