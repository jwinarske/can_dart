## 0.1.1

- Add test suite: N2kName 64-bit encoding/decoding with bit-position
  verification, ProductInfo decoding, and sealed BusEvent hierarchy tests.
- Add README, CHANGELOG, LICENSE, and example for pub.dev.
- Add repository, homepage, and topic metadata to pubspec.

## 0.1.0

- Initial release.
- `BusRegistry` for automatic NMEA 2000 device discovery.
- Auto-requests Product Information (PGN 126996) and PGN List (PGN 126464).
- Online/offline tracking with configurable timeouts.
- Address claim conflict detection.
- Sealed `BusEvent` hierarchy with six event types.
- `DeviceInfo` with NAME decoding, product info, and TX/RX PGN lists.
