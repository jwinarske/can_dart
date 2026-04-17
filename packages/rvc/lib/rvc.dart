// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// rvc.dart — RV-C (Recreation Vehicle CAN) protocol layer on top of
// package:j1939.
//
// Re-exports the public API surface:
//   - RvcEcu — wraps J1939Ecu with RV-C NAME defaults.
//   - RvcRegistry — DGN definition registry with .register() for extensions.
//   - MessageDefinition / FieldDefinition — field-level DGN schema types.
//   - Decoder / Encoder — raw bytes <-> named field values.
//   - DGN definitions — const definitions for the standard RV-C set.

// Re-export codec types for consumers.
export 'package:can_codec/can_codec.dart';

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

export 'src/rvc_ecu.dart';
export 'src/rvc_registry.dart';
export 'src/dgns/charger.dart';
export 'src/dgns/datetime_alarm.dart';
export 'src/dgns/dc_power.dart';
export 'src/dgns/generator.dart';
export 'src/dgns/hvac.dart';
export 'src/dgns/inverter.dart';
export 'src/dgns/lighting.dart';
export 'src/dgns/tanks.dart';
