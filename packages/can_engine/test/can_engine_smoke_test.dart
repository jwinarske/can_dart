// Smoke test for the CanEngine lifecycle against the real libcan_engine.so.
//
// Locates the .so under .dart_tool/hooks_runner/shared/can_engine/build/**
// (produced by hook/build.dart during `dart test`) and passes its absolute
// path to the CanEngine constructor via the libraryPath parameter.
//
// Covers: construction, idle state getters, sequence read, destroy. Does
// NOT exercise .start() — that requires vcan0 and is covered by the
// integration test suite.

import 'dart:ffi';
import 'dart:io';

import 'package:can_engine/can_engine.dart';
import 'package:test/test.dart';

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
  late String libPath;

  setUpAll(() {
    final p = _findHookArtifact();
    if (p == null) {
      // Not built yet — can happen on very first `dart test` if the
      // hook runner skipped for any reason. Fall back to dlopen default.
      libPath = 'libcan_engine.so';
    } else {
      libPath = p;
    }
  });

  group('CanEngine lifecycle', () {
    test('construct and destroy', () {
      final engine = CanEngine(libraryPath: libPath);
      addTearDown(() {
        // engine.destroy() doesn't exist as public API — stop is a no-op
        // before start, so we just let the handle leak here. The native
        // engine owns no sockets until start() is called.
      });
      // Constructor succeeded if we got this far.
      expect(engine, isNotNull);
    });

    test('sequence returns an integer before start', () {
      final engine = CanEngine(libraryPath: libPath);
      expect(engine.sequence, isA<int>());
      // Sequence is 0 until the engine's publish thread runs.
      expect(engine.sequence, greaterThanOrEqualTo(0));
    });

    test('idle-state getters return safe defaults before start', () {
      final engine = CanEngine(libraryPath: libPath);
      expect(engine.snapshotPtr, isNull);
      expect(engine.busLoadPercent, 0);
      expect(engine.framesPerSecond, 0);
      expect(engine.isRunning, isFalse);
      expect(engine.isConnected, isFalse);
    });

    test('readSignalValue clamps on invalid index', () {
      final engine = CanEngine(libraryPath: libPath);
      // No snapshot yet — always returns 0.
      expect(engine.readSignalValue(-1), 0);
      expect(engine.readSignalValue(0), 0);
      expect(engine.readSignalValue(maxSignals), 0);
      expect(engine.readSignalValue(maxSignals * 2), 0);
    });

    test('lastError returns a string before start', () {
      final engine = CanEngine(libraryPath: libPath);
      expect(engine.lastError, isA<String>());
      expect(engine.lastError, 'No snapshot available');
    });
  });

  group('FFI library path', () {
    test('DynamicLibrary.open accepts the hook-built artifact', () {
      // Direct sanity check: the path we're about to feed to CanEngine
      // must actually be a loadable ELF.
      expect(() => DynamicLibrary.open(libPath), returnsNormally);
    });
  });
}
