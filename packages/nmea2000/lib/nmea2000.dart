// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// nmea2000.dart — NMEA 2000 protocol layer on top of package:j1939.
//
// Re-exports the public API surface:
//   • Nmea2000Ecu — wraps J1939Ecu with marine NAME defaults, heartbeat,
//     and mandatory PGN auto-responder.
//   • Nmea2000Registry — PGN definition registry with .register() for
//     per-app extensions.
//   • PgnDefinition / FieldDefinition — field-level PGN schema types.
//   • Decoder / Encoder — raw bytes ↔ named field values.
//   • PgnTransport — Dart mirror of the C++ transport enum.
//   • Mandatory PGN definitions — const definitions for the core set.

export 'src/decoder.dart';
export 'src/encoder.dart';
export 'src/nmea2000_ecu.dart';
export 'src/nmea2000_registry.dart';
export 'src/pgn_definition.dart';
export 'src/pgn_transport.dart';
export 'src/sentinels.dart';
export 'src/pgns/mandatory.dart';
export 'src/pgns/navigation.dart';
export 'src/pgns/wind.dart';
export 'src/pgns/depth_speed.dart';
export 'src/pgns/heading.dart';
export 'src/pgns/rudder.dart';
export 'src/pgns/engine.dart';
export 'src/pgns/electrical.dart';
export 'src/pgns/set_drift.dart';

// Re-export j1939 types consumers will need.
export 'package:j1939/j1939.dart'
    show
        J1939Ecu,
        J1939Event,
        FrameReceived,
        AddressClaimed,
        AddressClaimFailed,
        EcuError,
        Dm1Received,
        Pgn,
        kBroadcast,
        kNullAddress;
