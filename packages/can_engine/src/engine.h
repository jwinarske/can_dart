#pragma once

#include <asio.hpp>
#include <linux/can.h>
#include <linux/can/raw.h>

#include <cstdint>
#include <memory>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "bit_extract.h"
#include "snapshot.h"

namespace can_engine {

/// Periodic TX entry.
struct PeriodicTx {
    uint32_t can_id;
    struct can_frame frame;
    asio::steady_timer timer;
    uint32_t interval_ms;
    bool active{false};

    PeriodicTx(asio::io_context& io) : timer(io) {}
};

class Engine {
public:
    Engine();
    ~Engine();

    // Lifecycle
    int  start(const char* interface_name);
    void stop();

    // Signal database
    void load_signals(const SignalDef* signals, uint32_t signal_count,
                      const MessageDef* messages, uint32_t message_count);

    // Snapshot access (Dart reads this via Pointer.ref)
    const DisplaySnapshot* snapshot_ptr() const { return &snapshot_; }
    uint64_t sequence() const {
        return snapshot_.sequence.load(std::memory_order_acquire);
    }

    // Filter chain
    void set_filter_chain(uint32_t sig_idx, const FilterConfig* filters, uint8_t count);
    void clear_filter(uint32_t sig_idx);
    void reset_filters();

    // CAN hardware filters
    void set_can_filters(const struct can_filter* filters, uint32_t count);

    // TX
    int  send_frame(uint32_t can_id, const uint8_t* data, uint8_t dlc);
    int  start_periodic_tx(uint32_t can_id, const uint8_t* data,
                           uint8_t dlc, uint32_t interval_ms);
    void stop_periodic_tx(uint32_t can_id);
    void stop_all_periodic_tx();

    // Signal graphs
    int  add_graph_signal(uint32_t signal_index);
    void remove_graph_signal(uint32_t signal_index);

    // Display filter (UI-level)
    void set_display_filter(const uint32_t* pass_ids, uint32_t count);
    void clear_display_filter();

private:
    // Asio
    asio::io_context               io_ctx_;
    std::unique_ptr<asio::posix::stream_descriptor> can_stream_;
    std::thread                    io_thread_;
    asio::steady_timer             busload_timer_;
    asio::steady_timer             highlight_timer_;

    // Socket
    int sock_fd_{-1};
    std::string interface_name_;

    // THE frame buffer — read() writes here, everything reads from here
    alignas(8) uint8_t frame_buffer_[72]{};

    // Signal definitions
    std::vector<SignalDef>  signal_defs_;
    std::vector<MessageDef> message_defs_;
    std::unordered_map<uint32_t, const MessageDef*> msg_index_;

    // Per-signal filter state
    std::vector<PerSignalState> signal_state_;

    // Periodic TX entries
    std::vector<std::unique_ptr<PeriodicTx>> periodic_txs_;

    // Display filter
    std::unordered_set<uint32_t> display_filter_ids_;
    bool display_filter_active_{false};

    // Bus load calculation
    uint32_t busload_frame_count_{0};
    uint32_t busload_byte_count_{0};
    uint32_t busload_error_count_{0};

    // Timestamps
    uint64_t start_time_us_{0};

    // THE snapshot — Dart reads this via Pointer.ref
    alignas(64) DisplaySnapshot snapshot_;

    // Internal methods
    int  open_socket(const char* interface_name);
    void start_read();
    void on_frame(const asio::error_code& ec, std::size_t bytes);
    void process_frame(const struct can_frame* frame, uint64_t ts_us);
    void decode_signals(uint32_t can_id, const uint8_t* data, uint64_t ts_us);
    void update_message_row(uint32_t can_id, const uint8_t* data,
                           uint8_t dlc, uint64_t ts_us);
    void append_frame_row(uint32_t can_id, const uint8_t* data,
                         uint8_t dlc, uint64_t ts_us);
    void update_graph(uint32_t signal_index, double value, uint64_t ts_us);
    void publish_snapshot();

    void start_busload_timer();
    void on_busload_tick(const asio::error_code& ec);

    void start_highlight_timer();
    void on_highlight_tick(const asio::error_code& ec);

    void schedule_periodic_tx(PeriodicTx& ptx);

    uint64_t now_us() const;

    static void format_hex(const uint8_t* data, uint8_t dlc, char* out, size_t out_len);
    static void format_frame_text(uint32_t can_id, const uint8_t* data,
                                  uint8_t dlc, uint64_t ts_us, char* out, size_t out_len);
};

} // namespace can_engine
