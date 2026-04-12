// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/*
 * j1939_linux — Pure C++23 J1939 stack on SocketCAN
 *
 * Setup:
 *   sudo modprobe vcan
 *   sudo ip link add dev vcan0 type vcan
 *   sudo ip link set up vcan0
 *
 * Monitor:
 *   candump -t a vcan0
 *
 * Build:
 *   cmake -B build && cmake --build build -j$(nproc)
 *   ./build/j1939_demo
 */

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <numeric>
#include <thread>

#include "j1939/Ecu.hpp"

// ── print shim ────────────────────────────────────────────────────────────────
// GCC 15 ships <print> and the has_include branch fires, but std::print is not
// imported into the anonymous namespace automatically.  Pull it in explicitly.
#if __has_include(<print>)
#  include <print>
   using std::print;
#else
#  include <format>
namespace {
    template<typename... Args>
    void print(std::format_string<Args...> fmt, Args&&... args) {
        const auto s = std::format(fmt, std::forward<Args>(args)...);
        (void)std::fwrite(s.data(), 1, s.size(), stdout);  // cert-err33-c: void cast
    }
    template<typename... Args>
    void print(std::FILE* f, std::format_string<Args...> fmt, Args&&... args) {
        const auto s = std::format(fmt, std::forward<Args>(args)...);
        (void)std::fwrite(s.data(), 1, s.size(), f);
    }
}
#endif

// ── File-scope helpers (anonymous namespace per misc-use-anonymous-namespace) ─

