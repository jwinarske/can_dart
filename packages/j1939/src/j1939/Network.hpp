// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <chrono>
#include <expected>
#include <functional>
#include <optional>
#include <string_view>

#include "Types.hpp"
#include "can/Socket.hpp"

namespace j1939::network {

// ── AddressClaimer ────────────────────────────────────────────────────────────
//
// Implements the J1939/81 address claiming state machine.
//
// Flow
// ────
//   1. claim()  — transmits Address Claimed PGN and starts the 250 ms wait.
//   2. The RX loop calls on_address_claimed() whenever it receives an
//      Address Claimed frame from any node.
//   3. tick()   — call periodically (e.g. every 5 ms) to advance the timer.
//      Returns the final claimed address when the 250 ms window expires.
//
// Conflict handling
// ─────────────────
//   If a competing claim arrives with a lower NAME value, we either:
//     a) pick a different preferred address and re-claim (arbitrary_address=true), or
//     b) send "Cannot Claim Address" (SA=0xFE) and call on_cannot_claim.
//
//   In this implementation, if no alternative address is found in one scan
//   of the 0–253 space, we give up and report the error.

class AddressClaimer {
public:
    AddressClaimer(can::Socket& socket,
                   Address preferred_address,
                   Name own_name);

    // Begin the claim process.  Broadcasts Address Claimed with SA = preferred_.
    void claim();

    // Call from the RX thread whenever an Address Claimed frame is received.
    void on_address_claimed(Address sa, const Name& their_name);

    // Advance the state machine.  Returns the claimed address once stable,
    // or an error string if we could not claim any address.
    std::optional<std::expected<Address, std::string_view>>
    tick(std::chrono::milliseconds elapsed);

    // Broadcast our NAME + address so peers can learn we exist.
    void announce();

    // Send a Request for Address Claimed to all nodes (asks everyone to
    // re-announce themselves — useful at startup).
    void request_all_addresses();

    [[nodiscard]] Address current_address() const noexcept { return current_; }
    [[nodiscard]] bool    is_claimed()      const noexcept { return claimed_; }

private:
    void send_address_claimed(Address sa);
    void send_cannot_claim();
    Address find_free_address() const;

    can::Socket& socket_;
    Name         own_name_;
    Address      preferred_;
    Address      current_;
    bool         claimed_       = false;
    bool         conflict_seen_ = false;

    // addresses known to be in use by peers: index = address, value = name
    // (stored as encoded uint64 for compact storage)
    std::array<std::optional<uint64_t>, 254> peer_names_{};

    std::chrono::milliseconds elapsed_{0};
    static constexpr auto kClaimWindow = std::chrono::milliseconds{250};
};

} // namespace j1939::network
