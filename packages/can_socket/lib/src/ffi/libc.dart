// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Raw libc FFI bindings for SocketCAN operations.
///
/// All functions are resolved from libc.so.6 via DynamicLibrary.
class Libc {
  Libc._();

  static final DynamicLibrary _libc = DynamicLibrary.open('libc.so.6');

  // int socket(int domain, int type, int protocol);
  static final socket = _libc.lookupFunction<
    Int32 Function(Int32, Int32, Int32),
    int Function(int, int, int)
  >('socket');

  // int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
  static final bind = _libc.lookupFunction<
    Int32 Function(Int32, Pointer<Void>, Uint32),
    int Function(int, Pointer<Void>, int)
  >('bind');

  // int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
  static final connect = _libc.lookupFunction<
    Int32 Function(Int32, Pointer<Void>, Uint32),
    int Function(int, Pointer<Void>, int)
  >('connect');

  // ssize_t read(int fd, void *buf, size_t count);
  static final read = _libc.lookupFunction<
    IntPtr Function(Int32, Pointer<Void>, Size),
    int Function(int, Pointer<Void>, int)
  >('read');

  // ssize_t write(int fd, const void *buf, size_t count);
  static final write = _libc.lookupFunction<
    IntPtr Function(Int32, Pointer<Void>, Size),
    int Function(int, Pointer<Void>, int)
  >('write');

  // ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
  //                const struct sockaddr *dest_addr, socklen_t addrlen);
  static final sendto = _libc.lookupFunction<
    IntPtr Function(Int32, Pointer<Void>, Size, Int32, Pointer<Void>, Uint32),
    int Function(int, Pointer<Void>, int, int, Pointer<Void>, int)
  >('sendto');

  // ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags,
  //                  struct sockaddr *src_addr, socklen_t *addrlen);
  static final recvfrom = _libc.lookupFunction<
    IntPtr Function(
      Int32,
      Pointer<Void>,
      Size,
      Int32,
      Pointer<Void>,
      Pointer<Uint32>,
    ),
    int Function(int, Pointer<Void>, int, int, Pointer<Void>, Pointer<Uint32>)
  >('recvfrom');

  // int close(int fd);
  static final close = _libc
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');

  // int ioctl(int fd, unsigned long request, ...);
  static final ioctl = _libc.lookupFunction<
    Int32 Function(Int32, Uint64, Pointer<Void>),
    int Function(int, int, Pointer<Void>)
  >('ioctl');

  // int setsockopt(int sockfd, int level, int optname,
  //                const void *optval, socklen_t optlen);
  static final setsockopt = _libc.lookupFunction<
    Int32 Function(Int32, Int32, Int32, Pointer<Void>, Uint32),
    int Function(int, int, int, Pointer<Void>, int)
  >('setsockopt');

  // int getsockopt(int sockfd, int level, int optname,
  //                void *optval, socklen_t *optlen);
  static final getsockopt = _libc.lookupFunction<
    Int32 Function(Int32, Int32, Int32, Pointer<Void>, Pointer<Uint32>),
    int Function(int, int, int, Pointer<Void>, Pointer<Uint32>)
  >('getsockopt');

  // int poll(struct pollfd *fds, nfds_t nfds, int timeout);
  static final poll = _libc.lookupFunction<
    Int32 Function(Pointer<Void>, Uint64, Int32),
    int Function(Pointer<Void>, int, int)
  >('poll');

  // char *strerror(int errnum);
  static final strerror = _libc.lookupFunction<
    Pointer<Utf8> Function(Int32),
    Pointer<Utf8> Function(int)
  >('strerror');

  // int *__errno_location(void);
  static final _errnoLocation = _libc
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        '__errno_location',
      );

  /// Returns the current errno value.
  static int get errno => _errnoLocation().value;

  /// Returns a human-readable error message for the given errno.
  static String errorMessage(int errnum) => strerror(errnum).toDartString();
}
