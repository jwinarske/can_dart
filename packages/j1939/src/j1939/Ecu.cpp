// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

#include <algorithm>
#include <chrono>
#include <future>
#include <mutex>
#include <ranges>
#include <thread>

// ASIO — for io_context, strand, co_spawn.
// Must be included before Transport.hpp in translation units that use both.
#include <asio/bind_executor.hpp>
#include <asio/co_spawn.hpp>
#include <asio/detached.hpp>
#include <asio/executor_work_guard.hpp>
#include <asio/io_context.hpp>
#include <asio/strand.hpp>

#include "Ecu.hpp"
#include "FastPacket.hpp"
#include "Network.hpp"
#include "PgnTransport.hpp"
#include "Transport.hpp"
#include "can/Socket.hpp"

// ── print shim
// ────────────────────────────────────────────────────────────────
#if __has_include(<print>)
#include <print>
namespace j1939 {
using std::print;
}
#else
#include <cstdio>
#include <format>
namespace j1939 {
template <typename... Args>
void print(std::format_string<Args...> fmt, Args&&... args) {
    const auto s = std::format(fmt, std::forward<Args>(args)...);
    (void)std::fwrite(s.data(), 1, s.size(), stdout);
}
template <typename... Args>
void print(std::FILE* f, std::format_string<Args...> fmt, Args&&... args) {
    const auto s = std::format(fmt, std::forward<Args>(args)...);
    (void)std::fwrite(s.data(), 1, s.size(), f);
}
} // namespace j1939
#endif

namespace j1939 {

using namespace std::chrono_literals;

// ── Impl
// ──────────────────────────────────────────────────────────────────────
//
// Member declaration order is load-bearing — C++ destroys members in reverse
// declaration order.  The threads must be destroyed before the objects they
// reference, so they are declared last (destroyed first).
//
// Destruction sequence:
//   1. asio_thread_ — stop_callback fires io_ctx_.stop(); run() returns; joins.
//      Any in-flight BAM coroutines receive operation_aborted and call their
//      on_complete callbacks before the io_context exits.
//   2. rx_thread_   — stop requested; socket.receive() timeout unblocks; joins.
//   3. bam_strand_, asio_work_, io_ctx_ — harmless after thread has joined.
//   4. transport_rx, claimer, socket — protocol state torn down.

struct Ecu::Impl {
    // ── Protocol state ────────────────────────────────────────────────────
    can::Socket socket;
    std::mutex mutex;
    network::AddressClaimer claimer;
    transport::Receiver transport_rx;
    fast_packet::Receiver fp_rx;
    fast_packet::Sender fp_tx;
    std::vector<Dm1Fault> dm1_faults;
    MessageHandler message_handler;
    ClaimHandler claim_result_handler; // fires once on claim settle
    Address own_address = kNullAddress;

    // Active RTS/CTS send sessions, keyed by destination address.
    // Populated by send()/send_async() for unicast payloads > 8 bytes.
    // Drained by dispatch_tx_tp_cm() on the RX thread.
    std::unordered_map<Address, transport::RtsCtsSession> tx_sessions_;

    // ── ASIO runtime ──────────────────────────────────────────────────────
    //
    // io_ctx_ must be declared before bam_strand_ and asio_work_ (they
    // reference it on construction).  All three must be declared before
    // the threads (threads destroyed first, io_ctx_ destroyed last).
    asio::io_context io_ctx_;
    asio::executor_work_guard<asio::io_context::executor_type> asio_work_ {
        asio::make_work_guard(io_ctx_)};
    asio::strand<asio::io_context::executor_type> bam_strand_ {
        asio::make_strand(io_ctx_)};

    // ── Threads (declared last → destroyed first) ─────────────────────────
    std::jthread rx_thread_;   // RX poll loop; destroyed 2nd
    std::jthread asio_thread_; // ASIO run loop; destroyed 1st

    // ── Constructor ───────────────────────────────────────────────────────

    Impl(can::Socket sock, Address preferred, const Name& name)
        : socket {std::move(sock)}, claimer {socket, preferred, name},
          transport_rx {
              socket, preferred,
              [this](const Frame& frame) { on_assembled_frame(frame); }},
          fp_rx {[this](const Frame& frame) { on_assembled_frame(frame); }},
          fp_tx {socket} {}

    // ── Internal helpers ──────────────────────────────────────────────────

