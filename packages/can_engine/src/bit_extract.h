// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include "snapshot.h"
#include <algorithm>
#include <cstdint>

namespace can_engine {

/// Extract a little-endian (Intel) signal from CAN data.
/// start_bit is the LSB position in the data array.
inline uint64_t extract_le(const uint8_t *data, uint16_t start, uint16_t len) {
  uint64_t val = 0;
  for (int i = 0; i < len; ++i) {
    uint16_t bit = start + i;
    if (data[bit >> 3] & (1u << (bit & 7)))
      val |= (1ULL << i);
  }
  return val;
}

/// Extract a big-endian (Motorola) signal from CAN data.
/// start_bit is the MSB position in Motorola bit numbering.
inline uint64_t extract_be(const uint8_t *data, uint16_t start, uint16_t len) {
  uint64_t val = 0;
  int bit_pos = start;
  for (int i = len - 1; i >= 0; --i) {
    if (data[bit_pos >> 3] & (1u << (7 - (bit_pos & 7))))
      val |= (1ULL << i);
    // Motorola bit numbering: within a byte go 7..0,
    // then jump to the next byte's MSB
    if ((bit_pos & 7) == 0)
      bit_pos += 15;
    else
      bit_pos--;
  }
  return val;
}

/// Convert raw extracted bits to a physical value using factor/offset/clamp.
inline double normalize(uint64_t raw, const SignalDef &def) {
  double val;
  if (def.value_type == 1) {
    // Signed: sign-extend
    int64_t sraw = static_cast<int64_t>(raw);
    if (raw & (1ULL << (def.bit_length - 1)))
      sraw |= ~((1ULL << def.bit_length) - 1);
    val = static_cast<double>(sraw);
  } else {
    val = static_cast<double>(raw);
  }
  return std::clamp(val * def.factor + def.offset, def.minimum, def.maximum);
}

/// Apply a filter chain to a signal value in-place.
inline double apply_filters(double value, PerSignalState &state,
                            uint64_t ts_us) {
  for (uint8_t i = 0; i < state.filter_count; ++i) {
    const auto &cfg = state.configs[i];
    switch (cfg.type) {
    case FilterType::Ema:
      value = state.ema[i].update(value, cfg.params.ema.alpha);
      break;
    case FilterType::RateLimit:
      value = state.rate[i].update(
          value, cfg.params.rate_limit.max_rate_per_sec, ts_us);
      break;
    case FilterType::Hysteresis:
      value = state.hyst[i].update(value, cfg.params.hysteresis.deadband);
      break;
    case FilterType::None:
      break;
    }
  }
  return value;
}

} // namespace can_engine
