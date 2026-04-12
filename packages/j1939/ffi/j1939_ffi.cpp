// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// j1939_ffi.cpp — Dart FFI implementation layer
//
// Depends on:
//   • j1939_ffi.h          — C API surface
//   • j1939/Ecu.hpp        — C++23 J1939 stack
//   • dart_native_api.h    — Dart_PostCObject_DL, Dart_CObject
//
// Build as a shared library:
//   add_library(j1939_plugin SHARED
//       ../src/can/Socket.cpp
//       ../src/j1939/Transport.cpp
//       ../src/j1939/Network.cpp
//       ../src/j1939/Ecu.cpp
//       j1939_ffi.cpp)
//   target_include_directories(j1939_plugin PRIVATE
//       ../src
//       ${DART_SDK}/include)
//   target_link_libraries(j1939_plugin PRIVATE pthread)
//   set_target_properties(j1939_plugin PROPERTIES
//       CXX_STANDARD 23
//       POSITION_INDEPENDENT_CODE ON)

#include "j1939_ffi.h"

// dart_native_api.h from the Dart SDK defines Dart_CObject and Dart_Port_DL.
// We no longer use dart_api_dl.h or its associated dart_api_dl.c compilation
// unit.  Instead, j1939_set_post_cobject() receives NativeApi.postCObject
// directly from Dart and stores it as a plain function pointer.
#include "dart_native_api.h"

// Function pointer set once at startup via j1939_set_post_cobject().
// NativeApi.postCObject in Dart has C signature:
//   int8_t Dart_PostCObject(int64_t port_id, Dart_CObject* message)
using PostCObjectFn = int8_t (*)(int64_t port_id, Dart_CObject *message);
static PostCObjectFn g_post_cobject = nullptr;

#include "j1939/Ecu.hpp"
#include "j1939/PgnTransport.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <mutex>
#include <vector>

using namespace j1939;

// ── Buffer pool
// ───────────────────────────────────────────────────────────────
//
// Pre-allocates kPoolSize buffers so the hot receive path never calls new[].
// The Dart finalizer (called when GC releases a Uint8List) returns the buffer
// to the pool rather than freeing it.
//
// If all pool buffers are in-flight simultaneously the pool falls back to a
// plain new[] / delete[] allocation.  This is detectable via acquire_count and
// pool_hit_count if profiling is needed.

namespace {

inline constexpr size_t kPoolSize = 32U;
inline constexpr size_t kMaxFrameSize = 1800U;

// PoolBuf — buffer node for pool-resident and fallback allocations.
//
// Pool-resident bufs (from_pool = true):
//   owner_raw is a plain BufPool* because g_pool has process lifetime and
//   always outlives any in-flight Dart Uint8List.
//
// Fallback bufs (from_pool = false):
//   The pool was exhausted at acquire() time.  The buf is heap-allocated and
//   carries a shared_ptr<BufPool> (owner_shared) that prevents the pool from
//   being destroyed while the Dart GC still holds a reference to this buffer.
//   Without this, if an ECU is disposed while a fallback buf is live in Dart,
//   the finalizer would dereference a freed pool.

struct BufPool;

struct PoolBuf {
  uint8_t data[kMaxFrameSize];
  BufPool *owner_raw = nullptr;          // for pool-resident bufs
  std::shared_ptr<BufPool> owner_shared; // for fallback bufs
  bool from_pool = false;
};

struct BufPool : std::enable_shared_from_this<BufPool> {
  std::array<PoolBuf, kPoolSize> storage{};
  std::vector<PoolBuf *> free_list;
  std::mutex mutex;

  BufPool() {
    free_list.reserve(kPoolSize);
    for (auto &b : storage) {
      b.owner_raw = this;
      b.from_pool = true;
      free_list.push_back(&b);
    }
  }

  PoolBuf *acquire() {
    const std::scoped_lock lock{mutex};
    if (!free_list.empty()) {
      PoolBuf *b = free_list.back();
      free_list.pop_back();
      return b;
    }
    // Pool exhausted: heap fallback.  Share ownership so the pool stays
    // alive at least as long as this buffer does.
    auto *b = new PoolBuf{};
    b->owner_shared = shared_from_this();
    b->from_pool = false;
    return b;
  }

