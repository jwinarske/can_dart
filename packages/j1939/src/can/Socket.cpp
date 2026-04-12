// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Linux CAN headers confined to this translation unit.
#include <cerrno>
#include <system_error>

#include <linux/can.h>
#include <linux/can/raw.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

#include "Socket.hpp"

namespace can {

Socket::Socket(Socket&& other) noexcept : fd_{other.fd_} { other.fd_ = -1; }

Socket& Socket::operator=(Socket&& other) noexcept {
    if (this != &other) {
        close();
        fd_       = other.fd_;
        other.fd_ = -1;
    }
    return *this;
}

Socket::~Socket() { close(); }

void Socket::close() noexcept {
    if (fd_ >= 0) {
        ::close(fd_);
        fd_ = -1;
    }
}

// ── Factory ───────────────────────────────────────────────────────────────────

std::expected<Socket, std::error_code>
Socket::open(std::string_view ifname, std::chrono::milliseconds timeout)
{
    // Capture the current errno before any subsequent call can clobber it.
    const auto sys_err = [] {
        return std::error_code{errno, std::system_category()};
    };

    // 1. Create socket — fd is const; it is never re-assigned after this point.
    const int fd = ::socket(PF_CAN, SOCK_RAW, CAN_RAW);
    if (fd < 0) {
        return std::unexpected(sys_err());
    }

    // 2. Receive timeout
    if (timeout.count() > 0) {
        timeval tv{
            .tv_sec  = static_cast<time_t>(timeout.count() / 1000),
            .tv_usec = static_cast<suseconds_t>((timeout.count() % 1000) * 1000),
        };
        if (::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0) {
            const auto err = sys_err();
            ::close(fd);
            return std::unexpected(err);
        }
    }

    // 3. Disable own-message loopback
    int disable = 0;
    if (::setsockopt(fd, SOL_CAN_RAW, CAN_RAW_RECV_OWN_MSGS,
                     &disable, sizeof(disable)) < 0) {
        const auto err = sys_err();
        ::close(fd);
        return std::unexpected(err);
    }

    // 4. Resolve interface index
    ifreq ifr{};
    ifname.copy(ifr.ifr_name, sizeof(ifr.ifr_name) - 1U);
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg) — ioctl requires varargs
    if (::ioctl(fd, SIOCGIFINDEX, &ifr) < 0) {
        const auto err = sys_err();
        ::close(fd);
        return std::unexpected(err);
    }

    // 5. Bind
    sockaddr_can addr{
        .can_family  = AF_CAN,
        .can_ifindex = ifr.ifr_ifindex,
    };
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast) — POSIX API
    if (::bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        const auto err = sys_err();
        ::close(fd);
        return std::unexpected(err);
    }

    return Socket{fd};
}

// ── I/O ───────────────────────────────────────────────────────────────────────

bool Socket::send(const RawFrame& frame) const noexcept {
    can_frame f{};
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access) — Linux CAN API
    f.can_id  = frame.id | CAN_EFF_FLAG;
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access)
    f.can_dlc = frame.dlc;
    std::copy_n(frame.data.begin(), frame.dlc, f.data);
    return ::write(fd_, &f, sizeof(f)) == static_cast<ssize_t>(sizeof(f));
}

std::optional<RawFrame> Socket::receive() const noexcept {
    can_frame f{};
    const ssize_t n = ::read(fd_, &f, sizeof(f));
    if (n != static_cast<ssize_t>(sizeof(f))) {
        return std::nullopt;
    }
    RawFrame frame;
    frame.id  = f.can_id & CAN_EFF_MASK;
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access)
    frame.dlc = f.can_dlc;
    // NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access)
    std::copy_n(f.data, f.can_dlc, frame.data.begin());
    return frame;
}

} // namespace can
