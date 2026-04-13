/// NMEA 2000 Group Function (PGN 126208) types.
///
/// Group Functions are the RPC layer of NMEA 2000. Subfunctions:
///   0 = Request, 1 = Command, 2 = Acknowledge,
///   3 = Read Fields, 4 = Read Fields Reply,
///   5 = Write Fields, 6 = Write Fields Reply.
library;

/// Group Function subfunction codes.
enum GroupFunctionCode {
  request(0),
  command(1),
  acknowledge(2),
  readFields(3),
  readFieldsReply(4),
  writeFields(5),
  writeFieldsReply(6);

  const GroupFunctionCode(this.value);
  final int value;

  static GroupFunctionCode? fromValue(int v) {
    for (final code in values) {
      if (code.value == v) return code;
    }
    return null;
  }
}

/// PGN-level error code in Acknowledge (function 2).
enum PgnErrorCode {
  ok(0),
  pgnNotSupported(1),
  pgnTemporarilyNotAvailable(2),
  accessDenied(3),
  requestOrCommandNotSupported(4),
  definerTagNotSupported(5),
  readOrWriteNotSupported(6);

  const PgnErrorCode(this.value);
  final int value;

  static PgnErrorCode fromValue(int v) {
    for (final code in values) {
      if (code.value == v) return code;
    }
    return PgnErrorCode.pgnNotSupported;
  }
}

/// Per-field error code in Acknowledge (function 2).
enum FieldErrorCode {
  ok(0),
  invalidRequestOrCommand(1),
  cannotComply(2),
  requestOrCommandNotAvailable(3),
  accessDenied(4);

  const FieldErrorCode(this.value);
  final int value;

  static FieldErrorCode fromValue(int v) {
    for (final code in values) {
      if (code.value == v) return code;
    }
    return FieldErrorCode.cannotComply;
  }
}

/// A field number + value pair used in Group Function requests/replies.
class FieldPair {
  const FieldPair(this.fieldNumber, this.value);

  /// 1-based field number within the target PGN.
  final int fieldNumber;

  /// The field value. For numeric fields this is [num]; for strings, [String].
  /// [null] means "data not available" / "don't care" (selection filter).
  final Object? value;

  @override
  String toString() => 'Field($fieldNumber=$value)';
}

/// Parsed Acknowledge response (function code 2).
class GroupFunctionAck {
  const GroupFunctionAck({
    required this.pgn,
    required this.pgnError,
    this.fieldErrors = const [],
  });

  final int pgn;
  final PgnErrorCode pgnError;
  final List<FieldErrorCode> fieldErrors;

  bool get isOk => pgnError == PgnErrorCode.ok;

  @override
  String toString() => 'GroupFunctionAck(pgn=$pgn ${pgnError.name} '
      'fields=[${fieldErrors.map((e) => e.name).join(', ')}])';
}

/// Parsed Read Fields Reply (function code 4).
class ReadFieldsReply {
  const ReadFieldsReply({
    required this.pgn,
    required this.fields,
  });

  final int pgn;
  final List<FieldPair> fields;

  @override
  String toString() => 'ReadFieldsReply(pgn=$pgn fields=$fields)';
}

/// Parsed Write Fields Reply (function code 6).
class WriteFieldsReply {
  const WriteFieldsReply({
    required this.pgn,
    required this.fields,
  });

  final int pgn;
  final List<FieldPair> fields;

  @override
  String toString() => 'WriteFieldsReply(pgn=$pgn fields=$fields)';
}

/// An incoming Group Function request that a server handler receives.
///
/// Call [acknowledge], [reject], or [reply] to send the response.
class GroupFunctionRequest {
  GroupFunctionRequest({
    required this.functionCode,
    required this.pgn,
    required this.requesterSa,
    required this.fields,
    required this.sendReply,
  });

  final GroupFunctionCode functionCode;
  final int pgn;
  final int requesterSa;
  final List<FieldPair> fields;

  /// Internal callback to send the reply payload.
  final void Function(int functionCode, int pgn, List<int> payload) sendReply;

  bool _replied = false;

  /// Accept the request — send Acknowledge with OK.
  void acknowledge() {
    if (_replied) return;
    _replied = true;
    final payload = <int>[
      GroupFunctionCode.acknowledge.value,
      pgn & 0xFF,
      (pgn >> 8) & 0xFF,
      (pgn >> 16) & 0xFF,
      PgnErrorCode.ok.value &
          0x0F, // PGN error (low nibble) + tx interval error (high nibble)
      fields.length & 0xFF,
    ];
    for (var i = 0; i < fields.length; i++) {
      payload.add(FieldErrorCode.ok.value);
    }
    sendReply(GroupFunctionCode.acknowledge.value, pgn, payload);
  }

  /// Reject the request with a PGN-level error.
  void reject(PgnErrorCode error) {
    if (_replied) return;
    _replied = true;
    final payload = <int>[
      GroupFunctionCode.acknowledge.value,
      pgn & 0xFF,
      (pgn >> 8) & 0xFF,
      (pgn >> 16) & 0xFF,
      error.value & 0x0F,
      fields.length & 0xFF,
    ];
    for (var i = 0; i < fields.length; i++) {
      payload.add(FieldErrorCode.cannotComply.value);
    }
    sendReply(GroupFunctionCode.acknowledge.value, pgn, payload);
  }

  /// Send a Read Fields Reply with actual values.
  void replyWithFields(List<FieldPair> replyFields) {
    if (_replied) return;
    _replied = true;
    // Build Read Fields Reply or Write Fields Reply depending on function code.
    final replyCode = functionCode == GroupFunctionCode.readFields
        ? GroupFunctionCode.readFieldsReply.value
        : GroupFunctionCode.writeFieldsReply.value;
    final payload = <int>[
      replyCode,
      pgn & 0xFF,
      (pgn >> 8) & 0xFF,
      (pgn >> 16) & 0xFF,
      0xFF, // manufacturer code low (0x7FF = not proprietary)
      0x07, // manufacturer code high (3 bits) + reserved (2) + industry (3)
      0x00, // unique ID
      0, // number of selection pairs (none for reply)
      replyFields.length & 0xFF,
    ];
    for (final pair in replyFields) {
      payload.add(pair.fieldNumber & 0xFF);
      // Encode value as raw bytes. For simplicity, use 2 bytes LE for numeric.
      final val = (pair.value as num?)?.toInt() ?? 0xFFFF;
      payload.add(val & 0xFF);
      payload.add((val >> 8) & 0xFF);
    }
    sendReply(replyCode, pgn, payload);
  }
}

/// Handler signature for incoming Group Function requests.
typedef GroupFunctionHandler = void Function(GroupFunctionRequest request);
