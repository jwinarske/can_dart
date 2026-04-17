// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Field data type for CAN message signal decoding.
enum FieldType {
  unsigned,
  signed,
  float32,
  float64,
  string,
  lookup,
  reserved,
}

/// A single field within a message payload.
class FieldDefinition {
  const FieldDefinition({
    required this.name,
    required this.bitOffset,
    required this.bitLength,
    this.resolution = 1.0,
    this.offset = 0.0,
    this.type = FieldType.unsigned,
    this.lookupTable,
  });

  final String name;
  final int bitOffset;
  final int bitLength;
  final double resolution;
  final double offset;
  final FieldType type;

  /// Optional lookup table for [FieldType.lookup] fields.
  final Map<int, String>? lookupTable;

  /// "Data not available" sentinel: all bits set for the field width.
  int get naSentinel {
    if (bitLength >= 64) return -1; // unsigned overflow protection
    return (1 << bitLength) - 1;
  }

  /// "Out of range" sentinel: all bits set minus 1.
  int get oorSentinel => naSentinel - 1;

  /// "Reserved" sentinel: all bits set minus 2.
  int get reservedSentinel => naSentinel - 2;
}

/// Complete definition of a CAN bus message (PGN in J1939/NMEA 2000/RV-C).
class MessageDefinition {
  const MessageDefinition({
    required this.pgn,
    required this.name,
    required this.transport,
    required this.dataLength,
    required this.fields,
    this.repeating = false,
  });

  /// PGN number (e.g. 129025 for Position Rapid Update).
  final int pgn;

  /// Human-readable name.
  final String name;

  /// Transport type index: 0=single, 1=fast_packet, 2=iso_tp.
  /// Matches [TransportType.value].
  final int transport;

  /// Expected payload length in bytes.
  final int dataLength;

  /// Ordered list of fields in the payload.
  final List<FieldDefinition> fields;

  /// Whether the message has a repeating field group at the end.
  final bool repeating;
}