  // Dart finalizer — called on the GC thread when the Uint8List is collected.
  static void release(void * /*isolate_data*/, void *peer) noexcept {
    auto *b = static_cast<PoolBuf *>(peer);
    if (b->from_pool) {
      const std::scoped_lock lock{b->owner_raw->mutex};
      b->owner_raw->free_list.push_back(b);
    } else {
      // Dropping owner_shared here: if the pool has already been
      // destroyed, this is the last reference and the pool is freed.
      delete b;
    }
  }
};

// g_pool must be a shared_ptr so enable_shared_from_this works in acquire().
std::shared_ptr<BufPool> g_pool = std::make_shared<BufPool>();
thread_local int32_t tl_last_error = 0;

// ── CObject helpers
// ───────────────────────────────────────────────────────────
//
// All CObject structs are stack-allocated.  Dart_PostCObject_DL copies the
// structure before returning, so stack allocation is safe.  Only the external
// typed data buffer (PoolBuf::data) must outlive the call — the finalizer
// handles its lifetime.

void post_frame(Dart_Port port, uint32_t pgn, uint8_t sa, uint8_t da,
                const uint8_t *src, size_t len) noexcept {
  PoolBuf *buf = g_pool->acquire();
  const size_t n = std::min(len, kMaxFrameSize);
  std::copy_n(src, n, buf->data);

  Dart_CObject type_obj{Dart_CObject_kInt32, {.as_int32 = 0}};
  Dart_CObject pgn_obj{Dart_CObject_kInt32,
                       {.as_int32 = static_cast<int32_t>(pgn)}};
  Dart_CObject sa_obj{Dart_CObject_kInt32, {.as_int32 = sa}};
  Dart_CObject da_obj{Dart_CObject_kInt32, {.as_int32 = da}};

  Dart_CObject data_obj;
  data_obj.type = Dart_CObject_kExternalTypedData;
  data_obj.value.as_external_typed_data.type = Dart_TypedData_kUint8;
  data_obj.value.as_external_typed_data.length = static_cast<intptr_t>(n);
  data_obj.value.as_external_typed_data.data = buf->data;
  data_obj.value.as_external_typed_data.peer = buf;
  data_obj.value.as_external_typed_data.callback = BufPool::release;

  Dart_CObject *fields[] = {&type_obj, &pgn_obj, &sa_obj, &da_obj, &data_obj};
  Dart_CObject envelope;
  envelope.type = Dart_CObject_kArray;
  envelope.value.as_array.length = 5;
  envelope.value.as_array.values = fields;

  g_post_cobject(port, &envelope);
}

void post_address_claimed(Dart_Port port, uint8_t address) noexcept {
  Dart_CObject t{Dart_CObject_kInt32, {.as_int32 = 1}};
  Dart_CObject a{Dart_CObject_kInt32, {.as_int32 = address}};
  Dart_CObject *fields[] = {&t, &a};
  Dart_CObject env;
  env.type = Dart_CObject_kArray;
  env.value.as_array.length = 2;
  env.value.as_array.values = fields;
  g_post_cobject(port, &env);
}

void post_address_failed(Dart_Port port) noexcept {
  Dart_CObject t{Dart_CObject_kInt32, {.as_int32 = 2}};
  Dart_CObject *fields[] = {&t};
  Dart_CObject env;
  env.type = Dart_CObject_kArray;
  env.value.as_array.length = 1;
  env.value.as_array.values = fields;
  g_post_cobject(port, &env);
}

void post_error(Dart_Port port, int32_t err) noexcept {
  Dart_CObject t{Dart_CObject_kInt32, {.as_int32 = 3}};
  Dart_CObject e{Dart_CObject_kInt32, {.as_int32 = err}};
  Dart_CObject *fields[] = {&t, &e};
  Dart_CObject env;
  env.type = Dart_CObject_kArray;
  env.value.as_array.length = 2;
  env.value.as_array.values = fields;
  g_post_cobject(port, &env);
}

void post_dm1(Dart_Port port, uint8_t source, uint32_t spn, uint8_t fmi,
              uint8_t occurrence) noexcept {
  Dart_CObject t{Dart_CObject_kInt32, {.as_int32 = 4}};
  Dart_CObject src{Dart_CObject_kInt32, {.as_int32 = source}};
  Dart_CObject s{Dart_CObject_kInt32, {.as_int32 = static_cast<int32_t>(spn)}};
  Dart_CObject f{Dart_CObject_kInt32, {.as_int32 = fmi}};
  Dart_CObject occ{Dart_CObject_kInt32, {.as_int32 = occurrence}};
  Dart_CObject *fields[] = {&t, &src, &s, &f, &occ};
  Dart_CObject env;
  env.type = Dart_CObject_kArray;
  env.value.as_array.length = 5;
  env.value.as_array.values = fields;
  g_post_cobject(port, &env);
}

void post_send_complete(Dart_Port port, int32_t send_id,
                        int32_t errno_val) noexcept {
  Dart_CObject t{Dart_CObject_kInt32, {.as_int32 = 5}};
  Dart_CObject id{Dart_CObject_kInt32, {.as_int32 = send_id}};
  Dart_CObject e{Dart_CObject_kInt32, {.as_int32 = errno_val}};
  Dart_CObject *fields[] = {&t, &id, &e};
  Dart_CObject env;
  env.type = Dart_CObject_kArray;
  env.value.as_array.length = 3;
  env.value.as_array.values = fields;
  g_post_cobject(port, &env);
}

} // namespace

