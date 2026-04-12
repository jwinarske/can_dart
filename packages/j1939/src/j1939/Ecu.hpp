#pragma once

#include <expected>
#include <functional>
#include <memory>
#include <optional>
#include <span>
#include <string_view>
#include <system_error>
#include <vector>

#include "Types.hpp"

namespace j1939 {

// ── Ecu ───────────────────────────────────────────────────────────────────────
//
// One logical J1939 ECU on a SocketCAN interface.  Owns:
//   • A SocketCAN RAII socket
//   • A transport-layer receiver (BAM + RTS/CTS reassembly)
//   • An address claimer (J1939/81 state machine)
//   • An RX jthread  — polls the socket, drives address claiming, dispatches frames
//   • An ASIO io_context + thread — runs BAM send coroutines without blocking
//   • A BAM strand — serialises concurrent send_async() calls (J1939/21 §5.10.2.1)
//
// Thread safety
// ─────────────
//   • send() and all mutating public methods acquire the internal mutex.
//   • send_async() captures own_address under the mutex, then releases it before
//     co-spawning the BAM coroutine.  The coroutine runs on the ASIO thread.
//   • on_message callback fires on the RX thread with the mutex released.
//   • The destructor stops both threads and is safe to call from any thread.
//
// Destruction order (reverse of Impl declaration)
// ───────────────────────────────────────────────
//   asio_thread_ (destroyed first)
//     → stop_callback fires → io_context::stop()
//     → pending BAM coroutines receive operation_aborted → call on_complete(ec)
//     → io_context::run() returns → thread joins
//   rx_thread_ (destroyed second)
//     → stop_token triggered → loop exits → joins
//   bam_strand_, asio_work_, io_ctx_ destroyed (harmless after thread joined)
//   socket destroyed last

class Ecu {
public:
    Ecu(const Ecu&)            = delete;
    Ecu& operator=(const Ecu&) = delete;
    Ecu(Ecu&&)                 = delete;
    Ecu& operator=(Ecu&&)      = delete;

    ~Ecu();

    // ── Factory ───────────────────────────────────────────────────────────

    [[nodiscard]]
    static std::expected<std::unique_ptr<Ecu>, std::error_code>
    create(std::string_view ifname,
           Address          preferred_address,
           Name             name);

    // ── Transmit ──────────────────────────────────────────────────────────

    // Synchronous.  For single frames (≤ 8 bytes) this is always fast.
    // For BAM (broadcast, len > 8) it blocks for N_packets × 50 ms.
    // For RTS/CTS (unicast, len > 8) it sends RTS and returns — DT packets
    // are driven by CTS responses on the RX thread (see RtsCtsSession note).
    [[nodiscard]]
    std::expected<void, std::string_view>
    send(Pgn pgn, Priority priority, Address dest,
         std::span<const uint8_t> data);

    // Asynchronous.  Returns immediately; on_complete fires on the ASIO thread
    // when the full transmission is done (or on error/cancellation).
    //
    // For single frames: dispatches synchronously and calls on_complete inline.
    // For BAM broadcast: co-spawns a coroutine on the BAM strand; the strand
    //   serialises concurrent sends so only one BAM runs at a time.
    // For unicast (RTS/CTS): calls on_complete with errc::not_supported.
    //   Full async RTS/CTS requires a response channel (TODO).
    void send_async(Pgn pgn, Priority priority, Address dest,
                    std::vector<uint8_t> data,
                    std::function<void(std::error_code)> on_complete);

    // Convenience: send a request for any PGN (3-byte payload, PGN 0xEA00).
    [[nodiscard]]
    std::expected<void, std::string_view>
    send_request(Address dest, Pgn requested_pgn);

    // ── Receive ───────────────────────────────────────────────────────────

    using MessageHandler = std::function<void(const Frame&)>;
    void on_message(MessageHandler handler);

    // Register a handler invoked once when address claiming settles.
    // addr = the claimed address on success; std::nullopt on failure.
    // Fires on the RX thread with no lock held.
    // Must be registered before the claim can settle (~250 ms after create()).
    using ClaimHandler = std::function<void(std::optional<Address>)>;
    void on_claim_result(ClaimHandler handler);

    // ── Diagnostics ───────────────────────────────────────────────────────

    void add_dm1_fault(Dm1Fault fault);
    void clear_dm1_faults();

    // ── Identity ──────────────────────────────────────────────────────────

    [[nodiscard]] Address address()        const noexcept;
    [[nodiscard]] bool    address_claimed() const noexcept;

private:
    Ecu() = default;

    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace j1939
