## 0.1.3

- Extract codec to shared `package:can_codec`.
- Add CI coverage and pubspec_overrides.yaml workflow.
## 0.1.2

- Use canonical Apache-2.0 text in LICENSE so pana's SPDX detector recognizes it.

## 0.1.1

- Add comprehensive test suite: decoder, encoder, sentinels, PGN definitions,
  registry, Group Function types and codec, and vcan0 integration tests.
- Add README, CHANGELOG, LICENSE, and example for pub.dev.
- Add repository, homepage, and topic metadata to pubspec.

## 0.1.0

- Initial release.
- `Nmea2000Ecu` with marine NAME defaults and automatic heartbeat.
- Mandatory PGN auto-responder (Product Info, Config Info, PGN List).
- Fast Packet transport registration and reassembly.
- Field-level `decode()` and `encode()` with NA/OOR sentinel handling.
- `Nmea2000Registry` with 30+ pre-defined display PGNs.
- Demo executable and multi-device traffic simulator.
