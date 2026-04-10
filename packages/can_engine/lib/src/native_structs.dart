/// Native struct definitions matching the C++ DisplaySnapshot layout.
///
/// These structs are used with Pointer.ref for zero-copy reads.
library;

import 'dart:ffi';

// Size constants matching C++
const int maxFrames = 200;
const int maxMessages = 512;
const int maxSignals = 256;
const int maxTextLen = 128;
const int maxNameLen = 64;
const int maxUnitLen = 16;
const int maxValLen = 32;
const int maxGraphPoints = 1024;
const int maxGraphSignals = 8;
const int maxFilters = 4;

/// Matches can_engine::SignalSnapshot
final class SignalSnapshotNative extends Struct {
  @Array(64) // name[MAX_NAME_LEN]
  external Array<Uint8> name;

  @Array(32) // formatted[MAX_VAL_LEN]
  external Array<Uint8> formatted;

  @Array(16) // unit[MAX_UNIT_LEN]
  external Array<Uint8> unit;

  @Double()
  external double value;

  @Double()
  external double minDef;

  @Double()
  external double maxDef;

  @Uint8()
  external int changed;

  @Uint8()
  external int valid;

  @Array(6) // _pad[6]
  external Array<Uint8> pad;
}

/// Matches can_engine::MessageRow
final class MessageRowNative extends Struct {
  @Uint32()
  external int canId;

  @Array(64) // name[MAX_NAME_LEN]
  external Array<Uint8> nameBytes;

  @Uint8()
  external int dlc;

  @Uint8()
  external int direction;

  @Array(2) // _pad[2]
  external Array<Uint8> pad1;

  @Array(64) // data[64]
  external Array<Uint8> data;

  @Array(192) // data_hex[192]
  external Array<Uint8> dataHex;

  @Uint64()
  external int timestampUs;

  @Uint32()
  external int count;

  @Uint32()
  external int periodUs;

  @Uint8()
  external int highlight;

  @Array(3) // _pad2[3]
  external Array<Uint8> pad2;
}

/// Matches can_engine::FrameRow
final class FrameRowNative extends Struct {
  @Array(128) // text[MAX_TEXT_LEN]
  external Array<Uint8> text;

  @Uint32()
  external int canId;

  @Uint8()
  external int dlc;

  @Uint8()
  external int direction;

  @Array(2) // _pad[2]
  external Array<Uint8> pad;

  @Uint64()
  external int timestampUs;
}

/// Matches can_engine::GraphPoint
final class GraphPointNative extends Struct {
  @Double()
  external double value;

  @Uint64()
  external int timestampUs;
}

/// Matches can_engine::SignalGraph
final class SignalGraphNative extends Struct {
  @Uint32()
  external int signalIndex;

  @Uint32()
  external int head;

  @Uint32()
  external int count;

  @Uint32()
  external int pad;

  @Array(1024) // points[MAX_GRAPH_POINTS]
  external Array<GraphPointNative> points;
}

/// Matches can_engine::BusStatistics
final class BusStatisticsNative extends Struct {
  @Double()
  external double busLoadPercent;

  @Uint32()
  external int framesPerSecond;

  @Uint32()
  external int dataBytesPerSecond;

  @Uint32()
  external int errorFrames;

  @Uint32()
  external int overrunCount;

  @Uint8()
  external int controllerState;

  @Uint8()
  external int txErrorCount;

  @Uint8()
  external int rxErrorCount;

  @Uint8()
  external int pad1;

  @Uint64()
  external int totalFrames;

  @Uint64()
  external int totalTxFrames;

  @Uint64()
  external int totalRxFrames;

  @Uint64()
  external int totalErrorFrames;

  @Uint64()
  external int totalBytes;

  @Uint64()
  external int uptimeUs;

  @Double()
  external double peakBusLoad;

  @Uint32()
  external int peakFps;

  @Uint32()
  external int pad2;
}

/// Matches can_engine::LogState
final class LogStateNative extends Struct {
  @Uint8()
  external int active;

  @Array(3) // _pad[3]
  external Array<Uint8> pad1;

  @Uint32()
  external int pad2;

  @Uint64()
  external int loggedFrames;

  @Uint64()
  external int fileSizeBytes;

  @Array(256) // filename[256]
  external Array<Uint8> filename;
}

/// Matches can_engine::DisplaySnapshot.
///
/// This is THE interface between C++ and Dart. Dart reads fields
/// via Pointer.ref — a direct memory dereference, no copy.
///
/// Note: We cannot represent std::atomic<uint64_t> directly in Dart FFI.
/// We read the sequence counter via the engine_sequence() C API call instead.
/// The remaining fields are accessed via pointer arithmetic on the snapshot.
final class DisplaySnapshotNative extends Struct {
  @Uint64() // sequence (atomic, read via C API)
  external int sequence;

  // Overwrite mode
  @Array(512) // messages[MAX_MESSAGES]
  external Array<MessageRowNative> messages;

  @Uint32()
  external int messageCount;

  // 4 bytes padding for alignment before frames array
  @Uint32()
  external int messagesPad;

  // Append mode
  @Array(200) // frames[MAX_FRAMES]
  external Array<FrameRowNative> frames;

  @Uint32()
  external int frameHead;

  @Uint32()
  external int frameCount;

  // Signal watch
  @Array(256) // signals[MAX_SIGNALS]
  external Array<SignalSnapshotNative> signals;

  @Uint32()
  external int signalCount;

  // 4 bytes padding for alignment before graphs
  @Uint32()
  external int signalsPad;

  // Signal graphs
  @Array(8) // graphs[MAX_GRAPH_SIGNALS]
  external Array<SignalGraphNative> graphs;

  @Uint32()
  external int graphCount;

  // 4 bytes padding for alignment before stats
  @Uint32()
  external int graphsPad;

  // Bus statistics
  external BusStatisticsNative stats;

  // Logging
  external LogStateNative log;

  // Engine state
  @Uint8()
  external int running;

  @Uint8()
  external int connected;

  @Uint8()
  external int errorCode;

  @Array(5) // _pad[5]
  external Array<Uint8> pad;

  @Array(128) // error_msg[128]
  external Array<Uint8> errorMsg;
}

/// Matches can_engine::FilterConfig
final class FilterConfigNative extends Struct {
  @Uint8()
  external int type; // FilterType enum

  @Array(7)
  external Array<Uint8> pad;

  @Double()
  external double param; // union: alpha, max_rate_per_sec, or deadband
}
