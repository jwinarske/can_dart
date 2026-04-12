// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'dbc_signal.dart';

/// A message definition from a DBC file.
class DbcMessage {
  /// CAN message ID (without flags).
  final int id;

  /// Whether this is an extended frame format (29-bit) ID.
  final bool isExtended;

  /// Message name.
  final String name;

  /// Message length in bytes (DLC).
  final int length;

  /// Transmitting node name (or empty string if none).
  final String transmitter;

  /// Signals contained in this message.
  final List<DbcSignal> signals;

  /// Optional comment.
  String? comment;

  DbcMessage({
    required this.id,
    this.isExtended = false,
    required this.name,
    required this.length,
    this.transmitter = '',
    List<DbcSignal>? signals,
    this.comment,
  }) : signals = signals ?? [];

  @override
  String toString() =>
      'DbcMessage(0x${id.toRadixString(16).toUpperCase()}, $name, '
      'dlc=$length, ${signals.length} signals)';
}
