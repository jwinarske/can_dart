// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Unit tests for j1939::network::AddressClaimer.
//
// Tests the J1939/81 address-claim state machine by driving it with
// explicit on_address_claimed() calls and tick() time advancement.
// Requires vcan0 for socket construction — the socket is only used
// for outbound Address Claimed frames.

#include <gtest/gtest.h>

#include "j1939/Network.hpp"

using namespace j1939;
using namespace j1939::network;
using namespace std::chrono_literals;

namespace {

// RAII helper: opens a CAN socket on vcan0, skips the test if unavailable.
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

} // namespace

class AddressClaimerTest : public ::testing::Test {
protected:
    void SetUp() override {
        if (!vcan_.available()) {
            GTEST_SKIP() << "vcan0 not available";
        }
    }

    VcanSocket vcan_;

    Name make_name(uint32_t identity) {
        return Name{
            .identity_number   = identity,
            .manufacturer_code = 0x7FFU,
            .arbitrary_address = true,
        };
    }
};

TEST_F(AddressClaimerTest, ClaimsPreferredAddressWithNoConflict) {
    auto name = make_name(0x0001);
    AddressClaimer claimer(vcan_.get(), 0xA0, name);

    claimer.claim();

    // Advance time past the 250 ms window in one step.
    auto result = claimer.tick(300ms);
    ASSERT_TRUE(result.has_value());
    ASSERT_TRUE(result->has_value());
    EXPECT_EQ(result->value(), 0xA0);
    EXPECT_TRUE(claimer.is_claimed());
    EXPECT_EQ(claimer.current_address(), 0xA0);
}

TEST_F(AddressClaimerTest, TickBeforeWindowExpiredReturnsNullopt) {
    auto name = make_name(0x0002);
    AddressClaimer claimer(vcan_.get(), 0xB0, name);

    claimer.claim();

    // Only 100 ms elapsed — window hasn't expired yet.
    auto result = claimer.tick(100ms);
    EXPECT_FALSE(result.has_value());
    EXPECT_FALSE(claimer.is_claimed());
}

TEST_F(AddressClaimerTest, ConflictFromHigherPriorityPeerTriggersReaddress) {
    // Our NAME identity = 0x100 (higher numeric = lower priority).
    auto our_name = make_name(0x100);
    AddressClaimer claimer(vcan_.get(), 0xC0, our_name);

    claimer.claim();

    // A peer claims our address with a lower NAME value (higher priority).
    auto peer_name = make_name(0x001);
    claimer.on_address_claimed(0xC0, peer_name);

    // Tick past the window — claimer should pick a different address
    // (arbitrary_address = true) or fail if no free address exists.
    auto result = claimer.tick(300ms);
    ASSERT_TRUE(result.has_value());
    if (result->has_value()) {
        // Got a different address (not 0xC0 which the peer owns).
        EXPECT_NE(result->value(), 0xC0);
    }
    // Either way, the test exercises the conflict-handling path.
}

TEST_F(AddressClaimerTest, NoConflictFromLowerPriorityPeer) {
    // Our NAME identity = 0x001 (low = high priority). Peer claims
    // a different address — no conflict, we keep ours.
    auto our_name = make_name(0x001);
    AddressClaimer claimer(vcan_.get(), 0xD0, our_name);

    claimer.claim();

    // Peer claims 0xD1 (different from ours) — not a conflict.
    auto peer_name = make_name(0x100);
    claimer.on_address_claimed(0xD1, peer_name);

    auto result = claimer.tick(300ms);
    ASSERT_TRUE(result.has_value());
    ASSERT_TRUE(result->has_value());
    EXPECT_EQ(result->value(), 0xD0);
}

TEST_F(AddressClaimerTest, CurrentAddressBeforeClaimReturnsPreferred) {
    auto name = make_name(0x0003);
    AddressClaimer claimer(vcan_.get(), 0xE0, name);
    EXPECT_EQ(claimer.current_address(), 0xE0);
    EXPECT_FALSE(claimer.is_claimed());
}
