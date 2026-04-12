// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

#include <algorithm>
#include <thread>

#include "Transport.hpp"

namespace j1939::transport {

namespace {

can::RawFrame make_tp_cm(Address sa, Address da, Priority prio,
                          std::span<const uint8_t, 8> payload)
{
    const Id id = Id::from_pgn(static_cast<uint32_t>(Pgn::TpCm), prio, da, sa);
    can::RawFrame f;
    f.id  = id.encode();
    f.dlc = 8U;
    std::ranges::copy(payload, f.data.begin());
    return f;
}

can::RawFrame make_tp_dt(Address sa, Address da, Priority prio,
                          std::span<const uint8_t, 8> payload)
{
    const Id id = Id::from_pgn(static_cast<uint32_t>(Pgn::TpDt), prio, da, sa);
    can::RawFrame f;
    f.id  = id.encode();
    f.dlc = 8U;
    std::ranges::copy(payload, f.data.begin());
    return f;
}

// Build the CM_BAM control message.  Shared by both sync and async paths.
std::array<uint8_t, 8> make_bam_cm(uint32_t pgn,
                                    uint16_t total_bytes,
                                    uint8_t  total_packets) noexcept
{
    std::array<uint8_t, 8> cm{};
    cm[0] = static_cast<uint8_t>(TpControl::Bam);
    cm[1] = static_cast<uint8_t>(total_bytes & 0xFFU);
    cm[2] = static_cast<uint8_t>(total_bytes >> 8U);
    cm[3] = total_packets;
    cm[4] = 0xFFU;
    cm[5] = static_cast<uint8_t>(pgn & 0xFFU);
    cm[6] = static_cast<uint8_t>((pgn >>  8U) & 0xFFU);
    cm[7] = static_cast<uint8_t>((pgn >> 16U) & 0xFFU);
    return cm;
}

// Build the N-th DT frame (seq is 1-based).
std::array<uint8_t, 8> make_bam_dt(uint8_t seq,
                                    std::span<const uint8_t> data) noexcept
{
    std::array<uint8_t, 8> dt{};
    dt[0] = seq;
    const size_t offset = static_cast<size_t>(seq - 1U) * 7U;
    for (uint8_t b = 0U; b < 7U; ++b) {
        const size_t idx = offset + b;
        // NOLINTNEXTLINE(cppcoreguidelines-pro-bounds-constant-array-index)
        dt[1U + b] = (idx < data.size()) ? data[idx] : 0xFFU;
    }
    return dt;
}

} // namespace

// ── BamSender::send (synchronous) ────────────────────────────────────────────

std::expected<void, std::string_view>
BamSender::send(uint32_t pgn, Priority priority,
                std::span<const uint8_t> data) const
{
    const auto total_bytes   = static_cast<uint16_t>(data.size());
    const auto total_packets = static_cast<uint8_t>((data.size() + 6U) / 7U);
    const auto cm            = make_bam_cm(pgn, total_bytes, total_packets);

    if (!socket_->send(make_tp_cm(sa_, kBroadcast, priority, cm))) {
        return std::unexpected(std::string_view{"BAM: TP.CM_BAM send failed"});
    }

    for (uint8_t seq = 1U; seq <= total_packets; ++seq) {
        std::this_thread::sleep_for(kBamInterpacket);
        if (!socket_->send(make_tp_dt(sa_, kBroadcast, priority, make_bam_dt(seq, data)))) {
            return std::unexpected(std::string_view{"BAM: TP.DT send failed"});
        }
    }

    return {};
}

// ── BamSender::send_async (coroutine) ────────────────────────────────────────
//
// Identical packet sequence to send(), but each inter-packet gap is a
// co_await on an asio::steady_timer instead of a blocking sleep_for.
// The ASIO thread is free (can service other coroutines) during each 50 ms gap.
//
// Cancellation: if io_context::stop() is called while a timer is pending
// (e.g. during ECU shutdown), async_wait completes with operation_aborted.
// We catch that and return std::unexpected{"BAM: cancelled"}.

asio::awaitable<std::expected<void, std::string_view>>
BamSender::send_async(uint32_t pgn, Priority priority,
                       std::vector<uint8_t> data) const
{
    using Result = std::expected<void, std::string_view>;

    const auto total_bytes   = static_cast<uint16_t>(data.size());
    const auto total_packets = static_cast<uint8_t>((data.size() + 6U) / 7U);
    const auto cm            = make_bam_cm(pgn, total_bytes, total_packets);

    if (!socket_->send(make_tp_cm(sa_, kBroadcast, priority, cm))) {
        co_return Result{std::unexpect, "BAM: TP.CM_BAM send failed"};
    }

    // Retrieve the executor this coroutine is running on (the BAM strand).
    const auto ex = co_await asio::this_coro::executor;

    for (uint8_t seq = 1U; seq <= total_packets; ++seq) {
        // Non-blocking inter-packet delay.
        // redirect_error routes the error code into ec rather than throwing,
        // letting us distinguish operation_aborted (shutdown) from real errors.
        asio::steady_timer timer{ex, kBamInterpacket};
        asio::error_code   ec;
        co_await timer.async_wait(asio::redirect_error(asio::use_awaitable, ec));
        if (ec) {
            co_return Result{std::unexpect,
                ec == asio::error::operation_aborted
                    ? std::string_view{"BAM: cancelled"}
                    : std::string_view{"BAM: timer error"}};
        }

        if (!socket_->send(make_tp_dt(sa_, kBroadcast, priority,
                                      make_bam_dt(seq, data)))) {
            co_return Result{std::unexpect, "BAM: TP.DT send failed"};
        }
    }

    co_return Result{};
}

// ── RtsCtsSession ─────────────────────────────────────────────────────────────

RtsCtsSession::RtsCtsSession(can::Socket& socket, Address sa, Address da,
                              uint32_t pgn, Priority priority,
                              std::vector<uint8_t> data)
    : socket_{&socket}, sa_{sa}, da_{da}, pgn_{pgn}, priority_{priority}
    , data_{std::move(data)}
    , total_packets_{static_cast<uint8_t>((data_.size() + 6U) / 7U)}
{}

std::expected<void, std::string_view> RtsCtsSession::start() const
{
    const auto total_bytes = static_cast<uint16_t>(data_.size());

    std::array<uint8_t, 8> cm{};
    cm[0] = static_cast<uint8_t>(TpControl::Rts);
    cm[1] = static_cast<uint8_t>(total_bytes & 0xFFU);
    cm[2] = static_cast<uint8_t>(total_bytes >> 8U);
    cm[3] = total_packets_;
    cm[4] = 0x01U;
    cm[5] = static_cast<uint8_t>(pgn_ & 0xFFU);
    cm[6] = static_cast<uint8_t>((pgn_ >>  8U) & 0xFFU);
    cm[7] = static_cast<uint8_t>((pgn_ >> 16U) & 0xFFU);

    if (!socket_->send(make_tp_cm(sa_, da_, priority_, cm))) {
        return std::unexpected(std::string_view{"RTS/CTS: RTS send failed"});
    }
    return {};
}

bool RtsCtsSession::on_cts(uint8_t num_packets, uint8_t next_packet)
{
    send_dt_packets(next_packet, num_packets);
    return false;
}

void RtsCtsSession::on_eom_ack()
{
    complete_ = true;
    if (complete_cb_) { complete_cb_(true); }
}

void RtsCtsSession::on_abort()
{
    failed_ = true;
    if (complete_cb_) { complete_cb_(false); }
}

void RtsCtsSession::send_dt_packets(uint8_t first_packet, uint8_t count)
{
    for (uint8_t i = 0U; i < count; ++i) {
        const uint8_t seq    = first_packet + i;
        const size_t  offset = static_cast<size_t>(seq - 1U) * 7U;

        std::array<uint8_t, 8> dt{};
        dt[0] = seq;
        for (uint8_t b = 0U; b < 7U; ++b) {
            const size_t idx = offset + b;
            // NOLINTNEXTLINE(cppcoreguidelines-pro-bounds-constant-array-index)
            dt[1U + b] = (idx < data_.size()) ? data_[idx] : 0xFFU;
        }
        socket_->send(make_tp_dt(sa_, da_, priority_, dt));
    }
}

// ── Receiver ─────────────────────────────────────────────────────────────────

void Receiver::on_tp_cm(const Id& id, std::span<const uint8_t> data)
{
    if (data.size() < 8U) { return; }

    const auto ctrl = static_cast<TpControl>(data[0]);
    const Address src = id.sa;

    if (ctrl == TpControl::Bam) {
        Session s;
        s.type          = TpControl::Bam;
        s.total_bytes   = static_cast<uint16_t>(static_cast<uint32_t>(data[1])
                        | (static_cast<uint32_t>(data[2]) << 8U));
        s.total_packets = data[3];
        s.next_packet   = 1U;
        s.dest          = kBroadcast;
        s.pgn           = static_cast<uint32_t>(data[5])
                        | (static_cast<uint32_t>(data[6]) <<  8U)
                        | (static_cast<uint32_t>(data[7]) << 16U);
        s.buffer.clear();
        sessions_[src] = std::move(s);

    } else if (ctrl == TpControl::Rts) {
        Session s;
        s.type          = TpControl::Rts;
        s.total_bytes   = static_cast<uint16_t>(static_cast<uint32_t>(data[1])
                        | (static_cast<uint32_t>(data[2]) << 8U));
        s.total_packets = data[3];
        s.next_packet   = 1U;
        s.dest          = own_;
        s.pgn           = static_cast<uint32_t>(data[5])
                        | (static_cast<uint32_t>(data[6]) <<  8U)
                        | (static_cast<uint32_t>(data[7]) << 16U);
        s.buffer.clear();

        const uint32_t pgn = s.pgn;
        sessions_[src] = std::move(s);
        send_cts(src, pgn, 1U);

    } else if (ctrl == TpControl::Abort) {
        sessions_.erase(src);
    }
}

void Receiver::on_tp_dt(const Id& id, std::span<const uint8_t> data)
{
    if (data.size() < 8U) { return; }

    const Address src = id.sa;
    auto it = sessions_.find(src);
    if (it == sessions_.end()) { return; }

    Session& s = it->second;
    const uint8_t seq = data[0];
    if (seq != s.next_packet) {
        if (!s.is_bam()) { send_cts(src, s.pgn, s.next_packet); }
        return;
    }

    const size_t remaining = s.total_bytes - s.buffer.size();
    const size_t take      = std::min<size_t>(7U, remaining);
    const auto   payload   = data.subspan(1U, take);
    s.buffer.insert(s.buffer.end(), payload.begin(), payload.end());
    ++s.next_packet;

    if (!s.is_complete()) {
        if (!s.is_bam()) { send_cts(src, s.pgn, s.next_packet); }
        return;
    }

    if (!s.is_bam()) {
        send_eom_ack(src, s.pgn, s.total_bytes, s.total_packets);
    }

    Frame frame{
        .pgn         = s.pgn,
        .source      = src,
        .destination = s.dest,
        .data        = std::move(s.buffer),
    };
    sessions_.erase(it);
    on_complete_(std::move(frame));
}

void Receiver::send_cts(Address dest, uint32_t pgn, uint8_t next_packet)
{
    std::array<uint8_t, 8> cm{};
    cm[0] = static_cast<uint8_t>(TpControl::Cts);
    cm[1] = 1U;
    cm[2] = next_packet;
    cm[3] = 0xFFU;
    cm[4] = 0xFFU;
    cm[5] = static_cast<uint8_t>(pgn & 0xFFU);
    cm[6] = static_cast<uint8_t>((pgn >>  8U) & 0xFFU);
    cm[7] = static_cast<uint8_t>((pgn >> 16U) & 0xFFU);

    const Id id = Id::from_pgn(static_cast<uint32_t>(Pgn::TpCm), 7U, dest, own_);
    can::RawFrame f;
    f.id  = id.encode();
    f.dlc = 8U;
    std::ranges::copy(cm, f.data.begin());
    socket_->send(f);
}

void Receiver::send_eom_ack(Address dest, uint32_t pgn,
                             uint16_t total_bytes, uint8_t total_packets)
{
    std::array<uint8_t, 8> cm{};
    cm[0] = static_cast<uint8_t>(TpControl::EndOfMsgAck);
    cm[1] = static_cast<uint8_t>(total_bytes & 0xFFU);
    cm[2] = static_cast<uint8_t>(total_bytes >> 8U);
    cm[3] = total_packets;
    cm[4] = 0xFFU;
    cm[5] = static_cast<uint8_t>(pgn & 0xFFU);
    cm[6] = static_cast<uint8_t>((pgn >>  8U) & 0xFFU);
    cm[7] = static_cast<uint8_t>((pgn >> 16U) & 0xFFU);

    const Id id = Id::from_pgn(static_cast<uint32_t>(Pgn::TpCm), 7U, dest, own_);
    can::RawFrame f;
    f.id  = id.encode();
    f.dlc = 8U;
    std::ranges::copy(cm, f.data.begin());
    socket_->send(f);
}

} // namespace j1939::transport
