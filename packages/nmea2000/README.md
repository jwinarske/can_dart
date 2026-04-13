# nmea2000

NMEA 2000 marine protocol layer for Dart, built on top of `package:j1939`.
Provides an `Nmea2000Ecu` with marine NAME defaults, mandatory PGN
auto-responder, heartbeat, Fast Packet transport, and a field-level
codec with NA/OOR sentinel handling.

## Features

- **Marine ECU**: `Nmea2000Ecu` with industry group 4, display defaults, automatic heartbeat
- **Auto-responder**: handles ISO Requests for Product Info, Config Info, and PGN List
- **Fast Packet**: automatic reassembly and transmission of multi-frame PGNs
- **Field-level codec**: `decode()` and `encode()` with resolution, offset, and sentinels
- **PGN registry**: 30+ pre-defined display PGNs (navigation, wind, heading, engine, electrical)
- **Extensible**: register custom PGN definitions at runtime
- **Sealed events**: same exhaustive `switch` support as `package:j1939`

## Platform support

| Platform | Status |
|---|---|
| Linux (SocketCAN) | Supported |
| macOS / Windows | Not supported |

## Getting started

### Prerequisites

- **Dart SDK** >= 3.0.0
- **Linux** with SocketCAN and a CAN interface (physical or virtual)
- CMake >= 3.16 and a C++23 compiler (required by the `j1939` dependency)

### Install

```yaml
dependencies:
  nmea2000: ^0.1.0
```

### Virtual CAN setup

```bash
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0
```

## Usage

### Create an NMEA 2000 display node

```dart
import 'package:nmea2000/nmea2000.dart';

void main() async {
  final ecu = await Nmea2000Ecu.create(
    ifname: 'vcan0',
    address: 0x80,
    modelId: 'My Display',
    softwareVersion: '1.0.0',
  );

  print('Claimed: 0x${ecu.address.toRadixString(16)}');
  // Heartbeat and auto-responder are already running.

  ecu.dispose();
}
```

### Decode received PGN fields

```dart
ecu.framesForPgn(130306).listen((frame) {
  final fields = decode(frame.data, windDataPgn);
  if (fields != null) {
    final speed = fields['windSpeed'] as double; // m/s
    final angle = fields['windAngle'] as double; // radians
    print('Wind: ${speed.toStringAsFixed(1)} m/s @ '
        '${(angle * 180 / 3.14159).toStringAsFixed(0)} deg');
  }
});
```

### Encode and send a PGN

```dart
final data = encode({
  'sid': 42,
  'windSpeed': 5.5,
  'windAngle': 0.785,
  'reference': 2,
}, windDataPgn);

await ecu.send(130306, priority: 6, dest: kBroadcast, data: data);
```

### Exhaustive event handling

```dart
ecu.events.listen((event) => switch (event) {
  FrameReceived(:final pgn, :final data) =>
    print('PGN 0x${pgn.toRadixString(16)} len=${data.length}'),
  AddressClaimed(:final address) =>
    print('Claimed 0x${address.toRadixString(16)}'),
  AddressClaimFailed() => print('Claim failed'),
  EcuError(:final errorCode) => print('Error: $errorCode'),
  Dm1Received(:final spn, :final fmi) => print('DM1 $spn/$fmi'),
});
```

### Register custom PGNs

```dart
final registry = Nmea2000Registry.standard()
  ..register([
    PgnDefinition(
      pgn: 65280,
      name: 'Proprietary',
      transport: 0,
      dataLength: 8,
      fields: [
        FieldDefinition(
          name: 'value',
          bitOffset: 0,
          bitLength: 32,
          resolution: 0.1,
          type: FieldType.unsigned,
        ),
      ],
    ),
  ]);

final ecu = await Nmea2000Ecu.create(
  ifname: 'vcan0',
  address: 0x80,
  registry: registry,
);
```

### Full NAME field control

```dart
final ecu = await Nmea2000Ecu.create(
  ifname: 'can0',
  address: 0x80,
  identityNumber: 0x1234,
  manufacturerCode: 0x1FF,
  deviceClass: 120,    // Display
  deviceFunction: 130, // Display
);
```

## Pre-defined PGN categories

| Category | PGNs | Examples |
|---|---|---|
| Mandatory | 5 | Heartbeat, Product Info, Config Info, ISO Ack/Request |
| Navigation | 5 | Position, COG/SOG, GNSS, Time & Date, Distance Log |
| Wind | 1 | Wind Data |
| Heading | 3 | Vessel Heading, Rate of Turn, Magnetic Variation |
| Depth/Speed | 2 | Water Depth, Speed Water Referenced |
| Rudder | 1 | Rudder |
| Engine | 3 | Engine Params Rapid, Engine Params Dynamic, Transmission |
| Electrical | 2 | Battery Status, Fluid Level |
| Set & Drift | 1 | Set & Drift Rapid Update |

## Executables

```bash
dart run nmea2000:demo                          # NMEA 2000 display node
dart run nmea2000:marine_sim --scenario=coastal_cruise  # traffic simulator
```

## Testing

```bash
dart test
```

## License

Apache 2.0 -- see [LICENSE](LICENSE) for details.
