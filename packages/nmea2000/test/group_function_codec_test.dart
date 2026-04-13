// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:nmea2000/src/group_function.dart';
import 'package:nmea2000/src/group_function_codec.dart';
import 'package:test/test.dart';

void main() {
  group('encodeCommand', () {
    test('header structure', () {
      final data = encodeCommand(
        pgn: 0x01FECA,
        fields: [const FieldPair(1, 42)],
      );

      expect(data[0], GroupFunctionCode.command.value);
      // PGN LE
      expect(data[1], 0xCA);
      expect(data[2], 0xFE);
      expect(data[3], 0x01);
      // Priority 8 | 0xF0
      expect(data[4], (8 & 0x0F) | 0xF0);
      // numFields = 1
      expect(data[5], 1);
    });

    test('field pairs encoded as number + 2-byte LE value', () {
      final data = encodeCommand(
        pgn: 100,
        fields: [const FieldPair(3, 0x1234)],
      );

      expect(data[6], 3); // field number
      expect(data[7], 0x34); // value low
      expect(data[8], 0x12); // value high
    });

    test('null value encodes as 0xFFFF', () {
      final data = encodeCommand(
        pgn: 100,
        fields: [const FieldPair(1, null)],
      );

      expect(data[7], 0xFF);
      expect(data[8], 0xFF);
    });

    test('double value is rounded to int', () {
      final data = encodeCommand(
        pgn: 100,
        fields: [const FieldPair(1, 3.7)],
      );

      // 3.7 rounds to 4
      expect(data[7], 4);
      expect(data[8], 0);
    });

    test('non-numeric value encodes as 0xFFFF', () {
      final data = encodeCommand(
        pgn: 100,
        fields: [const FieldPair(1, 'text')],
      );

      expect(data[7], 0xFF);
      expect(data[8], 0xFF);
    });

    test('multiple fields', () {
      final data = encodeCommand(
        pgn: 100,
        fields: [
          const FieldPair(1, 10),
          const FieldPair(2, 20),
        ],
      );

      expect(data[5], 2); // numFields
      expect(data[6], 1); // field 1 number
      expect(data[9], 2); // field 2 number
    });

    test('custom priority', () {
      final data = encodeCommand(
        pgn: 100,
        priority: 3,
        fields: [],
      );

      expect(data[4], (3 & 0x0F) | 0xF0);
    });
  });

  group('encodeReadFields', () {
    test('header with manufacturer code', () {
      final data = encodeReadFields(
        pgn: 0x01FECA,
        manufacturerCode: 0x1FF,
        industryCode: 4,
        uniqueId: 7,
        requestedFieldNumbers: [1, 2, 3],
      );

      expect(data[0], GroupFunctionCode.readFields.value);
      // PGN LE
      expect(data[1], 0xCA);
      expect(data[2], 0xFE);
      expect(data[3], 0x01);
      // mfr low byte
      expect(data[4], 0x1FF & 0xFF);
      // mfr high 3 bits | industry 3 bits << 5
      expect(data[5], ((0x1FF >> 8) & 0x07) | ((4 & 0x07) << 5));
      // uniqueId
      expect(data[6], 7);
      // numSelection = 0
      expect(data[7], 0);
      // numRequestedFields = 3
      expect(data[8], 3);
      expect(data[9], 1);
      expect(data[10], 2);
      expect(data[11], 3);
    });

    test('with selection pairs', () {
      final data = encodeReadFields(
        pgn: 100,
        selectionPairs: [const FieldPair(5, 99)],
        requestedFieldNumbers: [1],
      );

      expect(data[7], 1); // numSelection = 1
      expect(data[8], 5); // selection field number
      expect(data[9], 99); // selection value low
      expect(data[10], 0); // selection value high
      expect(data[11], 1); // numRequestedFields = 1
      expect(data[12], 1); // requested field number
    });
  });

  group('encodeWriteFields', () {
    test('parameter pairs include field number and value', () {
      final data = encodeWriteFields(
        pgn: 100,
        fields: [const FieldPair(1, 42), const FieldPair(2, 0x0100)],
      );

      expect(data[0], GroupFunctionCode.writeFields.value);
      expect(data[7], 0); // numSelection = 0
      expect(data[8], 2); // numParams = 2
      // Field 1
      expect(data[9], 1);
      expect(data[10], 42);
      expect(data[11], 0);
      // Field 2
      expect(data[12], 2);
      expect(data[13], 0x00);
      expect(data[14], 0x01);
    });
  });

  group('decodeFunctionCode', () {
    test('decodes all 7 function codes', () {
      for (final code in GroupFunctionCode.values) {
        final data = Uint8List.fromList([code.value]);
        expect(decodeFunctionCode(data), code);
      }
    });

    test('empty data returns null', () {
      expect(decodeFunctionCode(Uint8List(0)), isNull);
    });

    test('unknown value returns null', () {
      expect(decodeFunctionCode(Uint8List.fromList([99])), isNull);
    });
  });

  group('decodeTargetPgn', () {
    test('decodes 3-byte LE PGN', () {
      final data = Uint8List.fromList([0, 0xCA, 0xFE, 0x01]);
      expect(decodeTargetPgn(data), 0x01FECA);
    });

    test('short data returns 0', () {
      expect(decodeTargetPgn(Uint8List.fromList([0, 1])), 0);
    });
  });

  group('decodeAcknowledge', () {
    test('decodes valid acknowledge', () {
      final data = Uint8List.fromList([
        GroupFunctionCode.acknowledge.value,
        0xCA, 0xFE, 0x01, // PGN
        PgnErrorCode.ok.value, // pgnError
        2, // numFields
        FieldErrorCode.ok.value,
        FieldErrorCode.cannotComply.value,
      ]);

      final ack = decodeAcknowledge(data)!;
      expect(ack.pgn, 0x01FECA);
      expect(ack.pgnError, PgnErrorCode.ok);
      expect(ack.isOk, isTrue);
      expect(ack.fieldErrors.length, 2);
      expect(ack.fieldErrors[0], FieldErrorCode.ok);
      expect(ack.fieldErrors[1], FieldErrorCode.cannotComply);
    });

    test('returns null for wrong function code', () {
      final data = Uint8List.fromList([
        GroupFunctionCode.command.value,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(decodeAcknowledge(data), isNull);
    });

    test('returns null for short data', () {
      expect(decodeAcknowledge(Uint8List.fromList([2, 0, 0])), isNull);
    });

    test('minimum 6-byte payload with zero fields', () {
      final data = Uint8List.fromList([
        GroupFunctionCode.acknowledge.value,
        100, 0, 0,
        PgnErrorCode.pgnNotSupported.value,
        0, // numFields
      ]);
      final ack = decodeAcknowledge(data)!;
      expect(ack.pgn, 100);
      expect(ack.isOk, isFalse);
      expect(ack.fieldErrors, isEmpty);
    });
  });

  group('decodeReadFieldsReply', () {
    test('decodes reply with field pairs', () {
      final data = Uint8List.fromList([
        GroupFunctionCode.readFieldsReply.value,
        0xCA, 0xFE, 0x01, // PGN
        0xFF, 0x07, // mfr
        0x00, // uniqueId
        0, // numSelection
        2, // numParams
        1, 0x26, 0x02, // field 1, value 550
        2, 0xAA, 0x1E, // field 2, value 7850
      ]);

      final reply = decodeReadFieldsReply(data)!;
      expect(reply.pgn, 0x01FECA);
      expect(reply.fields.length, 2);
      expect(reply.fields[0].fieldNumber, 1);
      expect(reply.fields[0].value, 550);
      expect(reply.fields[1].fieldNumber, 2);
      expect(reply.fields[1].value, 7850);
    });

    test('returns null for wrong function code', () {
      final data = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]);
      expect(decodeReadFieldsReply(data), isNull);
    });

    test('returns empty fields when data ends at header', () {
      final data = Uint8List.fromList([
        GroupFunctionCode.readFieldsReply.value,
        100, 0, 0,
        0xFF, 0x07,
        0x00,
        0, // numSelection = 0 → offset becomes 8 which == data.length
      ]);
      final reply = decodeReadFieldsReply(data)!;
      expect(reply.fields, isEmpty);
    });
  });

  group('decodeWriteFieldsReply', () {
    test('decodes reply with field pairs', () {
      final data = Uint8List.fromList([
        GroupFunctionCode.writeFieldsReply.value,
        100, 0, 0,
        0xFF, 0x07,
        0x00,
        0, // numSelection
        1, // numParams
        5, 0x2A, 0x00, // field 5, value 42
      ]);

      final reply = decodeWriteFieldsReply(data)!;
      expect(reply.pgn, 100);
      expect(reply.fields.length, 1);
      expect(reply.fields[0].fieldNumber, 5);
      expect(reply.fields[0].value, 42);
    });

    test('returns null for wrong function code', () {
      final data = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]);
      expect(decodeWriteFieldsReply(data), isNull);
    });
  });

  group('decodeIncomingFieldPairs', () {
    test('readFields returns field numbers with null values', () {
      final data = encodeReadFields(
        pgn: 100,
        requestedFieldNumbers: [1, 3, 5],
      );

      final pairs = decodeIncomingFieldPairs(data);
      expect(pairs.length, 3);
      expect(pairs[0].fieldNumber, 1);
      expect(pairs[0].value, isNull);
      expect(pairs[1].fieldNumber, 3);
      expect(pairs[2].fieldNumber, 5);
    });

    test('writeFields returns field numbers with values', () {
      final data = encodeWriteFields(
        pgn: 100,
        fields: [const FieldPair(1, 42), const FieldPair(2, 99)],
      );

      final pairs = decodeIncomingFieldPairs(data);
      expect(pairs.length, 2);
      expect(pairs[0].fieldNumber, 1);
      expect(pairs[0].value, 42);
      expect(pairs[1].fieldNumber, 2);
      expect(pairs[1].value, 99);
    });

    test('wrong function code returns empty list', () {
      final data = Uint8List.fromList([
        GroupFunctionCode.acknowledge.value,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(decodeIncomingFieldPairs(data), isEmpty);
    });

    test('short data returns empty list', () {
      expect(decodeIncomingFieldPairs(Uint8List.fromList([3])), isEmpty);
    });
  });

  group('encode-decode round trip', () {
    test('command encode then decode function code and PGN', () {
      final encoded = encodeCommand(
        pgn: 0x01FECA,
        fields: [const FieldPair(1, 42)],
      );

      expect(decodeFunctionCode(encoded), GroupFunctionCode.command);
      expect(decodeTargetPgn(encoded), 0x01FECA);
    });

    test('readFields encode then decodeIncomingFieldPairs round trip', () {
      final encoded = encodeReadFields(
        pgn: 130306,
        requestedFieldNumbers: [1, 2, 3, 4],
      );

      expect(decodeFunctionCode(encoded), GroupFunctionCode.readFields);
      expect(decodeTargetPgn(encoded), 130306);
      final pairs = decodeIncomingFieldPairs(encoded);
      expect(pairs.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(pairs[i].fieldNumber, i + 1);
        expect(pairs[i].value, isNull);
      }
    });

    test('writeFields encode then decodeIncomingFieldPairs round trip', () {
      final encoded = encodeWriteFields(
        pgn: 130306,
        fields: [const FieldPair(1, 550), const FieldPair(2, 7850)],
      );

      expect(decodeFunctionCode(encoded), GroupFunctionCode.writeFields);
      final pairs = decodeIncomingFieldPairs(encoded);
      expect(pairs.length, 2);
      expect(pairs[0].value, 550);
      expect(pairs[1].value, 7850);
    });
  });
}
