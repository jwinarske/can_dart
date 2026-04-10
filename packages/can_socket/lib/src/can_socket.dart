import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'can_filter.dart';
import 'can_frame.dart';
import 'ffi/constants.dart';
import 'ffi/libc.dart';
import 'ffi/structs.dart';

/// Exception thrown on SocketCAN errors.
class CanSocketException implements Exception {
  final String message;
  final int errno;

  CanSocketException(this.message, this.errno);

  @override
  String toString() =>
      'CanSocketException: $message (errno $errno: ${Libc.errorMessage(errno)})';
}

/// A raw CAN socket (CAN_RAW protocol).
///
/// Provides synchronous send/receive and an isolate-based async [frameStream].
/// This class is intended for CLI tools — Flutter apps should use `can_engine`.
class CanSocket {
  int _fd = -1;
  final String interface_;
  final bool canFd;
  bool _closed = false;

  /// Creates and binds a raw CAN socket to the given interface.
  ///
  /// Set [canFd] to true to enable CAN FD frame support.
  CanSocket(this.interface_, {this.canFd = false}) {
    _fd = Libc.socket(afCan, sockRaw, canRaw);
    if (_fd < 0) {
      _throwErrno('socket()');
    }

    if (canFd) {
      _enableCanFd();
    }

    _bind();
  }

  /// Creates a CanSocket from an existing file descriptor (for internal use).
  CanSocket.fromFd(this._fd, this.interface_, {this.canFd = false});

  /// The underlying file descriptor.
  int get fd {
    _checkOpen();
    return _fd;
  }

  /// Send a CAN frame.
  void send(CanFrame frame) {
    _checkOpen();

    if (frame.isFd || canFd) {
      final ptr = calloc<CanFdFrameNative>();
      try {
        frame.toFdNative(ptr);
        final written = Libc.write(_fd, ptr.cast(), sizeOf<CanFdFrameNative>());
        if (written < 0) _throwErrno('write(canfd)');
      } finally {
        calloc.free(ptr);
      }
    } else {
      final ptr = calloc<CanFrameNative>();
      try {
        frame.toNative(ptr);
        final written = Libc.write(_fd, ptr.cast(), sizeOf<CanFrameNative>());
        if (written < 0) _throwErrno('write(can)');
      } finally {
        calloc.free(ptr);
      }
    }
  }

  /// Receive a CAN frame (blocking).
  ///
  /// Use [timeoutMs] to set a timeout in milliseconds. Pass -1 for infinite
  /// (default). Returns null on timeout.
  CanFrame? receive({int timeoutMs = -1}) {
    _checkOpen();

    if (timeoutMs >= 0) {
      final pfd = calloc<PollFd>();
      try {
        pfd.ref.fd = _fd;
        pfd.ref.events = pollIn;
        pfd.ref.revents = 0;
        final ret = Libc.poll(pfd.cast(), 1, timeoutMs);
        if (ret < 0) _throwErrno('poll()');
        if (ret == 0) return null; // timeout
      } finally {
        calloc.free(pfd);
      }
    }

    if (canFd) {
      return _readFdFrame();
    } else {
      return _readFrame();
    }
  }

  /// Set hardware-level CAN filters.
  ///
  /// Pass an empty list to block all frames. Use [CanFilter.passAll] to
  /// accept everything.
  void setFilters(List<CanFilter> filters) {
    _checkOpen();

    if (filters.isEmpty) {
      // Setting zero filters blocks everything
      final ret = Libc.setsockopt(
          _fd, solCanRaw, canRawFilter, nullptr, 0);
      if (ret < 0) _throwErrno('setsockopt(CAN_RAW_FILTER)');
      return;
    }

    final ptr = calloc<CanFilterNative>(filters.length);
    try {
      for (var i = 0; i < filters.length; i++) {
        filters[i].toNative(ptr + i);
      }
      final ret = Libc.setsockopt(
        _fd,
        solCanRaw,
        canRawFilter,
        ptr.cast(),
        sizeOf<CanFilterNative>() * filters.length,
      );
      if (ret < 0) _throwErrno('setsockopt(CAN_RAW_FILTER)');
    } finally {
      calloc.free(ptr);
    }
  }

  /// Enable or disable local loopback of sent frames.
  void setLoopback(bool enable) {
    _checkOpen();
    _setIntOption(solCanRaw, canRawLoopback, enable ? 1 : 0);
  }

  /// Enable or disable receiving own sent frames.
  void setRecvOwnMsgs(bool enable) {
    _checkOpen();
    _setIntOption(solCanRaw, canRawRecvOwnMsgs, enable ? 1 : 0);
  }

  /// Set the error mask to receive error frames.
  void setErrorMask(int mask) {
    _checkOpen();
    _setIntOption(solCanRaw, canRawErrFilter, mask);
  }

