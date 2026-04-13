# j1939

A Dart package for the **SAE J1939** vehicle-bus protocol on Linux SocketCAN.
Provides address claiming, multi-packet transport (BAM and RTS/CTS), DM1
diagnostics, and NMEA 2000 Fast Packet support — all driven from idiomatic
async Dart with zero-copy frame delivery.

Built as a Dart FFI bridge over a C++23 engine that handles the
real-time socket I/O, protocol state machines, and transport-layer
reassembly on dedicated threads, posting events to Dart via
`Dart_PostCObject_DL`.

## Features

| Feature | Description |
|---|---|
| **Address claiming** | J1939/81 state machine with configurable NAME fields |
| **Single-frame TX/RX** | Standard 8-byte CAN frames with priority and destination |
| **BAM transport** | Broadcast Announce Message for payloads > 8 bytes (async, non-blocking) |
| **RTS/CTS transport** | Connection-mode transfer for unicast multi-packet messages |
| **DM1 diagnostics** | Inject and request active diagnostic trouble codes |
| **NMEA 2000 Fast Packet** | Reassembly and transmission of Fast Packet PGNs |
| **PGN transport registry** | Runtime registration of PGN transport types |
| **Zero-copy frames** | `Uint8List` backed by C++ pool buffers — no copies until you need one |
| **Sealed event hierarchy** | Exhaustive `switch` over all event types (Dart 3.0+) |
| **Native asset hook** | `dart pub get` compiles the shared library automatically via CMake |

## Platform support

| Platform | Status |
|---|---|
| Linux (SocketCAN) | Supported |
| macOS / Windows | Not supported (no SocketCAN) |

Requires a CAN interface (physical or virtual). For development and testing,
`vcan` (virtual CAN) works without hardware.

## Prerequisites

- **Dart SDK** >= 3.0.0
- **Linux** with SocketCAN support
- **CMake** >= 3.16 and a C++23 compiler (GCC 13+ or Clang 17+)
- **Ninja** (recommended) or Make

## Getting started

### 1. Add the dependency

```yaml
dependencies:
  j1939: ^0.1.0
```

### 2. Set up a virtual CAN interface (for development)

```bash
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0
```

### 3. Build and run

The native library is compiled automatically by the build hook during
`dart pub get`. No manual CMake invocation required.

```bash
dart pub get
dart run j1939          # two-ECU demo on vcan0
```

## Usage

### Create an ECU and listen for events

```dart
import 'package:j1939/j1939.dart';

void main() async {
  final ecu = J1939Ecu.create(
    ifname: 'vcan0',
    address: 0x80,
    identityNumber: 0x1234,
  );

  // Wait for address claiming to complete.
  final claim = await ecu.events
      .where((e) => e is AddressClaimed)
      .cast<AddressClaimed>()
      .first
      .timeout(const Duration(milliseconds: 400));
  print('Claimed address: 0x${claim.address.toRadixString(16)}');

  // Listen for all incoming frames.
  ecu.frames.listen((frame) {
    print('PGN=0x${frame.pgn.toRadixString(16)} '
        'from=0x${frame.source.toRadixString(16)} '
        'len=${frame.data.length}');
  });

  // Send a single-frame message.
  await ecu.send(
    Pgn.proprietaryA,
    priority: 6,
    dest: 0xFF, // broadcast
    data: Uint8List.fromList([0x01, 0x02, 0x03]),
  );

  // Clean up when done.
  ecu.dispose();
}
```

### Exhaustive event handling

The event hierarchy is a sealed class, so the compiler verifies you handle
every case:

```dart
ecu.events.listen((event) => switch (event) {
  FrameReceived(:final pgn, :final data) => handleFrame(pgn, data),
  AddressClaimed(:final address)         => print('claimed $address'),
  AddressClaimFailed()                   => print('claim failed'),
  EcuError(:final errorCode)             => print('errno $errorCode'),
  Dm1Received(:final spn, :final fmi)    => handleFault(spn, fmi),
});
```

### Multi-packet BAM (> 8 bytes)

Large payloads are transmitted automatically via BAM. The returned future
completes when the last data-transfer packet is sent on the C++ ASIO thread.
The Dart event loop is never blocked.

```dart
final payload = Uint8List.fromList(List.generate(25, (i) => i));
await ecu.send(Pgn.softwareId, priority: 6, dest: kBroadcast, data: payload);
```

