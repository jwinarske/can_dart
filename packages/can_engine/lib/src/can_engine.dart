import 'dart:ffi';
import 'dart:typed_data';

import 'package:can_dbc/can_dbc.dart';
import 'package:ffi/ffi.dart';

import 'native_structs.dart';

/// FFI bindings to the can_engine C API.
class _EngineBindings {
  final DynamicLibrary _lib;

  _EngineBindings(this._lib);

  // Lifecycle
  late final engineCreate = _lib
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'engine_create',
      );

  late final engineDestroy = _lib.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)
  >('engine_destroy');

  late final engineStart = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Utf8>),
    int Function(Pointer<Void>, Pointer<Utf8>)
  >('engine_start');

  late final engineStop = _lib.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)
  >('engine_stop');

  // Signal database
  late final engineLoadSignals = _lib.lookupFunction<
    Void Function(Pointer<Void>, Pointer<Void>, Uint32, Pointer<Void>, Uint32),
    void Function(Pointer<Void>, Pointer<Void>, int, Pointer<Void>, int)
  >('engine_load_signals');

  // Snapshot
  late final engineSnapshotPtr = _lib.lookupFunction<
    Pointer<Void> Function(Pointer<Void>),
    Pointer<Void> Function(Pointer<Void>)
  >('engine_snapshot_ptr');

  late final engineSequence = _lib.lookupFunction<
    Uint64 Function(Pointer<Void>),
    int Function(Pointer<Void>)
  >('engine_sequence');

  // Filter chain
  late final engineSetFilterChain = _lib.lookupFunction<
    Void Function(Pointer<Void>, Uint32, Pointer<Void>, Uint8),
    void Function(Pointer<Void>, int, Pointer<Void>, int)
  >('engine_set_filter_chain');

  late final engineClearFilter = _lib.lookupFunction<
    Void Function(Pointer<Void>, Uint32),
    void Function(Pointer<Void>, int)
  >('engine_clear_filter');

  late final engineResetFilters = _lib.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)
  >('engine_reset_filters');

  // CAN hardware filters
  late final engineSetCanFilters = _lib.lookupFunction<
    Void Function(Pointer<Void>, Pointer<Void>, Uint32),
    void Function(Pointer<Void>, Pointer<Void>, int)
  >('engine_set_can_filters');

  // TX
  late final engineSendFrame = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Uint32, Pointer<Uint8>, Uint8),
    int Function(Pointer<Void>, int, Pointer<Uint8>, int)
  >('engine_send_frame');

  late final engineStartPeriodicTx = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Uint32, Pointer<Uint8>, Uint8, Uint32),
    int Function(Pointer<Void>, int, Pointer<Uint8>, int, int)
  >('engine_start_periodic_tx');

  late final engineStopPeriodicTx = _lib.lookupFunction<
    Void Function(Pointer<Void>, Uint32),
    void Function(Pointer<Void>, int)
  >('engine_stop_periodic_tx');

  late final engineStopAllPeriodicTx = _lib.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)
  >('engine_stop_all_periodic_tx');

  // Signal graphs
  late final engineAddGraphSignal = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Uint32),
    int Function(Pointer<Void>, int)
  >('engine_add_graph_signal');

  late final engineRemoveGraphSignal = _lib.lookupFunction<
    Void Function(Pointer<Void>, Uint32),
    void Function(Pointer<Void>, int)
  >('engine_remove_graph_signal');

  // Display filter
  late final engineSetDisplayFilter = _lib.lookupFunction<
    Void Function(Pointer<Void>, Pointer<Uint32>, Uint32),
    void Function(Pointer<Void>, Pointer<Uint32>, int)
  >('engine_set_display_filter');

  late final engineClearDisplayFilter = _lib.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)
  >('engine_clear_display_filter');

  // ISO-TP
  late final engineIsotpOpen = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Uint32, Uint32),
    int Function(Pointer<Void>, int, int)
  >('engine_isotp_open');

  late final engineIsotpClose = _lib.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)
  >('engine_isotp_close');

  late final engineIsotpSend = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32),
    int Function(Pointer<Void>, Pointer<Uint8>, int)
  >('engine_isotp_send');

  late final engineIsotpRecv = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Int32),
    int Function(Pointer<Void>, Pointer<Uint8>, int, int)
  >('engine_isotp_recv');
}

/// Filter types matching C++ FilterType enum.
enum FilterType { none, ema, rateLimit, hysteresis }

