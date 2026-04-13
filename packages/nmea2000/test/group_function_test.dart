// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'package:nmea2000/src/group_function.dart';
import 'package:test/test.dart';

void main() {
  group('GroupFunctionCode', () {
    test('all 7 codes round-trip via fromValue', () {
      for (final code in GroupFunctionCode.values) {
        expect(GroupFunctionCode.fromValue(code.value), code);
      }
    });

    test('values are 0 through 6', () {
      expect(GroupFunctionCode.request.value, 0);
      expect(GroupFunctionCode.command.value, 1);
      expect(GroupFunctionCode.acknowledge.value, 2);
      expect(GroupFunctionCode.readFields.value, 3);
      expect(GroupFunctionCode.readFieldsReply.value, 4);
      expect(GroupFunctionCode.writeFields.value, 5);
      expect(GroupFunctionCode.writeFieldsReply.value, 6);
    });

    test('unknown value returns null', () {
      expect(GroupFunctionCode.fromValue(7), isNull);
      expect(GroupFunctionCode.fromValue(99), isNull);
      expect(GroupFunctionCode.fromValue(-1), isNull);
    });
  });

  group('PgnErrorCode', () {
    test('all codes round-trip via fromValue', () {
      for (final code in PgnErrorCode.values) {
        expect(PgnErrorCode.fromValue(code.value), code);
      }
    });

    test('unknown value returns pgnNotSupported', () {
      expect(PgnErrorCode.fromValue(99), PgnErrorCode.pgnNotSupported);
    });
  });

  group('FieldErrorCode', () {
    test('all codes round-trip via fromValue', () {
      for (final code in FieldErrorCode.values) {
        expect(FieldErrorCode.fromValue(code.value), code);
      }
    });

    test('unknown value returns cannotComply', () {
      expect(FieldErrorCode.fromValue(99), FieldErrorCode.cannotComply);
    });
  });

  group('FieldPair', () {
    test('stores fieldNumber and value', () {
      const pair = FieldPair(3, 42);
      expect(pair.fieldNumber, 3);
      expect(pair.value, 42);
    });

    test('value can be null', () {
      const pair = FieldPair(1, null);
      expect(pair.value, isNull);
    });

    test('toString format', () {
      expect(const FieldPair(3, 42).toString(), 'Field(3=42)');
      expect(const FieldPair(1, null).toString(), 'Field(1=null)');
    });
  });

  group('GroupFunctionAck', () {
    test('isOk returns true when pgnError is ok', () {
      const ack = GroupFunctionAck(
        pgn: 130306,
        pgnError: PgnErrorCode.ok,
      );
      expect(ack.isOk, isTrue);
    });

    test('isOk returns false on error', () {
      const ack = GroupFunctionAck(
        pgn: 130306,
        pgnError: PgnErrorCode.pgnNotSupported,
      );
      expect(ack.isOk, isFalse);
    });

    test('toString format', () {
      const ack = GroupFunctionAck(
        pgn: 130306,
        pgnError: PgnErrorCode.ok,
        fieldErrors: [FieldErrorCode.ok, FieldErrorCode.cannotComply],
      );
      final s = ack.toString();
      expect(s, contains('130306'));
      expect(s, contains('ok'));
      expect(s, contains('cannotComply'));
    });
  });

  group('ReadFieldsReply', () {
    test('stores pgn and fields', () {
      const reply = ReadFieldsReply(
        pgn: 129025,
        fields: [FieldPair(1, 100), FieldPair(2, 200)],
      );
      expect(reply.pgn, 129025);
      expect(reply.fields.length, 2);
      expect(reply.fields[0].fieldNumber, 1);
      expect(reply.fields[1].value, 200);
    });

    test('toString contains pgn', () {
      const reply = ReadFieldsReply(pgn: 129025, fields: []);
      expect(reply.toString(), contains('129025'));
    });
  });

  group('WriteFieldsReply', () {
    test('stores pgn and fields', () {
      const reply = WriteFieldsReply(
        pgn: 130306,
        fields: [FieldPair(1, 50)],
      );
      expect(reply.pgn, 130306);
      expect(reply.fields.length, 1);
    });
  });

  group('GroupFunctionRequest', () {
    test('acknowledge sends OK payload', () {
      int? capturedFc;
      int? capturedPgn;
      List<int>? capturedPayload;

      final request = GroupFunctionRequest(
        functionCode: GroupFunctionCode.command,
        pgn: 0x01FECA, // 130762
        requesterSa: 0x10,
        fields: [const FieldPair(1, 42), const FieldPair(2, 99)],
        sendReply: (fc, pgn, payload) {
          capturedFc = fc;
          capturedPgn = pgn;
          capturedPayload = payload;
        },
      );

      request.acknowledge();

      expect(capturedFc, GroupFunctionCode.acknowledge.value);
      expect(capturedPgn, 0x01FECA);
      expect(capturedPayload, isNotNull);
      // Payload: [ackCode, pgn_lo, pgn_mid, pgn_hi, pgnError, numFields, field0Err, field1Err]
      expect(capturedPayload![0], GroupFunctionCode.acknowledge.value);
      expect(capturedPayload![4] & 0x0F, PgnErrorCode.ok.value);
      expect(capturedPayload![5], 2); // numFields
      expect(capturedPayload![6], FieldErrorCode.ok.value);
      expect(capturedPayload![7], FieldErrorCode.ok.value);
    });

    test('acknowledge is idempotent', () {
      var callCount = 0;
      final request = GroupFunctionRequest(
        functionCode: GroupFunctionCode.command,
        pgn: 100,
        requesterSa: 0x10,
        fields: [],
        sendReply: (_, __, ___) => callCount++,
      );

      request.acknowledge();
      request.acknowledge();
      expect(callCount, 1);
    });

    test('reject sends error payload', () {
      List<int>? capturedPayload;

      final request = GroupFunctionRequest(
        functionCode: GroupFunctionCode.command,
        pgn: 100,
        requesterSa: 0x10,
        fields: [const FieldPair(1, 42)],
        sendReply: (_, __, payload) => capturedPayload = payload,
      );

      request.reject(PgnErrorCode.pgnNotSupported);

      expect(capturedPayload![4] & 0x0F, PgnErrorCode.pgnNotSupported.value);
      expect(capturedPayload![6], FieldErrorCode.cannotComply.value);
    });

    test('reject after acknowledge is no-op', () {
      var callCount = 0;
      final request = GroupFunctionRequest(
        functionCode: GroupFunctionCode.command,
        pgn: 100,
        requesterSa: 0x10,
        fields: [],
        sendReply: (_, __, ___) => callCount++,
      );

      request.acknowledge();
      request.reject(PgnErrorCode.pgnNotSupported);
      expect(callCount, 1);
    });

    test('replyWithFields sends read fields reply', () {
      int? capturedFc;
      List<int>? capturedPayload;

      final request = GroupFunctionRequest(
        functionCode: GroupFunctionCode.readFields,
        pgn: 130306,
        requesterSa: 0x10,
        fields: [],
        sendReply: (fc, _, payload) {
          capturedFc = fc;
          capturedPayload = payload;
        },
      );

      request.replyWithFields([
        const FieldPair(1, 550),
        const FieldPair(2, 7850),
      ]);

      expect(capturedFc, GroupFunctionCode.readFieldsReply.value);
      expect(capturedPayload![0], GroupFunctionCode.readFieldsReply.value);
      // numParams = 2
      expect(capturedPayload![8], 2);
      // Field 1: number=1, value=550 (0x0226)
      expect(capturedPayload![9], 1);
      expect(capturedPayload![10], 550 & 0xFF);
      expect(capturedPayload![11], (550 >> 8) & 0xFF);
    });

    test('replyWithFields for write returns writeFieldsReply code', () {
      int? capturedFc;

      final request = GroupFunctionRequest(
        functionCode: GroupFunctionCode.writeFields,
        pgn: 100,
        requesterSa: 0x10,
        fields: [],
        sendReply: (fc, _, __) => capturedFc = fc,
      );

      request.replyWithFields([const FieldPair(1, 42)]);
      expect(capturedFc, GroupFunctionCode.writeFieldsReply.value);
    });
  });
}
