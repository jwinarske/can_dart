import 'dart:ffi';
import 'dart:typed_data';

import 'package:can_socket/can_socket.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:can_socket/src/ffi/structs.dart';

void main() {
  group('CanFrame', () {
    test('constructs standard frame', () {
      final frame = CanFrame(
        id: 0x123,
        data: Uint8List.fromList([0x01, 0x02, 0x03]),
      );

      expect(frame.id, 0x123);
      expect(frame.dlc, 3);
      expect(frame.isExtended, false);
      expect(frame.isRemote, false);
      expect(frame.isError, false);
      expect(frame.isFd, false);
      expect(frame.data, [0x01, 0x02, 0x03]);
    });

    test('constructs extended frame', () {
      final frame = CanFrame(
        id: 0x12345678,
        isExtended: true,
        data: Uint8List.fromList([0xFF]),
      );

      expect(frame.id, 0x12345678);
      expect(frame.isExtended, true);
      expect(frame.rawId, 0x12345678 | canEffFlag);
    });

    test('constructs RTR frame', () {
      final frame = CanFrame(id: 0x100, isRemote: true, data: Uint8List(0));

      expect(frame.isRemote, true);
      expect(frame.rawId, 0x100 | canRtrFlag);
    });

    test('rawId includes all flags', () {
      final frame = CanFrame(
        id: 0x1ABCDEF,
        isExtended: true,
        isRemote: true,
        isError: true,
        data: Uint8List(0),
      );

      expect(frame.rawId & canEffFlag, canEffFlag);
      expect(frame.rawId & canRtrFlag, canRtrFlag);
      expect(frame.rawId & canErrFlag, canErrFlag);
      expect(frame.rawId & canEffMask, 0x1ABCDEF);
    });

    test('round-trips through native can_frame', () {
      final original = CanFrame(
        id: 0x7FF,
        data: Uint8List.fromList([
          0xDE,
          0xAD,
          0xBE,
          0xEF,
          0xCA,
          0xFE,
          0xBA,
          0xBE,
        ]),
      );

      final ptr = calloc<CanFrameNative>();
      original.toNative(ptr);
      final restored = CanFrame.fromNative(ptr.ref);
      calloc.free(ptr);

      expect(restored.id, original.id);
      expect(restored.dlc, original.dlc);
      expect(restored.data, original.data);
      expect(restored.isExtended, original.isExtended);
    });

    test('round-trips extended frame through native', () {
      final original = CanFrame(
        id: 0x1FFFFFFF,
        isExtended: true,
        data: Uint8List.fromList([0x01, 0x02]),
      );

      final ptr = calloc<CanFrameNative>();
      original.toNative(ptr);
      final restored = CanFrame.fromNative(ptr.ref);
      calloc.free(ptr);

      expect(restored.id, original.id);
      expect(restored.isExtended, true);
    });

    test('round-trips through native canfd_frame', () {
      final data = Uint8List(64);
      for (var i = 0; i < 64; i++) {
        data[i] = i;
      }

      final original = CanFrame(id: 0x456, isFd: true, isBrs: true, data: data);

      final ptr = calloc<CanFdFrameNative>();
      original.toFdNative(ptr);
      final restored = CanFrame.fromFdNative(ptr.ref);
      calloc.free(ptr);

      expect(restored.id, original.id);
      expect(restored.dlc, 64);
      expect(restored.isFd, true);
      expect(restored.isBrs, true);
      expect(restored.data, data);
    });

    test('toFdNative zero-fills trailing bytes of short payloads', () {
      // Exercises the zero-fill loop at can_frame.dart:132 — previously
      // uncovered because every canfd roundtrip test used a full 64-byte
      // payload.
      final original = CanFrame(
        id: 0x7EF,
        isFd: true,
        data: Uint8List.fromList([0xAA, 0xBB, 0xCC]),
      );

      final ptr = calloc<CanFdFrameNative>();
      try {
        original.toFdNative(ptr);
        // First three bytes carry the payload.
        expect(ptr.ref.data[0], 0xAA);
        expect(ptr.ref.data[1], 0xBB);
        expect(ptr.ref.data[2], 0xCC);
        // Remaining bytes up to canfdMaxDlc (64) must be zero.
        for (var i = 3; i < 64; i++) {
          expect(ptr.ref.data[i], 0, reason: 'byte $i not zeroed');
        }
      } finally {
        calloc.free(ptr);
      }
    });

    test('toString formats correctly', () {
      final frame = CanFrame(
        id: 0x123,
        data: Uint8List.fromList([0x01, 0x02, 0x03]),
      );
      expect(frame.toString(), '123 [3] 01 02 03');
    });

    test('toString includes flags', () {
      final frame = CanFrame(
        id: 0x123,
        isExtended: true,
        isFd: true,
        isBrs: true,
        data: Uint8List.fromList([0xAB]),
      );
      expect(frame.toString(), contains('EFF'));
      expect(frame.toString(), contains('FD'));
      expect(frame.toString(), contains('BRS'));
    });
  });

  group('CanFilter', () {
    test('exact filter matches standard ID', () {
      final filter = CanFilter.exact(0x123);
      expect(filter.canId, 0x123);
      expect(filter.canMask, 0x7FF);
    });

    test('exactExtended sets EFF flag', () {
      final filter = CanFilter.exactExtended(0x12345);
      expect(filter.canId & canEffFlag, canEffFlag);
    });

    test('passAll has zero mask', () {
      expect(CanFilter.passAll.canMask, 0);
    });

    test('round-trips through native', () {
      final filter = CanFilter(canId: 0x100, canMask: 0x7F0);
      final ptr = calloc<CanFilterNative>();
      filter.toNative(ptr);

      expect(ptr.ref.canId, 0x100);
      expect(ptr.ref.canMask, 0x7F0);

      calloc.free(ptr);
    });

    test('toString formats id + mask as lower-case hex', () {
      final f = CanFilter(canId: 0x7E0, canMask: 0x7F0);
      expect(f.toString(), 'CanFilter(id: 0x7e0, mask: 0x7f0)');
    });
  });

  group('CanSocketException', () {
    test('stores message and errno', () {
      final ex = CanSocketException('bind failed', 19);
      expect(ex.message, 'bind failed');
      expect(ex.errno, 19);
    });

    test('toString includes strerror(errno) from libc', () {
      // ENODEV = 19; strerror typically yields "No such device".
      final ex = CanSocketException('bind failed', 19);
      final s = ex.toString();
      expect(s, startsWith('CanSocketException: bind failed (errno 19:'));
      expect(s.toLowerCase(), contains('no such'));
    });

    test('is an Exception', () {
      expect(CanSocketException('x', 0), isA<Exception>());
    });
  });
}
