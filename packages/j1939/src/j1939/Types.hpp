#pragma once

#include <array>
#include <cstdint>
#include <vector>
#include <span>

namespace j1939 {

using Address  = uint8_t;
using Priority = uint8_t;

inline constexpr Address  kBroadcast   = 0xFFU;
inline constexpr Address  kNullAddress = 0xFEU;
inline constexpr uint8_t  kMaxDataSize = 8U;

enum class Pgn : uint32_t {
    Request             = 0x00EA00U,
    Acknowledgement     = 0x00E800U,
    TpCm                = 0x00EC00U,
    TpDt                = 0x00EB00U,
    AddressClaimed      = 0x00EE00U,
    ProprietaryA        = 0x00EF00U,
    CommandedAddress    = 0x00FED8U,
    Dm1                 = 0x00FECAU,
    Dm2                 = 0x00FECBU,
    Dm3                 = 0x00FECCU,
    Dm14                = 0x00D900U,
    Dm15                = 0x00D800U,
    Dm16                = 0x00D700U,
    SoftwareId          = 0x00FEDAU,
    EcuId               = 0x00FDC5U,
    ComponentId         = 0x00FEEBU,
    ProprietaryBStart   = 0x00FF00U,
    ProprietaryBEnd     = 0x00FFFFU,
};

enum class TpControl : uint8_t {
    Rts         = 0x10U,
    Cts         = 0x11U,
    EndOfMsgAck = 0x13U,
    Bam         = 0x20U,
    Abort       = 0xFFU,
};

// 29-bit CAN ID: encode/decode without endian-dependent unions.
// All shift counts use unsigned literals (hicpp-signed-bitwise).
struct Id {
    Priority priority = 6U;
    bool     edp      = false;
    bool     dp       = false;
    uint8_t  pf       = 0U;
    uint8_t  ps       = 0xFFU;
    Address  sa       = kNullAddress;

    [[nodiscard]] bool is_broadcast() const noexcept { return pf >= 0xF0U; }

    [[nodiscard]] uint32_t pgn() const noexcept {
        const uint32_t base =
              (static_cast<uint32_t>(edp) << 17U)
            | (static_cast<uint32_t>(dp)  << 16U)
            | (static_cast<uint32_t>(pf)  <<  8U);
        return is_broadcast() ? (base | static_cast<uint32_t>(ps)) : base;
    }

    [[nodiscard]] uint32_t encode() const noexcept {
        return  (static_cast<uint32_t>(priority & 0x7U) << 26U)
              | (static_cast<uint32_t>(edp)             << 25U)
              | (static_cast<uint32_t>(dp)              << 24U)
              | (static_cast<uint32_t>(pf)              << 16U)
              | (static_cast<uint32_t>(ps)              <<  8U)
              |  static_cast<uint32_t>(sa);
    }

    [[nodiscard]] static Id decode(uint32_t raw) noexcept {
        return {
            .priority = static_cast<uint8_t>((raw >> 26U) & 0x7U),
            .edp      = static_cast<bool>   ((raw >> 25U) & 0x1U),
            .dp       = static_cast<bool>   ((raw >> 24U) & 0x1U),
            .pf       = static_cast<uint8_t>((raw >> 16U) & 0xFFU),
            .ps       = static_cast<uint8_t>((raw >>  8U) & 0xFFU),
            .sa       = static_cast<uint8_t>( raw         & 0xFFU),
        };
    }

    [[nodiscard]] static Id from_pgn(uint32_t pgn_val, Priority prio,
                                      Address dest, Address src) noexcept {
        const auto pf_field = static_cast<uint8_t>((pgn_val >> 8U) & 0xFFU);
        const uint8_t ps_field = (pf_field < 0xF0U)
                                 ? dest
                                 : static_cast<uint8_t>(pgn_val & 0xFFU);
        return {
            .priority = prio,
            .edp      = static_cast<bool>((pgn_val >> 17U) & 0x1U),
            .dp       = static_cast<bool>((pgn_val >> 16U) & 0x1U),
            .pf       = pf_field,
            .ps       = ps_field,
            .sa       = src,
        };
    }
};

// 64-bit ECU NAME field — explicit unsigned shifts, no union tricks.
struct Name {
    uint32_t identity_number         = 0U;
    uint16_t manufacturer_code       = 0x7FFU;
    uint8_t  function_instance       = 0U;
    uint8_t  ecu_instance            = 0U;
    uint8_t  function                = 0U;
    uint8_t  vehicle_system          = 0U;
    bool     arbitrary_address       = true;
    uint8_t  industry_group          = 0U;
    uint8_t  vehicle_system_instance = 0U;

    [[nodiscard]] uint64_t encode() const noexcept {
        return   static_cast<uint64_t>(identity_number   & 0x1FFFFFU)
              | (static_cast<uint64_t>(manufacturer_code & 0x7FFU)  << 21U)
              | (static_cast<uint64_t>(function_instance & 0x1FU)   << 32U)
              | (static_cast<uint64_t>(ecu_instance      & 0x07U)   << 37U)
              | (static_cast<uint64_t>(function)                     << 40U)
              | (static_cast<uint64_t>(vehicle_system    & 0x7FU)   << 49U)
              | (static_cast<uint64_t>(arbitrary_address ? 1U : 0U) << 56U)
              | (static_cast<uint64_t>(industry_group    & 0x07U)   << 57U)
              | (static_cast<uint64_t>(vehicle_system_instance & 0xFU) << 60U);
    }

    [[nodiscard]] static Name decode(uint64_t raw) noexcept {
        return {
            .identity_number         = static_cast<uint32_t>( raw          & 0x1FFFFFU),
            .manufacturer_code       = static_cast<uint16_t>((raw >> 21U)  & 0x7FFU),
            .function_instance       = static_cast<uint8_t> ((raw >> 32U)  & 0x1FU),
            .ecu_instance            = static_cast<uint8_t> ((raw >> 37U)  & 0x07U),
            .function                = static_cast<uint8_t> ((raw >> 40U)  & 0xFFU),
            .vehicle_system          = static_cast<uint8_t> ((raw >> 49U)  & 0x7FU),
            .arbitrary_address       = static_cast<bool>    ((raw >> 56U)  & 0x1U),
            .industry_group          = static_cast<uint8_t> ((raw >> 57U)  & 0x07U),
            .vehicle_system_instance = static_cast<uint8_t> ((raw >> 60U)  & 0x0FU),
        };
    }

    [[nodiscard]] bool outranks(const Name& other) const noexcept {
        return encode() < other.encode();
    }
};

struct Frame {
    uint32_t             pgn         = 0U;
    Address              source      = kNullAddress;
    Address              destination = kBroadcast;
    std::vector<uint8_t> data;
};

struct Dm1Fault {
    uint32_t spn             = 0U;
    uint8_t  fmi             = 0U;
    uint8_t  occurrence      = 1U;
    bool     conversion_flag = false;
};

} // namespace j1939
