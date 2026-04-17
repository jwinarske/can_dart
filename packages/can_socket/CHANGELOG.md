## 0.1.3

- Add CI coverage for all packages and Flutter examples.
- Add pubspec_overrides.yaml workflow for monorepo development.
## 0.1.2

- Use canonical Apache-2.0 text in LICENSE so pana's SPDX detector recognizes it.

## 0.1.1

- Add README, CHANGELOG, LICENSE, and example for pub.dev.
- Add repository, homepage, and topic metadata to pubspec.

## 0.1.0

- Initial release.
- Raw CAN and CAN FD frame send/receive (`CanSocket`).
- Isolate-based async `frameStream` for non-blocking reception.
- Hardware-level CAN filters (`CanFilter`).
- CAN Broadcast Manager for cyclic TX and content-change RX (`CanBcmSocket`).
- ISO-TP transport for UDS/OBD-II diagnostics (`CanIsotpSocket`).
- SAE J1939 PGN-level socket (`CanJ1939Socket`).
- All Linux SocketCAN constants exported.
