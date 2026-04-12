// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

#include <algorithm>

#include "FastPacket.hpp"

namespace j1939::fast_packet {

// ── Sender ──────────────────────────────────────────────────────────────────

void Sender::set_own_address(Address /*a*/) noexcept {
  // Reserved for future per-address sequence tracking.
}

std::expected<void, std::string_view>
Sender::send(uint32_t pgn, Priority priority, Address dest, Address sa,
             std::span<const uint8_t> data) {
  std::lock_guard lock{mutex_};

  if (data.empty() || data.size() > kMaxPayload) {
    return std::unexpected(
        std::string_view{"FastPacket: payload size must be in [1, 223]"});
  }

  const auto total_len = static_cast<uint8_t>(data.size());
  const Id can_id = Id::from_pgn(pgn, priority, dest, sa);
  const auto encoded_id = can_id.encode();

  const uint8_t seq_bits = static_cast<uint8_t>(sequence_counter_ << 5U);

  // ── Frame 0: [seq<<5 | 0x00] [totalLen] [up to 6 data bytes] ────────
  {
    can::RawFrame f{};
    f.id = encoded_id;
    f.dlc = 8U;
    f.data[0] = seq_bits; // frame counter = 0
    f.data[1] = total_len;
    const size_t first_chunk = std::min<size_t>(6U, data.size());
    for (size_t i = 0U; i < 6U; ++i) {
      // NOLINTNEXTLINE(cppcoreguidelines-pro-bounds-constant-array-index)
      f.data[2U + i] = (i < first_chunk) ? data[i] : 0xFFU;
    }
    if (!socket_->send(f)) {
      return std::unexpected(
          std::string_view{"FastPacket: frame 0 send failed"});
    }
  }

  // ── Frames 1..N: [seq<<5 | frameCounter] [up to 7 data bytes] ───────
  size_t offset = 6U;
  uint8_t frame_counter = 1U;

  while (offset < data.size()) {
    can::RawFrame f{};
    f.id = encoded_id;
    f.dlc = 8U;
    f.data[0] = static_cast<uint8_t>(seq_bits | (frame_counter & 0x1FU));
    const size_t remaining = data.size() - offset;
    const size_t chunk = std::min<size_t>(7U, remaining);
    for (size_t i = 0U; i < 7U; ++i) {
      // NOLINTNEXTLINE(cppcoreguidelines-pro-bounds-constant-array-index)
      f.data[1U + i] = (i < chunk) ? data[offset + i] : 0xFFU;
    }
    if (!socket_->send(f)) {
      return std::unexpected(
          std::string_view{"FastPacket: subsequent frame send failed"});
    }
    offset += chunk;
    ++frame_counter;
  }

  // Advance 3-bit sequence counter (wraps 0-7).
  sequence_counter_ = static_cast<uint8_t>((sequence_counter_ + 1U) & 0x07U);

  return {};
}

// ── Receiver ────────────────────────────────────────────────────────────────

void Receiver::on_frame(const Id &id, std::span<const uint8_t> data) {
  if (data.empty()) {
    return;
  }

  const uint8_t byte0 = data[0];
  const uint8_t seq = static_cast<uint8_t>((byte0 >> 5U) & 0x07U);
  const uint8_t frame_counter = static_cast<uint8_t>(byte0 & 0x1FU);
  const uint32_t pgn = id.pgn();
  const SessionKey key = make_key(id.sa, pgn);

  if (frame_counter == 0U) {
    // ── First frame of a new Fast Packet message ─────────────────────
    if (data.size() < 2U) {
      return;
    }

    Session s{};
    s.pgn = pgn;
    s.sequence = seq;
    s.total_bytes = static_cast<uint16_t>(data[1]);
    s.source = id.sa;
    s.destination = id.is_broadcast() ? kBroadcast : id.ps;
    s.next_frame = 1U;
    s.last_seen = std::chrono::steady_clock::now();

    if (s.total_bytes == 0U) {
      return;
    }

    s.buffer.resize(s.total_bytes);

    const size_t available = data.size() - 2U; // bytes after header
    const size_t first_chunk =
        std::min<size_t>(std::min<size_t>(6U, available), s.total_bytes);
    for (size_t i = 0U; i < first_chunk; ++i) {
      s.buffer[i] = data[2U + i];
    }

    // Complete in a single frame?
    if (first_chunk >= s.total_bytes) {
      Frame frame{
          .pgn = s.pgn,
          .source = s.source,
          .destination = s.destination,
          .data = std::move(s.buffer),
      };
      on_complete_(std::move(frame));
      return;
    }

    sessions_.insert_or_assign(key, std::move(s));

  } else {
    // ── Subsequent frame ─────────────────────────────────────────────
    auto it = sessions_.find(key);
    if (it == sessions_.end()) {
      return;
    }

    Session &s = it->second;

    // Validate sequence counter and frame ordering.
    if (seq != s.sequence || frame_counter != s.next_frame) {
      sessions_.erase(it);
      return;
    }

    const size_t offset = 6U + static_cast<size_t>(frame_counter - 1U) * 7U;
    const size_t remaining =
        (offset < s.total_bytes) ? (s.total_bytes - offset) : 0U;
    const size_t available = (data.size() > 1U) ? (data.size() - 1U) : 0U;
    const size_t chunk =
        std::min<size_t>(std::min<size_t>(7U, remaining), available);

    for (size_t i = 0U; i < chunk; ++i) {
      s.buffer[offset + i] = data[1U + i];
    }

    s.next_frame = static_cast<uint8_t>(frame_counter + 1U);
    s.last_seen = std::chrono::steady_clock::now();

    // Check if reassembly is complete.
    if (offset + chunk >= s.total_bytes) {
      Frame frame{
          .pgn = s.pgn,
          .source = s.source,
          .destination = s.destination,
          .data = std::move(s.buffer),
      };
      sessions_.erase(it);
      on_complete_(std::move(frame));
    }
  }

  // Periodically purge stale sessions to prevent unbounded memory growth.
  expire_stale_sessions();
}

void Receiver::expire_stale_sessions() {
  const auto now = std::chrono::steady_clock::now();
  for (auto it = sessions_.begin(); it != sessions_.end();) {
    if (now - it->second.last_seen > kSessionTimeout) {
      it = sessions_.erase(it);
    } else {
      ++it;
    }
  }
}

} // namespace j1939::fast_packet
