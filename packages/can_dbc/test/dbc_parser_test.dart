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
        TokenType.pipe, // |
        TokenType.integer, // 16
        TokenType.at, // @
        TokenType.integer, // 1
        TokenType.plus, // +
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
      expect(
        db.nodes.map((n) => n.name),
        containsAll(['ECU1', 'ECU2', 'Diag']),
      );
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

  group('DbcParser - extended_multiplex.dbc (m<N>M)', () {
    late DbcDatabase db;

    setUpAll(() {
      final content =
          File('test/fixtures/extended_multiplex.dbc').readAsStringSync();
      db = DbcParser().parse(content);
    });

    test('root mux selector parses as multiplexer', () {
      final msg = db.messageById(2024)!;
      final service = msg.signals.firstWhere((s) => s.name == 'service');
      expect(service.multiplexType, MultiplexType.multiplexer);
      expect(service.multiplexValue, isNull);
    });

    test('m<N>M parses as extendedMultiplexor with selector value', () {
      final msg = db.messageById(2024)!;
      final pid1 = msg.signals.firstWhere(
        (s) => s.name == 'ParameterID_Service01',
      );
      expect(pid1.multiplexType, MultiplexType.extendedMultiplexor);
      expect(pid1.multiplexValue, 1);

      final pid2 = msg.signals.firstWhere(
        (s) => s.name == 'ParameterID_Service02',
      );
      expect(pid2.multiplexType, MultiplexType.extendedMultiplexor);
      expect(pid2.multiplexValue, 2);
    });

    test('m<N> leaves under an extended mux still parse as multiplexed', () {
      final msg = db.messageById(2024)!;
      final rpm = msg.signals.firstWhere(
        (s) => s.name == 'S1_PID_0C_EngineRPM',
      );
      expect(rpm.multiplexType, MultiplexType.multiplexed);
      expect(rpm.multiplexValue, 12);

      final dtc = msg.signals.firstWhere(
        (s) => s.name == 'S2_PID_02_FreezeDTC',
      );
      expect(dtc.multiplexType, MultiplexType.multiplexed);
      expect(dtc.multiplexValue, 2);
    });

    test('non-mux signals alongside extended mux are unmarked', () {
      final msg = db.messageById(2024)!;
      final resp = msg.signals.firstWhere((s) => s.name == 'response');
      expect(resp.multiplexType, MultiplexType.none);
      expect(resp.multiplexValue, isNull);
    });

    test('SG_MUL_VAL_ sections are tolerated (not yet modelled)', () {
      // The fixture contains 5 SG_MUL_VAL_ rows; parse succeeded in setUpAll,
      // which is the whole assertion here — they must not trip the parser.
      expect(db.messages, isNotEmpty);
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
      expect(
        msg.comment,
        'Message with Motorola (big-endian) byte order signals',
      );
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

    test('accepts message and signal names starting with a digit', () {
      // Real-world DBC files (e.g. mazda_2017.dbc's "2017_5" message and
      // psa_aee2010_r3.dbc's "0_COUNTER" signal in opendbc) contain names
      // that begin with a digit. Cantools accepts these; the tokenizer
      // must too.
      final db = DbcParser().parse('''
VERSION ""
BO_ 1275 2017_5: 8 XXX
 SG_ 0_COUNTER : 4|5@0+ (1,0) [0|255] "" XXX
''');
      expect(db.messages.length, 1);
      final msg = db.messages.first;
      expect(msg.name, '2017_5');
      expect(msg.id, 1275);
      expect(msg.signals.length, 1);
      expect(msg.signals.first.name, '0_COUNTER');
    });

    test('accepts bare "m" multiplexer indicator', () {
      // vw_pq.dbc in opendbc uses bare "m" (no value) for signals whose
      // selector value is defined elsewhere via SG_MUL_VAL_ extended
      // multiplexing. Modelled as multiplexed with a null multiplexValue.
      final db = DbcParser().parse('''
VERSION ""
BO_ 648 Motor_2: 8 Motor
 SG_ MO2_Mp_Code m : 6|2@1+ (1,0) [0|3] "" Gateway
 SG_ MO2_Getr_Code m2 : 0|6@1+ (1,0) [0|63] "" Gateway
''');
      final msg = db.messages.first;
      final bareM = msg.signals.firstWhere((s) => s.name == 'MO2_Mp_Code');
      expect(bareM.multiplexType, MultiplexType.multiplexed);
      expect(bareM.multiplexValue, isNull);

      final m2 = msg.signals.firstWhere((s) => s.name == 'MO2_Getr_Code');
      expect(m2.multiplexType, MultiplexType.multiplexed);
      expect(m2.multiplexValue, 2);
    });

    test('skips canonical NS_ symbol list without mis-dispatching CM_', () {
      // Real-world DBC files exported from Vector CANdb++ emit an NS_
      // section listing every optional symbol the DBC spec defines. Many
      // of those names (NS_DESC_, CM_, BA_DEF_, BA_, VAL_, VAL_TABLE_,
      // BA_DEF_DEF_, SG_MUL_VAL_, SIG_GROUP_, SIG_VALTYPE_, BO_TX_BU_)
      // collide with section starters. A buggy NS_ skipper would return
      // control to the dispatcher mid-list, which would then parse "CM_"
      // as a comment section and consume the BU_/BO_ lines that follow
      // it up to the first semicolon.
      final db = DbcParser().parse('''
VERSION ""


NS_ :
\tNS_DESC_
\tCM_
\tBA_DEF_
\tBA_
\tVAL_
\tCAT_DEF_
\tCAT_
\tFILTER
\tBA_DEF_DEF_
\tEV_DATA_
\tENVVAR_DATA_
\tSGTYPE_
\tSGTYPE_VAL_
\tBA_DEF_SGTYPE_
\tBA_SGTYPE_
\tSIG_TYPE_REF_
\tVAL_TABLE_
\tSIG_GROUP_
\tSIG_VALTYPE_
\tSIGTYPE_VALTYPE_
\tBO_TX_BU_
\tBA_DEF_REL_
\tBA_REL_
\tBA_DEF_DEF_REL_
\tBU_SG_REL_
\tBU_EV_REL_
\tBU_BO_REL_
\tSG_MUL_VAL_

BS_:

BU_: Vector_XXX
VAL_TABLE_ SNA_8bit 255 "SNA" ;

BO_ 100 TestMsg: 1 Vector_XXX
 SG_ TestSig : 0|8@1+ (1,0) [0|255] "-" Vector_XXX

''');
      expect(db.nodes.length, 1);
      expect(db.nodes.first.name, 'Vector_XXX');
      expect(db.messages.length, 1);
      expect(db.messages.first.name, 'TestMsg');
      expect(db.messages.first.signals.first.name, 'TestSig');
    });
  });

  group('DbcParser - full_sections.dbc (coverage of all DBC sections)', () {
    late DbcDatabase db;

    setUpAll(() {
      final content =
          File('test/fixtures/full_sections.dbc').readAsStringSync();
      db = DbcParser().parse(content);
    });

    test('parses bus speed from BS_ section', () {
      expect(db.busSpeed, 500000);
    });

    test('parses BA_DEF_ / BA_DEF_DEF_ / BA_ without error', () {
      // These sections are consumed (skipped to semicolon) — the test
      // validates they don't trip the parser. Attribute values are not
      // yet modelled.
      expect(db.messages, isNotEmpty);
    });

    test('parses VAL_ and attaches value descriptions', () {
      final gear = db.messageById(200)!.signals.firstWhere(
        (s) => s.name == 'Gear',
      );
      expect(gear.valueDescriptions, isNotNull);
      expect(gear.valueDescriptions![0], 'Park');
      expect(gear.valueDescriptions![3], 'Drive');
    });

    test('parses VAL_TABLE_ without error', () {
      expect(db.messages, isNotEmpty);
    });

    test('parses SIG_GROUP_ without error', () {
      expect(db.messages, isNotEmpty);
    });

    test('parses SIG_VALTYPE_ without error', () {
      expect(db.messages, isNotEmpty);
    });

    test('parses BO_TX_BU_ without error', () {
      expect(db.messages, isNotEmpty);
    });

    test('parses global comment (CM_ without qualifier)', () {
      // Global comments are skipped — just must not crash.
      expect(db.messages, isNotEmpty);
    });

    test('parses node comment', () {
      final ecu1 = db.nodes.firstWhere((n) => n.name == 'ECU1');
      expect(ecu1.comment, 'Engine control unit');
    });

    test('parses signed signal correctly', () {
      final temp = db.messageById(100)!.signals.firstWhere(
        (s) => s.name == 'Temp',
      );
      expect(temp.valueType, ValueType.signed);
      expect(temp.offset, -40);
    });
  });

  group('model toString() coverage', () {
    test('DbcDatabase.toString', () {
      final db = DbcDatabase(
        version: '1.0',
        nodes: [DbcNode(name: 'N1')],
        messages: [
          DbcMessage(id: 100, name: 'M1', length: 8, signals: [
            DbcSignal(
              name: 'S1',
              startBit: 0,
              length: 8,
              byteOrder: ByteOrder.littleEndian,
              valueType: ValueType.unsigned,
              factor: 1,
              offset: 0,
              minimum: 0,
              maximum: 255,
              unit: '',
              receivers: [],
            ),
          ]),
        ],
      );
      expect(db.toString(), contains('version=1.0'));
      expect(db.toString(), contains('1 nodes'));
      expect(db.toString(), contains('1 messages'));
      expect(db.toString(), contains('1 signals'));
    });

    test('DbcMessage.toString', () {
      final msg = DbcMessage(id: 0x1FF, name: 'TestMsg', length: 8);
      expect(msg.toString(), contains('1FF'));
      expect(msg.toString(), contains('TestMsg'));
      expect(msg.toString(), contains('dlc=8'));
    });

    test('DbcSignal.toString', () {
      final sig = DbcSignal(
        name: 'RPM',
        startBit: 0,
        length: 16,
        byteOrder: ByteOrder.littleEndian,
        valueType: ValueType.unsigned,
        factor: 0.25,
        offset: 0,
        minimum: 0,
        maximum: 16383.75,
        unit: 'rpm',
        receivers: ['ECU2'],
      );
      expect(sig.toString(), contains('RPM'));
      expect(sig.toString(), contains('LE'));
      expect(sig.toString(), contains('unsigned'));
      expect(sig.toString(), contains('factor=0.25'));
      expect(sig.toString(), contains('rpm'));
    });

    test('DbcSignal.toString for signed BE signal', () {
      final sig = DbcSignal(
        name: 'Temp',
        startBit: 7,
        length: 8,
        byteOrder: ByteOrder.bigEndian,
        valueType: ValueType.signed,
        factor: 1,
        offset: -40,
        minimum: -40,
        maximum: 215,
        unit: 'degC',
        receivers: [],
      );
      expect(sig.toString(), contains('BE'));
      expect(sig.toString(), contains('signed'));
    });

    test('DbcNode.toString', () {
      final node = DbcNode(name: 'ECU1');
      expect(node.toString(), 'DbcNode(ECU1)');
    });

    test('DbcDatabase.messageById returns null for missing ID', () {
      final db = DbcDatabase();
      expect(db.messageById(999), isNull);
    });
  });

  group('DbcParseException', () {
    test('toString includes message, line, and column', () {
      final ex = DbcParseException('bad token', 10, 5);
      expect(ex.toString(), 'DbcParseException: bad token at 10:5');
    });

    test('parser throws DbcParseException on malformed input', () {
      expect(
        () => DbcParser().parse('BO_ notanumber BadMsg: 8 Node'),
        throwsA(
          isA<DbcParseException>().having((e) => e.message, 'message',
              contains('Expected integer')),
        ),
      );
    });
  });

  group('Token toString', () {
    test('formats type, value, and position', () {
      final t = Token(TokenType.keyword, 'VERSION', 1, 1);
      expect(t.toString(), 'Token(TokenType.keyword, "VERSION", 1:1)');
    });
  });

  group('Tokenizer edge cases', () {
    test('scientific notation with explicit sign', () {
      final tokens = DbcTokenizer('1.5E+3 2.0e-1').tokenize();
      expect(tokens[0].type, TokenType.float_);
      expect(tokens[0].value, '1.5E+3');
      expect(tokens[1].type, TokenType.float_);
      expect(tokens[1].value, '2.0e-1');
    });
  });
}
