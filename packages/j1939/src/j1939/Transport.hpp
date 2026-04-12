// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <chrono>
#include <cstdint>
#include <expected>
#include <functional>
#include <optional>
#include <span>
#include <string_view>
#include <unordered_map>
#include <vector>

#include "Types.hpp"
#include "can/Socket.hpp"

// Standalone ASIO (header-only, no Boost).
// CMakeLists must add the ASIO include/ tree and define:
//   ASIO_STANDALONE  ASIO_NO_DEPRECATED  ASIO_HAS_CO_AWAIT
#include <asio/awaitable.hpp>
#include <asio/redirect_error.hpp>
#include <asio/steady_timer.hpp>
#include <asio/use_awaitable.hpp>
#include <asio/this_coro.hpp>

namespace j1939::transport {

// ── Timing constants (J1939/21 §5.10.2.4) ────────────────────────────────────

inline constexpr auto kBamInterpacket   = std::chrono::milliseconds{50};
inline constexpr auto kT1_DataTimeout   = std::chrono::milliseconds{750};
inline constexpr auto kT2_CtsTimeout    = std::chrono::milliseconds{1250};
inline constexpr auto kT3_ResponseWait  = std::chrono::milliseconds{1250};
inline constexpr auto kT4_HoldWait      = std::chrono::milliseconds{1050};
inline constexpr uint8_t kMaxRetries    = 3;

// ── BamSender ─────────────────────────────────────────────────────────────────
//
// send()       — synchronous; sleeps kBamInterpacket between DT frames.
//                Blocks the calling thread for (N_packets × 50 ms).
//                Kept for compatibility and unit tests.
//
// send_async() — coroutine; co_awaits an asio::steady_timer between frames.
//                The ASIO thread is free during each 50 ms gap.
//                Co-spawn on a strand to prevent concurrent BAM sessions
//                from the same SA (prohibited by J1939/21 §5.10.2.1).

class BamSender {
public:
    BamSender(can::Socket& socket, Address sa) noexcept
        : socket_{&socket}, sa_{sa} {}

    std::expected<void, std::string_view>
    send(uint32_t pgn, Priority priority, std::span<const uint8_t> data) const;

    // data is taken by value so the coroutine owns the buffer across every
    // timer suspension point.  The caller does not need to keep its buffer alive.
    asio::awaitable<std::expected<void, std::string_view>>
    send_async(uint32_t pgn, Priority priority, std::vector<uint8_t> data) const;

private:
    can::Socket* socket_;
    Address      sa_;
};

// ── RtsCtsSession ─────────────────────────────────────────────────────────────
//
// Initiates a peer-to-peer RTS/CTS multi-packet transfer.
//
// Known limitation: Ecu::Impl does not store active sender sessions or wire
// on_cts()/on_eom_ack() back from the RX loop, so large unicast sends transmit
// only the initial RTS and then stall.  Fix: store sessions keyed by dest
// address and call these callbacks from handle_request_frame / rx_loop.

class RtsCtsSession {
public:
    using CompleteCallback = std::function<void(bool /*success*/)>;

    RtsCtsSession(can::Socket& socket, Address sa, Address da,
                  uint32_t pgn, Priority priority,
                  std::vector<uint8_t> data);

    // Register a callback fired once when the transfer completes or aborts.
    // Must be set before on_eom_ack() / on_abort() are called.
    // Fires on the RX jthread with no Ecu mutex held.
    void set_complete_callback(CompleteCallback cb)
        { complete_cb_ = std::move(cb); }

    bool on_cts(uint8_t num_packets, uint8_t next_packet);
    void on_eom_ack();
    void on_abort();

    [[nodiscard]] bool    complete() const noexcept { return complete_; }
    [[nodiscard]] bool    failed()   const noexcept { return failed_; }
    [[nodiscard]] Address dest()     const noexcept { return da_; }

    std::expected<void, std::string_view> start() const;

private:
    void send_dt_packets(uint8_t first_packet, uint8_t count);

    can::Socket*         socket_;
    Address              sa_, da_;
    uint32_t             pgn_;
    Priority             priority_;
    std::vector<uint8_t> data_;
    uint8_t              total_packets_ = 0;
    bool                 complete_      = false;
    bool                 failed_        = false;
    CompleteCallback     complete_cb_;
};

// ── Receiver ─────────────────────────────────────────────────────────────────

class Receiver {
public:
    using OnComplete = std::function<void(Frame)>;

    explicit Receiver(can::Socket& socket, Address own_address,
                      OnComplete on_complete)
        : socket_{&socket}, own_{own_address}
        , on_complete_{std::move(on_complete)} {}

    void set_own_address(Address a) noexcept { own_ = a; }

    void on_tp_cm(const Id& id, std::span<const uint8_t> data);
    void on_tp_dt(const Id& id, std::span<const uint8_t> data);

private:
    struct Session {
        uint32_t  pgn           = 0;
        uint16_t  total_bytes   = 0;
        uint8_t   total_packets = 0;
        uint8_t   next_packet   = 1;
        Address   dest          = kBroadcast;
        TpControl type          = TpControl::Bam;
        std::vector<uint8_t> buffer;

        [[nodiscard]] bool is_bam()      const noexcept { return type == TpControl::Bam; }
        [[nodiscard]] bool is_complete() const noexcept { return next_packet > total_packets; }
    };

    void send_cts(Address dest, uint32_t pgn, uint8_t next_packet);
    void send_eom_ack(Address dest, uint32_t pgn,
                      uint16_t total_bytes, uint8_t total_packets);

    can::Socket*                         socket_;
    Address                              own_;
    OnComplete                           on_complete_;
    std::unordered_map<Address, Session> sessions_;
};

} // namespace j1939::transport
