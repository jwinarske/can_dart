## 0.1.2

- Use canonical Apache-2.0 text in LICENSE so pana's SPDX detector recognizes it.

## 0.1.1

- Add README, CHANGELOG, LICENSE, and example for pub.dev.
- Add repository, homepage, and topic metadata to pubspec.
- Apply clang-format to all C++ sources.

## 0.1.0

- Initial release.
- Zero-copy `DisplaySnapshot` accessible from Dart via `Pointer.ref`.
- Real-time signal decoding from DBC definitions (via `can_dbc`).
- Signal filter chains: EMA, rate limiting, hysteresis.
- Signal graph ring-buffers (1024 points, up to 8 signals).
- Single-frame and periodic CAN transmission.
- ISO-TP segmentation/reassembly for UDS and OBD-II.
- Bus statistics: load %, frames/sec, error counts, uptime.
- Display filtering by CAN ID whitelist.
- Native build hook -- `dart pub get` compiles `libcan_engine.so` via CMake.
