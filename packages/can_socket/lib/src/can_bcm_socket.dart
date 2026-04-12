import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'can_frame.dart';
import 'can_socket.dart';
import 'ffi/constants.dart' as c;
import 'ffi/libc.dart';
import 'ffi/structs.dart';

/// Configuration for a cyclic BCM transmission.
class BcmTxConfig {
  /// CAN ID to transmit.
  final int canId;

  /// Frames to transmit cyclically.
  final List<CanFrame> frames;

  /// Initial interval (phase 1) in microseconds.
  final int ival1Us;

  /// Repeating interval (phase 2) in microseconds.
  final int ival2Us;

  /// Number of transmissions at ival1 before switching to ival2.
  /// 0 means use ival2 immediately.
  final int count;

  const BcmTxConfig({
    required this.canId,
    required this.frames,
    this.ival1Us = 0,
    required this.ival2Us,
    this.count = 0,
  });
}

/// Configuration for a content-change BCM reception filter.
class BcmRxConfig {
  /// CAN ID to monitor.
  final int canId;

  /// Timeout interval in microseconds (0 = no timeout).
  final int ival1Us;

  /// Throttle interval in microseconds (0 = no throttle).
  final int ival2Us;

  const BcmRxConfig({required this.canId, this.ival1Us = 0, this.ival2Us = 0});
}

/// A CAN Broadcast Manager (BCM) socket.
///
/// Provides cyclic transmission and content-change receive filtering
/// handled in-kernel for efficiency.
class CanBcmSocket {
  int _fd = -1;
  final String interface_;
  bool _closed = false;

  CanBcmSocket(this.interface_) {
    _fd = Libc.socket(c.afCan, c.sockDgram, c.canBcm);
    if (_fd < 0) _throwErrno('socket(BCM)');
    _connect();
  }

  /// Set up cyclic transmission.
  void txSetup(BcmTxConfig config) {
    _checkOpen();

    final totalSize =
        sizeOf<BcmMsgHead>() + config.frames.length * sizeOf<CanFrameNative>();
    final buf = calloc<Uint8>(totalSize);

    try {
      final head = buf.cast<BcmMsgHead>();
      head.ref.opcode = c.txSetup;
      head.ref.flags = c.settimer | c.starttimer;
      head.ref.count = config.count;
      head.ref.ival1Sec = config.ival1Us ~/ 1000000;
      head.ref.ival1Usec = config.ival1Us % 1000000;
      head.ref.ival2Sec = config.ival2Us ~/ 1000000;
      head.ref.ival2Usec = config.ival2Us % 1000000;
      head.ref.canId = config.canId;
      head.ref.nframes = config.frames.length;

      // Write frames after the header
      final framesPtr = (buf + sizeOf<BcmMsgHead>()).cast<CanFrameNative>();
      for (var i = 0; i < config.frames.length; i++) {
        config.frames[i].toNative(framesPtr + i);
      }

      final written = Libc.write(_fd, buf.cast(), totalSize);
      if (written < 0) _throwErrno('write(TX_SETUP)');
    } finally {
      calloc.free(buf);
    }
  }

  /// Delete a cyclic transmission.
  void txDelete(int canId) {
    _checkOpen();
    _sendOpcode(c.txDelete, canId);
  }

  /// Set up content-change receive filter.
  void rxSetup(BcmRxConfig config) {
    _checkOpen();

    final buf = calloc<BcmMsgHead>();
    try {
      buf.ref.opcode = c.rxSetup;
      buf.ref.flags = c.settimer | c.rxFilterId;
      buf.ref.count = 0;
      buf.ref.ival1Sec = config.ival1Us ~/ 1000000;
      buf.ref.ival1Usec = config.ival1Us % 1000000;
      buf.ref.ival2Sec = config.ival2Us ~/ 1000000;
      buf.ref.ival2Usec = config.ival2Us % 1000000;
      buf.ref.canId = config.canId;
      buf.ref.nframes = 0;

      final written = Libc.write(_fd, buf.cast(), sizeOf<BcmMsgHead>());
      if (written < 0) _throwErrno('write(RX_SETUP)');
    } finally {
      calloc.free(buf);
    }
  }

  /// Delete a receive filter.
  void rxDelete(int canId) {
    _checkOpen();
    _sendOpcode(c.rxDelete, canId);
  }

  /// Read a BCM response (blocking).
  ///
  /// Returns the received frame and the BCM header opcode.
  ({int opcode, int canId, List<CanFrame> frames}) receive() {
    _checkOpen();

    // Read up to header + 1 frame
    final bufSize = sizeOf<BcmMsgHead>() + sizeOf<CanFrameNative>();
    final buf = calloc<Uint8>(bufSize);

    try {
      final nbytes = Libc.read(_fd, buf.cast(), bufSize);
      if (nbytes < 0) _throwErrno('read(BCM)');

      final head = buf.cast<BcmMsgHead>().ref;
      final frames = <CanFrame>[];

      if (nbytes > sizeOf<BcmMsgHead>() && head.nframes > 0) {
        final framePtr = (buf + sizeOf<BcmMsgHead>()).cast<CanFrameNative>();
        frames.add(CanFrame.fromNative(framePtr.ref));
      }

      return (opcode: head.opcode, canId: head.canId, frames: frames);
    } finally {
      calloc.free(buf);
    }
  }

  /// Close the BCM socket.
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
    if (_closed) throw StateError('CanBcmSocket is closed');
  }

  Never _throwErrno(String call) {
    final err = Libc.errno;
    throw CanSocketException('$call failed', err);
  }

  void _connect() {
    final ifindex = _getIfindex(interface_);
    final addr = calloc<SockaddrCan>();
    try {
      addr.ref.canFamily = c.afCan;
      addr.ref.canIfindex = ifindex;
      final ret = Libc.connect(_fd, addr.cast(), sizeOf<SockaddrCan>());
      if (ret < 0) _throwErrno('connect(BCM)');
    } finally {
      calloc.free(addr);
    }
  }

  int _getIfindex(String name) {
    final ifreq = calloc<Ifreq>();
    try {
      setIfreqName(ifreq.ref, name);
      final ret = Libc.ioctl(_fd, c.siocgifindex, ifreq.cast());
      if (ret < 0) _throwErrno('ioctl(SIOCGIFINDEX)');
      return ifreq.ref.ifrIfindex;
    } finally {
      calloc.free(ifreq);
    }
  }

  void _sendOpcode(int opcode, int canId) {
    final buf = calloc<BcmMsgHead>();
    try {
      buf.ref.opcode = opcode;
      buf.ref.canId = canId;
      buf.ref.nframes = 0;
      final written = Libc.write(_fd, buf.cast(), sizeOf<BcmMsgHead>());
      if (written < 0) _throwErrno('write(opcode $opcode)');
    } finally {
      calloc.free(buf);
    }
  }
}
