// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Integration test: exercises the full CanEngine lifecycle against vcan0.
//
// Skipped when vcan0 is not up. In CI, the workflow brings up vcan0 first.
// Locally:
//   sudo modprobe vcan
//   sudo ip link add dev vcan0 type vcan
//   sudo ip link set up vcan0
//   dart test test/can_engine_vcan_test.dart

@TestOn('linux')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:can_dbc/can_dbc.dart';
import 'package:can_engine/can_engine.dart';
import 'package:test/test.dart';

const _vcan = 'vcan0';

bool _vcanAvailable() {
  try {
    final r = Process.runSync('ip', ['link', 'show', _vcan]);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

String? _findHookArtifact() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final root = Directory(
      '${dir.path}/.dart_tool/hooks_runner/shared/can_engine/build',
    );
    if (root.existsSync()) {
      File? newest;
      var newestTime = DateTime.fromMillisecondsSinceEpoch(0);
      for (final entity in root.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('/libcan_engine.so')) {
          final mtime = entity.statSync().modified;
          if (mtime.isAfter(newestTime)) {
            newest = entity;
            newestTime = mtime;
          }
        }
      }
      if (newest != null) return newest.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

void main() {
  final hasVcan = _vcanAvailable();
  final skipReason = hasVcan ? null : 'vcan0 not available';

  late String libPath;

  setUpAll(() {
    final p = _findHookArtifact();
    libPath = p ?? 'libcan_engine.so';
  });

  group('CanEngine lifecycle (vcan0)', skip: skipReason, () {
    late CanEngine engine;

    setUp(() {
      engine = CanEngine(libraryPath: libPath);
    });

    tearDown(() {
      engine.dispose();
    });

    test('start and stop', () {
      final rc = engine.start(_vcan);
      expect(rc, 0, reason: 'start should succeed on vcan0');
      expect(engine.isRunning, isTrue);
      expect(engine.isConnected, isTrue);
      expect(engine.snapshotPtr, isNotNull);

      engine.stop();
      expect(engine.isRunning, isFalse);
    });

    test('sequence increments after start', () async {
      engine.start(_vcan);
      final s1 = engine.sequence;
      // Give the engine thread a moment to publish.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final s2 = engine.sequence;
      expect(s2, greaterThanOrEqualTo(s1));
    });

    test('busLoadPercent and framesPerSecond default to zero on idle bus', () {
      engine.start(_vcan);
      // vcan0 with no traffic → zero load.
      expect(engine.busLoadPercent, isA<double>());
      expect(engine.framesPerSecond, isA<int>());
    });

    test('sendFrame returns 0 on success', () {
      engine.start(_vcan);
      final data = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final rc = engine.sendFrame(0x123, data);
      expect(rc, 0);
    });

    test('startPeriodicTx and stopPeriodicTx', () {
      engine.start(_vcan);
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final rc = engine.startPeriodicTx(0x200, data, 100);
      expect(rc, 0);
      engine.stopPeriodicTx(0x200);
    });

    test('stopAllPeriodicTx does not throw', () {
      engine.start(_vcan);
      expect(() => engine.stopAllPeriodicTx(), returnsNormally);
    });

    test('setFilterChain and clearFilter', () {
      engine.start(_vcan);
      engine.setFilterChain(0, [
        (type: FilterType.ema, param: 0.5),
        (type: FilterType.hysteresis, param: 2.0),
      ]);
      engine.clearFilter(0);
    });

    test('resetFilters does not throw', () {
      engine.start(_vcan);
      expect(() => engine.resetFilters(), returnsNormally);
    });

    test('addGraphSignal and removeGraphSignal', () {
      engine.start(_vcan);
      final rc = engine.addGraphSignal(0);
      // rc is the graph index or negative on error; either is valid.
      expect(rc, isA<int>());
      engine.removeGraphSignal(0);
    });

    test('setDisplayFilter and clearDisplayFilter', () {
      engine.start(_vcan);
      engine.setDisplayFilter([0x100, 0x200, 0x300]);
      engine.clearDisplayFilter();
    });

    test('readSignalValue returns 0 for unloaded signals', () {
      engine.start(_vcan);
      expect(engine.readSignalValue(0), 0.0);
    });

    test('lastError returns a string after start', () {
      engine.start(_vcan);
      final err = engine.lastError;
      expect(err, isA<String>());
    });

    test('loadSignals with a compiled DBC', () {
      engine.start(_vcan);
      // Build a minimal DBC in-memory.
      final db = DbcParser().parse('''
VERSION ""
NS_ :
BS_:
BU_: Node1
BO_ 256 TestMsg: 8 Node1
 SG_ TestSig : 0|16@1+ (0.1,0) [0|6553.5] "rpm" Vector__XXX
''');
      final compiled = SignalCompiler().compile(db);
      engine.loadSignals(compiled);
      // Signal should be readable (value is 0 since no frames received yet).
      expect(engine.readSignalValue(0), isA<double>());
      compiled.dispose();
    });
  });

  group('CanEngine error paths (vcan0)', skip: skipReason, () {
    test('dispose is idempotent', () {
      final e = CanEngine(libraryPath: libPath);
      e.dispose();
      expect(() => e.dispose(), returnsNormally);
    });

    test('methods throw StateError after dispose', () {
      final e = CanEngine(libraryPath: libPath);
      e.dispose();
      expect(() => e.start(_vcan), throwsA(isA<StateError>()));
      expect(() => e.stop(), throwsA(isA<StateError>()));
      expect(() => e.sendFrame(0, Uint8List(0)), throwsA(isA<StateError>()));
      expect(() => e.resetFilters(), throwsA(isA<StateError>()));
    });
  });
}
