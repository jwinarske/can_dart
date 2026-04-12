// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';

/// Max lengths matching can_engine C++ definitions.
const maxNameLen = 64;
const maxUnitLen = 16;

/// Native signal definition matching can_engine::SignalDef.
///
/// ```cpp
/// struct SignalDef {
///     uint16_t start_bit;
///     uint16_t bit_length;
///     uint8_t  byte_order;     // 0=LE 1=BE
///     uint8_t  value_type;     // 0=unsigned 1=signed
///     uint8_t  _pad[2];
///     double   factor, offset, minimum, maximum;
///     char     name[MAX_NAME_LEN];
///     char     unit[MAX_UNIT_LEN];
/// };
/// ```
final class SignalDefNative extends Struct {
  @Uint16()
  external int startBit;

  @Uint16()
  external int bitLength;

  @Uint8()
  external int byteOrder; // 0=LE, 1=BE

  @Uint8()
  external int valueType; // 0=unsigned, 1=signed

  @Uint8()
  external int pad0;

  @Uint8()
  external int pad1;

  @Double()
  external double factor;

  @Double()
  external double offset;

  @Double()
  external double minimum;

  @Double()
  external double maximum;

  @Array(64) // MAX_NAME_LEN
  external Array<Uint8> name;

  @Array(16) // MAX_UNIT_LEN
  external Array<Uint8> unit;
}

/// Native message definition matching can_engine::MessageDef.
///
/// ```cpp
/// struct MessageDef {
///     uint32_t can_id;
///     uint32_t signal_offset;
///     uint32_t signal_count;
/// };
/// ```
final class MessageDefNative extends Struct {
  @Uint32()
  external int canId;

  @Uint32()
  external int signalOffset;

  @Uint32()
  external int signalCount;
}
