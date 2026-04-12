// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';

import 'constants.dart';

/// struct can_frame {
///   canid_t can_id;   // 32-bit CAN ID + EFF/RTR/ERR flags
///   __u8    can_dlc;  // data length code: 0..8
///   __u8    __pad;
///   __u8    __res0;
///   __u8    __res1;
///   __u8    data[8];
/// };
/// Total: 16 bytes (CAN_MTU)
final class CanFrameNative extends Struct {
  @Uint32()
  external int canId;

  @Uint8()
  external int dlc;

  @Uint8()
  external int pad;

  @Uint8()
  external int res0;

  @Uint8()
  external int res1;

  @Array(8)
  external Array<Uint8> data;
}

/// struct canfd_frame {
///   canid_t can_id;   // 32-bit CAN ID + EFF/RTR/ERR flags
///   __u8    len;      // data length: 0..64
///   __u8    flags;    // FD flags (BRS, ESI)
///   __u8    __res0;
///   __u8    __res1;
///   __u8    data[64];
/// };
/// Total: 72 bytes (CANFD_MTU)
final class CanFdFrameNative extends Struct {
  @Uint32()
  external int canId;

  @Uint8()
  external int len;

  @Uint8()
  external int flags;

  @Uint8()
  external int res0;

  @Uint8()
  external int res1;

  @Array(64)
  external Array<Uint8> data;
}

/// struct sockaddr_can {
///   sa_family_t can_family;  // AF_CAN
///   int         can_ifindex;
///   union {
///     struct { canid_t rx_id, tx_id; } tp;
///     struct { uint64_t name; uint32_t pgn; uint8_t addr; } j1939;
///   } can_addr;
/// };
/// We model the largest variant (j1939) to ensure correct size.
/// Total size: 24 bytes on 64-bit.
final class SockaddrCan extends Struct {
  @Uint16()
  external int canFamily;

  // 2 bytes padding inserted by compiler
  @Uint16()
  external int pad;

  @Int32()
  external int canIfindex;

  // Union: tp { rx_id, tx_id } or j1939 { name, pgn, addr }
  // We expose the raw bytes and provide typed accessors.
  @Uint32()
  external int addrField0; // tp.rx_id or j1939.name (low 32)

  @Uint32()
  external int addrField1; // tp.tx_id or j1939.name (high 32)

  @Uint32()
  external int addrField2; // j1939.pgn

  @Uint8()
  external int addrField3; // j1939.addr

  @Uint8()
  external int addrPad0;

  @Uint8()
  external int addrPad1;

  @Uint8()
  external int addrPad2;
}

/// struct can_filter {
///   canid_t can_id;
///   canid_t can_mask;
/// };
final class CanFilterNative extends Struct {
  @Uint32()
  external int canId;

  @Uint32()
  external int canMask;
}

/// struct ifreq — we only need ifr_name[IFNAMSIZ] + ifr_ifindex.
/// Total: 40 bytes on 64-bit Linux.
final class Ifreq extends Struct {
  // ifr_name: 16 bytes
  @Array(16)
  external Array<Uint8> ifrName;

  // ifr_ifindex sits at offset 16 in the union
  @Int32()
  external int ifrIfindex;

  // Remaining padding to fill 40 bytes (16 + 4 + 20 = 40)
  @Array(20)
  external Array<Uint8> pad;
}

/// struct pollfd {
///   int   fd;
///   short events;
///   short revents;
/// };
final class PollFd extends Struct {
  @Int32()
  external int fd;

  @Int16()
  external int events;

  @Int16()
  external int revents;
}

/// struct timeval {
///   time_t      tv_sec;
///   suseconds_t tv_usec;
/// };
final class Timeval extends Struct {
  @Int64()
  external int tvSec;

  @Int64()
  external int tvUsec;
}

/// BCM message header.
/// struct bcm_msg_head {
///   __u32 opcode;
///   __u32 flags;
///   __u32 count;
///   struct bcm_timeval ival1, ival2;
///   canid_t can_id;
///   __u32 nframes;
///   // followed by can_frame[]
/// };
final class BcmMsgHead extends Struct {
  @Uint32()
  external int opcode;

  @Uint32()
  external int flags;

  @Uint32()
  external int count;

  // ival1: tv_sec (8 bytes) + tv_usec (8 bytes) = 16 bytes
  @Int64()
  external int ival1Sec;

  @Int64()
  external int ival1Usec;

  // ival2
  @Int64()
  external int ival2Sec;

  @Int64()
  external int ival2Usec;

  @Uint32()
  external int canId;

  @Uint32()
  external int nframes;
}

/// ISO-TP options struct.
/// struct can_isotp_options {
///   __u32 flags;
///   __u32 frame_txtime;
///   __u8  ext_address;
///   __u8  txpad_content;
///   __u8  rxpad_content;
///   __u8  rx_ext_address;
/// };
final class CanIsotpOptions extends Struct {
  @Uint32()
  external int flags;

  @Uint32()
  external int frameTxtime;

  @Uint8()
  external int extAddress;

  @Uint8()
  external int txpadContent;

  @Uint8()
  external int rxpadContent;

  @Uint8()
  external int rxExtAddress;
}

/// ISO-TP flow control options.
/// struct can_isotp_fc_options {
///   __u8 bs;    // block size
///   __u8 stmin; // separation time min
///   __u8 wftmax;
/// };
final class CanIsotpFcOptions extends Struct {
  @Uint8()
  external int bs;

  @Uint8()
  external int stmin;

  @Uint8()
  external int wftmax;

  @Uint8()
  external int pad;
}

/// J1939 filter struct.
/// struct j1939_filter {
///   name_t name;
///   name_t name_mask;
///   uint8_t addr;
///   uint8_t addr_mask;
///   uint32_t pgn;
///   uint32_t pgn_mask;
/// };
final class J1939Filter extends Struct {
  @Uint64()
  external int name;

  @Uint64()
  external int nameMask;

  @Uint8()
  external int addr;

  @Uint8()
  external int addrMask;

  @Uint16()
  external int pad;

  @Uint32()
  external int pgn;

  @Uint32()
  external int pgnMask;
}

/// Helper to set ifreq name from a Dart string.
void setIfreqName(Ifreq ifreq, String name) {
  final bytes = name.codeUnits;
  final len = bytes.length < ifNameSize - 1 ? bytes.length : ifNameSize - 1;
  for (var i = 0; i < len; i++) {
    ifreq.ifrName[i] = bytes[i];
  }
  ifreq.ifrName[len] = 0; // null terminator
}
