# rvc

RV-C (Recreation Vehicle CAN) protocol layer for Dart, built on top of
`package:j1939`. Provides `RvcEcu` with RV-C NAME defaults, DGN
definitions for common RV subsystems, and command/status helpers.

## Features

- **RvcEcu**: J1939 ECU with RV-C industry group defaults
- **RvcRegistry**: pre-loaded with standard RV-C DGN definitions
- **DGN categories**: DC power, tanks, HVAC, lighting, generator, charger, inverter, date/time/alarm
- **Command helpers**: `sendCommand()` and `sendCommandFields()` for DGN command pairs
- **Shared codec**: uses `package:can_codec` for bit-level encode/decode

## Platform support

| Platform | Status |
|---|---|
| Linux (SocketCAN) | Supported |
| macOS / Windows | Not supported |

## Getting started

```yaml
dependencies:
  rvc: ^0.1.0
```

Requires a CAN interface (physical or virtual) and the j1939 native library.

## Usage

### Query the DGN registry

```dart
import 'package:rvc/rvc.dart';

void main() {
  final registry = RvcRegistry.standard();
  print('${registry.dgnNumbers.length} DGNs loaded');

  final dgn = registry.lookup(0x1FFAD); // DC_SOURCE_STATUS_1
  if (dgn != null) {
    print('${dgn.name}: ${dgn.fields.length} fields');
  }
}
```

### Decode an RV-C frame

```dart
import 'package:can_codec/can_codec.dart';
import 'package:rvc/rvc.dart';

void decodeFrame(int dgn, Uint8List data) {
  final registry = RvcRegistry.standard();
  final def = registry.lookup(dgn);
  if (def != null) {
    final fields = decode(data, def);
    print('$fields');
  }
}
```

## Executables

```bash
dart run rvc:rvc_demo    # RV-C node demo
dart run rvc:rv_sim      # RV system simulator
```

## Testing

```bash
dart test
```

## License

Apache 2.0 -- see [LICENSE](LICENSE) for details.
