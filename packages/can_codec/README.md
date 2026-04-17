# can_codec

Protocol-agnostic CAN bus message codec for Dart. Provides bit-level
decoder/encoder with NA/OOR sentinel handling, shared by the `nmea2000`,
`rvc`, and other J1939-family packages.

## Features

- Bit-level field extraction and insertion (little-endian)
- Resolution and offset scaling for physical values
- Signed and unsigned integer fields with two's complement
- Fixed-length ASCII string fields with 0xFF padding
- Lookup fields (enumerated values)
- NA (data not available), OOR (out of range), and reserved sentinel detection
- `MessageDefinition` / `FieldDefinition` schema types
- `TransportType` enum (single, fastPacket, isoTp)
- Backward-compatible `PgnDefinition` and `PgnTransport` aliases

## Usage

### Decode a CAN payload

```dart
import 'dart:typed_data';
import 'package:can_codec/can_codec.dart';

const windDef = MessageDefinition(
  pgn: 130306,
  name: 'Wind Data',
  transport: 0,
  dataLength: 6,
  fields: [
    FieldDefinition(name: 'sid', bitOffset: 0, bitLength: 8),
    FieldDefinition(
      name: 'windSpeed', bitOffset: 8, bitLength: 16, resolution: 0.01),
    FieldDefinition(
      name: 'windAngle', bitOffset: 24, bitLength: 16, resolution: 0.0001),
  ],
);

void main() {
  final data = Uint8List.fromList([42, 0x26, 0x02, 0xAA, 0x1E, 0x00]);
  final fields = decode(data, windDef)!;
  print('Speed: ${fields['windSpeed']} m/s'); // 5.50
  print('Angle: ${fields['windAngle']} rad'); // 0.7850
}
```

### Encode field values

```dart
final payload = encode({
  'sid': 42,
  'windSpeed': 5.50,
  'windAngle': 0.7850,
}, windDef);
// payload is a 6-byte Uint8List, little-endian.
```

### Sentinel handling

```dart
// Fields set to all-bits-1 are omitted from decode output (NA).
// Fields set to all-bits-1 minus 1 decode as double.nan (OOR).
// Missing fields in encode are filled with 0xFF (NA).
```

## Testing

```bash
dart test
```

## License

Apache 2.0 -- see [LICENSE](LICENSE) for details.
