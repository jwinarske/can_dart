// Unit tests for can_engine bit extraction, signal normalization, and filter
// state machines.
//
// All functions under test are pure, stateless (or self-contained-state),
// zero-allocation, and have no Asio / socket / thread dependencies.

#include <gtest/gtest.h>
#include <cmath>
#include <cstring>

#include "bit_extract.h"

using namespace can_engine;

// ── extract_le ──────────────────────────────────────────────────────────────

TEST(ExtractLe, SingleBitAtOrigin) {
    const uint8_t data[8] = {0x01, 0, 0, 0, 0, 0, 0, 0};
    EXPECT_EQ(extract_le(data, 0, 1), 1U);
}

TEST(ExtractLe, SingleBitZero) {
    const uint8_t data[8] = {0x00};
    EXPECT_EQ(extract_le(data, 0, 1), 0U);
}

TEST(ExtractLe, EightBitsFirstByte) {
    const uint8_t data[8] = {0xAB, 0, 0, 0, 0, 0, 0, 0};
    EXPECT_EQ(extract_le(data, 0, 8), 0xABU);
}

TEST(ExtractLe, SixteenBitsSpanningBytes) {
    // LE: byte[0] = low, byte[1] = high → 0x1234 stored as {0x34, 0x12}.
    const uint8_t data[8] = {0x34, 0x12, 0, 0, 0, 0, 0, 0};
    EXPECT_EQ(extract_le(data, 0, 16), 0x1234U);
}

TEST(ExtractLe, OffsetBits) {
    // 12-bit signal starting at bit 4: bits [4..15].
    // Byte layout: 0xF0, 0xAB → bits 4..15 = 0xABF.
    const uint8_t data[8] = {0xF0, 0xAB, 0, 0, 0, 0, 0, 0};
    EXPECT_EQ(extract_le(data, 4, 12), 0xABFU);
}

// ── extract_be ──────────────────────────────────────────────────────────────
//
// Motorola/BE DBC bit numbering in this implementation:
//   bit_pos 0 = byte 0 physical bit 7 (MSB of byte)
//   bit_pos 7 = byte 0 physical bit 0 (LSB of byte)
//   bit_pos 8 = byte 1 physical bit 7 (MSB of byte)
//   bit_pos 15 = byte 1 physical bit 0 (LSB of byte)
//
// Within the extraction loop the MSB of the result comes from start_bit
// and subsequent bits walk *down* through the byte then jump to the next
// byte's MSB — matching the Vector DBC Motorola forward convention.

TEST(ExtractBe, SingleBitReadsMsbOfByteZero) {
    // bit_pos=0 → byte 0 physical bit 7 (MSB).
    const uint8_t data[8] = {0x80, 0, 0, 0, 0, 0, 0, 0};
    EXPECT_EQ(extract_be(data, 0, 1), 1U);
}

TEST(ExtractBe, SingleBitReadsLsbOfByteZero) {
    // bit_pos=7 → byte 0 physical bit 0 (LSB).
    const uint8_t data[8] = {0x01, 0, 0, 0, 0, 0, 0, 0};
    EXPECT_EQ(extract_be(data, 7, 1), 1U);
}

TEST(ExtractBe, FourBitNibbleHighByte) {
    // 4-bit signal at start_bit=3 → reads physical bits 4,5,6,7.
    // data = 0xF0 (11110000) → physical bits 4..7 all set → 0b1111 = 15.
    const uint8_t data[8] = {0xF0, 0, 0, 0, 0, 0, 0, 0};
    EXPECT_EQ(extract_be(data, 3, 4), 0x0FU);
}

TEST(ExtractBe, EightBitsFromStartBitSeven) {
    // 8-bit signal at start_bit=7 reads byte 0 in bit-reversed order
    // (as documented by the Motorola DBC bit-walk algorithm).
    const uint8_t data[8] = {0xAB, 0, 0, 0, 0, 0, 0, 0};
    EXPECT_EQ(extract_be(data, 7, 8), 0xD5U); // bit-reverse of 0xAB
}

// ── normalize ───────────────────────────────────────────────────────────────

TEST(Normalize, UnsignedIdentity) {
    SignalDef def{};
    def.bit_length = 8;
    def.value_type = 0; // unsigned
    def.factor     = 1.0;
    def.offset     = 0.0;
    def.minimum    = 0.0;
    def.maximum    = 255.0;

    EXPECT_DOUBLE_EQ(normalize(128, def), 128.0);
}

TEST(Normalize, FactorAndOffset) {
    SignalDef def{};
    def.bit_length = 16;
    def.value_type = 0;
    def.factor     = 0.1;
    def.offset     = -40.0;
    def.minimum    = -40.0;
    def.maximum    = 215.0;

    // raw=400 → 400 * 0.1 + (-40) = 0.0
    EXPECT_DOUBLE_EQ(normalize(400, def), 0.0);
    // raw=2150 → 2150 * 0.1 - 40 = 175.0
    EXPECT_DOUBLE_EQ(normalize(2150, def), 175.0);
}

TEST(Normalize, ClampsToMaximum) {
    SignalDef def{};
    def.bit_length = 8;
    def.value_type = 0;
    def.factor     = 1.0;
    def.offset     = 0.0;
    def.minimum    = 0.0;
    def.maximum    = 100.0;

    EXPECT_DOUBLE_EQ(normalize(200, def), 100.0);
}

TEST(Normalize, ClampsToMinimum) {
    SignalDef def{};
    def.bit_length = 8;
    def.value_type = 0;
    def.factor     = 1.0;
    def.offset     = -200.0;
    def.minimum    = -50.0;
    def.maximum    = 100.0;

    // raw=0 → 0 - 200 = -200 → clamped to -50
    EXPECT_DOUBLE_EQ(normalize(0, def), -50.0);
}

