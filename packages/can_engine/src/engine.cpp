#include "engine.h"

#include <net/if.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>
#include <linux/can.h>
#include <linux/can/isotp.h>
#include <linux/can/raw.h>
#include <poll.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>

namespace can_engine {

Engine::Engine()
    : busload_timer_(io_ctx_)
    , highlight_timer_(io_ctx_)
{}

Engine::~Engine() {
    stop();
}

// ── Lifecycle ──

int Engine::start(const char* interface_name) {
    if (snapshot_.running) return -1;

    interface_name_ = interface_name;
    int fd = open_socket(interface_name);
    if (fd < 0) return fd;

    sock_fd_ = fd;
    can_stream_ = std::make_unique<asio::posix::stream_descriptor>(io_ctx_, fd);

    // Reset state
    std::memset(&snapshot_, 0, sizeof(snapshot_));
    snapshot_.sequence.store(0, std::memory_order_relaxed);
    snapshot_.running = 1;
    snapshot_.connected = 1;
    busload_frame_count_ = 0;
    busload_byte_count_ = 0;
    busload_error_count_ = 0;
    start_time_us_ = now_us();

    // Initialize signal snapshots from defs
    snapshot_.signal_count = static_cast<uint32_t>(signal_defs_.size());
    for (uint32_t i = 0; i < snapshot_.signal_count && i < MAX_SIGNALS; ++i) {
        auto& ss = snapshot_.signals[i];
        std::strncpy(ss.name, signal_defs_[i].name, MAX_NAME_LEN - 1);
        std::strncpy(ss.unit, signal_defs_[i].unit, MAX_UNIT_LEN - 1);
        ss.min_def = signal_defs_[i].minimum;
        ss.max_def = signal_defs_[i].maximum;
        ss.value = 0;
        ss.valid = 0;
        ss.changed = 0;
        std::snprintf(ss.formatted, MAX_VAL_LEN, "---");
    }

    start_read();
    start_busload_timer();
    start_highlight_timer();

    io_thread_ = std::thread([this]() {
        io_ctx_.run();
    });

    return 0;
}

void Engine::stop() {
    if (!snapshot_.running) return;

    snapshot_.running = 0;
    snapshot_.connected = 0;

    stop_all_periodic_tx();

    io_ctx_.stop();
    if (io_thread_.joinable()) {
        io_thread_.join();
    }

    isotp_close();

    can_stream_.reset();
    if (sock_fd_ >= 0) {
        ::close(sock_fd_);
        sock_fd_ = -1;
    }

    io_ctx_.restart();
}

// ── Signal database ──

void Engine::load_signals(const SignalDef* signals, uint32_t signal_count,
                          const MessageDef* messages, uint32_t message_count) {
    signal_defs_.assign(signals, signals + signal_count);
    message_defs_.assign(messages, messages + message_count);

    msg_index_.clear();
    for (auto& md : message_defs_) {
        msg_index_[md.can_id] = &md;
    }

    signal_state_.resize(signal_count);
    for (auto& s : signal_state_) {
        s = PerSignalState{};
    }
}

// ── Filter chain ──

void Engine::set_filter_chain(uint32_t sig_idx, const FilterConfig* filters, uint8_t count) {
    if (sig_idx >= signal_state_.size()) return;
    auto& state = signal_state_[sig_idx];
    state.filter_count = std::min(count, static_cast<uint8_t>(MAX_FILTERS));
    for (uint8_t i = 0; i < state.filter_count; ++i) {
        state.configs[i] = filters[i];
        state.ema[i] = EmaState{};
        state.rate[i] = RateLimitState{};
        state.hyst[i] = HysteresisState{};
    }
}

void Engine::clear_filter(uint32_t sig_idx) {
    if (sig_idx >= signal_state_.size()) return;
    signal_state_[sig_idx].filter_count = 0;
}

void Engine::reset_filters() {
    for (auto& s : signal_state_) {
        s.filter_count = 0;
    }
}

// ── CAN hardware filters ──

void Engine::set_can_filters(const struct can_filter* filters, uint32_t count) {
    if (sock_fd_ < 0) return;
    setsockopt(sock_fd_, SOL_CAN_RAW, CAN_RAW_FILTER,
               filters, count * sizeof(struct can_filter));
}

// ── TX ──

int Engine::send_frame(uint32_t can_id, const uint8_t* data, uint8_t dlc) {
    if (sock_fd_ < 0) return -1;

    struct can_frame frame{};
    frame.can_id = can_id;
    frame.can_dlc = std::min(dlc, static_cast<uint8_t>(CAN_MAX_DLEN));
    std::memcpy(frame.data, data, frame.can_dlc);

    ssize_t nbytes = ::write(sock_fd_, &frame, sizeof(frame));
    if (nbytes < 0) return -1;

    // Record TX in snapshot
    uint64_t ts = now_us();
    update_message_row(can_id, data, dlc, ts);
    append_frame_row(can_id, data, dlc, ts);
    snapshot_.stats.total_tx_frames++;
    publish_snapshot();

    return 0;
}

int Engine::start_periodic_tx(uint32_t can_id, const uint8_t* data,
                              uint8_t dlc, uint32_t interval_ms) {
    if (sock_fd_ < 0) return -1;

    // Check if already exists
    for (auto& ptx : periodic_txs_) {
        if (ptx->can_id == can_id) {
            // Update existing
            ptx->frame.can_id = can_id;
            ptx->frame.can_dlc = std::min(dlc, static_cast<uint8_t>(CAN_MAX_DLEN));
            std::memcpy(ptx->frame.data, data, ptx->frame.can_dlc);
            ptx->interval_ms = interval_ms;
            if (!ptx->active) {
                ptx->active = true;
                schedule_periodic_tx(*ptx);
            }
            return 0;
        }
    }

    auto ptx = std::make_unique<PeriodicTx>(io_ctx_);
    ptx->can_id = can_id;
    ptx->frame.can_id = can_id;
    ptx->frame.can_dlc = std::min(dlc, static_cast<uint8_t>(CAN_MAX_DLEN));
    std::memcpy(ptx->frame.data, data, ptx->frame.can_dlc);
    ptx->interval_ms = interval_ms;
    ptx->active = true;

    auto* ptr = ptx.get();
    periodic_txs_.push_back(std::move(ptx));
    schedule_periodic_tx(*ptr);

    return 0;
}

void Engine::stop_periodic_tx(uint32_t can_id) {
    for (auto& ptx : periodic_txs_) {
        if (ptx->can_id == can_id) {
            ptx->active = false;
            ptx->timer.cancel();
            break;
        }
    }
}

void Engine::stop_all_periodic_tx() {
    for (auto& ptx : periodic_txs_) {
        ptx->active = false;
        ptx->timer.cancel();
    }
    periodic_txs_.clear();
}

void Engine::schedule_periodic_tx(PeriodicTx& ptx) {
    ptx.timer.expires_after(std::chrono::milliseconds(ptx.interval_ms));
    ptx.timer.async_wait([this, &ptx](const asio::error_code& ec) {
        if (ec || !ptx.active) return;
        ::write(sock_fd_, &ptx.frame, sizeof(ptx.frame));

        uint64_t ts = now_us();
        update_message_row(ptx.can_id, ptx.frame.data, ptx.frame.can_dlc, ts);
        snapshot_.stats.total_tx_frames++;
        publish_snapshot();

        schedule_periodic_tx(ptx);
    });
}

// ── Signal graphs ──

int Engine::add_graph_signal(uint32_t signal_index) {
    if (signal_index >= signal_defs_.size()) return -1;
    if (snapshot_.graph_count >= MAX_GRAPH_SIGNALS) return -1;

    // Check for duplicate
    for (uint32_t i = 0; i < snapshot_.graph_count; ++i) {
        if (snapshot_.graphs[i].signal_index == signal_index) return -1;
    }

    auto& g = snapshot_.graphs[snapshot_.graph_count];
    g.signal_index = signal_index;
    g.head = 0;
    g.count = 0;
    snapshot_.graph_count++;
    return 0;
}

void Engine::remove_graph_signal(uint32_t signal_index) {
    for (uint32_t i = 0; i < snapshot_.graph_count; ++i) {
        if (snapshot_.graphs[i].signal_index == signal_index) {
            // Shift remaining
            for (uint32_t j = i; j + 1 < snapshot_.graph_count; ++j) {
                snapshot_.graphs[j] = snapshot_.graphs[j + 1];
            }
            snapshot_.graph_count--;
            return;
        }
    }
}

void Engine::update_graph(uint32_t signal_index, double value, uint64_t ts_us) {
    for (uint32_t i = 0; i < snapshot_.graph_count; ++i) {
        if (snapshot_.graphs[i].signal_index == signal_index) {
            auto& g = snapshot_.graphs[i];
            g.points[g.head] = {value, ts_us};
            g.head = (g.head + 1) % MAX_GRAPH_POINTS;
            if (g.count < MAX_GRAPH_POINTS) g.count++;
            return;
        }
    }
}

// ── Display filter ──

void Engine::set_display_filter(const uint32_t* pass_ids, uint32_t count) {
    display_filter_ids_.clear();
    for (uint32_t i = 0; i < count; ++i) {
        display_filter_ids_.insert(pass_ids[i]);
    }
    display_filter_active_ = true;
}

void Engine::clear_display_filter() {
    display_filter_ids_.clear();
    display_filter_active_ = false;
}

// ── Socket ──

int Engine::open_socket(const char* interface_name) {
    int fd = ::socket(AF_CAN, SOCK_RAW, CAN_RAW);
    if (fd < 0) {
        std::snprintf(snapshot_.error_msg, sizeof(snapshot_.error_msg),
                     "socket() failed: %s", strerror(errno));
        snapshot_.error_code = 1;
        return -1;
    }

    struct ifreq ifr{};
    std::strncpy(ifr.ifr_name, interface_name, IFNAMSIZ - 1);
    if (ioctl(fd, SIOCGIFINDEX, &ifr) < 0) {
        std::snprintf(snapshot_.error_msg, sizeof(snapshot_.error_msg),
                     "ioctl(SIOCGIFINDEX) failed for %s: %s",
                     interface_name, strerror(errno));
        snapshot_.error_code = 2;
        ::close(fd);
        return -1;
    }

    struct sockaddr_can addr{};
    addr.can_family = AF_CAN;
    addr.can_ifindex = ifr.ifr_ifindex;
    if (::bind(fd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) < 0) {
        std::snprintf(snapshot_.error_msg, sizeof(snapshot_.error_msg),
                     "bind() failed: %s", strerror(errno));
        snapshot_.error_code = 3;
        ::close(fd);
        return -1;
    }

    return fd;
}

// ── Async read loop ──

void Engine::start_read() {
    can_stream_->async_read_some(
        asio::buffer(frame_buffer_, sizeof(struct can_frame)),
        [this](const asio::error_code& ec, std::size_t bytes) {
            on_frame(ec, bytes);
        });
}

void Engine::on_frame(const asio::error_code& ec, std::size_t bytes) {
    if (ec) {
        if (ec != asio::error::operation_aborted) {
            std::snprintf(snapshot_.error_msg, sizeof(snapshot_.error_msg),
                         "read error: %s", ec.message().c_str());
            snapshot_.error_code = 4;
        }
        return;
    }

    if (bytes >= sizeof(struct can_frame)) {
        auto* frame = reinterpret_cast<struct can_frame*>(frame_buffer_);
        uint64_t ts = now_us();
        process_frame(frame, ts);
    }

    // Continue reading
    if (snapshot_.running) {
        start_read();
    }
}

void Engine::process_frame(const struct can_frame* frame, uint64_t ts_us) {
    uint32_t can_id = frame->can_id & CAN_EFF_MASK;
    if (frame->can_id & CAN_EFF_FLAG) {
        can_id = frame->can_id & CAN_EFF_MASK;
    } else {
        can_id = frame->can_id & CAN_SFF_MASK;
    }

    // Bus load counters
    busload_frame_count_++;
    busload_byte_count_ += frame->can_dlc;

    // Error frame
    if (frame->can_id & CAN_ERR_FLAG) {
        busload_error_count_++;
        snapshot_.stats.total_error_frames++;
        return;
    }

    // Stats
    snapshot_.stats.total_frames++;
    snapshot_.stats.total_rx_frames++;
    snapshot_.stats.total_bytes += frame->can_dlc;

    // Update overwrite mode (message row)
    update_message_row(can_id, frame->data, frame->can_dlc, ts_us);

    // Update append mode (frame row)
    append_frame_row(can_id, frame->data, frame->can_dlc, ts_us);

    // Decode signals
    decode_signals(can_id, frame->data, ts_us);

    // Publish
    publish_snapshot();
}

void Engine::decode_signals(uint32_t can_id, const uint8_t* data, uint64_t ts_us) {
    auto it = msg_index_.find(can_id);
    if (it == msg_index_.end()) return;

    const auto& mdef = *it->second;
    for (uint32_t i = 0; i < mdef.signal_count; ++i) {
        uint32_t sig_idx = mdef.signal_offset + i;
        if (sig_idx >= signal_defs_.size() || sig_idx >= MAX_SIGNALS) continue;

        const auto& sdef = signal_defs_[sig_idx];
        auto& sstate = signal_state_[sig_idx];
        auto& ss = snapshot_.signals[sig_idx];

        if (!sstate.subscribed) continue;

        // Extract raw bits
        uint64_t raw;
        if (sdef.byte_order == 0) {
            raw = extract_le(data, sdef.start_bit, sdef.bit_length);
        } else {
            raw = extract_be(data, sdef.start_bit, sdef.bit_length);
        }

        // Normalize to physical value
        double value = normalize(raw, sdef);

        // Apply filter chain
        value = apply_filters(value, sstate, ts_us);

        // Update snapshot
        ss.changed = (value != sstate.prev_value) ? 1 : 0;
        sstate.prev_value = value;
        ss.value = value;
        ss.valid = 1;
        std::snprintf(ss.formatted, MAX_VAL_LEN, "%.4g", value);

        // Update graph if tracking this signal
        update_graph(sig_idx, value, ts_us);
    }
}

void Engine::update_message_row(uint32_t can_id, const uint8_t* data,
                                uint8_t dlc, uint64_t ts_us) {
    // Find existing or create new
    MessageRow* row = nullptr;
    for (uint32_t i = 0; i < snapshot_.message_count; ++i) {
        if (snapshot_.messages[i].can_id == can_id) {
            row = &snapshot_.messages[i];
            break;
        }
    }

    if (!row && snapshot_.message_count < MAX_MESSAGES) {
        row = &snapshot_.messages[snapshot_.message_count++];
        row->can_id = can_id;
        row->count = 0;
        row->period_us = 0;
        row->direction = 0;

        // Try to find DBC name
        auto it = msg_index_.find(can_id);
        if (it != msg_index_.end()) {
            // Find the name from signal defs (message name is in the DBC)
            std::snprintf(row->name, MAX_NAME_LEN, "0x%X", can_id);
        } else {
            std::snprintf(row->name, MAX_NAME_LEN, "0x%X", can_id);
        }
    }

    if (!row) return;

    // Measure period
    if (row->count > 0 && ts_us > row->timestamp_us) {
        row->period_us = static_cast<uint32_t>(ts_us - row->timestamp_us);
    }

    row->dlc = dlc;
    std::memcpy(row->data, data, std::min(dlc, static_cast<uint8_t>(64)));
    format_hex(data, dlc, row->data_hex, sizeof(row->data_hex));
    row->timestamp_us = ts_us;
    row->count++;
    row->highlight = 1;
}

void Engine::append_frame_row(uint32_t can_id, const uint8_t* data,
                              uint8_t dlc, uint64_t ts_us) {
    // Skip display-filtered frames
    if (display_filter_active_ &&
        display_filter_ids_.find(can_id) == display_filter_ids_.end()) {
        return;
    }

    auto& row = snapshot_.frames[snapshot_.frame_head];
    row.can_id = can_id;
    row.dlc = dlc;
    row.direction = 0;
    row.timestamp_us = ts_us;
    format_frame_text(can_id, data, dlc, ts_us, row.text, MAX_TEXT_LEN);

    snapshot_.frame_head = (snapshot_.frame_head + 1) % MAX_FRAMES;
    if (snapshot_.frame_count < MAX_FRAMES) {
        snapshot_.frame_count++;
    }
}

void Engine::publish_snapshot() {
    // Seqlock: odd sequence = write in progress
    snapshot_.sequence.store(snapshot_.sequence.load(std::memory_order_relaxed) + 1,
                           std::memory_order_release);
    // Data is already written in-place — no copy needed
    snapshot_.stats.uptime_us = now_us() - start_time_us_;
    // Even sequence = consistent
    snapshot_.sequence.store(snapshot_.sequence.load(std::memory_order_relaxed) + 1,
                           std::memory_order_release);
}

// ── Bus load timer (1 Hz) ──

void Engine::start_busload_timer() {
    busload_timer_.expires_after(std::chrono::seconds(1));
    busload_timer_.async_wait([this](const asio::error_code& ec) {
        on_busload_tick(ec);
    });
}

void Engine::on_busload_tick(const asio::error_code& ec) {
    if (ec) return;

    snapshot_.stats.frames_per_second = busload_frame_count_;
    snapshot_.stats.data_bytes_per_second = busload_byte_count_;
    snapshot_.stats.error_frames = busload_error_count_;

    // Bus load estimate: assume 500 kbit/s, standard CAN frame overhead ~111 bits + data
    // This is a rough estimate; accurate calculation requires bitrate config
    double bits_per_sec = 0;
    // Average frame: 47 bits overhead + 8*dlc data bits (standard CAN)
    if (busload_frame_count_ > 0) {
        double avg_dlc = static_cast<double>(busload_byte_count_) / busload_frame_count_;
        bits_per_sec = busload_frame_count_ * (47.0 + 8.0 * avg_dlc);
    }
    double bus_load = bits_per_sec / 500000.0 * 100.0; // Assume 500 kbit/s
    snapshot_.stats.bus_load_percent = std::min(bus_load, 100.0);

    if (snapshot_.stats.bus_load_percent > snapshot_.stats.peak_bus_load) {
        snapshot_.stats.peak_bus_load = snapshot_.stats.bus_load_percent;
    }
    if (busload_frame_count_ > snapshot_.stats.peak_fps) {
        snapshot_.stats.peak_fps = busload_frame_count_;
    }

    busload_frame_count_ = 0;
    busload_byte_count_ = 0;
    busload_error_count_ = 0;

    publish_snapshot();

    if (snapshot_.running) {
        start_busload_timer();
    }
}

// ── Highlight decay timer (200ms) ──

void Engine::start_highlight_timer() {
    highlight_timer_.expires_after(std::chrono::milliseconds(200));
    highlight_timer_.async_wait([this](const asio::error_code& ec) {
        on_highlight_tick(ec);
    });
}

void Engine::on_highlight_tick(const asio::error_code& ec) {
    if (ec) return;

    for (uint32_t i = 0; i < snapshot_.message_count; ++i) {
        snapshot_.messages[i].highlight = 0;
    }

    if (snapshot_.running) {
        start_highlight_timer();
    }
}

// ── Utility ──

uint64_t Engine::now_us() const {
    auto now = std::chrono::steady_clock::now();
    return static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            now.time_since_epoch()).count());
}