// ── Handle
// ────────────────────────────────────────────────────────────────────

struct J1939Handle_ {
  std::unique_ptr<Ecu> ecu;
  Dart_Port event_port;
};

// ── Public C API
// ──────────────────────────────────────────────────────────────

extern "C" {

// Store NativeApi.postCObject so the RX/ASIO threads can post CObjects.
// Called once from Dart before j1939_create().  Thread-safe by convention
// (call before any ECU is created).
void j1939_set_post_cobject(void *fn) {
  g_post_cobject = reinterpret_cast<PostCObjectFn>(fn);
}

int32_t j1939_last_error(void) { return tl_last_error; }

J1939Handle *j1939_create(const char *ifname, uint8_t preferred_address,
                          uint32_t identity_number, uint16_t manufacturer_code,
                          uint8_t industry_group, int64_t event_port_id) {
  // Designated initializers must appear in declaration order (C++20).
  // See j1939::Name in src/j1939/Types.hpp — arbitrary_address is declared
  // before industry_group.
  const Name name{
      .identity_number = identity_number,
      .manufacturer_code = manufacturer_code,
      .arbitrary_address = true,
      .industry_group = industry_group,
  };

  auto result = Ecu::create(ifname, preferred_address, name);
  if (!result) {
    tl_last_error = result.error().value();
    return nullptr;
  }

  auto *h = new J1939Handle_{};
  h->event_port = static_cast<Dart_Port>(event_port_id);
  h->ecu = std::move(*result);

  const Dart_Port port = h->event_port;

  // on_message fires on the C++ RX thread — Dart_PostCObject_DL is thread-safe.
  h->ecu->on_message([port](const Frame &f) {
    // DM1 PGN — parse faults and post individual fault events.
    if (f.pgn == static_cast<uint32_t>(Pgn::Dm1) && f.data.size() >= 6U) {
      const size_t fault_count = (f.data.size() - 2U) / 4U;
      for (size_t i = 0U; i < fault_count; ++i) {
        const size_t base = 2U + i * 4U;
        const uint32_t spn =
            static_cast<uint32_t>(f.data[base]) |
            (static_cast<uint32_t>(f.data[base + 1U]) << 8U) |
            (static_cast<uint32_t>(f.data[base + 2U] & 0x07U) << 16U);
        const uint8_t fmi = f.data[base + 2U] & 0x1FU;
        const uint8_t occurrence = f.data[base + 3U] & 0x7FU;
        post_dm1(port, f.source, spn, fmi, occurrence);
      }
      return;
    }
    // All other frames — post as zero-copy frame event.
    post_frame(port, f.pgn, f.source, f.destination, f.data.data(),
               f.data.size());
  });

  // on_claim_result fires once on the RX thread when address claiming settles.
  // addr = claimed address on success; std::nullopt on failure (no free
  // address).
  h->ecu->on_claim_result([port](std::optional<j1939::Address> addr) {
    if (addr) {
      post_address_claimed(port, *addr);
    } else {
      post_address_failed(port);
    }
  });

  return h;
}

void j1939_destroy(J1939Handle *handle) { delete handle; }

int32_t j1939_send(J1939Handle *handle, uint32_t pgn, uint8_t priority,
                   uint8_t dest, const uint8_t *data, uint16_t len) {
  auto r = handle->ecu->send(static_cast<Pgn>(pgn), priority, dest,
                             std::span<const uint8_t>{data, len});
  if (!r) {
    tl_last_error = EPIPE;
    return -EPIPE;
  }
  return 0;
}

void j1939_add_dm1_fault(J1939Handle *handle, uint32_t spn, uint8_t fmi,
                         uint8_t occurrence) {
  handle->ecu->add_dm1_fault(Dm1Fault{
      .spn = spn,
      .fmi = fmi,
      .occurrence = occurrence,
  });
}

void j1939_clear_dm1_faults(J1939Handle *handle) {
  handle->ecu->clear_dm1_faults();
}

uint8_t j1939_address(J1939Handle *handle) { return handle->ecu->address(); }

bool j1939_address_claimed(J1939Handle *handle) {
  return handle->ecu->address_claimed();
}

int32_t j1939_send_request(J1939Handle *handle, uint8_t dest,
                           uint32_t requested_pgn) {
  const auto r =
      handle->ecu->send_request(dest, static_cast<j1939::Pgn>(requested_pgn));
  if (!r) {
    tl_last_error = EPIPE;
    return -EPIPE;
  }
  return 0;
}

void j1939_send_async(J1939Handle *handle, int32_t send_id, uint32_t pgn,
                      uint8_t priority, uint8_t dest, const uint8_t *data,
                      uint16_t len) {
  // Copy payload before returning — Dart may free its buffer immediately.
  std::vector<uint8_t> payload(data, data + len);
  const Dart_Port port = handle->event_port;

  handle->ecu->send_async(
      static_cast<j1939::Pgn>(pgn), priority, dest, std::move(payload),
      [port, send_id](std::error_code ec) {
        // Fires on the ASIO thread — Dart_PostCObject_DL is thread-safe.
        const auto errno_val = ec ? static_cast<int32_t>(ec.value()) : 0;
        post_send_complete(port, send_id, errno_val);
      });
}

J1939Handle *j1939_create_full(const char *ifname, uint8_t preferred_address,
                               uint32_t identity_number,
                               uint16_t manufacturer_code,
                               uint8_t industry_group, uint8_t device_function,
                               uint8_t device_class, uint8_t function_instance,
                               uint8_t ecu_instance, int64_t event_port_id) {
  const Name name{
      .identity_number = identity_number,
      .manufacturer_code = manufacturer_code,
      .function_instance = function_instance,
      .ecu_instance = ecu_instance,
      .function = device_function,
      .vehicle_system = device_class,
      .arbitrary_address = true,
      .industry_group = industry_group,
  };

  auto result = Ecu::create(ifname, preferred_address, name);
  if (!result) {
    tl_last_error = result.error().value();
    return nullptr;
  }

  auto *h = new J1939Handle_{};
  h->event_port = static_cast<Dart_Port>(event_port_id);
  h->ecu = std::move(*result);

  const Dart_Port port = h->event_port;

  // Same on_message and on_claim_result handlers as j1939_create.
  h->ecu->on_message([port](const Frame &f) {
    if (f.pgn == static_cast<uint32_t>(Pgn::Dm1) && f.data.size() >= 6U) {
      const size_t fault_count = (f.data.size() - 2U) / 4U;
      for (size_t i = 0U; i < fault_count; ++i) {
        const size_t base = 2U + i * 4U;
        const uint32_t spn =
            static_cast<uint32_t>(f.data[base]) |
            (static_cast<uint32_t>(f.data[base + 1U]) << 8U) |
            (static_cast<uint32_t>(f.data[base + 2U] & 0x07U) << 16U);
        const uint8_t fmi = f.data[base + 2U] & 0x1FU;
        const uint8_t occurrence = f.data[base + 3U] & 0x7FU;
        post_dm1(port, f.source, spn, fmi, occurrence);
      }
      return;
    }
    post_frame(port, f.pgn, f.source, f.destination, f.data.data(),
               f.data.size());
  });

  h->ecu->on_claim_result([port](std::optional<j1939::Address> addr) {
    if (addr) {
      post_address_claimed(port, *addr);
    } else {
      post_address_failed(port);
    }
  });

  return h;
}

void nmea2000_set_pgn_transport(uint32_t pgn, uint8_t transport) {
  j1939::set_pgn_transport(pgn, static_cast<j1939::PgnTransport>(transport));
}

} // extern "C"
