// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Unit tests for j1939::transport::Receiver (BAM reassembly).
//
// Feeds synthetic TP.CM (BAM announcement) and TP.DT (data transfer)
// frames into the Receiver and verifies the on_complete callback fires
// with the correctly reassembled Frame.
//
// Requires vcan0 — the Socket& is only used by the Receiver for sending
// CTS/EOM_ACK responses (which don't fire in BAM mode), but the
// constructor requires a valid reference.

#include <gtest/gtest.h>
#include <vector>

#include "j1939/Transport.hpp"

using namespace j1939;
using namespace j1939::transport;
using namespace std::chrono_literals;

namespace {

class VcanSocket {
public:
    VcanSocket() {
        auto result = can::Socket::open("vcan0");
        if (!result) {
            available_ = false;
        } else {
            socket_ = std::move(*result);
            available_ = true;
        }
    }
    [[nodiscard]] bool available() const { return available_; }
    can::Socket& get() { return socket_; }
private:
    can::Socket socket_;
    bool available_{false};
};

// Build a TP.CM_BAM announcement frame (8 bytes).
//
// Layout (J1939/21 §5.10.2.2):
//   byte 0:    control = 0x20 (BAM)
//   byte 1-2:  total data size (LE)
//   byte 3:    total packets
//   byte 4:    0xFF (reserved)
//   byte 5-7:  PGN (LE, 3 bytes)
std::array<uint8_t, 8> make_bam_cm(uint16_t total_bytes,
                                    uint8_t total_packets,
                                    uint32_t pgn) {
    return {
        static_cast<uint8_t>(TpControl::Bam),
        static_cast<uint8_t>(total_bytes & 0xFF),
        static_cast<uint8_t>((total_bytes >> 8) & 0xFF),
        total_packets,
        0xFF,
        static_cast<uint8_t>(pgn & 0xFF),
        static_cast<uint8_t>((pgn >> 8) & 0xFF),
        static_cast<uint8_t>((pgn >> 16) & 0xFF),
    };
}

// Build a TP.DT data-transfer frame (8 bytes).
//
// Layout:
//   byte 0:    sequence number (1-based)
//   byte 1-7:  up to 7 data bytes (padded with 0xFF)
std::array<uint8_t, 8> make_dt(uint8_t seq,
                                const uint8_t* payload, size_t len) {
    std::array<uint8_t, 8> frame{};
    frame[0] = seq;
    for (size_t i = 0; i < 7 && i < len; ++i) {
        frame[1 + i] = payload[i];
    }
    for (size_t i = len; i < 7; ++i) {
        frame[1 + i] = 0xFF; // pad
    }
    return frame;
}

// Build an Id for TP.CM or TP.DT with the given source address.
Id make_tp_id(uint32_t pgn, Address sa) {
    return Id::from_pgn(pgn, 6, kBroadcast, sa);
}

// Helper: array<uint8_t,8> → span<const uint8_t> (implicit conversion
// sometimes fails with brace-init under GCC's C++23 mode).
std::span<const uint8_t> as_span(const std::array<uint8_t, 8>& a) {
    return {a.data(), a.size()};
}

} // namespace

class ReceiverTest : public ::testing::Test {
protected:
    void SetUp() override {
        if (!vcan_.available()) {
            GTEST_SKIP() << "vcan0 not available";
        }
    }

    VcanSocket vcan_;
    std::vector<Frame> received_;

    std::unique_ptr<Receiver> make_receiver(Address own = 0xB0) {
        return std::make_unique<Receiver>(
            vcan_.get(), own,
            [this](Frame f) { received_.push_back(std::move(f)); });
    }
};

TEST_F(ReceiverTest, BamReassemblesSmallPayload) {
    auto rx = make_receiver();

    // 9-byte payload → 2 DT packets (7 + 2 bytes, 5 bytes padding in last).
    const uint32_t pgn = static_cast<uint32_t>(Pgn::SoftwareId);
    const Address sender = 0xA0;
    const std::vector<uint8_t> payload = {
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09};

    // TP.CM_BAM announcement
    auto cm = make_bam_cm(9, 2, pgn);
    auto cm_id = make_tp_id(static_cast<uint32_t>(Pgn::TpCm), sender);
    rx->on_tp_cm(cm_id, as_span(cm));

    // TP.DT #1: bytes 0-6
    auto dt1 = make_dt(1, payload.data(), 7);
    auto dt_id = make_tp_id(static_cast<uint32_t>(Pgn::TpDt), sender);
    rx->on_tp_dt(dt_id, as_span(dt1));

    // TP.DT #2: bytes 7-8 (padded)
    auto dt2 = make_dt(2, payload.data() + 7, 2);
    rx->on_tp_dt(dt_id, as_span(dt2));

    ASSERT_EQ(received_.size(), 1U);
    EXPECT_EQ(received_[0].pgn, pgn);
    EXPECT_EQ(received_[0].source, sender);
    ASSERT_EQ(received_[0].data.size(), 9U);
    for (size_t i = 0; i < 9; ++i) {
        EXPECT_EQ(received_[0].data[i], payload[i])
            << "mismatch at byte " << i;
    }
}

