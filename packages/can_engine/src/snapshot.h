// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>

namespace can_engine {

// ── Size constants ──

constexpr size_t MAX_FRAMES = 200;
constexpr size_t MAX_MESSAGES = 512;
constexpr size_t MAX_SIGNALS = 256;
constexpr size_t MAX_TEXT_LEN = 128;
constexpr size_t MAX_NAME_LEN = 64;
constexpr size_t MAX_UNIT_LEN = 16;
constexpr size_t MAX_VAL_LEN = 32;
constexpr size_t MAX_GRAPH_POINTS = 1024;
constexpr size_t MAX_GRAPH_SIGNALS = 8;
constexpr int MAX_FILTERS = 4;

// ── Signal definition (loaded from DBC via can_dbc) ──

struct SignalDef {
    uint16_t start_bit;
    uint16_t bit_length;
    uint8_t byte_order; // 0=LE 1=BE
    uint8_t value_type; // 0=unsigned 1=signed
    uint8_t _pad[2];
    double factor, offset, minimum, maximum;
    char name[MAX_NAME_LEN];
    char unit[MAX_UNIT_LEN];
};

struct MessageDef {
    uint32_t can_id;
    uint32_t signal_offset;
    uint32_t signal_count;
};

// ── Filter types ──

enum class FilterType : uint8_t { None, Ema, RateLimit, Hysteresis };

struct FilterConfig {
    FilterType type {FilterType::None};
    uint8_t _pad[7];
    union {
        struct {
            double alpha;
        } ema;
        struct {
            double max_rate_per_sec;
        } rate_limit;
        struct {
            double deadband;
        } hysteresis;
    } params {};
};

// ── Filter states (pre-allocated, update in-place, zero allocation) ──

struct EmaState {
    double state {0};
    bool init {false};

    double update(double input, double alpha) {
        if (!init) {
            state = input;
            init = true;
            return input;
        }
        state = alpha * input + (1.0 - alpha) * state;
        return state;
    }
};

struct RateLimitState {
    double last {0};
    uint64_t last_ts {0};
    bool init {false};

    double update(double input, double max_rate, uint64_t ts_us) {
        if (!init) {
            last = input;
            last_ts = ts_us;
            init = true;
            return input;
        }
        double dt = static_cast<double>(ts_us - last_ts) / 1e6;
        if (dt <= 0)
            return last;
        double max_delta = max_rate * dt;
        double delta = input - last;
        if (delta > max_delta)
            delta = max_delta;
        else if (delta < -max_delta)
            delta = -max_delta;
        last += delta;
        last_ts = ts_us;
        return last;
    }
};

struct HysteresisState {
    double last_out {0};
    bool init {false};

    double update(double input, double deadband) {
        if (!init) {
            last_out = input;
            init = true;
            return input;
        }
        if (std::abs(input - last_out) > deadband)
            last_out = input;
        return last_out;
    }
};

struct PerSignalState {
    std::array<FilterConfig, MAX_FILTERS> configs {};
    uint8_t filter_count {0};
    EmaState ema[MAX_FILTERS] {};
    RateLimitState rate[MAX_FILTERS] {};
    HysteresisState hyst[MAX_FILTERS] {};
    double prev_value {0};
    bool subscribed {true};
};

// ── Overwrite mode row: one per unique CAN ID ──

struct MessageRow {
    uint32_t can_id;
    char name[MAX_NAME_LEN];
    uint8_t dlc;
    uint8_t direction; // 0=RX, 1=TX
    uint8_t _pad[2];
    uint8_t data[64];
    char data_hex[192];
    uint64_t timestamp_us;
    uint32_t count;
    uint32_t period_us;
    uint8_t highlight;
    uint8_t _pad2[3];
};

// ── Append mode row: chronological log ──

struct FrameRow {
    char text[MAX_TEXT_LEN];
    uint32_t can_id;
    uint8_t dlc;
    uint8_t direction;
    uint8_t _pad[2];
    uint64_t timestamp_us;
};

// ── Signal value snapshot ──

struct SignalSnapshot {
    char name[MAX_NAME_LEN];
    char formatted[MAX_VAL_LEN];
    char unit[MAX_UNIT_LEN];
    double value;
    double min_def;
    double max_def;
    uint8_t changed;
    uint8_t valid;
    uint8_t _pad[6];
};

// ── Signal graph history point ──

struct GraphPoint {
    double value;
    uint64_t timestamp_us;
};

struct SignalGraph {
    uint32_t signal_index;
    uint32_t head;
    uint32_t count;
    uint32_t _pad;
    GraphPoint points[MAX_GRAPH_POINTS];
};

// ── Bus statistics ──

struct BusStatistics {
    double bus_load_percent;
    uint32_t frames_per_second;
    uint32_t data_bytes_per_second;
    uint32_t error_frames;
    uint32_t overrun_count;

    uint8_t controller_state; // 0=active, 1=warning, 2=passive, 3=bus-off
    uint8_t tx_error_count;
    uint8_t rx_error_count;
    uint8_t _pad;

    uint64_t total_frames;
    uint64_t total_tx_frames;
    uint64_t total_rx_frames;
    uint64_t total_error_frames;
    uint64_t total_bytes;
    uint64_t uptime_us;

    double peak_bus_load;
    uint32_t peak_fps;
    uint32_t _pad2;
};

// ── Logging state ──

struct LogState {
    uint8_t active;
    uint8_t _pad[3];
    uint32_t _pad2;
    uint64_t logged_frames;
    uint64_t file_size_bytes;
    char filename[256];
};

// ── THE SNAPSHOT ──

struct alignas(64) DisplaySnapshot {
    std::atomic<uint64_t> sequence {0};

    // Overwrite mode
    std::array<MessageRow, MAX_MESSAGES> messages {};
    uint32_t message_count {0};

    // Append mode
    std::array<FrameRow, MAX_FRAMES> frames {};
    uint32_t frame_head {0};
    uint32_t frame_count {0};

    // Signal watch
    std::array<SignalSnapshot, MAX_SIGNALS> signals {};
    uint32_t signal_count {0};

    // Signal graphs
    std::array<SignalGraph, MAX_GRAPH_SIGNALS> graphs {};
    uint32_t graph_count {0};

    // Bus statistics
    BusStatistics stats {};

    // Logging
    LogState log {};

    // Engine state
    uint8_t running {0};
    uint8_t connected {0};
    uint8_t error_code {0};
    uint8_t _pad[5];
    char error_msg[128] {};
};

} // namespace can_engine