/// Zero-copy CAN engine.
///
/// Wraps the native C++ engine that owns the entire CAN pipeline:
/// socket I/O, signal decode, filter chain, and snapshot publish.
///
/// Dart reads the [DisplaySnapshotNative] via [Pointer.ref] — a direct
/// memory dereference with no copy and no GC involvement.
class CanEngine {
  late final _EngineBindings _bindings;
  Pointer<Void> _handle = nullptr;
  Pointer<DisplaySnapshotNative>? _snapshotPtr;
  bool _destroyed = false;

  /// Create a new engine instance.
  ///
  /// [libraryPath] is the path or filename of the libcan_engine.so shared
  /// library. Defaults to `'libcan_engine.so'`, which uses the system's
  /// dynamic linker search order: `LD_LIBRARY_PATH`, `/etc/ld.so.cache`,
  /// then default library paths.
  CanEngine({String libraryPath = 'libcan_engine.so'}) {
    final lib = DynamicLibrary.open(libraryPath);
    _bindings = _EngineBindings(lib);
    _handle = _bindings.engineCreate();
  }

  /// Load signal definitions from a compiled DBC database.
  void loadSignals(CompiledSignalDb db) {
    _checkValid();
    _bindings.engineLoadSignals(
      _handle,
      db.signalDefs.cast(),
      db.signalCount,
      db.messageDefs.cast(),
      db.messageCount,
    );
  }

