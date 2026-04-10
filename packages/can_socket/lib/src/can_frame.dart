import 'dart:ffi';
import 'dart:typed_data';

import 'ffi/constants.dart';
import 'ffi/structs.dart';

/// A CAN bus frame (standard or CAN FD).
class CanFrame {
  /// The CAN identifier (11-bit standard or 29-bit extended).
  final int id;

  /// Whether this is an extended frame format (29-bit ID).
  final bool isExtended;

  /// Whether this is a remote transmission request.
  final bool isRemote;

  /// Whether this is an error frame.
  final bool isError;

  /// Whether this is a CAN FD frame.
  final bool isFd;

  /// CAN FD: bit rate switch flag.
  final bool isBrs;

  /// CAN FD: error state indicator flag.
  final bool isEsi;

  /// Frame payload data.
  final Uint8List data;

  /// Timestamp of frame reception (if available).
  final DateTime? timestamp;

  CanFrame({
    required this.id,
    this.isExtended = false,
    this.isRemote = false,
    this.isError = false,
    this.isFd = false,
    this.isBrs = false,
    this.isEsi = false,
    required this.data,
    this.timestamp,
  });

  /// The data length code.
  int get dlc => data.length;

  /// Construct the raw can_id field with flags.
  int get rawId {
    var raw = id;
    if (isExtended) raw |= canEffFlag;
    if (isRemote) raw |= canRtrFlag;
    if (isError) raw |= canErrFlag;
    return raw;
  }

  /// Create a CanFrame from a native can_frame struct.
  factory CanFrame.fromNative(CanFrameNative native, {DateTime? timestamp}) {
    final rawId = native.canId;
    final dlc = native.dlc;
    final data = Uint8List(dlc);
    for (var i = 0; i < dlc; i++) {
      data[i] = native.data[i];
    }
    return CanFrame(
      id: rawId & (rawId & canEffFlag != 0 ? canEffMask : canSffMask),
      isExtended: rawId & canEffFlag != 0,
      isRemote: rawId & canRtrFlag != 0,
      isError: rawId & canErrFlag != 0,
      data: data,
      timestamp: timestamp,
    );
  }

  /// Create a CanFrame from a native canfd_frame struct.
  factory CanFrame.fromFdNative(CanFdFrameNative native, {DateTime? timestamp}) {
    final rawId = native.canId;
    final len = native.len;
    final data = Uint8List(len);
    for (var i = 0; i < len; i++) {
      data[i] = native.data[i];
    }
    return CanFrame(
      id: rawId & (rawId & canEffFlag != 0 ? canEffMask : canSffMask),
      isExtended: rawId & canEffFlag != 0,
      isRemote: rawId & canRtrFlag != 0,
      isError: rawId & canErrFlag != 0,
      isFd: true,
      isBrs: native.flags & canfdBrs != 0,
      isEsi: native.flags & canfdEsi != 0,
      data: data,
      timestamp: timestamp,
    );
  }

  /// Write this frame into a native can_frame struct.
  void toNative(Pointer<CanFrameNative> ptr) {
    final frame = ptr.ref;
    frame.canId = rawId;
    frame.dlc = data.length > canMaxDlc ? canMaxDlc : data.length;
    frame.pad = 0;
    frame.res0 = 0;
    frame.res1 = 0;
    final len = frame.dlc;
    for (var i = 0; i < len; i++) {
      frame.data[i] = data[i];
    }
    // Zero remaining bytes
    for (var i = len; i < canMaxDlc; i++) {
      frame.data[i] = 0;
    }
  }

  /// Write this frame into a native canfd_frame struct.
  void toFdNative(Pointer<CanFdFrameNative> ptr) {
    final frame = ptr.ref;
    frame.canId = rawId;
    frame.len = data.length > canfdMaxDlc ? canfdMaxDlc : data.length;
    frame.flags = 0;
    if (isBrs) frame.flags |= canfdBrs;
    if (isEsi) frame.flags |= canfdEsi;
    frame.res0 = 0;
    frame.res1 = 0;
    final len = frame.len;
    for (var i = 0; i < len; i++) {
      frame.data[i] = data[i];
    }
    for (var i = len; i < canfdMaxDlc; i++) {
      frame.data[i] = 0;
    }
  }

  @override
  String toString() {
    final hexId = id.toRadixString(16).toUpperCase().padLeft(isExtended ? 8 : 3, '0');
    final hexData = data.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
    final flags = [
      if (isExtended) 'EFF',
      if (isRemote) 'RTR',
      if (isError) 'ERR',
      if (isFd) 'FD',
      if (isBrs) 'BRS',
      if (isEsi) 'ESI',
    ];
    final flagStr = flags.isEmpty ? '' : ' [${flags.join(',')}]';
    return '$hexId [$dlc] $hexData$flagStr';
  }
}
