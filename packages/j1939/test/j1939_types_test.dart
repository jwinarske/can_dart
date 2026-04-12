// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Pure-Dart tests for lib/src/j1939_types.dart.
//
// Intentionally does NOT import package:j1939/j1939.dart — that barrel pulls
// in j1939_native.dart which eagerly opens libj1939_plugin.so at static-init
// time. These tests import the types file directly so they can run on any
// host without the native plugin being built.

import 'dart:typed_data';

import 'package:j1939/src/j1939_types.dart';
import 'package:test/test.dart';

void main() {
  group('Pgn constants', () {
    test('match the values in j1939/Types.hpp', () {
      expect(Pgn.proprietaryA, 0xEF00);
      expect(Pgn.proprietaryB, 0xFF00);
      expect(Pgn.addressClaimed, 0xEE00);
      expect(Pgn.requestPgn, 0xEA00);
      expect(Pgn.dm1, 0xFECA);
      expect(Pgn.softwareId, 0xFEDA);
    });
  });

  group('top-level address constants', () {
    test('kBroadcast == 0xFF', () => expect(kBroadcast, 0xFF));
    test('kNullAddress == 0xFE', () => expect(kNullAddress, 0xFE));
  });

  group('FrameReceived', () {
    final frame = FrameReceived(
      pgn: 0xEF00,
      source: 0xA0,
      destination: 0xB0,
      data: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
    );

    test('stores fields verbatim', () {
      expect(frame.pgn, 0xEF00);
      expect(frame.source, 0xA0);
      expect(frame.destination, 0xB0);
      expect(frame.data, [0xDE, 0xAD, 0xBE, 0xEF]);
    });

    test('toString renders hex with zero padding and length', () {
      expect(
        frame.toString(),
        'FrameReceived(pgn=0x0EF00 sa=0xA0 da=0xB0 len=4)',
      );
    });

    test('is a J1939Event subtype (sealed hierarchy)', () {
      expect(frame, isA<J1939Event>());
    });

    test('pads single-hex-digit source/destination to two chars', () {
      final f = FrameReceived(
        pgn: 0x00,
        source: 0x01,
        destination: 0x0F,
        data: Uint8List(0),
      );
      expect(f.toString(), 'FrameReceived(pgn=0x00000 sa=0x01 da=0x0F len=0)');
    });
  });

  group('AddressClaimed', () {
    test('stores address and renders hex', () {
      const e = AddressClaimed(0xA0);
      expect(e.address, 0xA0);
      expect(e.toString(), 'AddressClaimed(0xA0)');
    });

    test('single-digit address is zero-padded', () {
      const e = AddressClaimed(0x7);
      expect(e.toString(), 'AddressClaimed(0x07)');
    });

    test('const constructor', () {
      const a = AddressClaimed(0x10);
      const b = AddressClaimed(0x10);
      expect(identical(a, b), isTrue,
          reason: 'const AddressClaimed should canonicalise');
    });
  });

  group('AddressClaimFailed', () {
    test('toString is stable', () {
      expect(const AddressClaimFailed().toString(), 'AddressClaimFailed()');
    });

    test('const instances canonicalise', () {
      const a = AddressClaimFailed();
      const b = AddressClaimFailed();
      expect(identical(a, b), isTrue);
    });
  });

  group('EcuError', () {
    test('stores errno and renders it', () {
      const e = EcuError(19);
      expect(e.errorCode, 19);
      expect(e.toString(), 'EcuError(errno=19)');
    });
  });

  group('Dm1Received', () {
    test('stores all four fields', () {
      const e = Dm1Received(source: 0xA0, spn: 100, fmi: 1, occurrence: 2);
      expect(e.source, 0xA0);
      expect(e.spn, 100);
      expect(e.fmi, 1);
      expect(e.occurrence, 2);
    });

    test('toString formats source as hex', () {
      const e = Dm1Received(source: 0xA0, spn: 100, fmi: 1, occurrence: 2);
      expect(e.toString(), 'Dm1Received(sa=0xa0 spn=100 fmi=1 occ=2)');
    });
  });

  group('sealed hierarchy exhaustive switch', () {
    // Every member of the sealed hierarchy should be dispatchable from a
    // single exhaustive switch. This compiles only if every subclass is
    // named — if a new subclass is added without updating this test, the
    // compiler will fail and so will the test.
    String classify(J1939Event e) => switch (e) {
          FrameReceived() => 'frame',
          AddressClaimed() => 'claimed',
          AddressClaimFailed() => 'failed',
          EcuError() => 'error',
          Dm1Received() => 'dm1',
        };

    test('all subclasses reachable', () {
      final samples = <J1939Event>[
        FrameReceived(pgn: 0, source: 0, destination: 0, data: Uint8List(0)),
        const AddressClaimed(1),
        const AddressClaimFailed(),
        const EcuError(1),
        const Dm1Received(source: 0, spn: 0, fmi: 0, occurrence: 0),
      ];
      expect(
        samples.map(classify).toList(),
        ['frame', 'claimed', 'failed', 'error', 'dm1'],
      );
    });
  });
}
