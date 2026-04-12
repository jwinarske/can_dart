// Copyright 2024 can_dart Contributors
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <chrono>
#include <cstdint>
#include <expected>
#include <functional>
#include <mutex>
#include <span>
#include <string_view>
#include <unordered_map>
#include <vector>

#include "Types.hpp"
#include "can/Socket.hpp"

namespace j1939::fast_packet {

// Max Fast Packet payload: 223 bytes (first frame: 6 data bytes,
// subsequent frames: 7 data bytes each, max 32 frames).
inline constexpr size_t kMaxPayload = 223;

// Stale session timeout
inline constexpr auto kSessionTimeout = std::chrono::milliseconds{750};

class Sender {
public:
    explicit Sender(can::Socket& socket) noexcept : socket_{&socket} {}

    // Send a Fast Packet message. Thread-safe (internal mutex serializes sends).
    // data.size() must be in [1, kMaxPayload].
    [[nodiscard]]
    std::expected<void, std::string_view>
    send(uint32_t pgn, Priority priority, Address dest, Address sa,
         std::span<const uint8_t> data);

    void set_own_address(Address a) noexcept;

private:
    can::Socket* socket_;
    std::mutex   mutex_;
    uint8_t      sequence_counter_ = 0;  // 3-bit, wraps 0-7
};

class Receiver {
public:
    using OnComplete = std::function<void(Frame)>;

    explicit Receiver(OnComplete on_complete)
        : on_complete_{std::move(on_complete)} {}

    // Called from the RX loop for every frame whose PGN is flagged fast_packet.
    void on_frame(const Id& id, std::span<const uint8_t> data);

private:
    struct Session {
        uint32_t             pgn           = 0;
        uint8_t              sequence      = 0;   // 3-bit sequence counter
        uint16_t             total_bytes   = 0;
        uint8_t              next_frame    = 0;   // next expected frame counter
        Address              source        = kNullAddress;
        Address              destination   = kBroadcast;
        std::vector<uint8_t> buffer;
        std::chrono::steady_clock::time_point last_seen;
    };

    // Key: (source_address << 24) | pgn — unique per concurrent FP from same SA
    using SessionKey = uint64_t;
    static SessionKey make_key(Address sa, uint32_t pgn) {
        return (static_cast<uint64_t>(sa) << 24) | static_cast<uint64_t>(pgn & 0xFFFFFFU);
    }

    void expire_stale_sessions();

    OnComplete                                on_complete_;
    std::unordered_map<SessionKey, Session>   sessions_;
};

} // namespace j1939::fast_packet
