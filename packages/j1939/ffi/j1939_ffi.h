// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/*
 * j1939_ffi.h — Dart/C++ boundary for the J1939 Linux stack
 *
 * Two-plane design
 * ────────────────
 * Control plane (Dart → C++, synchronous)
 *   All functions below map to dart:ffi @Native declarations.  They run on
 *   the calling Dart isolate thread and acquire the Ecu mutex internally.
 *
 * Event plane (C++ → Dart, asynchronous, zero-copy)
 *   The RX jthread calls Dart_PostCObject_DL(port, &envelope) from C++.
 *   Frame payloads use Dart_CObject_kExternalTypedData — the resulting
 *   Dart Uint8List points directly at a C++ pool buffer with no copy.
 *   When Dart GC collects the Uint8List the pool finalizer recycles the
 *   buffer.  No heap allocation on the hot receive path once pool is warm.
 *
 * Message envelope layout (each message is a Dart_CObject kArray)
 * ────────────────────────────────────────────────────────────────
 *   type 0  frame received
 *           [Int32:0, Int32:pgn, Int32:sa, Int32:da, ExternalTypedData:payload]
 *
 *   type 1  address claimed
 *           [Int32:1, Int32:address]
 *
 *   type 2  address claim failed (no free address)
 *           [Int32:2]
 *
 *   type 3  OS error (e.g. socket write failed on RX thread)
 *           [Int32:3, Int32:errno_code]
 *
 *   type 4  DM1 fault received from a remote ECU
 *           [Int32:4, Int32:source, Int32:spn, Int32:fmi, Int32:occurrence]
 *
 * Initialization
 * ──────────────
 *   Call j1939_initialize_api(NativeApi.initializeApiCallback) once before
 *   any other function.  This loads Dart_PostCObject_DL via dart_api_dl
 *   without a link-time dependency on the Dart VM library.
 *
 * Large-payload sends (BAM)
 * ─────────────────────────
 *   j1939_send() copies data immediately and returns.  For payloads > 8 bytes
 *   the BAM path blocks ~200–400 ms (inter-packet delay).  Call via
 *   Isolate.run() to avoid stalling the main isolate.
 */

#pragma once
#include <stdbool.h>
#include <stdint.h>

// The shared library is built with -fvisibility=hidden (see CMakeLists.txt),
// so every symbol Dart looks up via DynamicLibrary.lookupFunction must be
// explicitly tagged with default visibility. extern "C" alone is not enough.
#if defined(_WIN32) || defined(__CYGWIN__)
#  define J1939_FFI_EXPORT __declspec(dllexport)
#else
#  define J1939_FFI_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct J1939Handle_ J1939Handle;

// ── Initialization ────────────────────────────────────────────────────────────

// Store NativeApi.postCObject so the RX / ASIO threads can post CObjects.
// Call once from Dart before j1939_create().  Thread-safe by convention
// (call before any ECU is created).
J1939_FFI_EXPORT void j1939_set_post_cobject(void* fn);

// ── Lifecycle ─────────────────────────────────────────────────────────────────

// Create an ECU.  Starts address claiming immediately.
// event_port_id: RawReceivePort.sendPort.nativePort on the Dart side.
// Returns null on failure; j1939_last_error() gives the OS errno.
J1939_FFI_EXPORT J1939Handle* j1939_create(
    const char* ifname,
    uint8_t     preferred_address,
    uint32_t    identity_number,
    uint16_t    manufacturer_code,
    uint8_t     industry_group,
    int64_t     event_port_id
);

// Stop the RX thread and close the socket.  Safe from any thread.
J1939_FFI_EXPORT void j1939_destroy(J1939Handle* handle);

// errno value set by the most recent failed call on this thread.
J1939_FFI_EXPORT int32_t j1939_last_error(void);

// ── Transmit ──────────────────────────────────────────────────────────────────

// Copy data and transmit.  Automatically selects:
//   len ≤ 8             → single CAN frame
//   len > 8, broadcast  → BAM  (blocks ~200–400 ms, call from worker isolate)
//   len > 8, unicast    → RTS/CTS
// Returns 0 on success, -errno on failure.
J1939_FFI_EXPORT int32_t j1939_send(
    J1939Handle*   handle,
    uint32_t       pgn,
    uint8_t        priority,
    uint8_t        dest,
    const uint8_t* data,
    uint16_t       len
);

// ── Diagnostics ───────────────────────────────────────────────────────────────

J1939_FFI_EXPORT void j1939_add_dm1_fault(
    J1939Handle* handle,
    uint32_t     spn,
    uint8_t      fmi,
    uint8_t      occurrence
);

J1939_FFI_EXPORT void j1939_clear_dm1_faults(J1939Handle* handle);

// ── Convenience transmit ──────────────────────────────────────────────────────

// Send a PGN request (3-byte payload, PGN 0xEA00).
// Returns 0 on success, -errno on failure.
J1939_FFI_EXPORT int32_t j1939_send_request(
    J1939Handle* handle,
    uint8_t      dest,
    uint32_t     requested_pgn
);

// ── Async transmit ────────────────────────────────────────────────────────────
//
// Returns immediately.  When the full transmission completes (or fails),
// a type-5 message is posted to the ECU's event port:
//   [Int32: 5, Int32: send_id, Int32: errno]   (errno = 0 on success)
//
// send_id is chosen by the caller; use it to match completions to requests.
//
// For broadcast payloads > 8 bytes (BAM): runs on the ASIO thread — no Dart
// isolate or Pointer.fromAddress hack required.
// For unicast payloads > 8 bytes (RTS/CTS): calls on_complete with ENOTSUP
// immediately (full async RTS/CTS is not yet implemented).
J1939_FFI_EXPORT void j1939_send_async(
    J1939Handle*   handle,
    int32_t        send_id,
    uint32_t       pgn,
    uint8_t        priority,
    uint8_t        dest,
    const uint8_t* data,
    uint16_t       len
);

// ── State ─────────────────────────────────────────────────────────────────────

J1939_FFI_EXPORT uint8_t j1939_address(J1939Handle* handle);
J1939_FFI_EXPORT bool    j1939_address_claimed(J1939Handle* handle);

// ── Extended lifecycle (NMEA 2000) ───────────────────────────────────────────

// Create an ECU with full NAME field control.
// Same as j1939_create but accepts all J1939 NAME fields needed for NMEA 2000.
J1939_FFI_EXPORT J1939Handle* j1939_create_full(
    const char* ifname,
    uint8_t     preferred_address,
    uint32_t    identity_number,
    uint16_t    manufacturer_code,
    uint8_t     industry_group,
    uint8_t     device_function,
    uint8_t     device_class,
    uint8_t     function_instance,
    uint8_t     ecu_instance,
    int64_t     event_port_id
);

// ── NMEA 2000 Fast Packet ────────────────────────────────────────────────────

// Register a PGN transport type at runtime.
// transport: 0 = single, 1 = fast_packet, 2 = iso_tp.
// Takes effect immediately for all ECU instances.
J1939_FFI_EXPORT void nmea2000_set_pgn_transport(uint32_t pgn, uint8_t transport);

#ifdef __cplusplus
}
#endif
