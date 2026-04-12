// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to the engine.
typedef struct can_engine_t can_engine_t;

// ── Lifecycle ──

can_engine_t *engine_create(void);
void engine_destroy(can_engine_t *e);
int engine_start(can_engine_t *e, const char *interface_name);
void engine_stop(can_engine_t *e);

// ── Signal database ──
// signal_defs and message_defs must point to arrays matching the
// SignalDef / MessageDef struct layouts defined in snapshot.h.

void engine_load_signals(can_engine_t *e, const void *signal_defs,
                         uint32_t signal_count, const void *message_defs,
                         uint32_t message_count);

// ── Snapshot access ──

const void *engine_snapshot_ptr(const can_engine_t *e);
uint64_t engine_sequence(const can_engine_t *e);

// ── Filter chain ──

void engine_set_filter_chain(can_engine_t *e, uint32_t sig_idx,
                             const void *filters, uint8_t count);
void engine_clear_filter(can_engine_t *e, uint32_t sig_idx);
void engine_reset_filters(can_engine_t *e);

// ── CAN hardware filters ──

void engine_set_can_filters(can_engine_t *e, const void *filters,
                            uint32_t count);

// ── TX ──

int engine_send_frame(can_engine_t *e, uint32_t can_id, const uint8_t *data,
                      uint8_t dlc);
int engine_start_periodic_tx(can_engine_t *e, uint32_t can_id,
                             const uint8_t *data, uint8_t dlc,
                             uint32_t interval_ms);
void engine_stop_periodic_tx(can_engine_t *e, uint32_t can_id);
void engine_stop_all_periodic_tx(can_engine_t *e);

// ── Signal graphs ──

int engine_add_graph_signal(can_engine_t *e, uint32_t signal_index);
void engine_remove_graph_signal(can_engine_t *e, uint32_t signal_index);

// ── Display filter ──

void engine_set_display_filter(can_engine_t *e, const uint32_t *pass_ids,
                               uint32_t count);
void engine_clear_display_filter(can_engine_t *e);

// ── ISO-TP (ISO 15765-2) ──

int engine_isotp_open(can_engine_t *e, uint32_t tx_id, uint32_t rx_id);
void engine_isotp_close(can_engine_t *e);
int engine_isotp_send(can_engine_t *e, const uint8_t *data, uint32_t len);
int engine_isotp_recv(can_engine_t *e, uint8_t *buf, uint32_t buf_len,
                      int timeout_ms);

#ifdef __cplusplus
}
#endif