    void on_assembled_frame(const Frame& frame) const;
    void handle_address_claimed_frame(const Id& id,
                                      std::span<const uint8_t> data);
    void send_dm1_response(Address dest);
    void rx_loop(const std::stop_token& stop);
    void dispatch_tx_tp_cm(const Id& id, std::span<const uint8_t> data);
};

// ── Factory
// ───────────────────────────────────────────────────────────────────

std::expected<std::unique_ptr<Ecu>, std::error_code>
Ecu::create(std::string_view ifname, Address preferred_address, Name name) {
    auto sock = can::Socket::open(ifname, 10ms);
    if (!sock) {
        return std::unexpected(sock.error());
    }

    auto ecu = std::unique_ptr<Ecu>(new Ecu {});
    ecu->impl_ =
        std::make_unique<Impl>(std::move(*sock), preferred_address, name);
    auto& impl = *ecu->impl_;

    impl.claimer.claim();
    impl.claimer.request_all_addresses();

    // Start the RX thread.
    impl.rx_thread_ = std::jthread {
        [&impl](const std::stop_token& stop) { impl.rx_loop(stop); }};

    // Start the ASIO thread.
    // A stop_callback wires jthread's stop_token to io_context::stop() so that
    // when the jthread is destroyed (stop requested + join), the io_context
    // exits cleanly rather than blocking forever on pending work.
    impl.asio_thread_ = std::jthread {[&impl](const std::stop_token& st) {
        const std::stop_callback stop_cb {st, [&impl] { impl.io_ctx_.stop(); }};
        impl.io_ctx_.run();
    }};

    print("[ECU 0x{:02X}] started on {}\n", preferred_address, ifname);
    return ecu;
}

Ecu::~Ecu() = default;

// ── RX loop
// ───────────────────────────────────────────────────────────────────

void Ecu::Impl::rx_loop(const std::stop_token& stop) {
    auto last_tick = std::chrono::steady_clock::now();

    while (!stop.stop_requested()) {

        // ── Tick address claim ─────────────────────────────────────────────
        //
        // Capture the claim result outside the lock so we can fire the
        // callback without holding the mutex (same reasoning as on_message).
        //
        // claim_event layout:
        //   std::nullopt              — no claim event this tick
        //   std::optional<Address>{}  — claim failed (no free address)
        //   std::optional<Address>{a} — claimed successfully at address a
        std::optional<std::optional<Address>> claim_event;
        {
            const auto now = std::chrono::steady_clock::now();
            const auto elapsed =
                std::chrono::duration_cast<std::chrono::milliseconds>(
                    now - last_tick);
            last_tick = now;

            const std::scoped_lock lock {mutex};
            if (!claimer.is_claimed()) {
                if (auto result = claimer.tick(elapsed); result.has_value()) {
                    if (*result) {
                        own_address = **result;
                        transport_rx.set_own_address(own_address);
                        print("[ECU 0x{:02X}] address claimed\n", own_address);
                        claim_event.emplace(own_address); // success
                    } else {
                        print("[ECU] address claim failed: {}\n",
                              result->error());
                        claim_event.emplace(std::nullopt); // failure
                    }
                }
            }
        }
        // Fire claim callback outside the lock.
        if (claim_event.has_value() && claim_result_handler) {
            claim_result_handler(*claim_event);
        }

        const auto raw = socket.receive();
        if (!raw) {
            continue;
        }

        const Id id = Id::decode(raw->id);
        const auto frame_pgn = id.pgn();

        // Use unique_lock so we can release before invoking the message
        // handler. Calling an arbitrary callback under the mutex is fragile: it
        // would deadlock if the handler ever called back into send() or any
        // other method that acquires the same mutex.
        std::unique_lock lock {mutex};

        std::optional<Frame> user_frame;

        // Capture any deferred action before releasing the lock.
        std::optional<Address> dm1_response_dest;

        if (frame_pgn == static_cast<uint32_t>(Pgn::TpCm)) {
            // RX receiver side (BAM reassembly, incoming RTS/CTS)
            transport_rx.on_tp_cm(id, {raw->data.data(), raw->dlc});
            // TX sender side (CTS/ACK/Abort responses to our outstanding RTS)
            dispatch_tx_tp_cm(id, {raw->data.data(), raw->dlc});
        } else if (frame_pgn == static_cast<uint32_t>(Pgn::TpDt)) {
            transport_rx.on_tp_dt(id, {raw->data.data(), raw->dlc});
        } else if (frame_pgn == static_cast<uint32_t>(Pgn::AddressClaimed)) {
            handle_address_claimed_frame(id, {raw->data.data(), raw->dlc});
        } else if (frame_pgn == static_cast<uint32_t>(Pgn::Request)) {
            // Parse inline so we can act after releasing the lock.
            // handle_request_frame() used to call send_dm1_response() under
            // the lock, which would block the RX thread for up to 400 ms if
            // the DM1 payload required a BAM transmission.
            const std::span<const uint8_t> req_data {raw->data.data(),
                                                     raw->dlc};
            if (req_data.size() >= 3U &&
                (id.is_broadcast() || id.ps == own_address)) {
                const uint32_t req_pgn =
                    static_cast<uint32_t>(req_data[0]) |
                    (static_cast<uint32_t>(req_data[1]) << 8U) |
                    (static_cast<uint32_t>(req_data[2]) << 16U);

                if (req_pgn == static_cast<uint32_t>(Pgn::AddressClaimed)) {
                    claimer.announce(); // fast — just queues a frame
                } else if (req_pgn == static_cast<uint32_t>(Pgn::Dm1)) {
                    dm1_response_dest = id.sa; // deferred outside lock
                }
            }
            // Always deliver Request frames to user handler so Dart can
            // implement protocol-level auto-responders (NMEA 2000).
            user_frame = Frame {
                .pgn = frame_pgn,
                .source = id.sa,
                .destination = id.is_broadcast() ? kBroadcast : id.ps,
                .data = {raw->data.begin(), raw->data.begin() + raw->dlc},
            };
        } else if (pgn_transport(frame_pgn) == PgnTransport::fast_packet) {
            // Fast Packet reassembly — fp_rx fires on_assembled_frame when
            // complete.
            fp_rx.on_frame(id, {raw->data.data(), raw->dlc});
        } else {
            user_frame = Frame {
                .pgn = frame_pgn,
                .source = id.sa,
                .destination = id.is_broadcast() ? kBroadcast : id.ps,
                .data = {raw->data.begin(), raw->data.begin() + raw->dlc},
            };
        }

        lock.unlock();

        // Send DM1 response without holding the mutex — send_dm1_response()
        // acquires the lock itself to snapshot fault state, then releases
        // before any blocking BAM operation.
        if (dm1_response_dest) {
            send_dm1_response(*dm1_response_dest);
        }
        if (user_frame) {
            on_assembled_frame(*user_frame);
        }
    }
}

// ── Frame dispatch
// ────────────────────────────────────────────────────────────

void Ecu::Impl::on_assembled_frame(const Frame& frame) const {
    if (message_handler) {
        message_handler(frame);
    }
}

void Ecu::Impl::handle_address_claimed_frame(const Id& id,
                                             std::span<const uint8_t> data) {
    if (data.size() < 8U) {
        return;
    }
    uint64_t name_raw = 0U;
    for (uint8_t i = 0U; i < 8U; ++i) {
        name_raw |= static_cast<uint64_t>(data[i])
                    << (static_cast<uint64_t>(i) * 8U);
    }
    claimer.on_address_claimed(id.sa, Name::decode(name_raw));
}

// ── dispatch_tx_tp_cm
// ─────────────────────────────────────────────────────────
//
// Called from rx_loop under the mutex whenever a TP.CM frame arrives whose
// source address matches one of our active RTS/CTS send sessions.
// Routes CTS / EndOfMsgAck / Abort to the appropriate session.
//
// Note: on_eom_ack() and on_abort() move the session out before calling the
// CompleteCallback to avoid a use-after-erase if the callback re-enters here.

void Ecu::Impl::dispatch_tx_tp_cm(const Id& id, std::span<const uint8_t> data) {
    if (data.size() < 8U) {
        return;
    }

    const auto ctrl = static_cast<TpControl>(data[0]);

    // Only interested in responses directed at us.
    if (ctrl != TpControl::Cts && ctrl != TpControl::EndOfMsgAck &&
        ctrl != TpControl::Abort) {
        return;
    }

    auto it = tx_sessions_.find(id.sa);
    if (it == tx_sessions_.end()) {
        return;
    }

    if (ctrl == TpControl::Cts) {
        it->second.on_cts(data[1], data[2]);
        if (it->second.complete() || it->second.failed()) {
            tx_sessions_.erase(it);
        }
    } else {
        // Move out before callback to avoid iterator invalidation.
        auto session = std::move(it->second);
        tx_sessions_.erase(it);

        if (ctrl == TpControl::EndOfMsgAck) {
            session.on_eom_ack();
        } else {
            session.on_abort();
        }
    }
}

void Ecu::Impl::send_dm1_response(Address dest) {
    // Called WITHOUT holding the mutex — snapshot protected state first.
    std::vector<Dm1Fault> faults_snap;
    Address own_addr;
    {
        const std::scoped_lock lock {mutex};
        faults_snap = dm1_faults;
        own_addr = own_address;
    }

    std::vector<uint8_t> payload;
    payload.push_back(0x00U);
    payload.push_back(0x00U);

    for (const auto& fault : faults_snap) {
        payload.push_back(static_cast<uint8_t>(fault.spn & 0xFFU));
        payload.push_back(static_cast<uint8_t>((fault.spn >> 8U) & 0xFFU));
        payload.push_back(
            static_cast<uint8_t>(((fault.spn >> 16U) & 0x07U) << 5U) |
            (fault.fmi & 0x1FU));
        payload.push_back(
            static_cast<uint8_t>((fault.conversion_flag ? 0x80U : 0x00U) |
                                 (fault.occurrence & 0x7FU)));
    }

    const uint32_t pgn = static_cast<uint32_t>(Pgn::Dm1);

    if (payload.size() <= kMaxDataSize) {
        const Id id = Id::from_pgn(pgn, 6U, dest, own_addr);
        can::RawFrame f;
        f.id = id.encode();
        f.dlc = static_cast<uint8_t>(payload.size());
        std::ranges::copy(payload, f.data.begin());
        socket.send(f);
    } else if (dest == kBroadcast) {
        // Dispatch BAM onto the ASIO thread so the RX loop is never blocked.
        asio::co_spawn(bam_strand_,
                       transport::BamSender {socket, own_addr}.send_async(
                           pgn, 6U, std::move(payload)),
                       asio::detached);
    } else {
        // Unicast DM1 > 8 bytes: send RTS and let the RX loop drive it.
        transport::RtsCtsSession session {socket, own_addr, dest,
                                          pgn,    6U,       payload};
        if (auto r = session.start(); !r) {
            return;
        }
        const std::scoped_lock lock {mutex};
        tx_sessions_.emplace(dest, std::move(session));
    }
}

// ── Public API
// ────────────────────────────────────────────────────────────────

std::expected<void, std::string_view> Ecu::send(Pgn pgn, Priority priority,
                                                Address dest,
                                                std::span<const uint8_t> data) {
    const uint32_t pgn_raw = static_cast<uint32_t>(pgn);

    // Single frame: hold lock only for the instantaneous socket write.
    if (data.size() <= kMaxDataSize) {
        const std::scoped_lock lock {impl_->mutex};
        const Id id = Id::from_pgn(pgn_raw, priority, dest, impl_->own_address);
        can::RawFrame f;
        f.id = id.encode();
        f.dlc = static_cast<uint8_t>(data.size());
        std::ranges::copy(data, f.data.begin());
        if (!impl_->socket.send(f)) {
            return std::unexpected(
                std::string_view {"send: socket write failed"});
        }
        return {};
    }

    // Fast Packet: use FP framing when the PGN is registered as fast_packet.
    if (pgn_transport(pgn_raw) == PgnTransport::fast_packet) {
        Address own_addr;
        {
            const std::scoped_lock lock {impl_->mutex};
            own_addr = impl_->own_address;
        }
        return impl_->fp_tx.send(pgn_raw, priority, dest, own_addr, data);
    }

    // Multi-frame: capture own_address and release the lock before the blocking
    // send path.  Holding the mutex across BAM's sleep_for() calls starved the
    // RX jthread for the entire transmission window.
    Address own_addr;
    {
        const std::scoped_lock lock {impl_->mutex};
        own_addr = impl_->own_address;
    }

    if (dest == kBroadcast) {
        const transport::BamSender bam {impl_->socket, own_addr};
        return bam.send(pgn_raw, priority, data);
    }

    // RTS/CTS: store session in tx_sessions_ before calling start() so there
    // is no window where a CTS arrives before the session is registered.
    // Use shared_ptr<> wrappers so the callback (stored as std::function, which
    // requires copy-constructibility) can share ownership of the sync
    // primitives.
    auto done = std::make_shared<bool>(false);
    auto success = std::make_shared<bool>(false);
    auto cv = std::make_shared<std::condition_variable>();
    auto cv_mtx = std::make_shared<std::mutex>();

    {
        const std::scoped_lock lock {impl_->mutex};
        transport::RtsCtsSession session {
            impl_->socket, own_addr, dest,
            pgn_raw,       priority, {data.begin(), data.end()}};
        session.set_complete_callback([done, success, cv, cv_mtx](bool ok) {
            {
                const std::scoped_lock lk {*cv_mtx};
                *done = true;
                *success = ok;
            }
            cv->notify_one();
        });
        if (auto r = session.start(); !r) {
            return r;
        }
        impl_->tx_sessions_.emplace(dest, std::move(session));
    }

    // Wait for EndOfMsgAck or Abort.  Timeout = T3_ResponseWait × (retries +
    // 1).
    const auto timeout = transport::kT3_ResponseWait *
                         static_cast<int>(transport::kMaxRetries + 1U);
    std::unique_lock<std::mutex> ul {*cv_mtx};
    const bool in_time = cv->wait_for(ul, timeout, [&done] { return *done; });

    if (!in_time) {
        const std::scoped_lock lock {impl_->mutex};
        impl_->tx_sessions_.erase(dest);
        return std::unexpected(std::string_view {"RTS/CTS: timed out"});
    }
    return *success
               ? std::expected<void, std::string_view> {}
               : std::unexpected(std::string_view {"RTS/CTS: remote aborted"});
}

// ── send_async
// ────────────────────────────────────────────────────────────────
//
// Co-spawns a BamSender::send_async() coroutine onto the BAM strand.
// The strand serialises concurrent send_async() calls so only one BAM session
// runs at a time per ECU (required by J1939/21 §5.10.2.1).
//
// The on_complete callback fires on the ASIO thread.  For the Dart FFI use case
// it calls Dart_PostCObject_DL (thread-safe) to deliver a type-5 completion
// message to the Dart ReceivePort.

void Ecu::send_async(Pgn pgn, Priority priority, Address dest,
                     std::vector<uint8_t> data,
                     std::function<void(std::error_code)> on_complete) {
    // Single frame: inline, synchronous, call on_complete immediately.
    if (data.size() <= kMaxDataSize) {
        const auto r =
            send(pgn, priority, dest,
                 std::span<const uint8_t> {data.data(), data.size()});
        on_complete(r ? std::error_code {}
                      : std::make_error_code(std::errc::io_error));
        return;
    }

    // Fast Packet: no inter-packet delay, so run synchronously and call
    // on_complete.
    if (pgn_transport(static_cast<uint32_t>(pgn)) ==
        PgnTransport::fast_packet) {
        auto result = send(pgn, priority, dest,
                           std::span<const uint8_t> {data.data(), data.size()});
        on_complete(result ? std::error_code {}
                           : std::make_error_code(std::errc::io_error));
        return;
    }

    // Unicast (RTS/CTS): store session, drive it from the RX thread.
    // A timeout timer on bam_strand_ cancels the session if the remote
    // never responds with EndOfMsgAck or Abort.
    if (dest != kBroadcast) {
        Address own_addr;
        {
            const std::scoped_lock lock {impl_->mutex};
            own_addr = impl_->own_address;
        }

        // Shared flag so the callback and timer can cancel each other exactly
        // once.
        auto fired = std::make_shared<std::atomic<bool>>(false);

        // Timeout: T3_ResponseWait × (kMaxRetries + 1) per J1939/21 §5.10.2.3
        const auto timeout = transport::kT3_ResponseWait *
                             static_cast<int>(transport::kMaxRetries + 1U);
        auto timer =
            std::make_shared<asio::steady_timer>(impl_->bam_strand_, timeout);

        // Cancel the session if the timer fires before EndOfMsgAck arrives.
        timer->async_wait(asio::bind_executor(
            impl_->bam_strand_,
            [timer, fired, dest_addr = dest, impl_ptr = impl_.get(),
             cb = on_complete](const asio::error_code& ec) mutable {
                if (ec || fired->exchange(true)) {
                    return;
                }
                {
                    const std::scoped_lock lk {impl_ptr->mutex};
                    impl_ptr->tx_sessions_.erase(dest_addr);
                }
                cb(std::make_error_code(std::errc::timed_out));
            }));

        {
            const std::scoped_lock lock {impl_->mutex};
            transport::RtsCtsSession session {
                impl_->socket, own_addr,       dest, static_cast<uint32_t>(pgn),
                priority,      std::move(data)};
            session.set_complete_callback([timer, fired, dest_addr = dest,
                                           impl_ptr = impl_.get(),
                                           cb = on_complete](bool ok) mutable {
                timer->cancel(); // stop the timeout
                if (fired->exchange(true)) {
                    return;
                }
                {
                    const std::scoped_lock lk {impl_ptr->mutex};
                    impl_ptr->tx_sessions_.erase(dest_addr);
                }
                cb(ok ? std::error_code {}
                      : std::make_error_code(std::errc::connection_aborted));
            });
            if (auto r = session.start(); !r) {
                timer->cancel();
                on_complete(std::make_error_code(std::errc::io_error));
                return;
            }
            impl_->tx_sessions_.emplace(dest, std::move(session));
        }
        return;
    }

    // BAM broadcast: capture own_address under lock, release before co_spawn.
    Address own_addr;
    {
        const std::scoped_lock lock {impl_->mutex};
        own_addr = impl_->own_address;
    }

    // The lambda captures BamSender by value (contains only a raw pointer to
    // socket_ and a uint8_t for sa_).  The socket lives in Impl which outlives
    // the ASIO thread (destroyed after asio_thread_ joins).
    asio::co_spawn(
        impl_->bam_strand_,
        [bam = transport::BamSender {impl_->socket, own_addr},
         pgn_raw = static_cast<uint32_t>(pgn), priority,
         payload = std::move(data),
         cb = std::move(on_complete)]() mutable -> asio::awaitable<void> {
            std::error_code ec;
            try {
                const auto result = co_await bam.send_async(pgn_raw, priority,
                                                            std::move(payload));
                if (!result) {
                    ec = std::make_error_code(std::errc::io_error);
                }
            } catch (...) {
                ec = std::make_error_code(std::errc::operation_canceled);
            }
            cb(ec);
        },
        asio::detached);
}

std::expected<void, std::string_view> Ecu::send_request(Address dest,
                                                        Pgn requested_pgn) {
    const std::scoped_lock lock {impl_->mutex};

    const uint32_t target_pgn = static_cast<uint32_t>(requested_pgn);
    const std::array<uint8_t, 3> payload {
        static_cast<uint8_t>(target_pgn & 0xFFU),
        static_cast<uint8_t>((target_pgn >> 8U) & 0xFFU),
        static_cast<uint8_t>((target_pgn >> 16U) & 0xFFU),
    };
    const Id id = Id::from_pgn(static_cast<uint32_t>(Pgn::Request), 6U, dest,
                               impl_->own_address);
    can::RawFrame f;
    f.id = id.encode();
    f.dlc = 3U;
    std::ranges::copy(payload, f.data.begin());
    if (!impl_->socket.send(f)) {
        return std::unexpected(std::string_view {"send_request: write failed"});
    }
    return {};
}

void Ecu::on_message(MessageHandler handler) {
    const std::scoped_lock lock {impl_->mutex};
    impl_->message_handler = std::move(handler);
}

void Ecu::on_claim_result(ClaimHandler handler) {
    const std::scoped_lock lock {impl_->mutex};
    impl_->claim_result_handler = std::move(handler);
}

void Ecu::add_dm1_fault(Dm1Fault fault) {
    const std::scoped_lock lock {impl_->mutex};
    impl_->dm1_faults.push_back(fault);
}

void Ecu::clear_dm1_faults() {
    const std::scoped_lock lock {impl_->mutex};
    impl_->dm1_faults.clear();
}

Address Ecu::address() const noexcept {
    const std::scoped_lock lock {impl_->mutex};
    return impl_->own_address;
}

bool Ecu::address_claimed() const noexcept {
    const std::scoped_lock lock {impl_->mutex};
    return impl_->claimer.is_claimed();
}

} // namespace j1939
