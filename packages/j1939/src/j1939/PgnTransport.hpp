// Copyright 2024 can_dart Contributors
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <cstdint>

namespace j1939 {

enum class PgnTransport : uint8_t { single = 0, fast_packet = 1, iso_tp = 2 };

// Thread-safe PGN transport lookup. The read path (pgn_transport) uses a
// shared lock since it is called on every received frame. The write path
// (set_pgn_transport) uses an exclusive lock and is only called at startup
// from Dart.

PgnTransport pgn_transport(uint32_t pgn);
void set_pgn_transport(uint32_t pgn, PgnTransport transport);

} // namespace j1939
