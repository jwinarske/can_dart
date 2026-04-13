# can_engine

Zero-copy CAN bus engine with a C++ Asio event loop. Dart reads the shared
`DisplaySnapshot` via `Pointer.ref` -- no marshalling, no copies, no GC
pressure. Designed for real-time dashboards and instrument clusters.

## Features

- **Zero-copy snapshot**: shared memory struct read directly from Dart via FFI
- **Signal decoding**: load DBC definitions via `can_dbc`, decode in real-time
- **Signal filters**: EMA smoothing, rate limiting, hysteresis (chainable, up to 4)
- **Signal graphs**: 1024-point ring-buffer history for up to 8 signals
- **CAN TX**: single-frame and periodic (cyclic) transmission
- **ISO-TP**: segmentation/reassembly for UDS and OBD-II diagnostics
- **Bus statistics**: load %, frames/sec, error counts, uptime, peak values
- **Display filtering**: whitelist CAN IDs for UI-level message tables
- **Native build hook**: `dart pub get` compiles `libcan_engine.so` automatically

## Platform support

| Platform | Status |
|---|---|
| Linux x64 | Supported |
| Linux ARM64 | Supported |
| macOS / Windows | Not supported |

## Getting started

### Prerequisites

- **Dart SDK** >= 3.7.0
- **Linux** with SocketCAN support
- **CMake** >= 3.16 and a C++23 compiler (GCC 13+ or Clang 17+)
- **Ninja** (recommended)

### Install

```yaml
dependencies:
  can_engine: ^0.1.0
  can_dbc: ^0.1.0
```

The native library is compiled automatically by the build hook.

## Usage

### Basic monitoring

```dart
import 'package:can_engine/can_engine.dart';

void main() {
  final engine = CanEngine();

  final rc = engine.start('vcan0');
  if (rc != 0) {
    print('Failed: ${engine.lastError}');
    return;
  }

  print('Running: ${engine.isRunning}');
  print('Bus load: ${engine.busLoadPercent}%');
  print('FPS: ${engine.framesPerSecond}');

  engine.stop();
  engine.dispose();
}
```

### Load signals from a DBC file

```dart
import 'package:can_dbc/can_dbc.dart';
import 'package:can_engine/can_engine.dart';

void main() {
  final engine = CanEngine();
  engine.start('vcan0');

  // Parse and compile a DBC database.
  final dbc = DbcParser().parse(dbcContent);
  final compiled = SignalCompiler().compile(dbc);
  engine.loadSignals(compiled);

  // Read decoded signal values (zero-copy from snapshot).
  final rpm = engine.readSignalValue(0);
  print('RPM: $rpm');

  compiled.dispose();
  engine.dispose();
}
```

### Signal filters

```dart
// Smooth signal 0 with exponential moving average (alpha = 0.3).
engine.setFilterChain(0, [
  (type: FilterType.ema, param: 0.3),
]);

// Chain: smooth then rate-limit.
engine.setFilterChain(1, [
  (type: FilterType.ema, param: 0.5),
  (type: FilterType.rateLimit, param: 100.0),
]);

engine.clearFilter(0);
```

### Send CAN frames

```dart
import 'dart:typed_data';

// Single frame.
engine.sendFrame(0x123, Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]));

// Periodic transmission every 100 ms.
engine.startPeriodicTx(0x200, Uint8List.fromList([1, 2, 3]), 100);
engine.stopPeriodicTx(0x200);
```

### ISO-TP (OBD-II)

```dart
engine.isotpOpen(txId: 0x7E0, rxId: 0x7E8);
engine.isotpSend(Uint8List.fromList([0x01, 0x0C])); // PID: RPM
final response = engine.isotpRecv(timeoutMs: 1000);
engine.isotpClose();
```

### Zero-copy snapshot access

```dart
final ptr = engine.snapshotPtr;
if (ptr != null) {
  final snap = ptr.ref;
  print('Messages: ${snap.messageCount}');
  print('Bus load: ${snap.stats.busLoadPercent}%');
  print('Total frames: ${snap.stats.totalFrames}');
}
```

### Change detection

```dart
var lastSeq = engine.sequence;
// Poll for snapshot changes.
if (engine.sequence != lastSeq) {
  // Snapshot updated -- safe to re-read.
  lastSeq = engine.sequence;
}
```

## Architecture

```
Dart (CanEngine)          C++23 (Asio event loop)
─────────────────         ─────────────────────────
readSignalValue() ──ptr──> DisplaySnapshot (shared memory)
sendFrame()       ──ffi──> CAN socket write
start()/stop()    ──ffi──> I/O thread lifecycle
loadSignals()     ──ffi──> Signal definition table
```

The C++ engine runs on a dedicated thread, owns all I/O and signal decoding,
and publishes a fixed-size pre-allocated snapshot. Dart reads the snapshot
via `Pointer.ref` with no allocations. An atomic sequence counter enables
lock-free change detection.

## Testing

```bash
# Smoke tests (no CAN interface needed)
dart test test/can_engine_smoke_test.dart
dart test test/native_structs_test.dart

# Integration tests (require vcan0)
sudo modprobe vcan && sudo ip link add dev vcan0 type vcan && sudo ip link set up vcan0
dart test test/can_engine_vcan_test.dart
```

## License

Apache 2.0 -- see [LICENSE](LICENSE) for details.
