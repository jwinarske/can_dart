// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

#include "PgnTransport.hpp"

#include <mutex>
#include <shared_mutex>
#include <unordered_map>

namespace j1939 {

namespace {

// NOLINTNEXTLINE(cppcoreguidelines-avoid-non-const-global-variables)
std::shared_mutex g_mutex;

// NOLINTNEXTLINE(cppcoreguidelines-avoid-non-const-global-variables)
std::unordered_map<uint32_t, PgnTransport> g_map = {
    // Known NMEA 2000 Fast Packet PGNs
    {129025U, PgnTransport::fast_packet},  // Position, Rapid Update
    {129026U, PgnTransport::fast_packet},  // COG & SOG, Rapid Update
    {129029U, PgnTransport::fast_packet},  // GNSS Position Data
    {129033U, PgnTransport::fast_packet},  // Time & Date
    {128275U, PgnTransport::fast_packet},  // Distance Log
    {127489U, PgnTransport::fast_packet},  // Engine Parameters, Dynamic
    {126993U, PgnTransport::fast_packet},  // Heartbeat
    {126996U, PgnTransport::fast_packet},  // Product Information
    {126998U, PgnTransport::fast_packet},  // Configuration Information
    {126464U, PgnTransport::fast_packet},  // PGN List (Tx/Rx)
    {126720U, PgnTransport::fast_packet},  // Proprietary Fast Packet
    {126208U, PgnTransport::fast_packet},  // NMEA Command/Request Group
    {129038U, PgnTransport::fast_packet},  // AIS Class A Position Report
    {129039U, PgnTransport::fast_packet},  // AIS Class B Position Report
};

} // namespace

PgnTransport pgn_transport(uint32_t pgn)
{
    std::shared_lock lock{g_mutex};
    const auto it = g_map.find(pgn);
    return (it != g_map.end()) ? it->second : PgnTransport::single;
}

void set_pgn_transport(uint32_t pgn, PgnTransport transport)
{
    std::unique_lock lock{g_mutex};
    g_map.insert_or_assign(pgn, transport);
}

} // namespace j1939
