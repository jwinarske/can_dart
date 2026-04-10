import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../model/dbc_database.dart';
import '../model/dbc_signal.dart';
import 'native_structs.dart';

/// Compiled signal database ready for consumption by can_engine.
///
/// Contains packed native structs allocated via [calloc]. Call [dispose]
/// when done to free the memory.
class CompiledSignalDb {
  /// Pointer to the array of signal definitions.
  final Pointer<SignalDefNative> signalDefs;

  /// Total number of signal definitions.
  final int signalCount;

  /// Pointer to the array of message definitions.
  final Pointer<MessageDefNative> messageDefs;

  /// Total number of message definitions.
  final int messageCount;

  CompiledSignalDb._({
    required this.signalDefs,
    required this.signalCount,
    required this.messageDefs,
    required this.messageCount,
  });

  /// Free the native memory.
  void dispose() {
    if (signalCount > 0) calloc.free(signalDefs);
    if (messageCount > 0) calloc.free(messageDefs);
  }
}

/// Compiles a [DbcDatabase] into packed native structs for can_engine.
class SignalCompiler {
  /// Compile the database into native structs.
  ///
  /// The returned [CompiledSignalDb] owns allocated memory — caller
  /// must call [CompiledSignalDb.dispose] when done.
  CompiledSignalDb compile(DbcDatabase db) {
    // Count totals
    var totalSignals = 0;
    final messagesWithSignals = <({int id, int offset, int count})>[];

    for (final msg in db.messages) {
      if (msg.signals.isEmpty) continue;
      messagesWithSignals.add((
        id: msg.id,
        offset: totalSignals,
        count: msg.signals.length,
      ));
      totalSignals += msg.signals.length;
    }

    // Allocate
    final signalDefs = totalSignals > 0
        ? calloc<SignalDefNative>(totalSignals)
        : Pointer<SignalDefNative>.fromAddress(0);
    final messageDefs = messagesWithSignals.isNotEmpty
        ? calloc<MessageDefNative>(messagesWithSignals.length)
        : Pointer<MessageDefNative>.fromAddress(0);

    // Fill signal defs
    var sigIdx = 0;
    for (final msg in db.messages) {
      for (final sig in msg.signals) {
        _fillSignalDef((signalDefs + sigIdx).ref, sig);
        sigIdx++;
      }
    }

    // Fill message defs
    for (var i = 0; i < messagesWithSignals.length; i++) {
      final m = messagesWithSignals[i];
      final def = (messageDefs + i).ref;
      def.canId = m.id;
      def.signalOffset = m.offset;
      def.signalCount = m.count;
    }

    return CompiledSignalDb._(
      signalDefs: signalDefs,
      signalCount: totalSignals,
      messageDefs: messageDefs,
      messageCount: messagesWithSignals.length,
    );
  }

  void _fillSignalDef(SignalDefNative def, DbcSignal sig) {
    def.startBit = sig.startBit;
    def.bitLength = sig.length;
    def.byteOrder = sig.byteOrder == ByteOrder.littleEndian ? 0 : 1;
    def.valueType = sig.valueType == ValueType.signed ? 1 : 0;
    def.pad0 = 0;
    def.pad1 = 0;
    def.factor = sig.factor;
    def.offset = sig.offset;
    def.minimum = sig.minimum;
    def.maximum = sig.maximum;

    _writeFixedString(def.name, sig.name, maxNameLen);
    _writeFixedString(def.unit, sig.unit, maxUnitLen);
  }

  void _writeFixedString(Array<Uint8> dest, String src, int maxLen) {
    final bytes = src.codeUnits;
    final len = bytes.length < maxLen - 1 ? bytes.length : maxLen - 1;
    for (var i = 0; i < len; i++) {
      dest[i] = bytes[i];
    }
    dest[len] = 0; // null terminator
  }
}
