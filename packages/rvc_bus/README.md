# rvc_bus

RV-C bus topology tracker and device registry. Attaches to an `RvcEcu`
event stream, auto-discovers devices via Address Claimed frames, maps
RV-C device function codes to human-readable names, and exposes a
reactive `Stream<RvcBusEvent>`.

## Features

- **Auto-discovery**: detects new devices as they claim addresses
- **Device function lookup**: maps RV-C function codes to names (Generator, Battery Charger, Inverter, Tank Sensor, etc.)
- **Online/offline tracking**: configurable timeouts with reactive events
- **Sealed event hierarchy**: exhaustive `switch` over all bus event types

## Getting started

```yaml
dependencies:
  rvc_bus: ^0.1.0
```

Requires a running `RvcEcu` from `package:rvc`.

## Usage

### Discover devices

```dart
import 'package:rvc_bus/rvc_bus.dart';

// Attach to a running RvcEcu.
final registry = RvcBusRegistry(ecu);

registry.events.listen((event) => switch (event) {
  RvcDeviceAppeared(:final device) =>
    print('New: ${device.name.deviceTypeName} at 0x${device.address.toRadixString(16)}'),
  RvcDeviceDisappeared(:final address) =>
    print('Gone: 0x${address.toRadixString(16)}'),
  RvcDeviceWentOffline(:final address) =>
    print('Offline: 0x${address.toRadixString(16)}'),
  RvcDeviceCameOnline(:final device) =>
    print('Online: 0x${device.address.toRadixString(16)}'),
});
```

### Query the registry

```dart
for (final device in registry.onlineDevices) {
  print('0x${device.address.toRadixString(16)}: ${device.name.deviceTypeName}');
}
```

## Bus event types

| Event | When |
|---|---|
| `RvcDeviceAppeared` | New source address seen |
| `RvcDeviceWentOffline` | No frames within timeout |
| `RvcDeviceCameOnline` | Previously offline device resumes |
| `RvcDeviceDisappeared` | Device removed after extended silence |

## Testing

```bash
dart test
```

## License

Apache 2.0 -- see [LICENSE](LICENSE) for details.
