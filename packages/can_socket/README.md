# can_socket

Pure Dart FFI bindings for Linux SocketCAN. Provides raw CAN, CAN FD, BCM
(Broadcast Manager), ISO-TP, and J1939 socket access via direct `libc` calls
-- no native plugin compilation required.

## Features

| Socket type | Class | Description |
|---|---|---|
| **CAN_RAW** | `CanSocket` | Standard CAN and CAN FD frame send/receive |
| **CAN_BCM** | `CanBcmSocket` | Kernel-level cyclic TX and content-change RX filtering |
| **CAN_ISOTP** | `CanIsotpSocket` | ISO 15765-2 transport (segmentation/reassembly for UDS/OBD-II) |
| **CAN_J1939** | `CanJ1939Socket` | SAE J1939 PGN-level communication with transparent segmentation |

Additional capabilities:

- CAN FD (flexible data-rate) frames up to 64 bytes
- Hardware-level CAN filters (`CanFilter`)
- Isolate-based async `frameStream` for non-blocking reception
- Loopback and error-mask configuration
- All Linux SocketCAN constants exported for advanced use

## Platform support

| Platform | Status |
|---|---|
| Linux (SocketCAN) | Supported |
| macOS / Windows | Not supported (no SocketCAN) |

## Getting started

### Prerequisites

- **Dart SDK** >= 3.7.0
- **Linux** with SocketCAN support
- A CAN interface (physical or virtual)

### Set up a virtual CAN interface

```bash
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0
```

### Install

```yaml
dependencies:
  can_socket: ^0.1.0
```

## Usage

### Send and receive CAN frames

```dart
import 'dart:typed_data';
import 'package:can_socket/can_socket.dart';

void main() {
  final socket = CanSocket('vcan0');

  // Send a standard CAN frame.
  socket.send(CanFrame(
    id: 0x123,
    data: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
  ));

  // Blocking receive with timeout.
  final frame = socket.receive(timeoutMs: 1000);
  if (frame != null) {
    print('Received: $frame');
  }

  socket.close();
}
```

### Async frame stream

```dart
final socket = CanSocket('vcan0');
final sub = socket.frameStream.listen((frame) {
  print('${frame.id.toRadixString(16)}: ${frame.data}');
});

await Future.delayed(const Duration(seconds: 5));
await sub.cancel();
socket.close();
```

### Hardware filters

```dart
final socket = CanSocket('vcan0');
// Only receive CAN IDs 0x200 and 0x300.
socket.setFilters([
  CanFilter.exact(0x200),
  CanFilter.exact(0x300),
]);
```

### CAN FD

```dart
final socket = CanSocket('vcan0', canFd: true);
socket.send(CanFrame(
  id: 0x456,
  isFd: true,
  isBrs: true,
  data: Uint8List(64),
));
```

### BCM cyclic transmission

```dart
final bcm = CanBcmSocket('vcan0');
bcm.txSetup(BcmTxConfig(
  canId: 0x100,
  frames: [CanFrame(id: 0x100, data: Uint8List.fromList([1, 2, 3]))],
  ival2Us: 100000, // 100 ms interval
));
// Kernel sends the frame every 100 ms until stopped.
bcm.txDelete(0x100);
bcm.close();
```

### ISO-TP (UDS / OBD-II)

```dart
final isotp = CanIsotpSocket('vcan0', txId: 0x7E0, rxId: 0x7E8);
isotp.send(Uint8List.fromList([0x22, 0xF1, 0x86])); // ReadDataByIdentifier
final response = isotp.receive(timeoutMs: 5000);
print('Response: $response');
isotp.close();
```

### J1939

```dart
final j1939 = CanJ1939Socket('vcan0',
    name: 0x123456789ABCDEF0, pgn: 0xF004, addr: 0x00);
j1939.send(
  Uint8List.fromList([0x01, 0x02]),
  destAddr: 0x01,
  destPgn: 0xF004,
);
final (:data, :srcAddr, :pgn) = j1939.receive(timeoutMs: 1000);
j1939.close();
```

## Testing

```bash
# Set up vcan0 first (see above), then:
dart test
```

## License

Apache 2.0 -- see [LICENSE](LICENSE) for details.