void Engine::format_hex(const uint8_t* data, uint8_t dlc, char* out, size_t out_len) {
    size_t pos = 0;
    for (uint8_t i = 0; i < dlc && pos + 3 < out_len; ++i) {
        if (i > 0) out[pos++] = ' ';
        pos += std::snprintf(out + pos, out_len - pos, "%02X", data[i]);
    }
    if (pos < out_len) out[pos] = '\0';
}

void Engine::format_frame_text(uint32_t can_id, const uint8_t* data,
                               uint8_t dlc, uint64_t ts_us,
                               char* out, size_t out_len) {
    double ts_sec = static_cast<double>(ts_us) / 1e6;
    char hex[192];
    format_hex(data, dlc, hex, sizeof(hex));
    std::snprintf(out, out_len, "%10.6f  %03X  [%u]  %s",
                 ts_sec, can_id, dlc, hex);
}

// ── ISO-TP (ISO 15765-2) ──

int Engine::isotp_open(uint32_t tx_id, uint32_t rx_id) {
    if (isotp_fd_ >= 0) {
        // Already open — close first
        isotp_close();
    }

    if (interface_name_.empty()) {
        std::snprintf(snapshot_.error_msg, sizeof(snapshot_.error_msg),
                     "isotp_open: engine not started");
        return -1;
    }

    int fd = ::socket(AF_CAN, SOCK_DGRAM, CAN_ISOTP);
    if (fd < 0) {
        std::snprintf(snapshot_.error_msg, sizeof(snapshot_.error_msg),
                     "isotp socket() failed: %s", strerror(errno));
        return -1;
    }

    struct ifreq ifr{};
    std::strncpy(ifr.ifr_name, interface_name_.c_str(), IFNAMSIZ - 1);
    if (ioctl(fd, SIOCGIFINDEX, &ifr) < 0) {
        std::snprintf(snapshot_.error_msg, sizeof(snapshot_.error_msg),
                     "isotp ioctl(SIOCGIFINDEX) failed: %s", strerror(errno));
        ::close(fd);
        return -1;
    }

    struct sockaddr_can addr{};
    addr.can_family = AF_CAN;
    addr.can_ifindex = ifr.ifr_ifindex;
    addr.can_addr.tp.tx_id = tx_id;
    addr.can_addr.tp.rx_id = rx_id;

    if (::bind(fd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) < 0) {
        std::snprintf(snapshot_.error_msg, sizeof(snapshot_.error_msg),
                     "isotp bind() failed: %s", strerror(errno));
        ::close(fd);
        return -1;
    }

    isotp_fd_ = fd;
    return 0;
}