  /// Returns an isolate-based [Stream] of CAN frames.
  ///
  /// The stream runs a blocking receive loop in a separate isolate.
  /// Cancel the subscription to stop the isolate.
  Stream<CanFrame> get frameStream {
    _checkOpen();
    return _createFrameStream();
  }

  /// Close the socket.
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
    if (_closed) throw StateError('CanSocket is closed');
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
      final ret = Libc.bind(_fd, addr.cast(), sizeOf<SockaddrCan>());
      if (ret < 0) _throwErrno('bind()');
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

  void _enableCanFd() {
    _setIntOption(solCanRaw, canRawFdFrames, 1);
  }

  void _setIntOption(int level, int optname, int value) {
    final ptr = calloc<Int32>();
    try {
      ptr.value = value;
      final ret = Libc.setsockopt(_fd, level, optname, ptr.cast(), sizeOf<Int32>());
      if (ret < 0) _throwErrno('setsockopt($optname)');
    } finally {
      calloc.free(ptr);
    }
  }

  CanFrame _readFrame() {
    final ptr = calloc<CanFrameNative>();
    try {
      final nbytes = Libc.read(_fd, ptr.cast(), sizeOf<CanFrameNative>());
      if (nbytes < 0) _throwErrno('read(can)');
      if (nbytes < sizeOf<CanFrameNative>()) {
        throw CanSocketException('Incomplete CAN frame read', 0);
      }
      return CanFrame.fromNative(ptr.ref);
    } finally {
      calloc.free(ptr);
    }
  }

  CanFrame _readFdFrame() {
    final ptr = calloc<CanFdFrameNative>();
    try {
      final nbytes = Libc.read(_fd, ptr.cast(), sizeOf<CanFdFrameNative>());
      if (nbytes < 0) _throwErrno('read(canfd)');
      if (nbytes == sizeOf<CanFrameNative>()) {
        // Got a classic CAN frame on an FD socket
        return CanFrame.fromNative(ptr.cast<CanFrameNative>().ref);
      }
      return CanFrame.fromFdNative(ptr.ref);
    } finally {
      calloc.free(ptr);
    }
  }

  Stream<CanFrame> _createFrameStream() {
    late StreamController<CanFrame> controller;
    Isolate? isolate;

    controller = StreamController<CanFrame>(
      onCancel: () {
        isolate?.kill(priority: Isolate.immediate);
        isolate = null;
      },
    );

    final receivePort = ReceivePort();

    receivePort.listen((message) {
      if (message is CanFrame) {
        controller.add(message);
      } else if (message is String) {
        controller.addError(CanSocketException(message, 0));
      }
    });

    Isolate.spawn(
      _frameReadLoop,
      _IsolateConfig(
        fd: _fd,
        sendPort: receivePort.sendPort,
        canFd: canFd,
      ),
    ).then((iso) {
      isolate = iso;
    });

    return controller.stream;
  }

  /// Isolate entry point for blocking frame reads.
  static void _frameReadLoop(_IsolateConfig config) {
    final pollfd = calloc<PollFd>();
    pollfd.ref.fd = config.fd;
    pollfd.ref.events = pollIn;

    final framePtr = config.canFd
        ? calloc<CanFdFrameNative>().cast<Void>()
        : calloc<CanFrameNative>().cast<Void>();

    final frameSize =
        config.canFd ? sizeOf<CanFdFrameNative>() : sizeOf<CanFrameNative>();

    try {
      while (true) {
        pollfd.ref.revents = 0;
        final ret = Libc.poll(pollfd.cast(), 1, 100); // 100ms poll timeout
        if (ret < 0) {
          config.sendPort.send('poll() failed: errno ${Libc.errno}');
          break;
        }
        if (ret == 0) continue; // timeout, loop again to check for kill

        final nbytes = Libc.read(config.fd, framePtr, frameSize);
        if (nbytes < 0) {
          config.sendPort.send('read() failed: errno ${Libc.errno}');
          break;
        }

        if (config.canFd) {
          if (nbytes == sizeOf<CanFrameNative>()) {
            config.sendPort.send(
                CanFrame.fromNative(framePtr.cast<CanFrameNative>().ref));
          } else {
            config.sendPort.send(
                CanFrame.fromFdNative(framePtr.cast<CanFdFrameNative>().ref));
          }
        } else {
          config.sendPort.send(
              CanFrame.fromNative(framePtr.cast<CanFrameNative>().ref));
        }
      }
    } finally {
      calloc.free(pollfd);
      calloc.free(framePtr);
    }
  }
}

class _IsolateConfig {
  final int fd;
  final SendPort sendPort;
  final bool canFd;

  _IsolateConfig({
    required this.fd,
    required this.sendPort,
    required this.canFd,
  });
}
