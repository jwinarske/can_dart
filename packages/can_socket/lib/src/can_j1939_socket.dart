// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'can_socket.dart';
import 'ffi/constants.dart';
import 'ffi/libc.dart';
import 'ffi/structs.dart';

/// SAE J1939 transport protocol socket.
///
/// Provides J1939 parameter group (PGN) level communication,
/// handling transport protocol segmentation transparently.
class CanJ1939Socket {
  int _fd = -1;
  final String interface_;
  final int name;
  final int pgn;
  final int addr;
  bool _closed = false;

  /// Creates a J1939 socket bound to [interface_].
  ///
  /// - [name] is the 64-bit ECU NAME (0 for no name claiming).
  /// - [pgn] is the Parameter Group Number (J1939_NO_PGN for any).
  /// - [addr] is the source address (J1939_NO_ADDR for dynamic).
  CanJ1939Socket(
    this.interface_, {
    this.name = j1939NoName,
    this.pgn = j1939NoPgn,
    this.addr = j1939NoAddr,
  }) {
    _fd = Libc.socket(afCan, sockDgram, canJ1939);
    if (_fd < 0) _throwErrno('socket(J1939)');
    _bind();
  }

  /// Send J1939 data to a destination.
  void send(Uint8List data, {required int destAddr, required int destPgn}) {
    _checkOpen();

    final addr = calloc<SockaddrCan>();
    final buf = calloc<Uint8>(data.length);
    try {
      addr.ref.canFamily = afCan;
      addr.ref.canIfindex = _getIfindex(interface_);
      // J1939 addr fields: name (64-bit), pgn (32-bit), addr (8-bit)
      addr.ref.addrField0 = 0; // name low
      addr.ref.addrField1 = 0; // name high
      addr.ref.addrField2 = destPgn;
      addr.ref.addrField3 = destAddr;

      for (var i = 0; i < data.length; i++) {
        buf[i] = data[i];
      }

      final sent = Libc.sendto(
        _fd,
        buf.cast(),
        data.length,
        0,
        addr.cast(),
        sizeOf<SockaddrCan>(),
      );
      if (sent < 0) _throwErrno('sendto(J1939)');
    } finally {
      calloc.free(addr);
      calloc.free(buf);
    }
  }

  /// Receive J1939 data (blocking).
  ///
  /// Returns the received data and source info.
  ({Uint8List data, int srcAddr, int pgn}) receive({int timeoutMs = -1}) {
    _checkOpen();

    if (timeoutMs >= 0) {
      final pfd = calloc<PollFd>();
      try {
        pfd.ref.fd = _fd;
        pfd.ref.events = pollIn;
        pfd.ref.revents = 0;
        final ret = Libc.poll(pfd.cast(), 1, timeoutMs);
        if (ret < 0) _throwErrno('poll(J1939)');
        if (ret == 0) return (data: Uint8List(0), srcAddr: 0, pgn: 0);
      } finally {
        calloc.free(pfd);
      }
    }

    const maxSize = 1785; // Max J1939 TP size
    final buf = calloc<Uint8>(maxSize);
    final srcAddr = calloc<SockaddrCan>();
    final addrLen = calloc<Uint32>();

    try {
      addrLen.value = sizeOf<SockaddrCan>();
      final nbytes = Libc.recvfrom(
        _fd,
        buf.cast(),
        maxSize,
        0,
        srcAddr.cast(),
        addrLen,
      );
      if (nbytes < 0) _throwErrno('recvfrom(J1939)');

      final data = Uint8List(nbytes);
      for (var i = 0; i < nbytes; i++) {
        data[i] = buf[i];
      }

      return (
        data: data,
        srcAddr: srcAddr.ref.addrField3,
        pgn: srcAddr.ref.addrField2,
      );
    } finally {
      calloc.free(buf);
      calloc.free(srcAddr);
      calloc.free(addrLen);
    }
  }

  /// Enable promiscuous mode (receive all PGNs/addresses).
  void setPromiscuous(bool enable) {
    _checkOpen();
    final ptr = calloc<Int32>();
    try {
      ptr.value = enable ? 1 : 0;
      final ret = Libc.setsockopt(
        _fd,
        solCanJ1939,
        soJ1939Promisc,
        ptr.cast(),
        sizeOf<Int32>(),
      );
      if (ret < 0) _throwErrno('setsockopt(J1939_PROMISC)');
    } finally {
      calloc.free(ptr);
    }
  }

  /// Set J1939 address filters.
  void setFilters(
    List<
      ({int name, int nameMask, int addr, int addrMask, int pgn, int pgnMask})
    >
    filters,
  ) {
    _checkOpen();

    final ptr = calloc<J1939Filter>(filters.length);
    try {
      for (var i = 0; i < filters.length; i++) {
        final f = filters[i];
        final native = ptr + i;
        native.ref.name = f.name;
        native.ref.nameMask = f.nameMask;
        native.ref.addr = f.addr;
        native.ref.addrMask = f.addrMask;
        native.ref.pgn = f.pgn;
        native.ref.pgnMask = f.pgnMask;
      }
      final ret = Libc.setsockopt(
        _fd,
        solCanJ1939,
        soJ1939Filter,
        ptr.cast(),
        sizeOf<J1939Filter>() * filters.length,
      );
      if (ret < 0) _throwErrno('setsockopt(J1939_FILTER)');
    } finally {
      calloc.free(ptr);
    }
  }

  /// Close the J1939 socket.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_fd >= 0) {
      Libc.close(_fd);
      _fd = -1;
    }
  }

  // --- Private ---

  void _checkOpen() {
    if (_closed) throw StateError('CanJ1939Socket is closed');
  }

  Never _throwErrno(String call) {
    final err = Libc.errno;
    throw CanSocketException('$call failed', err);
  }

  void _bind() {
    final ifindex = _getIfindex(interface_);
    final saddr = calloc<SockaddrCan>();
    try {
      saddr.ref.canFamily = afCan;
      saddr.ref.canIfindex = ifindex;
      saddr.ref.addrField0 = name & 0xFFFFFFFF;
      saddr.ref.addrField1 = (name >> 32) & 0xFFFFFFFF;
      saddr.ref.addrField2 = pgn;
      saddr.ref.addrField3 = addr;
      final ret = Libc.bind(_fd, saddr.cast(), sizeOf<SockaddrCan>());
      if (ret < 0) _throwErrno('bind(J1939)');
    } finally {
      calloc.free(saddr);
    }
  }

  int _getIfindex(String ifname) {
    final ifreq = calloc<Ifreq>();
    try {
      setIfreqName(ifreq.ref, ifname);
      final ret = Libc.ioctl(_fd, siocgifindex, ifreq.cast());
      if (ret < 0) _throwErrno('ioctl(SIOCGIFINDEX)');
      return ifreq.ref.ifrIfindex;
    } finally {
      calloc.free(ifreq);
    }
  }
}