TEST(Normalize, SignedNegative) {
    SignalDef def{};
    def.bit_length = 8;
    def.value_type = 1; // signed
    def.factor     = 1.0;
    def.offset     = 0.0;
    def.minimum    = -128.0;
    def.maximum    = 127.0;

    // raw = 0xFF → 8-bit signed = -1
    EXPECT_DOUBLE_EQ(normalize(0xFF, def), -1.0);
    // raw = 0x80 → -128
    EXPECT_DOUBLE_EQ(normalize(0x80, def), -128.0);
}

// ── EmaState ────────────────────────────────────────────────────────────────

TEST(EmaState, FirstInputPassesThrough) {
    EmaState ema{};
    EXPECT_DOUBLE_EQ(ema.update(42.0, 0.5), 42.0);
}

TEST(EmaState, ConvergesToInput) {
    EmaState ema{};
    ema.update(100.0, 0.5); // init
    for (int i = 0; i < 50; ++i)
        ema.update(50.0, 0.5);
    EXPECT_NEAR(ema.state, 50.0, 1e-6);
}

TEST(EmaState, AlphaOneTracksInput) {
    EmaState ema{};
    ema.update(0.0, 1.0);
    EXPECT_DOUBLE_EQ(ema.update(100.0, 1.0), 100.0);
}

TEST(EmaState, AlphaZeroHoldsFirst) {
    EmaState ema{};
    ema.update(42.0, 0.0);
    EXPECT_DOUBLE_EQ(ema.update(100.0, 0.0), 42.0);
    EXPECT_DOUBLE_EQ(ema.update(200.0, 0.0), 42.0);
}

// ── RateLimitState ──────────────────────────────────────────────────────────

TEST(RateLimitState, FirstInputPassesThrough) {
    RateLimitState rl{};
    EXPECT_DOUBLE_EQ(rl.update(100.0, 10.0, 1'000'000), 100.0);
}

TEST(RateLimitState, LargeStepIsClamped) {
    RateLimitState rl{};
    rl.update(0.0, 10.0, 0); // init at t=0
    // dt=1s, max_rate=10/s → max delta=10. Jump from 0 to 100 → clamped to 10.
    double v = rl.update(100.0, 10.0, 1'000'000);
    EXPECT_DOUBLE_EQ(v, 10.0);
}

TEST(RateLimitState, SmallStepPassesThrough) {
    RateLimitState rl{};
    rl.update(0.0, 100.0, 0);
    // dt=1s, max_rate=100 → max delta=100. Step of 5 passes freely.
    EXPECT_DOUBLE_EQ(rl.update(5.0, 100.0, 1'000'000), 5.0);
}

TEST(RateLimitState, ZeroDtHoldsLast) {
    RateLimitState rl{};
    rl.update(42.0, 10.0, 0);
    EXPECT_DOUBLE_EQ(rl.update(100.0, 10.0, 0), 42.0);
}

// ── HysteresisState ─────────────────────────────────────────────────────────

TEST(HysteresisState, FirstInputPassesThrough) {
    HysteresisState hyst{};
    EXPECT_DOUBLE_EQ(hyst.update(42.0, 5.0), 42.0);
}

TEST(HysteresisState, SmallChangeIsFiltered) {
    HysteresisState hyst{};
    hyst.update(100.0, 10.0);
    // Change of 5 < deadband of 10 → output stays at 100.
    EXPECT_DOUBLE_EQ(hyst.update(105.0, 10.0), 100.0);
}

TEST(HysteresisState, LargeChangePassesThrough) {
    HysteresisState hyst{};
    hyst.update(100.0, 10.0);
    // Change of 15 > deadband of 10 → output jumps to 115.
    EXPECT_DOUBLE_EQ(hyst.update(115.0, 10.0), 115.0);
}

TEST(HysteresisState, ExactDeadbandIsFiltered) {
    HysteresisState hyst{};
    hyst.update(0.0, 5.0);
    // |5 - 0| == 5 → NOT > 5, so filtered.
    EXPECT_DOUBLE_EQ(hyst.update(5.0, 5.0), 0.0);
}

// ── apply_filters ───────────────────────────────────────────────────────────

TEST(ApplyFilters, NoFiltersPassesThrough) {
    PerSignalState state{};
    state.filter_count = 0;
    EXPECT_DOUBLE_EQ(apply_filters(42.0, state, 0), 42.0);
}

TEST(ApplyFilters, SingleEmaFilter) {
    PerSignalState state{};
    state.filter_count = 1;
    state.configs[0].type = FilterType::Ema;
    state.configs[0].params.ema.alpha = 0.5;

    double v1 = apply_filters(100.0, state, 0); // init
    EXPECT_DOUBLE_EQ(v1, 100.0);

    double v2 = apply_filters(0.0, state, 1'000'000);
    EXPECT_DOUBLE_EQ(v2, 50.0); // 0.5*0 + 0.5*100
}

TEST(ApplyFilters, ChainedEmaAndHysteresis) {
    PerSignalState state{};
    state.filter_count = 2;

    // Filter 0: EMA with alpha=1.0 (passthrough)
    state.configs[0].type = FilterType::Ema;
    state.configs[0].params.ema.alpha = 1.0;

    // Filter 1: Hysteresis with deadband=10
    state.configs[1].type = FilterType::Hysteresis;
    state.configs[1].params.hysteresis.deadband = 10.0;

    apply_filters(100.0, state, 0); // init both
    // Small change → EMA passes it but hysteresis filters it.
    EXPECT_DOUBLE_EQ(apply_filters(105.0, state, 1'000'000), 100.0);
    // Large change → both pass.
    EXPECT_DOUBLE_EQ(apply_filters(120.0, state, 2'000'000), 120.0);
}
