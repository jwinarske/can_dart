## 0.1.3

- Add README, CHANGELOG, LICENSE, and example for pub.dev.
- Add repository, homepage, and topic metadata to pubspec.
- Add unit tests: decode/encode round trips, sentinels, type aliases.

## 0.1.0

- Initial release.
- Extracted from `package:nmea2000` as a protocol-agnostic codec.
- `MessageDefinition` and `FieldDefinition` schema types.
- Bit-level `decode()` and `encode()` with little-endian byte order.
- NA/OOR/reserved sentinel detection and handling.
- `TransportType` enum (single, fastPacket, isoTp).
- Backward-compatible `PgnDefinition` and `PgnTransport` aliases.
