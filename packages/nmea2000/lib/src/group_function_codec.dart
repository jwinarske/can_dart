import 'dart:typed_data';

import 'group_function.dart';

/// PGN 126208 — NMEA 2000 Group Function.
const kGroupFunctionPgn = 126208;

// ── Encoders ─────────────────────────────────────────────────────────────────

/// Encode a Command (function 1) payload.
///
/// Command is a simplified Write Fields that expects an Acknowledge (function 2)
/// rather than a Write Fields Reply.
Uint8List encodeCommand({
  required int pgn,
  int priority = 8, // 8 = "do not change"
  required List<FieldPair> fields,
}) {
  final buf = <int>[
    GroupFunctionCode.command.value,
    pgn & 0xFF,
    (pgn >> 8) & 0xFF,
    (pgn >> 16) & 0xFF,
    (priority & 0x0F) | 0xF0, // priority (low nibble) + reserved (high nibble)
    fields.length & 0xFF,
  ];
  for (final pair in fields) {
    buf.add(pair.fieldNumber & 0xFF);
    _appendFieldValue(buf, pair.value);
  }
  return Uint8List.fromList(buf);
}

/// Encode a Read Fields (function 3) payload.
Uint8List encodeReadFields({
  required int pgn,
  int manufacturerCode = 0x7FF,
  int industryCode = 0,
  int uniqueId = 0,
  List<FieldPair> selectionPairs = const [],
  required List<int> requestedFieldNumbers,
}) {
  final buf = <int>[
    GroupFunctionCode.readFields.value,
    pgn & 0xFF,
    (pgn >> 8) & 0xFF,
    (pgn >> 16) & 0xFF,
    manufacturerCode & 0xFF,
    ((manufacturerCode >> 8) & 0x07) | ((industryCode & 0x07) << 5),
    uniqueId & 0xFF,
    selectionPairs.length & 0xFF,
  ];
  for (final pair in selectionPairs) {
    buf.add(pair.fieldNumber & 0xFF);
    _appendFieldValue(buf, pair.value);
  }
  buf.add(requestedFieldNumbers.length & 0xFF);
  for (final fn in requestedFieldNumbers) {
    buf.add(fn & 0xFF);
  }
  return Uint8List.fromList(buf);
}

/// Encode a Write Fields (function 5) payload.
Uint8List encodeWriteFields({
  required int pgn,
  int manufacturerCode = 0x7FF,
  int industryCode = 0,
  int uniqueId = 0,
  List<FieldPair> selectionPairs = const [],
  required List<FieldPair> fields,
}) {
  final buf = <int>[
    GroupFunctionCode.writeFields.value,
    pgn & 0xFF,
    (pgn >> 8) & 0xFF,
    (pgn >> 16) & 0xFF,
    manufacturerCode & 0xFF,
    ((manufacturerCode >> 8) & 0x07) | ((industryCode & 0x07) << 5),
    uniqueId & 0xFF,
    selectionPairs.length & 0xFF,
  ];
  for (final pair in selectionPairs) {
    buf.add(pair.fieldNumber & 0xFF);
    _appendFieldValue(buf, pair.value);
  }
  buf.add(fields.length & 0xFF);
  for (final pair in fields) {
    buf.add(pair.fieldNumber & 0xFF);
    _appendFieldValue(buf, pair.value);
  }
  return Uint8List.fromList(buf);
}

/// Append a field value as 2-byte LE (sufficient for most NMEA 2000 fields).
/// Null values encode as 0xFFFF (NA).
void _appendFieldValue(List<int> buf, Object? value) {
  if (value == null) {
    buf.addAll([0xFF, 0xFF]);
  } else if (value is int) {
    buf.add(value & 0xFF);
    buf.add((value >> 8) & 0xFF);
  } else if (value is double) {
    final intVal = value.round();
    buf.add(intVal & 0xFF);
    buf.add((intVal >> 8) & 0xFF);
  } else {
    buf.addAll([0xFF, 0xFF]);
  }
}

// ── Decoders ─────────────────────────────────────────────────────────────────

/// Decode the function code from the first byte of a PGN 126208 payload.
GroupFunctionCode? decodeFunctionCode(Uint8List data) {
  if (data.isEmpty) return null;
  return GroupFunctionCode.fromValue(data[0]);
}

/// Decode the target PGN from bytes 1-3 of a PGN 126208 payload.
int decodeTargetPgn(Uint8List data) {
  if (data.length < 4) return 0;
  return data[1] | (data[2] << 8) | (data[3] << 16);
}

