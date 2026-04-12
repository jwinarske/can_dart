// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Pure-Dart tests for native_structs.dart and the FilterType enum.
//
// These tests exercise the FFI struct layout (via calloc + field roundtrip)
// and the public constants. They do NOT load libcan_engine.so — that is
// covered by vcan0-gated integration tests once the native test harness
// lands.

import 'dart:ffi';

import 'package:can_engine/can_engine.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

void main() {
  group('size constants', () {
    // These constants must stay in lockstep with the C++ side. If you
    // change them here, update include/can_engine.h and vice versa; these
    // assertions exist to make drift loud.
    test('constants match the C++ defines', () {
      expect(maxFrames, 200);
      expect(maxMessages, 512);
      expect(maxSignals, 256);
      expect(maxTextLen, 128);
      expect(maxNameLen, 64);
      expect(maxUnitLen, 16);
      expect(maxValLen, 32);
      expect(maxGraphPoints, 1024);
      expect(maxGraphSignals, 8);
      expect(maxFilters, 4);
    });
  });

  group('FilterType enum', () {
    test('index values match C++ FilterType', () {
      // The engine uses FilterType.index over FFI (via
      // FilterConfigNative.type). If anyone reorders this enum, runtime
      // behaviour breaks silently — so pin the ordering with indices.
      expect(FilterType.none.index, 0);
      expect(FilterType.ema.index, 1);
      expect(FilterType.rateLimit.index, 2);
      expect(FilterType.hysteresis.index, 3);
    });

    test('values covers the full enum', () {
      expect(FilterType.values, hasLength(4));
    });
  });

  group('SignalSnapshotNative layout', () {
    test('roundtrips scalar fields', () {
      final p = calloc<SignalSnapshotNative>();
      try {
        p.ref
          ..value = 42.5
          ..minDef = -10.0
          ..maxDef = 100.0
          ..changed = 1
          ..valid = 1;
        expect(p.ref.value, 42.5);
        expect(p.ref.minDef, -10.0);
        expect(p.ref.maxDef, 100.0);
        expect(p.ref.changed, 1);
        expect(p.ref.valid, 1);
      } finally {
        calloc.free(p);
      }
    });

    test('name array length is MAX_NAME_LEN', () {
      final p = calloc<SignalSnapshotNative>();
      try {
        // Write 64 bytes; read back the last one to confirm the array
        // is exactly that long and accessible.
        for (var i = 0; i < maxNameLen; i++) {
          p.ref.name[i] = i & 0xFF;
        }
        expect(p.ref.name[0], 0);
        expect(p.ref.name[maxNameLen - 1], (maxNameLen - 1) & 0xFF);
      } finally {
        calloc.free(p);
      }
    });
  });

  group('FrameRowNative layout', () {
    test('roundtrips scalar fields', () {
      final p = calloc<FrameRowNative>();
      try {
        p.ref
          ..canId = 0x18EEFF00
          ..dlc = 8
          ..direction = 1
          ..timestampUs = 0xDEADBEEFCAFEBABE;
        expect(p.ref.canId, 0x18EEFF00);
        expect(p.ref.dlc, 8);
        expect(p.ref.direction, 1);
        expect(p.ref.timestampUs, 0xDEADBEEFCAFEBABE);
      } finally {
        calloc.free(p);
      }
    });
  });

  group('MessageRowNative layout', () {
    test('roundtrips all scalar fields', () {
      final p = calloc<MessageRowNative>();
      try {
        p.ref
          ..canId = 0x7DF
          ..dlc = 8
          ..direction = 0
          ..timestampUs = 1000
          ..count = 42
          ..periodUs = 100000
          ..highlight = 1;
        expect(p.ref.canId, 0x7DF);
        expect(p.ref.dlc, 8);
        expect(p.ref.direction, 0);
        expect(p.ref.timestampUs, 1000);
        expect(p.ref.count, 42);
        expect(p.ref.periodUs, 100000);
        expect(p.ref.highlight, 1);
      } finally {
        calloc.free(p);
      }
    });

    test('data and dataHex arrays are at their declared lengths', () {
      final p = calloc<MessageRowNative>();
      try {
        for (var i = 0; i < 64; i++) {
          p.ref.data[i] = 0xAA;
        }
        for (var i = 0; i < 192; i++) {
          p.ref.dataHex[i] = 0x55;
        }
        expect(p.ref.data[63], 0xAA);
        expect(p.ref.dataHex[191], 0x55);
      } finally {
        calloc.free(p);
      }
    });
  });

  group('GraphPointNative layout', () {
    test('roundtrips value + timestamp', () {
      final p = calloc<GraphPointNative>();
      try {
        p.ref
          ..value = 3.14159
          ..timestampUs = 1_700_000_000_000_000;
        expect(p.ref.value, 3.14159);
        expect(p.ref.timestampUs, 1_700_000_000_000_000);
      } finally {
        calloc.free(p);
      }
    });
  });

  group('SignalGraphNative layout', () {
    test('ring-buffer metadata fields roundtrip', () {
      final p = calloc<SignalGraphNative>();
      try {
        p.ref
          ..signalIndex = 5
          ..head = 100
          ..count = 200;
        expect(p.ref.signalIndex, 5);
        expect(p.ref.head, 100);
        expect(p.ref.count, 200);
      } finally {
        calloc.free(p);
      }
    });
  });

  group('BusStatisticsNative layout', () {
    test('roundtrips every scalar field', () {
      final p = calloc<BusStatisticsNative>();
      try {
        p.ref
          ..busLoadPercent = 27.5
          ..framesPerSecond = 1000
          ..dataBytesPerSecond = 8000
          ..errorFrames = 5
          ..overrunCount = 0
          ..controllerState = 0
          ..txErrorCount = 2
          ..rxErrorCount = 3
          ..totalFrames = 1_000_000
          ..totalTxFrames = 500_000
          ..totalRxFrames = 500_000
          ..totalErrorFrames = 10
          ..totalBytes = 8_000_000
          ..uptimeUs = 60_000_000
          ..peakBusLoad = 45.5
          ..peakFps = 1500;
        expect(p.ref.busLoadPercent, 27.5);
        expect(p.ref.framesPerSecond, 1000);
        expect(p.ref.dataBytesPerSecond, 8000);
        expect(p.ref.errorFrames, 5);
        expect(p.ref.overrunCount, 0);
        expect(p.ref.controllerState, 0);
        expect(p.ref.txErrorCount, 2);
        expect(p.ref.rxErrorCount, 3);
        expect(p.ref.totalFrames, 1_000_000);
        expect(p.ref.totalTxFrames, 500_000);
        expect(p.ref.totalRxFrames, 500_000);
        expect(p.ref.totalErrorFrames, 10);
        expect(p.ref.totalBytes, 8_000_000);
        expect(p.ref.uptimeUs, 60_000_000);
        expect(p.ref.peakBusLoad, 45.5);
        expect(p.ref.peakFps, 1500);
      } finally {
        calloc.free(p);
      }
    });
  });

  group('LogStateNative layout', () {
    test('roundtrips state + counters', () {
      final p = calloc<LogStateNative>();
      try {
        p.ref
          ..active = 1
          ..loggedFrames = 12345
          ..fileSizeBytes = 67890;
        expect(p.ref.active, 1);
        expect(p.ref.loggedFrames, 12345);
        expect(p.ref.fileSizeBytes, 67890);
      } finally {
        calloc.free(p);
      }
    });
  });

  group('DisplaySnapshotNative layout', () {
    test('top-level scalar fields roundtrip', () {
      final p = calloc<DisplaySnapshotNative>();
      try {
        p.ref
          ..sequence = 0xCAFEBABEDEADBEEF
          ..messageCount = 10
          ..frameHead = 5
          ..frameCount = 7
          ..signalCount = 20
          ..graphCount = 3
          ..running = 1
          ..connected = 1
          ..errorCode = 0;
        expect(p.ref.sequence, 0xCAFEBABEDEADBEEF);
        expect(p.ref.messageCount, 10);
        expect(p.ref.frameHead, 5);
        expect(p.ref.frameCount, 7);
        expect(p.ref.signalCount, 20);
        expect(p.ref.graphCount, 3);
        expect(p.ref.running, 1);
        expect(p.ref.connected, 1);
        expect(p.ref.errorCode, 0);
      } finally {
        calloc.free(p);
      }
    });

    test('contained arrays are indexable at their declared size', () {
      final p = calloc<DisplaySnapshotNative>();
      try {
        // Touch the last element of each fixed-size inner array. If the
        // Dart FFI Array<T> generator got a length wrong, these will
        // either trap or read garbage past the end.
        p.ref.messages[maxMessages - 1].canId = 0x7EF;
        expect(p.ref.messages[maxMessages - 1].canId, 0x7EF);

        p.ref.frames[maxFrames - 1].canId = 0x7FF;
        expect(p.ref.frames[maxFrames - 1].canId, 0x7FF);

        p.ref.signals[maxSignals - 1].value = 99.5;
        expect(p.ref.signals[maxSignals - 1].value, 99.5);

        p.ref.graphs[maxGraphSignals - 1].signalIndex = 7;
        expect(p.ref.graphs[maxGraphSignals - 1].signalIndex, 7);
      } finally {
        calloc.free(p);
      }
    });
  });

  group('FilterConfigNative layout', () {
    test('roundtrips type + param', () {
      final p = calloc<FilterConfigNative>();
      try {
        p.ref
          ..type = FilterType.ema.index
          ..param = 0.25;
        expect(p.ref.type, 1);
        expect(p.ref.param, 0.25);
      } finally {
        calloc.free(p);
      }
    });
  });
}
