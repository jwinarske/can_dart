// Unit tests for j1939::Id, j1939::Name, and j1939::Dm1Fault.
//
// These are pure value types with encode/decode bit-field codecs — no Asio,
// no sockets. Exercises the exact bit-shift math that the C++ stack depends
// on for CAN ID routing and J1939/81 address-claim priority resolution.

#include <gtest/gtest.h>

#include "j1939/Types.hpp"

using namespace j1939;

// ── Id ──────────────────────────────────────────────────────────────────────

TEST(Id, EncodeDecodeRoundtrip) {
    const Id original{
        .priority = 6,
        .edp      = false,
        .dp       = false,
        .pf       = 0xEF,
        .ps       = 0x00,
        .sa       = 0xA0,
    };
    const uint32_t raw = original.encode();
    const Id decoded   = Id::decode(raw);

    EXPECT_EQ(decoded.priority, 6);
    EXPECT_EQ(decoded.edp,      false);
    EXPECT_EQ(decoded.dp,       false);
    EXPECT_EQ(decoded.pf,       0xEF);
    EXPECT_EQ(decoded.ps,       0x00);
    EXPECT_EQ(decoded.sa,       0xA0);
}

TEST(Id, EncodeDecodeWithEdpDp) {
    const Id original{
        .priority = 3,
        .edp      = true,
        .dp       = true,
        .pf       = 0x42,
        .ps       = 0xFF,
        .sa       = 0x01,
    };
    const auto raw     = original.encode();
    const auto decoded = Id::decode(raw);

    EXPECT_EQ(decoded.priority, 3);
    EXPECT_TRUE(decoded.edp);
    EXPECT_TRUE(decoded.dp);
    EXPECT_EQ(decoded.pf,  0x42);
    EXPECT_EQ(decoded.ps,  0xFF);
    EXPECT_EQ(decoded.sa,  0x01);
}

TEST(Id, PgnBroadcast) {
    // ProprietaryA: PGN 0xEF00, pf=0xEF (≥ 0xF0 is false → PDU1).
    // Wait — 0xEF < 0xF0, so this is PDU1 (peer-to-peer). PGN = pf<<8 only.
    const Id pdsa{.pf = 0xEF, .ps = 0xB0, .sa = 0xA0};
    EXPECT_FALSE(pdsa.is_broadcast());
    EXPECT_EQ(pdsa.pgn(), 0x00EF00U);

    // Broadcast PGN: DM1 = 0xFECA. pf = 0xFE (≥ 0xF0 → broadcast / PDU2).
    const Id dm1{.pf = 0xFE, .ps = 0xCA, .sa = 0xA0};
    EXPECT_TRUE(dm1.is_broadcast());
    EXPECT_EQ(dm1.pgn(), 0x00FECAU);
}

TEST(Id, FromPgnPdu1) {
    // PDU1 (destination-specific): PGN 0xEA00 (Request), dest=0xFF, src=0xA0.
    const auto id = Id::from_pgn(0xEA00, 6, 0xFF, 0xA0);
    EXPECT_EQ(id.priority, 6);
    EXPECT_EQ(id.pf,       0xEA);
    EXPECT_EQ(id.ps,       0xFF);   // PS = dest for PDU1
    EXPECT_EQ(id.sa,       0xA0);
    EXPECT_EQ(id.pgn(),    0x00EA00U);
}

TEST(Id, FromPgnPdu2) {
    // PDU2 (broadcast): PGN 0xFECA (DM1), dest ignored, src=0xB0.
    const auto id = Id::from_pgn(0xFECA, 6, 0xFF, 0xB0);
    EXPECT_EQ(id.pf,    0xFE);
    EXPECT_EQ(id.ps,    0xCA);     // PS = low byte of PGN for PDU2
    EXPECT_EQ(id.sa,    0xB0);
    EXPECT_EQ(id.pgn(), 0x00FECAU);
}

TEST(Id, EncodeMatchesFromPgn) {
    const auto id  = Id::from_pgn(0xFECA, 6, 0xFF, 0xA0);
    const auto raw = id.encode();
    const auto dec = Id::decode(raw);
    EXPECT_EQ(dec.pgn(), 0xFECAU);
    EXPECT_EQ(dec.sa,    0xA0);
}

// ── Name ────────────────────────────────────────────────────────────────────

TEST(Name, EncodeDecodeRoundtrip) {
    const Name original{
        .identity_number         = 0x12345U,
        .manufacturer_code       = 0x123U,
        .function_instance       = 0x0AU,
        .ecu_instance            = 0x03U,
        .function                = 0xAAU,
        .vehicle_system          = 0x55U,
        .arbitrary_address       = true,
        .industry_group          = 0x05U,
        .vehicle_system_instance = 0x0BU,
    };

    const uint64_t raw = original.encode();
    const Name decoded = Name::decode(raw);

    EXPECT_EQ(decoded.identity_number,         0x12345U);
    EXPECT_EQ(decoded.manufacturer_code,       0x123U);
    EXPECT_EQ(decoded.function_instance,       0x0AU);
    EXPECT_EQ(decoded.ecu_instance,            0x03U);
    EXPECT_EQ(decoded.function,                0xAAU);
    EXPECT_EQ(decoded.vehicle_system,          0x55U);
    EXPECT_TRUE(decoded.arbitrary_address);
    EXPECT_EQ(decoded.industry_group,          0x05U);
    EXPECT_EQ(decoded.vehicle_system_instance, 0x0BU);
}