### DM1 diagnostics

```dart
// Inject a fault on this ECU.
ecu.addDm1Fault(spn: 100, fmi: 1, occurrence: 1);

// Request DM1 from another ECU.
ecu.sendRequest(0xA0, Pgn.dm1);

// Listen for DM1 events from the bus.
ecu.events
    .where((e) => e is Dm1Received)
    .cast<Dm1Received>()
    .listen((dm1) {
  print('Fault from 0x${dm1.source.toRadixString(16)}: '
      'SPN=${dm1.spn} FMI=${dm1.fmi}');
});
```

### NMEA 2000 ECU with full NAME fields

```dart
final ecu = J1939Ecu.createFull(
  ifname: 'can0',
  address: 0x80,
  identityNumber: 0x1234,
  manufacturerCode: 0x1FF,
  industryGroup: 4,       // Marine
  deviceFunction: 130,    // Display
  deviceClass: 120,       // Display
  functionInstance: 0,
  ecuInstance: 0,
);
```

### Register Fast Packet PGNs

```dart
// Register a PGN as Fast Packet transport (NMEA 2000).
J1939Ecu.setPgnTransport(129029, 1); // GNSS Position Data
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Dart (j1939.dart)                              │
│  ┌───────────┐  ┌────────────┐  ┌───────────┐  │
│  │ J1939Ecu  │  │  Sealed    │  │  Stream   │  │
│  │ .create() │  │  Events    │  │  filters  │  │
│  └─────┬─────┘  └──────▲─────┘  └───────────┘  │
│        │ FFI           │ Dart_PostCObject_DL     │
├────────┼───────────────┼────────────────────────┤
│  C++23 │ (j1939_ffi)   │                        │
│  ┌─────▼─────┐  ┌──────┴─────┐  ┌───────────┐  │
│  │    Ecu    │  │  RX thread │  │   ASIO    │  │
│  │  (mutex)  ├──┤  (poll)    │  │  thread   │  │
│  └─────┬─────┘  └──────┬─────┘  └─────┬─────┘  │
│        │        ┌──────┴─────┐        │         │
│        │        │ Transport  │   BAM strand     │
│        │        │ BAM/RTS/FP │        │         │
│  ┌─────▼────────┴────────────┴────────▼─────┐   │
│  │          SocketCAN (raw socket)           │   │
│  └───────────────────┬───────────────────────┘   │
└──────────────────────┼───────────────────────────┘
                       │
              ┌────────▼────────┐
              │  CAN interface  │
              │  (vcan0, can0)  │
              └─────────────────┘
```

**Control plane** (Dart → C++): synchronous FFI calls protected by a mutex.

**Event plane** (C++ → Dart): asynchronous posting via `Dart_PostCObject_DL`
on the RX thread. Frame payloads use `ExternalTypedData` for zero-copy
delivery — the `Uint8List` points directly into a C++ pool buffer until
the GC collects it.

## Executables

The package includes two command-line tools:

```bash
dart run j1939              # Two-ECU demo with frame logging
dart run j1939:load_node    # Configurable load-test node
```

`load_node` accepts CLI flags for address, interface, TX rate, BAM period,
DM1 period, and peer count — useful for stress testing the stack.

## Testing

```bash
# Dart unit tests (pure — no CAN interface needed)
dart test test/j1939_types_test.dart

# Integration tests (require vcan0)
sudo modprobe vcan && sudo ip link add dev vcan0 type vcan && sudo ip link set up vcan0
dart test test/j1939_vcan_test.dart

# C++ unit tests (optional, requires -DJ1939_BUILD_TESTING=ON)
cmake -S . -B build-test -GNinja -DJ1939_BUILD_TESTING=ON
cmake --build build-test
ctest --test-dir build-test --output-on-failure
```

## Zero-copy frame data

`FrameReceived.data` is a `Uint8List` backed by a C++ pool buffer via
`ExternalTypedData`. No bytes are copied during delivery. The C++ finalizer
reclaims the buffer when Dart's GC collects the list.

If you need the data to outlive the current event-loop turn (e.g. storing
it in a collection), copy it:

```dart
final safe = Uint8List.fromList(frame.data);
```

## Third-party licenses

See [THIRD_PARTY.md](THIRD_PARTY.md) for licenses of bundled dependencies
(Standalone Asio, GoogleTest).

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.