namespace {

// std::atomic<bool> is correct for a flag written in a signal handler.
std::atomic<bool> g_running{true};  // NOLINT(cppcoreguidelines-avoid-non-const-global-variables)

// SIG_* handlers must have C linkage signature — parameter intentionally unused.
extern "C" void on_signal(int /*sig*/) {
    g_running.store(false, std::memory_order_relaxed);
}

bool wait_for_claim(const std::unique_ptr<j1939::Ecu>& ecu,
                    std::chrono::milliseconds timeout = std::chrono::milliseconds{400})
{
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    while (std::chrono::steady_clock::now() < deadline) {
        if (ecu->address_claimed()) { return true; }
        std::this_thread::sleep_for(std::chrono::milliseconds{5});
    }
    return false;
}

void log_frame(std::string_view tag, const j1939::Frame& f)
{
    print("{}: PGN=0x{:05X}  SA=0x{:02X}  DA=0x{:02X}  data=[",
          tag, f.pgn, f.source, f.destination);
    for (size_t i = 0U; i < f.data.size(); ++i) {
        if (i != 0U) { print(" "); }
        print("{:02X}", f.data[i]);
    }
    print("]\n");
}

// Wraps main body; any exception is caught here so it does not escape main().
// bugprone-exception-escape: main() must not propagate exceptions to the runtime.
int run()
{
    using namespace j1939;

    // ── 1. Create two ECU instances ──────────────────────────────────────
    const Name name_a{
        .identity_number   = 0x0001U,
        .manufacturer_code = 0x7FFU,
        .function          = 0x00U,
        .arbitrary_address = true,
        .industry_group    = 0U,
    };
    const Name name_b{
        .identity_number   = 0x0002U,
        .manufacturer_code = 0x7FFU,
        .function          = 0x00U,
        .arbitrary_address = true,
        .industry_group    = 0U,
    };

    auto result_a = Ecu::create("vcan0", 0xA0, name_a);
    if (!result_a) {
        print(stderr, "ECU A: {}\n", result_a.error().message());
        return EXIT_FAILURE;
    }
    auto& ecu_a = *result_a;

    auto result_b = Ecu::create("vcan0", 0xB0, name_b);
    if (!result_b) {
        print(stderr, "ECU B: {}\n", result_b.error().message());
        return EXIT_FAILURE;
    }
    auto& ecu_b = *result_b;

    // ── 2. Register message handlers ─────────────────────────────────────
    ecu_a->on_message([](const Frame& f) { log_frame("[ECU A RX]", f); });
    ecu_b->on_message([](const Frame& f) { log_frame("[ECU B RX]", f); });

    // ── 3. Wait for address claims ────────────────────────────────────────
    print("[main] waiting for address claims (250 ms)...\n");
    if (!wait_for_claim(ecu_a) || !wait_for_claim(ecu_b)) {
        print(stderr, "[main] address claim timed out\n");
        return EXIT_FAILURE;
    }
    print("[main] ECU A claimed 0x{:02X}, ECU B claimed 0x{:02X}\n",
          ecu_a->address(), ecu_b->address());

    // ── 4. Single-frame proprietary-A: ECU A → ECU B ─────────────────────
    {
        const std::array<uint8_t, 7> payload{0xDE,0xAD,0xBE,0xEF,0x01,0x02,0x03};
        print("[main] ECU A → ECU B: proprietary-A\n");
        if (auto r = ecu_a->send(Pgn::ProprietaryA, 6U, ecu_b->address(), payload); !r) {
            print(stderr, "[main] send failed: {}\n", r.error());
        }
        std::this_thread::sleep_for(std::chrono::milliseconds{50});
    }

    // ── 5. Multi-packet BAM: ECU B → broadcast ────────────────────────────
    {
        std::vector<uint8_t> sw_id(25U);
        std::iota(sw_id.begin(), sw_id.end(), uint8_t{0x20U});

        print("[main] ECU B → broadcast: BAM {} bytes (SoftwareId)\n", sw_id.size());
        if (auto r = ecu_b->send(Pgn::SoftwareId, 6U, kBroadcast, sw_id); !r) {
            print(stderr, "[main] BAM failed: {}\n", r.error());
        }
        std::this_thread::sleep_for(std::chrono::milliseconds{600});
    }

    // ── 6. DM1 fault on ECU A; ECU B requests it ─────────────────────────
    print("[main] ECU A: add DM1 fault — SPN 100 (engine oil pressure), FMI 1\n");
    ecu_a->add_dm1_fault(Dm1Fault{.spn=100U, .fmi=1U, .occurrence=1U});

    print("[main] ECU B → ECU A: request DM1\n");
    if (auto r = ecu_b->send_request(ecu_a->address(), Pgn::Dm1); !r) {
        print(stderr, "[main] DM1 request failed: {}\n", r.error());
    }
    std::this_thread::sleep_for(std::chrono::milliseconds{150});

    // ── 7. Request all address claims ─────────────────────────────────────
    print("[main] ECU A: requesting all address claims\n");
    if (auto r = ecu_a->send_request(kBroadcast, Pgn::AddressClaimed); !r) {
        print(stderr, "[main] address request failed: {}\n", r.error());
    }
    std::this_thread::sleep_for(std::chrono::milliseconds{50});

    // ── 8. Run until Ctrl-C ───────────────────────────────────────────────
    print("\n[main] both ECUs active on vcan0 — Ctrl-C to stop\n");
    print("       try: cansend vcan0 18EAFFA0#CAFECA00  (DM1 request to ECU A)\n\n");

    while (g_running.load(std::memory_order_relaxed)) {
        std::this_thread::sleep_for(std::chrono::milliseconds{100});
    }

    print("\n[main] shutting down\n");
    return EXIT_SUCCESS;
}

} // namespace

int main()
{
    // NOLINTNEXTLINE(cert-msc54-cpp) — signal() is the standard POSIX interface
    (void)std::signal(SIGINT,  on_signal);
    (void)std::signal(SIGTERM, on_signal);

    try {
        return run();
    } catch (const std::exception& e) {
        (void)std::fprintf(stderr, "fatal: %s\n", e.what());
        return EXIT_FAILURE;
    } catch (...) {
        (void)std::fprintf(stderr, "fatal: unknown exception\n");
        return EXIT_FAILURE;
    }
}