TEST(Name, DecodeZero) {
    const auto n = Name::decode(0x0000000000000000ULL);
    EXPECT_EQ(n.identity_number,   0U);
    EXPECT_EQ(n.manufacturer_code, 0U);
    EXPECT_FALSE(n.arbitrary_address);
    EXPECT_EQ(n.industry_group,    0U);
}

TEST(Name, DecodeAllOnes) {
    const auto n = Name::decode(0xFFFFFFFFFFFFFFFFULL);
    EXPECT_EQ(n.identity_number,         0x1FFFFFU);
    EXPECT_EQ(n.manufacturer_code,       0x7FFU);
    EXPECT_EQ(n.function_instance,       0x1FU);
    EXPECT_EQ(n.ecu_instance,            0x07U);
    EXPECT_EQ(n.function,                0xFFU);
    EXPECT_EQ(n.vehicle_system,          0x7FU);
    EXPECT_TRUE(n.arbitrary_address);
    EXPECT_EQ(n.industry_group,          0x07U);
    EXPECT_EQ(n.vehicle_system_instance, 0x0FU);
}

TEST(Name, OutranksLowerValue) {
    // "outranks" means lower encoded value → higher priority.
    const Name low{.identity_number = 1};
    const Name high{.identity_number = 2};
    EXPECT_TRUE(low.outranks(high));
    EXPECT_FALSE(high.outranks(low));
}

TEST(Name, OutranksEqualIsFalse) {
    const Name a{.identity_number = 42};
    const Name b{.identity_number = 42};
    EXPECT_FALSE(a.outranks(b));
    EXPECT_FALSE(b.outranks(a));
}

// ── Dm1Fault ────────────────────────────────────────────────────────────────

TEST(Dm1Fault, DefaultValues) {
    const Dm1Fault f{};
    EXPECT_EQ(f.spn,             0U);
    EXPECT_EQ(f.fmi,             0U);
    EXPECT_EQ(f.occurrence,      1U);
    EXPECT_FALSE(f.conversion_flag);
}

TEST(Dm1Fault, DesignatedInit) {
    const Dm1Fault f{.spn = 190, .fmi = 2, .occurrence = 5, .conversion_flag = true};
    EXPECT_EQ(f.spn,        190U);
    EXPECT_EQ(f.fmi,        2U);
    EXPECT_EQ(f.occurrence,  5U);
    EXPECT_TRUE(f.conversion_flag);
}

// ── Frame ───────────────────────────────────────────────────────────────────

TEST(Frame, DefaultValues) {
    const Frame f{};
    EXPECT_EQ(f.pgn,         0U);
    EXPECT_EQ(f.source,      kNullAddress);
    EXPECT_EQ(f.destination, kBroadcast);
    EXPECT_TRUE(f.data.empty());
}

// ── PGN enum ────────────────────────────────────────────────────────────────

TEST(PgnEnum, KnownValues) {
    EXPECT_EQ(static_cast<uint32_t>(Pgn::Request),         0x00EA00U);
    EXPECT_EQ(static_cast<uint32_t>(Pgn::AddressClaimed),  0x00EE00U);
    EXPECT_EQ(static_cast<uint32_t>(Pgn::ProprietaryA),    0x00EF00U);
    EXPECT_EQ(static_cast<uint32_t>(Pgn::Dm1),             0x00FECAU);
    EXPECT_EQ(static_cast<uint32_t>(Pgn::SoftwareId),      0x00FEDAU);
}

// ── TpControl enum ──────────────────────────────────────────────────────────

TEST(TpControlEnum, KnownValues) {
    EXPECT_EQ(static_cast<uint8_t>(TpControl::Rts),         0x10U);
    EXPECT_EQ(static_cast<uint8_t>(TpControl::Cts),         0x11U);
    EXPECT_EQ(static_cast<uint8_t>(TpControl::EndOfMsgAck), 0x13U);
    EXPECT_EQ(static_cast<uint8_t>(TpControl::Bam),         0x20U);
    EXPECT_EQ(static_cast<uint8_t>(TpControl::Abort),       0xFFU);
}

// ── Constants ───────────────────────────────────────────────────────────────

TEST(Constants, AddressValues) {
    EXPECT_EQ(kBroadcast,   0xFFU);
    EXPECT_EQ(kNullAddress, 0xFEU);
    EXPECT_EQ(kMaxDataSize, 8U);
}
