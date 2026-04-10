import 'dart:io';

import 'package:can_dbc/can_dbc.dart';
import 'package:can_dbc/src/parser/dbc_tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('DbcTokenizer', () {
    test('tokenizes keyword', () {
      final tokens = DbcTokenizer('VERSION').tokenize();
      expect(tokens.first.type, TokenType.keyword);
      expect(tokens.first.value, 'VERSION');
    });

    test('tokenizes string', () {
      final tokens = DbcTokenizer('"hello world"').tokenize();
      expect(tokens.first.type, TokenType.string);
      expect(tokens.first.value, 'hello world');
    });

    test('tokenizes integer', () {
      final tokens = DbcTokenizer('42').tokenize();
      expect(tokens.first.type, TokenType.integer);
      expect(tokens.first.value, '42');
    });

    test('tokenizes negative integer', () {
      final tokens = DbcTokenizer('-10').tokenize();
      expect(tokens.first.type, TokenType.integer);
      expect(tokens.first.value, '-10');
    });

    test('tokenizes float', () {
      final tokens = DbcTokenizer('3.14').tokenize();
      expect(tokens.first.type, TokenType.float_);
      expect(tokens.first.value, '3.14');
    });

    test('tokenizes scientific notation', () {
      final tokens = DbcTokenizer('1.5E+03').tokenize();
      expect(tokens.first.type, TokenType.float_);
      expect(tokens.first.value, '1.5E+03');
    });

    test('tokenizes signal definition tokens', () {
      final tokens = DbcTokenizer('0|16@1+').tokenize();
      final types = tokens.map((t) => t.type).toList();
      expect(types, [
        TokenType.integer, // 0
        TokenType.pipe,    // |
        TokenType.integer, // 16
        TokenType.at,      // @
        TokenType.integer, // 1
        TokenType.plus,    // +
        TokenType.eof,
      ]);
    });

    test('skips line comments', () {
      final tokens = DbcTokenizer('// comment\nVERSION').tokenize();
      expect(tokens.first.type, TokenType.keyword);
      expect(tokens.first.value, 'VERSION');
    });

    test('handles escape sequences in strings', () {
      final tokens = DbcTokenizer(r'"line1\nline2"').tokenize();
      expect(tokens.first.value, 'line1\nline2');
    });
  });

  group('DbcParser - example.dbc', () {
    late DbcDatabase db;

    setUpAll(() {
      final content = File('test/fixtures/example.dbc').readAsStringSync();
      db = DbcParser().parse(content);
    });

    test('parses version', () {
      expect(db.version, '1.0');
    });

    test('parses nodes', () {
      expect(db.nodes.length, 3);
      expect(db.nodes.map((n) => n.name), containsAll(['ECU1', 'ECU2', 'Diag']));
    });

    test('parses node comments', () {
      final ecu1 = db.nodes.firstWhere((n) => n.name == 'ECU1');
      expect(ecu1.comment, 'Engine Control Unit');
    });

    test('parses messages', () {
      expect(db.messages.length, 3);
    });

    test('parses EngineData message', () {
      final msg = db.messageById(100)!;
      expect(msg.name, 'EngineData');
      expect(msg.length, 8);
      expect(msg.transmitter, 'ECU1');
      expect(msg.signals.length, 4);
      expect(msg.comment, 'Engine parameters at 100ms cycle time');
    });

    test('parses EngineSpeed signal', () {
      final msg = db.messageById(100)!;
      final sig = msg.signals.firstWhere((s) => s.name == 'EngineSpeed');
      expect(sig.startBit, 0);
      expect(sig.length, 16);
      expect(sig.byteOrder, ByteOrder.littleEndian);
      expect(sig.valueType, ValueType.unsigned);
      expect(sig.factor, 0.25);
      expect(sig.offset, 0);
      expect(sig.minimum, 0);
      expect(sig.maximum, 16383.75);
      expect(sig.unit, 'rpm');
      expect(sig.receivers, ['ECU2']);
      expect(sig.comment, 'Current engine speed in rpm');
    });

    test('parses signed signal', () {
      final msg = db.messageById(100)!;
      final sig = msg.signals.firstWhere((s) => s.name == 'EngineTemp');
      expect(sig.valueType, ValueType.signed);
      expect(sig.offset, -40);
      expect(sig.minimum, -40);
      expect(sig.maximum, 215);
      expect(sig.unit, 'degC');
    });

    test('parses value descriptions', () {
      final msg = db.messageById(100)!;
      final sig = msg.signals.firstWhere((s) => s.name == 'IdleRunning');
      expect(sig.valueDescriptions, isNotNull);
      expect(sig.valueDescriptions![0], 'Running');
      expect(sig.valueDescriptions![1], 'Idle');
    });

    test('parses GearPosition value descriptions', () {
      final msg = db.messageById(200)!;
      final sig = msg.signals.firstWhere((s) => s.name == 'GearPosition');
      expect(sig.valueDescriptions, isNotNull);
      expect(sig.valueDescriptions!.length, 8);
      expect(sig.valueDescriptions![0], 'Neutral');
      expect(sig.valueDescriptions![7], 'Reverse');
    });

    test('parses TransmissionData message', () {
      final msg = db.messageById(200)!;
      expect(msg.name, 'TransmissionData');
      expect(msg.length, 4);
      expect(msg.signals.length, 2);
    });

    test('parses BrakeData message', () {
      final msg = db.messageById(300)!;
      expect(msg.name, 'BrakeData');
      expect(msg.signals.length, 4);
    });

    test('total signal count', () {
      expect(db.signalCount, 10);
    });
  });

  group('DbcParser - multiplex.dbc', () {
    late DbcDatabase db;

    setUpAll(() {
      final content = File('test/fixtures/multiplex.dbc').readAsStringSync();
      db = DbcParser().parse(content);
    });

    test('parses multiplexer signal', () {
      final msg = db.messageById(400)!;
      final mux = msg.signals.firstWhere((s) => s.name == 'MuxSelector');
      expect(mux.multiplexType, MultiplexType.multiplexer);
    });

    test('parses multiplexed signals', () {
      final msg = db.messageById(400)!;
      final s0 = msg.signals.firstWhere((s) => s.name == 'Signal_0');
      expect(s0.multiplexType, MultiplexType.multiplexed);
      expect(s0.multiplexValue, 0);

      final s1 = msg.signals.firstWhere((s) => s.name == 'Signal_1');
      expect(s1.multiplexType, MultiplexType.multiplexed);
      expect(s1.multiplexValue, 1);

      final s2 = msg.signals.firstWhere((s) => s.name == 'Signal_2');
      expect(s2.multiplexType, MultiplexType.multiplexed);
      expect(s2.multiplexValue, 2);
    });

    test('parses non-multiplexed signal in multiplexed message', () {
      final msg = db.messageById(400)!;
      final common = msg.signals.firstWhere((s) => s.name == 'CommonSignal');
      expect(common.multiplexType, MultiplexType.none);
    });

    test('parses simple message alongside multiplexed', () {
      final msg = db.messageById(500)!;
      expect(msg.name, 'SimpleMsg');
      expect(msg.signals.length, 2);
    });
  });

  group('DbcParser - motorola.dbc', () {
    late DbcDatabase db;

    setUpAll(() {
      final content = File('test/fixtures/motorola.dbc').readAsStringSync();
      db = DbcParser().parse(content);
    });

    test('parses big-endian signals', () {
      final msg = db.messageById(600)!;
      final sig = msg.signals.firstWhere((s) => s.name == 'BigEndian16');
      expect(sig.byteOrder, ByteOrder.bigEndian);
      expect(sig.startBit, 7);
      expect(sig.length, 16);
    });

    test('parses big-endian signed signal', () {
      final msg = db.messageById(600)!;
      final sig = msg.signals.firstWhere((s) => s.name == 'BigEndianSigned');
      expect(sig.byteOrder, ByteOrder.bigEndian);
      expect(sig.valueType, ValueType.signed);
      expect(sig.length, 12);
    });

    test('parses little-endian signals', () {
      final msg = db.messageById(601)!;
      final sig = msg.signals.firstWhere((s) => s.name == 'LittleEndian16');
      expect(sig.byteOrder, ByteOrder.littleEndian);
      expect(sig.startBit, 0);
      expect(sig.length, 16);
    });

    test('parses extended frame format', () {
      final msg = db.messageById(512)!; // 2147484160 & 0x1FFFFFFF = 512
      expect(msg.isExtended, true);
      expect(msg.signals.length, 1);
      expect(msg.signals.first.name, 'ExtSignal');
    });

    test('message comments', () {
      final msg = db.messageById(600)!;
      expect(msg.comment, 'Message with Motorola (big-endian) byte order signals');
    });
  });

  group('DbcParser - edge cases', () {
    test('parses empty DBC', () {
      final db = DbcParser().parse('');
      expect(db.messages, isEmpty);
      expect(db.nodes, isEmpty);
    });

    test('parses DBC with only VERSION', () {
      final db = DbcParser().parse('VERSION "2.0"');
      expect(db.version, '2.0');
    });

    test('parses message with no signals', () {
      final db = DbcParser().parse('''
VERSION ""
BO_ 100 EmptyMsg: 0 Vector__XXX
''');
      expect(db.messages.length, 1);
      expect(db.messages.first.signals, isEmpty);
    });

    test('handles zero-length signal', () {
      final db = DbcParser().parse('''
VERSION ""
BO_ 100 Msg: 8 Sender
 SG_ ZeroBit : 0|1@1+ (1,0) [0|1] "" Receiver
''');
      final sig = db.messages.first.signals.first;
      expect(sig.length, 1);
    });
  });
}