/// Decode an Acknowledge (function 2) payload.
GroupFunctionAck? decodeAcknowledge(Uint8List data) {
  // Minimum: function(1) + pgn(3) + pgnError(1) + numFields(1) = 6 bytes.
  if (data.length < 6 || data[0] != GroupFunctionCode.acknowledge.value) {
    return null;
  }
  final pgn = data[1] | (data[2] << 8) | (data[3] << 16);
  final pgnError = PgnErrorCode.fromValue(data[4] & 0x0F);
  final numFields = data[5];
  final fieldErrors = <FieldErrorCode>[];
  for (var i = 0; i < numFields && (6 + i) < data.length; i++) {
    fieldErrors.add(FieldErrorCode.fromValue(data[6 + i]));
  }
  return GroupFunctionAck(
      pgn: pgn, pgnError: pgnError, fieldErrors: fieldErrors);
}

/// Decode a Read Fields Reply (function 4) payload.
ReadFieldsReply? decodeReadFieldsReply(Uint8List data) {
  // function(1) + pgn(3) + mfr(2) + uniqueId(1) + numSelection(1)
  if (data.length < 8 || data[0] != GroupFunctionCode.readFieldsReply.value) {
    return null;
  }
  final pgn = data[1] | (data[2] << 8) | (data[3] << 16);

  var offset = 7; // past function + pgn + mfr + uniqueId
  final numSelection = data[offset++];

  // Skip selection pairs (each: fieldNumber + 2 bytes value).
  offset += numSelection * 3;

  if (offset >= data.length) {
    return ReadFieldsReply(pgn: pgn, fields: []);
  }
  final numParams = data[offset++];
  final fields = <FieldPair>[];
  for (var i = 0; i < numParams && offset + 2 < data.length; i++) {
    final fn = data[offset++];
    final val = data[offset] | (data[offset + 1] << 8);
    offset += 2;
    fields.add(FieldPair(fn, val));
  }
  return ReadFieldsReply(pgn: pgn, fields: fields);
}

/// Decode a Write Fields Reply (function 6) payload.
WriteFieldsReply? decodeWriteFieldsReply(Uint8List data) {
  if (data.length < 8 || data[0] != GroupFunctionCode.writeFieldsReply.value) {
    return null;
  }
  final pgn = data[1] | (data[2] << 8) | (data[3] << 16);

  var offset = 7;
  final numSelection = data[offset++];
  offset += numSelection * 3;

  if (offset >= data.length) {
    return WriteFieldsReply(pgn: pgn, fields: []);
  }
  final numParams = data[offset++];
  final fields = <FieldPair>[];
  for (var i = 0; i < numParams && offset + 2 < data.length; i++) {
    final fn = data[offset++];
    final val = data[offset] | (data[offset + 1] << 8);
    offset += 2;
    fields.add(FieldPair(fn, val));
  }
  return WriteFieldsReply(pgn: pgn, fields: fields);
}

/// Decode an incoming Read Fields (function 3) or Write Fields (function 5)
/// request for the server handler.
///
/// Returns a list of [FieldPair]s from the parameter pairs section.
/// For Read Fields, the values are the requested field numbers (value=null).
/// For Write Fields, the values are the new field values.
List<FieldPair> decodeIncomingFieldPairs(Uint8List data) {
  if (data.length < 8) return [];
  final functionCode = data[0];
  if (functionCode != GroupFunctionCode.readFields.value &&
      functionCode != GroupFunctionCode.writeFields.value) {
    return [];
  }

  var offset = 7; // past function + pgn + mfr + uniqueId
  final numSelection = data[offset++];
  // Skip selection pairs.
  offset += numSelection * 3;

  if (offset >= data.length) return [];
  final numParams = data[offset++];
  final fields = <FieldPair>[];

  if (functionCode == GroupFunctionCode.readFields.value) {
    // Read Fields: parameter pairs are just field numbers (no values).
    for (var i = 0; i < numParams && offset < data.length; i++) {
      fields.add(FieldPair(data[offset++], null));
    }
  } else {
    // Write Fields: parameter pairs are field number + 2-byte value.
    for (var i = 0; i < numParams && offset + 2 < data.length; i++) {
      final fn = data[offset++];
      final val = data[offset] | (data[offset + 1] << 8);
      offset += 2;
      fields.add(FieldPair(fn, val));
    }
  }
  return fields;
}