TEST_F(ReceiverTest, BamReassemblesExactMultipleOf7) {
    auto rx = make_receiver();

    // 14 bytes = exactly 2 full DT packets (no padding).
    const uint32_t pgn = static_cast<uint32_t>(Pgn::ProprietaryA);
    const Address sender = 0xC0;
    std::vector<uint8_t> payload(14);
    for (size_t i = 0; i < 14; ++i) payload[i] = static_cast<uint8_t>(i);

    auto cm = make_bam_cm(14, 2, pgn);
    rx->on_tp_cm(
        make_tp_id(static_cast<uint32_t>(Pgn::TpCm), sender), as_span(cm));

    auto dt1 = make_dt(1, payload.data(), 7);
    rx->on_tp_dt(
        make_tp_id(static_cast<uint32_t>(Pgn::TpDt), sender), as_span(dt1));

    auto dt2 = make_dt(2, payload.data() + 7, 7);
    rx->on_tp_dt(
        make_tp_id(static_cast<uint32_t>(Pgn::TpDt), sender), as_span(dt2));

    ASSERT_EQ(received_.size(), 1U);
    ASSERT_EQ(received_[0].data.size(), 14U);
    for (size_t i = 0; i < 14; ++i) {
        EXPECT_EQ(received_[0].data[i], payload[i]);
    }
}

TEST_F(ReceiverTest, BamFromDifferentSourcesAreIndependent) {
    auto rx = make_receiver();
    const uint32_t pgn = 0xFEDAU;

    auto cm_a = make_bam_cm(9, 2, pgn);
    rx->on_tp_cm(make_tp_id(static_cast<uint32_t>(Pgn::TpCm), 0xA0), as_span(cm_a));

    auto cm_b = make_bam_cm(9, 2, pgn);
    rx->on_tp_cm(make_tp_id(static_cast<uint32_t>(Pgn::TpCm), 0xB1), as_span(cm_b));

    std::vector<uint8_t> data_a(9, 0xAA);
    std::vector<uint8_t> data_b(9, 0xBB);

    rx->on_tp_dt(make_tp_id(static_cast<uint32_t>(Pgn::TpDt), 0xA0),
                 as_span(make_dt(1, data_a.data(), 7)));
    rx->on_tp_dt(make_tp_id(static_cast<uint32_t>(Pgn::TpDt), 0xB1),
                 as_span(make_dt(1, data_b.data(), 7)));
    rx->on_tp_dt(make_tp_id(static_cast<uint32_t>(Pgn::TpDt), 0xA0),
                 as_span(make_dt(2, data_a.data() + 7, 2)));
    rx->on_tp_dt(make_tp_id(static_cast<uint32_t>(Pgn::TpDt), 0xB1),
                 as_span(make_dt(2, data_b.data() + 7, 2)));

    ASSERT_EQ(received_.size(), 2U);

    // Find each by source address.
    const auto& fa = received_[0].source == 0xA0 ? received_[0] : received_[1];
    const auto& fb = received_[0].source == 0xB1 ? received_[0] : received_[1];

    EXPECT_EQ(fa.source, 0xA0);
    for (auto b : fa.data) EXPECT_EQ(b, 0xAA);

    EXPECT_EQ(fb.source, 0xB1);
    for (auto b : fb.data) EXPECT_EQ(b, 0xBB);
}

TEST_F(ReceiverTest, TimingConstantsMatchJ1939Spec) {
    // J1939/21 §5.10.2.4 — verify the timing constants haven't drifted.
    EXPECT_EQ(kBamInterpacket,  50ms);
    EXPECT_EQ(kT1_DataTimeout,  750ms);
    EXPECT_EQ(kT2_CtsTimeout,   1250ms);
    EXPECT_EQ(kT3_ResponseWait, 1250ms);
    EXPECT_EQ(kT4_HoldWait,     1050ms);
    EXPECT_EQ(kMaxRetries,       3);
}