  /// Start the engine on the given CAN interface (e.g., "can0", "vcan0").
  ///
  /// Returns 0 on success, negative on error.
  /// On failure, [lastError] contains the error message from the engine.
  int start(String interfaceName) {
    _checkValid();
    final namePtr = interfaceName.toNativeUtf8();
    try {
      final result = _bindings.engineStart(_handle, namePtr);
      final ptr = _bindings.engineSnapshotPtr(_handle);
      _snapshotPtr = ptr.cast<DisplaySnapshotNative>();
      return result;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Read the last error message from the engine snapshot.
  String get lastError {
    if (_snapshotPtr == null) return 'No snapshot available';
    final bytes = <int>[];
    for (var i = 0; i < 128; i++) {
      final b = _snapshotPtr!.ref.errorMsg[i];
      if (b == 0) break;
      bytes.add(b);
    }
    return bytes.isEmpty ? 'Unknown error' : String.fromCharCodes(bytes);
  }

  /// Stop the engine.
  void stop() {
    _checkValid();
    _bindings.engineStop(_handle);
    _snapshotPtr = null;
  }

  /// Get the current sequence number (for change detection).
  ///
  /// This is a leaf call — no GC safepoint.
  int get sequence {
    _checkValid();
    return _bindings.engineSequence(_handle);
  }

  /// Direct pointer to the display snapshot.
  ///
  /// Dart reads this via Pointer.ref — one instruction, no copy.
  /// Returns null if the engine hasn't been started.
  Pointer<DisplaySnapshotNative>? get snapshotPtr => _snapshotPtr;

  /// Read a signal value directly from the snapshot (zero-copy).
  double readSignalValue(int index) {
    if (_snapshotPtr == null || index < 0 || index >= maxSignals) return 0;
    return _snapshotPtr!.ref.signals[index].value;
  }

  /// Read bus load percentage from the snapshot.
  double get busLoadPercent {
    if (_snapshotPtr == null) return 0;
    return _snapshotPtr!.ref.stats.busLoadPercent;
  }

  /// Read frames per second from the snapshot.
  int get framesPerSecond {
    if (_snapshotPtr == null) return 0;
    return _snapshotPtr!.ref.stats.framesPerSecond;
  }

  /// Whether the engine is currently running.
  bool get isRunning {
    if (_snapshotPtr == null) return false;
    return _snapshotPtr!.ref.running != 0;
  }

  /// Whether the engine is connected to a CAN interface.
  bool get isConnected {
    if (_snapshotPtr == null) return false;
    return _snapshotPtr!.ref.connected != 0;
  }

  // ── Filter chain ──

  /// Set a filter chain on a signal.
  void setFilterChain(
    int signalIndex,
    List<({FilterType type, double param})> filters,
  ) {
    _checkValid();
    final ptr = calloc<FilterConfigNative>(filters.length);
    try {
      for (var i = 0; i < filters.length; i++) {
        (ptr + i).ref.type = filters[i].type.index;
        (ptr + i).ref.param = filters[i].param;
      }
      _bindings.engineSetFilterChain(
        _handle,
        signalIndex,
        ptr.cast(),
        filters.length,
      );
    } finally {
      calloc.free(ptr);
    }
  }

  /// Clear filters on a signal.
  void clearFilter(int signalIndex) {
    _checkValid();
    _bindings.engineClearFilter(_handle, signalIndex);
  }

  /// Reset all filters.
  void resetFilters() {
    _checkValid();
    _bindings.engineResetFilters(_handle);
  }

  // ── TX ──

  /// Send a single CAN frame.
  int sendFrame(int canId, Uint8List data) {
    _checkValid();
    final ptr = calloc<Uint8>(data.length);
    try {
      for (var i = 0; i < data.length; i++) {
        ptr[i] = data[i];
      }
      return _bindings.engineSendFrame(_handle, canId, ptr, data.length);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Start periodic transmission.
  int startPeriodicTx(int canId, Uint8List data, int intervalMs) {
    _checkValid();
    final ptr = calloc<Uint8>(data.length);
    try {
      for (var i = 0; i < data.length; i++) {
        ptr[i] = data[i];
      }
      return _bindings.engineStartPeriodicTx(
        _handle,
        canId,
        ptr,
        data.length,
        intervalMs,
      );
    } finally {
      calloc.free(ptr);
    }
  }

  /// Stop periodic transmission for a CAN ID.
  void stopPeriodicTx(int canId) {
    _checkValid();
    _bindings.engineStopPeriodicTx(_handle, canId);
  }

  /// Stop all periodic transmissions.
  void stopAllPeriodicTx() {
    _checkValid();
    _bindings.engineStopAllPeriodicTx(_handle);
  }

  // ── Signal graphs ──

  /// Add a signal to the graph tracking.
  int addGraphSignal(int signalIndex) {
    _checkValid();
    return _bindings.engineAddGraphSignal(_handle, signalIndex);
  }

  /// Remove a signal from graph tracking.
  void removeGraphSignal(int signalIndex) {
    _checkValid();
    _bindings.engineRemoveGraphSignal(_handle, signalIndex);
  }

  // ── Display filter ──

  /// Set display filter to only show specific CAN IDs in append mode.
  void setDisplayFilter(List<int> passIds) {
    _checkValid();
    final ptr = calloc<Uint32>(passIds.length);
    try {
      for (var i = 0; i < passIds.length; i++) {
        ptr[i] = passIds[i];
      }
      _bindings.engineSetDisplayFilter(_handle, ptr, passIds.length);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Clear the display filter (show all CAN IDs).
  void clearDisplayFilter() {
    _checkValid();
    _bindings.engineClearDisplayFilter(_handle);
  }

  // ── ISO-TP (ISO 15765-2) ──

  /// Open an ISO-TP channel with the given TX and RX CAN IDs.
  ///
  /// For OBD-II: txId=0x7E0, rxId=0x7E8 (or 0x7DF for broadcast).
  /// The kernel handles segmentation and reassembly transparently.
  /// Returns 0 on success, negative on error (check [lastError]).
  int isotpOpen({required int txId, required int rxId}) {
    _checkValid();
    return _bindings.engineIsotpOpen(_handle, txId, rxId);
  }

  /// Close the ISO-TP channel.
  void isotpClose() {
    _checkValid();
    _bindings.engineIsotpClose(_handle);
  }

  /// Send an ISO-TP PDU. The kernel handles multi-frame segmentation.
  ///
  /// Returns the number of bytes sent, or negative on error.
  int isotpSend(Uint8List data) {
    _checkValid();
    final ptr = calloc<Uint8>(data.length);
    try {
      for (var i = 0; i < data.length; i++) {
        ptr[i] = data[i];
      }
      return _bindings.engineIsotpSend(_handle, ptr, data.length);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Receive a reassembled ISO-TP PDU.
  ///
  /// [timeoutMs] sets the timeout in milliseconds (-1 for blocking).
  /// Returns the received data, or empty on timeout.
  Uint8List isotpRecv({int timeoutMs = 1000}) {
    _checkValid();
    const maxPduSize = 4095; // ISO-TP max
    final buf = calloc<Uint8>(maxPduSize);
    try {
      final nbytes = _bindings.engineIsotpRecv(
        _handle,
        buf,
        maxPduSize,
        timeoutMs,
      );
      if (nbytes <= 0) return Uint8List(0);
      final result = Uint8List(nbytes);
      for (var i = 0; i < nbytes; i++) {
        result[i] = buf[i];
      }
      return result;
    } finally {
      calloc.free(buf);
    }
  }

  /// Destroy the engine and free native resources.
  void dispose() {
    if (_destroyed) return;
    _destroyed = true;
    _bindings.engineDestroy(_handle);
    _handle = nullptr;
    _snapshotPtr = null;
  }

  void _checkValid() {
    if (_destroyed) throw StateError('CanEngine has been disposed');
  }
}
