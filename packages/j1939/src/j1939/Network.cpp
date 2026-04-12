#include <algorithm>
#include <ranges>

#include "Network.hpp"

namespace j1939::network {

AddressClaimer::AddressClaimer(can::Socket& socket,
                               Address preferred_address,
                               Name own_name)
    : socket_{socket}
    , own_name_{own_name}
    , preferred_{preferred_address}
    , current_{preferred_address}
{}

void AddressClaimer::claim()
{
    send_address_claimed(current_);
    elapsed_ = std::chrono::milliseconds{0};
}

void AddressClaimer::announce()
{
    send_address_claimed(current_);
}

void AddressClaimer::request_all_addresses()
{
    const Id id = Id::from_pgn(static_cast<uint32_t>(Pgn::Request),
                               6U, kBroadcast, current_);
    can::RawFrame f;
    f.id  = id.encode();
    f.dlc = 3U;
    const auto pgn_req = static_cast<uint32_t>(Pgn::AddressClaimed);
    f.data[0] = static_cast<uint8_t>( pgn_req         & 0xFFU);
    f.data[1] = static_cast<uint8_t>((pgn_req >>  8U) & 0xFFU);
    f.data[2] = static_cast<uint8_t>((pgn_req >> 16U) & 0xFFU);
    socket_.send(f);
}

void AddressClaimer::on_address_claimed(Address sa, const Name& their_name)
{
    if (sa < 254U) {
        // NOLINTNEXTLINE(cppcoreguidelines-pro-bounds-constant-array-index)
        peer_names_[sa] = their_name.encode();
    }

    if (sa == current_ && !claimed_) {
        if (their_name.outranks(own_name_)) {
            const Address alt = find_free_address();
            if (alt != kNullAddress) {
                current_ = alt;
                send_address_claimed(current_);
                elapsed_ = std::chrono::milliseconds{0};
            } else {
                send_cannot_claim();
            }
        } else {
            send_address_claimed(current_);
        }
    }
}

std::optional<std::expected<Address, std::string_view>>
AddressClaimer::tick(std::chrono::milliseconds elapsed)
{
    if (claimed_) { return std::nullopt; }

    elapsed_ += elapsed;
    if (elapsed_ < kClaimWindow) { return std::nullopt; }

    if (current_ == kNullAddress) {
        return std::unexpected<std::string_view>(
            "address claim failed: all addresses in use");
    }

    claimed_ = true;
    return current_;
}

void AddressClaimer::send_address_claimed(Address sa)
{
    const Id id = Id::from_pgn(static_cast<uint32_t>(Pgn::AddressClaimed),
                               6U, kBroadcast, sa);
    const uint64_t name_enc = own_name_.encode();

    can::RawFrame f;
    f.id  = id.encode();
    f.dlc = 8U;
    for (uint8_t i = 0U; i < 8U; ++i) {
        // NOLINTNEXTLINE(cppcoreguidelines-pro-bounds-constant-array-index)
        f.data[i] = static_cast<uint8_t>((name_enc >> (static_cast<uint64_t>(i) * 8U)) & 0xFFU);
    }
    socket_.send(f);
}

void AddressClaimer::send_cannot_claim()
{
    current_ = kNullAddress;
    send_address_claimed(kNullAddress);
}

Address AddressClaimer::find_free_address() const
{
    for (Address a = preferred_; a < 254U; ++a) {
        // NOLINTNEXTLINE(cppcoreguidelines-pro-bounds-constant-array-index)
        if (!peer_names_[a].has_value()) { return a; }
    }
    for (Address a = 0U; a < preferred_; ++a) {
        // NOLINTNEXTLINE(cppcoreguidelines-pro-bounds-constant-array-index)
        if (!peer_names_[a].has_value()) { return a; }
    }
    return kNullAddress;
}

} // namespace j1939::network
