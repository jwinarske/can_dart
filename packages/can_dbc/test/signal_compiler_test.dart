import 'dart:ffi';
import 'dart:io';

import 'package:can_dbc/can_dbc.dart';
import 'package:test/test.dart';

void main() {
  group('SignalCompiler', () {
    late DbcDatabase db;
    late CompiledSignalDb compiled;

    setUpAll(() {
      final content = File('test/fixtures/example.dbc').readAsStringSync();
      db = DbcParser().parse(content);
      compiled = SignalCompiler().compile(db);
    });

    tearDownAll(() {
      compiled.dispose();
    });

    test('compiles correct signal count', () {
      expect(compiled.signalCount, db.signalCount);
      expect(compiled.signalCount, 10);
    });

    test('compiles correct message count', () {
      expect(compiled.messageCount, 3);
    });

    test('signal defs have correct data', () {
      // First signal is EngineSpeed from message 100
      final sig = compiled.signalDefs.ref;
      expect(sig.startBit, 0);
      expect(sig.bitLength, 16);
      expect(sig.byteOrder, 0); // LE
      expect(sig.valueType, 0); // unsigned
      expect(sig.factor, 0.25);
      expect(sig.offset, 0);
      expect(sig.minimum, 0);
      expect(sig.maximum, 16383.75);
    });

    test('signal name is written correctly', () {
      final sig = compiled.signalDefs.ref;
      // Read name bytes
      final nameBytes = <int>[];
      for (var i = 0; i < 64; i++) {
        final b = sig.name[i];
        if (b == 0) break;
        nameBytes.add(b);
      }
      final name = String.fromCharCodes(nameBytes);
      expect(name, 'EngineSpeed');
    });

    test('signal unit is written correctly', () {
      final sig = compiled.signalDefs.ref;
      final unitBytes = <int>[];
      for (var i = 0; i < 16; i++) {
        final b = sig.unit[i];
        if (b == 0) break;
        unitBytes.add(b);
      }
      final unit = String.fromCharCodes(unitBytes);
      expect(unit, 'rpm');
    });

    test('message defs have correct data', () {
      // First message is EngineData (ID 100) with 4 signals
      final msg = compiled.messageDefs.ref;
      expect(msg.canId, 100);
      expect(msg.signalOffset, 0);
      expect(msg.signalCount, 4);
    });

    test('second message def has correct offset', () {
      final msg = (compiled.messageDefs + 1).ref;
      expect(msg.canId, 200);
      expect(msg.signalOffset, 4); // After 4 signals from EngineData
      expect(msg.signalCount, 2);
    });

    test('third message def has correct offset', () {
      final msg = (compiled.messageDefs + 2).ref;
      expect(msg.canId, 300);
      expect(msg.signalOffset, 6); // After 4+2 signals
      expect(msg.signalCount, 4);
    });

    test('signed signal is compiled correctly', () {
      // EngineTemp is the second signal (index 1)
      final sig = (compiled.signalDefs + 1).ref;
      expect(sig.startBit, 16);
      expect(sig.bitLength, 8);
      expect(sig.valueType, 1); // signed
      expect(sig.offset, -40);
    });

    test('compile empty database', () {
      final emptyDb = DbcDatabase();
      final emptyCompiled = SignalCompiler().compile(emptyDb);
      expect(emptyCompiled.signalCount, 0);
      expect(emptyCompiled.messageCount, 0);
      emptyCompiled.dispose();
    });
  });
}
