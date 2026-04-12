#pragma once

#include <array>
#include <chrono>
#include <cstdint>
#include <expected>
#include <optional>
#include <span>
#include <string_view>
#include <system_error>

namespace can {

struct RawFrame {
    uint32_t              id   {};
    std::array<uint8_t,8> data {};
    uint8_t               dlc  {};
};

// RAII SocketCAN raw socket. Movable, not copyable.
// Linux headers are confined to Socket.cpp — none leak through here.
class Socket {
public:
    Socket()                                    = default;
    Socket(const Socket&)                       = delete;
    Socket& operator=(const Socket&)            = delete;
    Socket(Socket&& other)            noexcept;   // named: readability-named-parameter
    Socket& operator=(Socket&& other) noexcept;
    ~Socket();

    // Returns the OS errno as error_code on failure — zero allocation.
    [[nodiscard]]
    static std::expected<Socket, std::error_code>
    open(std::string_view ifname,
         std::chrono::milliseconds timeout = std::chrono::milliseconds{10});

    [[nodiscard]] bool is_open() const noexcept { return fd_ >= 0; }

    // const: fd_ is not modified; write() is a syscall side-effect.
    bool send(const RawFrame& frame)    const noexcept;
    std::optional<RawFrame> receive()   const noexcept;

    void close() noexcept;

private:
    explicit Socket(int fd) noexcept : fd_{fd} {}
    int fd_ = -1;
};

} // namespace can
