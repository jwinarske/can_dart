// Thin wrapper around the parsed [DbcDatabase] that keeps every lookup
// keyed by *string* — signal names and message names — so the rest of the
// app never hardcodes a CAN ID or bit layout.
//
// The "breaking interface changes without breaking code" property of the
// design lives here: if the DBC adds a new signal, this class picks it up
// at startup; if a signal is renamed, the UI reads `null` for the old
// name and keeps running. Nothing blows up because the model is
// data-driven from the DBC file, not from generated C structs.

import 'dart:typed_data';

import 'package:can_dbc/can_dbc.dart';

import 'dbc_codec.dart';

/// Loaded DBC database with O(1) name-indexed lookups and per-frame
/// decode/encode helpers.
class BoatDbc {
  BoatDbc._(
    this.database,
    this._messagesByName,
    this._messagesById,
    this._signalParents,
  );

  /// Parsed database — use this for introspection (signal lists, units,
  /// comments, value descriptions). The UI reads values via [decode] /
  /// [value], not by poking at this directly.
  final DbcDatabase database;

  final Map<String, DbcMessage> _messagesByName;
  final Map<int, DbcMessage> _messagesById;

  /// Signal name → (message, signal) pair. Signal names in the Throttle
  /// DBC are unique across messages so a single map is enough; if that
  /// ever changes we'll need `(messageName, signalName)` keys.
  final Map<String, ({DbcMessage message, DbcSignal signal})> _signalParents;

  /// Construct from an already-parsed database. Pure Dart — callers that
  /// want Flutter asset loading should use `BoatDbcAssetLoader` from
  /// `can/boat_dbc_asset_loader.dart` (which imports `package:flutter`).
  /// Keeping this file Flutter-free lets the CLI simulator import it
  /// without dragging in dart:ui.
  factory BoatDbc.fromDatabase(DbcDatabase db) => BoatDbc._fromDb(db);

  static BoatDbc _fromDb(DbcDatabase db) {
    final byName = <String, DbcMessage>{};
    final byId = <int, DbcMessage>{};
    final signalParents = <String, ({DbcMessage message, DbcSignal signal})>{};
    for (final msg in db.messages) {
      byName[msg.name] = msg;
      byId[msg.id] = msg;
      for (final sig in msg.signals) {
        signalParents[sig.name] = (message: msg, signal: sig);
      }
    }
    return BoatDbc._(db, byName, byId, signalParents);
  }

  /// Look up a message by DBC name. Returns null if the DBC file was
  /// updated and the name no longer exists.
  DbcMessage? message(String name) => _messagesByName[name];

  /// Look up a message by CAN ID.
  DbcMessage? messageById(int canId) => _messagesById[canId];

  /// Look up a signal by its (globally-unique) DBC name.
  DbcSignal? signal(String name) => _signalParents[name]?.signal;

  /// Look up the parent message for a named signal.
  DbcMessage? parentOf(String signalName) =>
      _signalParents[signalName]?.message;

  /// Decode every signal in [msg] from [payload] into a fresh map keyed
  /// by signal name. Signals that don't fit the payload are dropped.
  Map<String, double> decodeAll(DbcMessage msg, Uint8List payload) {
    final out = <String, double>{};
    for (final sig in msg.signals) {
      final v = decodeSignal(sig, payload);
      if (v != null) out[sig.name] = v;
    }
    return out;
  }

  /// Convenience: decode one named signal out of [payload], applying the
  /// message's declared length to bound the buffer.
  double? decodeNamed(String signalName, Uint8List payload) {
    final parent = _signalParents[signalName];
    if (parent == null) return null;
    return decodeSignal(parent.signal, payload);
  }

  /// Encode [values] (keyed by signal name) into a new payload sized to
  /// [msg].length. Any signal not mentioned in [values] is left at zero.
  /// Unknown signal names are silently ignored so that caller-side
  /// "optimistic updates" survive DBC schema drift.
  Uint8List packMessage(DbcMessage msg, Map<String, double> values) {
    final buf = Uint8List(msg.length);
    for (final entry in values.entries) {
      final sig = _findSignalIn(msg, entry.key);
      if (sig == null) continue;
      encodeSignal(sig, entry.value, buf);
    }
    return buf;
  }

  DbcSignal? _findSignalIn(DbcMessage msg, String name) {
    for (final sig in msg.signals) {
      if (sig.name == name) return sig;
    }
    return null;
  }
}