void Engine::isotp_close() {
    if (isotp_fd_ >= 0) {
        ::close(isotp_fd_);
        isotp_fd_ = -1;
    }
}

int Engine::isotp_send(const uint8_t* data, uint32_t len) {
    if (isotp_fd_ < 0) return -1;

    ssize_t ret = ::write(isotp_fd_, data, len);
    if (ret < 0) {
        std::snprintf(snapshot_.error_msg, sizeof(snapshot_.error_msg),
                     "isotp write() failed: %s", strerror(errno));
        return -1;
    }
    return static_cast<int>(ret);
}

int Engine::isotp_recv(uint8_t* buf, uint32_t buf_len, int timeout_ms) {
    if (isotp_fd_ < 0) return -1;

    if (timeout_ms >= 0) {
        struct pollfd pfd{};
        pfd.fd = isotp_fd_;
        pfd.events = POLLIN;
        int ret = ::poll(&pfd, 1, timeout_ms);
        if (ret < 0) {
            std::snprintf(snapshot_.error_msg, sizeof(snapshot_.error_msg),
                         "isotp poll() failed: %s", strerror(errno));
            return -1;
        }
        if (ret == 0) return 0; // timeout
    }

    ssize_t ret = ::read(isotp_fd_, buf, buf_len);
    if (ret < 0) {
        std::snprintf(snapshot_.error_msg, sizeof(snapshot_.error_msg),
                     "isotp read() failed: %s", strerror(errno));
        return -1;
    }
    return static_cast<int>(ret);
}

} // namespace can_engine
