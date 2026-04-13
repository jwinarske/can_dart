## 0.1.1

- Fix DM1 SPN decode bit-shift in FFI layer (was reading wrong 3 bits).
- Add `.clang-format` config for consistent C++ formatting across toolchain versions.
- Add `scripts/clang-format-check.sh` for local pre-commit checking.
- Add library-level and public API doc comments.

## 0.1.0

- Initial release.
- J1939/81 address claiming with configurable NAME fields.
- Single-frame TX/RX via SocketCAN raw sockets.
- BAM (Broadcast Announce Message) transport for payloads > 8 bytes.
- RTS/CTS connection-mode transport for unicast multi-packet messages.
- DM1 active diagnostic trouble code injection and request handling.
- NMEA 2000 Fast Packet reassembly and transmission.
- Runtime PGN transport type registration.
- Zero-copy frame delivery via `Dart_PostCObject_DL` and `ExternalTypedData`.
- Sealed event hierarchy (`J1939Event`) with exhaustive switch support.
- Native asset build hook — `dart pub get` compiles the shared library automatically.
- Two-ECU demo (`dart run j1939`) and load-test node (`dart run j1939:load_node`).
