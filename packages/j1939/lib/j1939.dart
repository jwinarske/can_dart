// j1939.dart — high-level Dart API for the J1939 Linux stack

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate'; // RawReceivePort, SendPort
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/j1939_native.dart';
import 'src/j1939_types.dart';

export 'src/j1939_types.dart';

// ── One-time API initialisation ───────────────────────────────────────────────

bool _apiInitialized = false;

// NativeApi.postCObject is stable in all Dart 3.x versions.
// Cast to Pointer<Void> because the C side receives void* and casts it
// to the matching function pointer type (int8_t(*)(int64_t, Dart_CObject*)).
void _ensureApiInitialized() {
  if (_apiInitialized) return;
  j1939SetPostCObject(NativeApi.postCObject.cast<Void>());
  _apiInitialized = true;
}

// ── J1939Ecu ──────────────────────────────────────────────────────────────────

class J1939Ecu {
  J1939Ecu._(this._handle, this._port, Stream<J1939Event> raw) : _events = raw;

  final Pointer<J1939Handle> _handle;
  final RawReceivePort _port;
  final Stream<J1939Event> _events;
  final _pendingSends = <int, Completer<void>>{};
  int _nextSendId = 0;
  bool _disposed = false;

  // ── Factory ────────────────────────────────────────────────────────────────

  static J1939Ecu create({
    required String ifname,
    required int address,
    required int identityNumber,
    int manufacturerCode = 0x7FF,
    int industryGroup = 0,
  }) {
    _ensureApiInitialized();

    final port = RawReceivePort();
    final controller = StreamController<J1939Event>.broadcast();
    late J1939Ecu ecu;

    port.handler = (dynamic msg) {
      if (msg is! List || msg.isEmpty) return;
      switch (msg[0] as int) {
        case 0:
          controller.add(FrameReceived(
            pgn: msg[1] as int,
            source: msg[2] as int,
            destination: msg[3] as int,
            data: msg[4] as Uint8List,
          ));
        case 1:
          controller.add(AddressClaimed(msg[1] as int));
        case 2:
          controller.add(const AddressClaimFailed());
        case 3:
          controller.add(EcuError(msg[1] as int));
        case 4:
          controller.add(Dm1Received(
            source: msg[1] as int,
            spn: msg[2] as int,
            fmi: msg[3] as int,
            occurrence: msg[4] as int,
          ));
        case 5:
          ecu._completeSend(msg[1] as int, msg[2] as int);
      }
    };

    final ifnameC = ifname.toNativeUtf8();
    final handle = j1939Create(
      ifnameC,
      address,
      identityNumber,
      manufacturerCode,
      industryGroup,
      port.sendPort.nativePort,
    );
    malloc.free(ifnameC);

    if (handle == nullptr) {
      port.close();
      controller.close();
      throw StateError(
          'j1939_create failed on "$ifname": errno ${j1939LastError()}');
    }

    ecu = J1939Ecu._(handle, port, controller.stream);
    return ecu;
  }

  // ── Event streams ──────────────────────────────────────────────────────────

  /// All ECU events: [FrameReceived], [AddressClaimed], [AddressClaimFailed],
  /// [EcuError], [Dm1Received].
  Stream<J1939Event> get events => _events;

  /// Convenience: only received CAN frames.
  ///
  /// [FrameReceived.data] is zero-copy — backed by a C++ pool buffer until
  /// GC'd.  Copy via `Uint8List.fromList(f.data)` to retain beyond the
  /// current event-loop turn.
  Stream<FrameReceived> get frames =>
      _events.where((e) => e is FrameReceived).cast<FrameReceived>();

  /// Convenience: only address-claim events.
  Stream<J1939Event> get addressEvents =>
      _events.where((e) => e is AddressClaimed || e is AddressClaimFailed);

  /// Frames matching a specific PGN.
  Stream<FrameReceived> framesForPgn(int pgn) =>
      frames.where((f) => f.pgn == pgn);

  // ── Transmit ───────────────────────────────────────────────────────────────

  /// Send a J1939 message.
  ///
  /// For single frames (≤ 8 bytes) the future completes synchronously.
  /// For BAM broadcast (> 8 bytes) it completes when the last DT packet is
  /// sent (~N_packets × 50 ms) on the C++ ASIO thread — no Dart isolate.
  ///
  /// Throws [StateError] on failure or if [dispose] was called.
  Future<void> send(
    int pgn, {
    required int priority,
    required int dest,
    required Uint8List data,
  }) {
    if (data.length <= 8) {
      return _sendSync(pgn, priority: priority, dest: dest, data: data);
    }
    return _sendAsync(pgn, priority: priority, dest: dest, data: data);
  }

  Future<void> _sendSync(
    int pgn, {
    required int priority,
    required int dest,
    required Uint8List data,
  }) {
    using((arena) {
      final ptr = arena<Uint8>(data.length);
      ptr.asTypedList(data.length).setAll(0, data);
      final rc = j1939Send(_handle, pgn, priority, dest, ptr, data.length);
      if (rc != 0) {
        throw StateError('j1939_send failed (pgn=0x${pgn.toRadixString(16)}): '
            'errno ${j1939LastError()}');
      }
    });
    return Future<void>.value();
  }

  Future<void> _sendAsync(
    int pgn, {
    required int priority,
    required int dest,
    required Uint8List data,
  }) {
    final sendId = _nextSendId++;
    final completer = Completer<void>();
    _pendingSends[sendId] = completer;

    using((arena) {
      final ptr = arena<Uint8>(data.length);
      ptr.asTypedList(data.length).setAll(0, data);
      j1939SendAsync(_handle, sendId, pgn, priority, dest, ptr, data.length);
    });

    return completer.future;
  }

  void _completeSend(int sendId, int errno) {
    final c = _pendingSends.remove(sendId);
    if (c == null) return;
    if (errno == 0) {
      c.complete();
    } else {
      c.completeError(
          StateError('send_async failed: errno $errno'), StackTrace.current);
    }
  }

  // ── Convenience transmit ───────────────────────────────────────────────────

  /// Send a PGN request (PGN 0xEA00, 3-byte LE payload).
  /// Throws [StateError] on failure.
  void sendRequest(int dest, int requestedPgn) {
    final rc = j1939SendRequest(_handle, dest, requestedPgn);
    if (rc != 0) {
      throw StateError('j1939_send_request failed '
          '(pgn=0x${requestedPgn.toRadixString(16)}): '
          'errno ${j1939LastError()}');
    }
  }

  // ── Diagnostics ────────────────────────────────────────────────────────────

  void addDm1Fault({required int spn, required int fmi, int occurrence = 1}) =>
      j1939AddDm1Fault(_handle, spn, fmi, occurrence);

  void clearDm1Faults() => j1939ClearDm1Faults(_handle);

  // ── State ──────────────────────────────────────────────────────────────────

  int get address => j1939Address(_handle);
  bool get addressClaimed => j1939AddressClaimed(_handle);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Stop C++ threads, close the socket, release all native resources.
  ///
  /// Pending [send] futures are completed with [StateError].
  /// In-flight pool buffers already delivered to Dart remain valid until
  /// their [Uint8List]s are GC'd — C++ finalizers fire correctly.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    j1939Destroy(_handle);
    _port.close();

    final pending = Map<int, Completer<void>>.from(_pendingSends);
    _pendingSends.clear();
    for (final c in pending.values) {
      c.completeError(StateError('J1939Ecu disposed while send was pending'));
    }
  }
}
