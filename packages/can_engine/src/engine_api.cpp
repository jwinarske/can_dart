// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

#include "engine_api.h"
#include "engine.h"

#include <linux/can.h>

using can_engine::Engine;
using can_engine::FilterConfig;
using can_engine::MessageDef;
using can_engine::SignalDef;

struct can_engine_t {
    Engine engine;
};

// ── Lifecycle ──

can_engine_t* engine_create(void) { return new can_engine_t(); }

void engine_destroy(can_engine_t* e) {
    if (e) {
        e->engine.stop();
        delete e;
    }
}

int engine_start(can_engine_t* e, const char* interface_name) {
    if (!e)
        return -1;
    return e->engine.start(interface_name);
}

void engine_stop(can_engine_t* e) {
    if (e)
        e->engine.stop();
}

// ── Signal database ──

void engine_load_signals(can_engine_t* e, const void* signal_defs,
                         uint32_t signal_count, const void* message_defs,
                         uint32_t message_count) {
    if (!e)
        return;
    e->engine.load_signals(
        static_cast<const SignalDef*>(signal_defs), signal_count,
        static_cast<const MessageDef*>(message_defs), message_count);
}

// ── Snapshot access ──

const void* engine_snapshot_ptr(const can_engine_t* e) {
    if (!e)
        return nullptr;
    return e->engine.snapshot_ptr();
}

uint64_t engine_sequence(const can_engine_t* e) {
    if (!e)
        return 0;
    return e->engine.sequence();
}

// ── Filter chain ──

void engine_set_filter_chain(can_engine_t* e, uint32_t sig_idx,
                             const void* filters, uint8_t count) {
    if (!e)
        return;
    e->engine.set_filter_chain(
        sig_idx, static_cast<const FilterConfig*>(filters), count);
}

void engine_clear_filter(can_engine_t* e, uint32_t sig_idx) {
    if (!e)
        return;
    e->engine.clear_filter(sig_idx);
}

void engine_reset_filters(can_engine_t* e) {
    if (e)
        e->engine.reset_filters();
}

// ── CAN hardware filters ──

void engine_set_can_filters(can_engine_t* e, const void* filters,
                            uint32_t count) {
    if (!e)
        return;
    e->engine.set_can_filters(static_cast<const struct can_filter*>(filters),
                              count);
}

// ── TX ──

int engine_send_frame(can_engine_t* e, uint32_t can_id, const uint8_t* data,
                      uint8_t dlc) {
    if (!e)
        return -1;
    return e->engine.send_frame(can_id, data, dlc);
}

int engine_start_periodic_tx(can_engine_t* e, uint32_t can_id,
                             const uint8_t* data, uint8_t dlc,
                             uint32_t interval_ms) {
    if (!e)
        return -1;
    return e->engine.start_periodic_tx(can_id, data, dlc, interval_ms);
}

void engine_stop_periodic_tx(can_engine_t* e, uint32_t can_id) {
    if (e)
        e->engine.stop_periodic_tx(can_id);
}

void engine_stop_all_periodic_tx(can_engine_t* e) {
    if (e)
        e->engine.stop_all_periodic_tx();
}

// ── Signal graphs ──

int engine_add_graph_signal(can_engine_t* e, uint32_t signal_index) {
    if (!e)
        return -1;
    return e->engine.add_graph_signal(signal_index);
}

void engine_remove_graph_signal(can_engine_t* e, uint32_t signal_index) {
    if (e)
        e->engine.remove_graph_signal(signal_index);
}

// ── Display filter ──

void engine_set_display_filter(can_engine_t* e, const uint32_t* pass_ids,
                               uint32_t count) {
    if (e)
        e->engine.set_display_filter(pass_ids, count);
}

void engine_clear_display_filter(can_engine_t* e) {
    if (e)
        e->engine.clear_display_filter();
}

// ── ISO-TP ──

int engine_isotp_open(can_engine_t* e, uint32_t tx_id, uint32_t rx_id) {
    if (!e)
        return -1;
    return e->engine.isotp_open(tx_id, rx_id);
}

void engine_isotp_close(can_engine_t* e) {
    if (e)
        e->engine.isotp_close();
}

int engine_isotp_send(can_engine_t* e, const uint8_t* data, uint32_t len) {
    if (!e)
        return -1;
    return e->engine.isotp_send(data, len);
}

int engine_isotp_recv(can_engine_t* e, uint8_t* buf, uint32_t buf_len,
                      int timeout_ms) {
    if (!e)
        return -1;
    return e->engine.isotp_recv(buf, buf_len, timeout_ms);
}
