# nmea2000_bus

NMEA 2000 bus topology tracker and device registry. Attaches to an
`Nmea2000Ecu` event stream, auto-discovers devices via Address Claimed
frames, requests Product Information and PGN Lists, and exposes a
reactive `Stream<BusEvent>` for Flutter/Dart binding.

## Features

- **Auto-discovery**: detects new devices as they claim addresses
- **Product info**: automatically requests PGN 126996 and 126464 from new devices
- **Online/offline tracking**: configurable timeouts with reactive events
- **Address claim conflicts**: detects and reports NAME arbitration conflicts
- **Sealed event hierarchy**: exhaustive `switch` over all six bus event types
- **Device registry**: queryable map of all known devices with full metadata

## Getting started

```yaml
dependencies:
  nmea2000_bus: ^0.1.0
```

Requires a running `Nmea2000Ecu` from `package:nmea2000`.

## Usage

### Attach to an ECU and discover devices

```dart
import 'package:nmea2000/nmea2000.dart';
import 'package:nmea2000_bus/nmea2000_bus.dart';

void main() async {
  final ecu = await Nmea2000Ecu.create(
    ifname: 'vcan0',
    address: 0x20,
    modelId: 'Bus Monitor',
    softwareVersion: '1.0.0',
  );

  final registry = BusRegistry(ecu);

  registry.events.listen((event) => switch (event) {
    DeviceAppeared(:final device) =>
      print('New: ${device.productInfo?.modelId ?? "unknown"} '
          'at 0x${device.address.toRadixString(16)}'),
    DeviceDisappeared(:final address) =>
      print('Gone: 0x${address.toRadixString(16)}'),
    DeviceInfoUpdated(:final device) =>
      print('Updated: ${device.productInfo?.modelId}'),
    DeviceWentOffline(:final address) =>
      print('Offline: 0x${address.toRadixString(16)}'),
    DeviceCameOnline(:final device) =>
      print('Online: 0x${device.address.toRadixString(16)}'),
    ClaimConflict(:final address, :final winner, :final loser) =>
      print('Conflict at 0x${address.toRadixString(16)}: '
          '$winner beat $loser'),
  });

  // Let it run...
  await Future.delayed(const Duration(minutes: 5));
  registry.dispose();
  ecu.dispose();
}
```

### Query the device registry

```dart
// All known devices.
final all = registry.devices; // Map<int, DeviceInfo>

// Only online devices.
for (final device in registry.onlineDevices) {
  print('0x${device.address.toRadixString(16)}: '
      '${device.name.industryGroupName} '
      '${device.productInfo?.modelId ?? "?"}');
}

// Lookup by address.
final gps = registry[0x42];
if (gps != null) {
  print('TX PGNs: ${gps.transmitPgns}');
  print('RX PGNs: ${gps.receivePgns}');
}
```

### Custom timeouts

```dart
final registry = BusRegistry(
  ecu,
  offlineTimeout: const Duration(seconds: 60),
  removeTimeout: const Duration(minutes: 10),
);
```

### Flutter integration

```dart
StreamBuilder<BusEvent>(
  stream: registry.events,
  builder: (context, snapshot) {
    final devices = registry.onlineDevices.toList();
    return ListView.builder(
      itemCount: devices.length,
      itemBuilder: (context, i) {
        final d = devices[i];
        return ListTile(
          title: Text(d.productInfo?.modelId ?? 'Unknown'),
          subtitle: Text(
            '0x${d.address.toRadixString(16)} '
            '(${d.name.industryGroupName})',
          ),
        );
      },
    );
  },
)
```

## Bus event types

| Event | When |
|---|---|
| `DeviceAppeared` | New source address seen for the first time |
| `DeviceInfoUpdated` | Product info or PGN list received for a device |
| `DeviceWentOffline` | No frames received within `offlineTimeout` |
| `DeviceCameOnline` | Previously offline device sends a frame |
| `DeviceDisappeared` | Device removed after `removeTimeout` |
| `ClaimConflict` | Two NAMEs compete for the same address |

## License

Apache 2.0 -- see [LICENSE](LICENSE) for details.
