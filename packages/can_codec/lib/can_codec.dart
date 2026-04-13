// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// can_codec.dart — Protocol-agnostic CAN bus message codec.
//
// Re-exports the public API surface:
//   • MessageDefinition / FieldDefinition — field-level message schema types.
//   • decode / encode — raw bytes ↔ named field values.
//   • TransportType — single / fastPacket / isoTp transport enum.
//   • Sentinel helpers — NA / OOR / reserved bit-pattern detection.

import 'src/message_definition.dart';
import 'src/transport_type.dart';

export 'src/message_definition.dart';
export 'src/decoder.dart';
export 'src/encoder.dart';
export 'src/sentinels.dart';
export 'src/transport_type.dart';

// Backward-compatible aliases for nmea2000 package migration.
typedef PgnDefinition = MessageDefinition;
typedef PgnTransport = TransportType;
