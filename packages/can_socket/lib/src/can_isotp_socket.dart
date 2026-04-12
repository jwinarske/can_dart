// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'can_socket.dart';
import 'ffi/constants.dart';
import 'ffi/libc.dart';
import 'ffi/structs.dart';

/// ISO-TP (ISO 15765-2) transport protocol socket.
///
/// Handles segmentation and reassembly of PDUs larger than a single CAN frame.
/// Used for UDS (Unified Diagnostic Services) and OBD-II extended diagnostics.
class CanIsotpSocket {
  int _fd = -1;
  final String interface_;
  final int txId;
  final int rxId;
  bool _closed = false;

  /// Creates an ISO-TP socket bound to [interface_] with the given
  /// transmit [txId] and receive [rxId] CAN IDs.
  CanIsotpSocket(this.interface_, {required this.txId, required this.rxId}) {
    _fd = Libc.socket(afCan, sockDgram, canIsotp);
    if (_fd < 0) _throwErrno('socket(ISOTP)');
    _bind();
  }

  /// Send an ISO-TP PDU. The kernel handles segmentation.
  void send(Uint8List data) {
    _checkOpen();
    final ptr = calloc<Uint8>(data.length);
    try {
      for (var i = 0; i < data.length; i++) {
        ptr[i] = data[i];
      }
      final written = Libc.write(_fd, ptr.cast(), data.length);
      if (written < 0) _throwErrno('write(ISOTP)');
    } finally {
      calloc.free(ptr);
    }
  }

  /// Receive a reassembled ISO-TP PDU (blocking).
  ///
  /// Returns up to 4095 bytes (ISO-TP max PDU size).
  Uint8List receive({int timeoutMs = -1}) {
    _checkOpen();

    if (timeoutMs >= 0) {
      final pfd = calloc<PollFd>();
      try {
        pfd.ref.fd = _fd;
        pfd.ref.events = pollIn;
        pfd.ref.revents = 0;
        final ret = Libc.poll(pfd.cast(), 1, timeoutMs);
        if (ret < 0) _throwErrno('poll(ISOTP)');
        if (ret == 0) return Uint8List(0); // timeout
      } finally {
        calloc.free(pfd);
      }
    }

    const maxPduSize = 4095;
    final buf = calloc<Uint8>(maxPduSize);
    try {
      final nbytes = Libc.read(_fd, buf.cast(), maxPduSize);
      if (nbytes < 0) _throwErrno('read(ISOTP)');
      final result = Uint8List(nbytes);
      for (var i = 0; i < nbytes; i++) {
        result[i] = buf[i];
      }
      return result;
    } finally {
      calloc.free(buf);
    }
  }

  /// Set ISO-TP options.
  void setOptions({
    int flags = 0,
    int frameTxtime = 0,
    int extAddress = 0,
    int txpadContent = 0xCC,
    int rxpadContent = 0xCC,
    int rxExtAddress = 0,
  }) {
    _checkOpen();
    final opts = calloc<CanIsotpOptions>();
    try {
      opts.ref.flags = flags;
      opts.ref.frameTxtime = frameTxtime;
      opts.ref.extAddress = extAddress;
      opts.ref.txpadContent = txpadContent;
      opts.ref.rxpadContent = rxpadContent;
      opts.ref.rxExtAddress = rxExtAddress;
      final ret = Libc.setsockopt(
        _fd,
        solCanIsotp,
        canIsotpOpts,
        opts.cast(),
        sizeOf<CanIsotpOptions>(),
      );
      if (ret < 0) _throwErrno('setsockopt(ISOTP_OPTS)');
    } finally {
      calloc.free(opts);
    }
  }

  /// Set flow control parameters.
  void setFlowControl({int bs = 0, int stmin = 0, int wftmax = 0}) {
    _checkOpen();
    final fc = calloc<CanIsotpFcOptions>();
    try {
      fc.ref.bs = bs;
      fc.ref.stmin = stmin;
      fc.ref.wftmax = wftmax;
      final ret = Libc.setsockopt(
        _fd,
        solCanIsotp,
        canIsotpRecvFc,
        fc.cast(),
        sizeOf<CanIsotpFcOptions>(),
      );
      if (ret < 0) _throwErrno('setsockopt(ISOTP_RECV_FC)');
    } finally {
      calloc.free(fc);
    }
  }

  /// Close the ISO-TP socket.
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
    if (_closed) throw StateError('CanIsotpSocket is closed');
  }

  Never _throwErrno(String call) {
    final err = Libc.errno;
    throw CanSocketException('$call failed', err);
  }

  void _bind() {
    final ifindex = _getIfindex(interface_);
    final addr = calloc<SockaddrCan>();
    try {
      addr.ref.canFamily = afCan;
      addr.ref.canIfindex = ifindex;
      addr.ref.addrField0 = rxId; // tp.rx_id
      addr.ref.addrField1 = txId; // tp.tx_id
      final ret = Libc.bind(_fd, addr.cast(), sizeOf<SockaddrCan>());
      if (ret < 0) _throwErrno('bind(ISOTP)');
    } finally {
      calloc.free(addr);
    }
  }

  int _getIfindex(String name) {
    final ifreq = calloc<Ifreq>();
    try {
      setIfreqName(ifreq.ref, name);
      final ret = Libc.ioctl(_fd, siocgifindex, ifreq.cast());
      if (ret < 0) _throwErrno('ioctl(SIOCGIFINDEX)');
      return ifreq.ref.ifrIfindex;
    } finally {
      calloc.free(ifreq);
    }
  }
}
