// Glue layer between can_engine and the Flutter helm UI.
//
// Mirrors the shape of charger_ui's ChargerService: a single ChangeNotifier
// that owns the engine, polls its zero-copy snapshot, decodes frames, and
// exposes the latest values to the widgets. The difference is that every
// signal lookup here goes through the DBC file (via [BoatDbc]) by *name*,
// so the Throttle DBC schema can change — signals added, removed, renamed —
// without breaking the UI. Widgets that reference a signal that no longer
// exists just get `null` / their default fallback.
//
// Three connection modes:
//   * connect(iface) — opens a real CAN interface through can_engine
//   * connectDemo()  — runs an in-process simulator (no can_engine, no vcan)
//   * the external CLI simulator (bin/throttle_sim.dart) drives vcan0
//
// Only the first two live here. The CLI simulator is a separate process.

import 'dart:async';
import 'dart:ffi';
import 'dart:math';

import 'package:can_dbc/can_dbc.dart';
import 'package:can_engine/can_engine.dart';
import 'package:flutter/foundation.dart';

import '../can/boat_dbc.dart';

/// Connection state for the top-level status banner.
enum ThrottleConnectionState { disconnected, connecting, connected, error }

/// Boat mode command (mirrors DBC value table for HELM_CMD.Boat_Mode).
enum BoatModeCmd {
  charging, // 0 — HVIL relay undriven
  driving, // 1 — HVIL relay activated
}

/// Service that owns the [CanEngine] and exposes decoded helm state by
/// signal name. All reads go through [signal] / [rawSignal] so the widget
/// layer never mentions CAN IDs or bit offsets.
class ThrottleService extends ChangeNotifier {
  ThrottleService(this.dbc) {
    // Pre-cache outbound message handles so setAuxRelay / setBoatMode can
    // encode without re-looking-up on every call. If the DBC ever drops
    // HELM_CMD, these stay null and the setters become no-ops.
    _helmCmdMsg = dbc.message('HELM_CMD');
  }

  final BoatDbc dbc;
  DbcMessage? _helmCmdMsg;

  CanEngine? _engine;
  Timer? _pollTimer;
  Timer? _demoTimer;
  int _lastSequence = 0;
  bool _demoMode = false;
  ThrottleConnectionState _state = ThrottleConnectionState.disconnected;
  String? _errorMessage;
  String? _interfaceName;

  // Latest decoded value for every signal we've ever seen, keyed by DBC
  // signal name. Physical units (scale/offset already applied).
  final Map<String, double> _values = {};

  // Latest raw frame bytes per CAN ID, so the sim-tick reads can round-trip
  // through the same path as real-bus reads.
  final Map<int, Uint8List> _rawFrames = {};

  // Currently-armed outbound command state. Cached so HELM_CMD encodes with
  // the correct "other" bit when the user only toggles one signal.
  bool _auxRelayOn = false;
  BoatModeCmd _boatMode = BoatModeCmd.charging;

  // ── Public state ──

  ThrottleConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  String? get interfaceName => _interfaceName;
  bool get isDemoMode => _demoMode;
  bool get isConnected => _state == ThrottleConnectionState.connected;
  bool get auxRelayOn => _auxRelayOn;
  BoatModeCmd get boatMode => _boatMode;

  /// Latest physical value for [signalName], or `null` if the DBC no
  /// longer defines that signal OR no frame carrying it has arrived yet.
  double? signal(String signalName) => _values[signalName];

  /// Same as [signal] but returns [fallback] instead of null.
  double signalOr(String signalName, double fallback) =>
      _values[signalName] ?? fallback;

  /// Whether the most recent frame carrying [signalName] has been seen.
  bool hasSignal(String signalName) => _values.containsKey(signalName);

  /// Look up the DBC metadata for [signalName] (unit, enum map, bit range).
  DbcSignal? signalDef(String signalName) => dbc.signal(signalName);

  /// Convert a raw signal value to its value-table label if the DBC has one.
  String? valueLabel(String signalName) {
    final def = dbc.signal(signalName);
    final value = _values[signalName];
    if (def == null || value == null) return null;
    final descriptions = def.valueDescriptions;
    if (descriptions == null) return null;
    // Reverse the physical conversion to get the raw key the DBC used.
    final raw = ((value - def.offset) / def.factor).round();
    return descriptions[raw];
  }

  // ── Lifecycle ──

  /// Open the named CAN interface (e.g. `vcan0`) through can_engine.
  Future<bool> connect(String iface) async {
    if (_state == ThrottleConnectionState.connected) return true;

    _state = ThrottleConnectionState.connecting;
    _errorMessage = null;
    _demoMode = false;
    notifyListeners();

    try {
      _engine = CanEngine();
      final result = _engine!.start(iface);
      if (result < 0) {
        _errorMessage = 'Failed to start engine: ${_engine!.lastError}';
        _engine!.dispose();
        _engine = null;
        _state = ThrottleConnectionState.error;
        notifyListeners();
        return false;
      }
      _interfaceName = iface;
      _state = ThrottleConnectionState.connected;
      _lastSequence = 0;
      _startPolling();
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _engine?.dispose();
      _engine = null;
      _state = ThrottleConnectionState.error;
      notifyListeners();
      return false;
    }
  }

  /// Run with synthetic data — no CAN interface required.
  void connectDemo() {
    if (_state == ThrottleConnectionState.connected) return;

    _demoMode = true;
    _interfaceName = null;
    _state = ThrottleConnectionState.connected;
    _errorMessage = null;
    _resetSimState();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _simulateTick();
    });
    notifyListeners();
  }

  /// Disconnect from the bus or stop the demo simulator.
  void disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _demoTimer?.cancel();
    _demoTimer = null;
    if (!_demoMode) {
      _engine?.stop();
      _engine?.dispose();
      _engine = null;
    }
    _values.clear();
    _rawFrames.clear();
    _state = ThrottleConnectionState.disconnected;
    _demoMode = false;
    _interfaceName = null;
    notifyListeners();
  }

  // ── Outbound commands ──

  /// Toggle the auxiliary relay command (HELM_CMD.AUX_Relay_Cmd).
  void setAuxRelay(bool on) {
    _auxRelayOn = on;
    _sendHelmCmd();
    notifyListeners();
  }

  /// Switch between CHARGING / DRIVING (HELM_CMD.Boat_Mode).
  void setBoatMode(BoatModeCmd mode) {
    _boatMode = mode;
    _sendHelmCmd();
    notifyListeners();
  }

  void _sendHelmCmd() {
    final msg = _helmCmdMsg;
    if (msg == null) return; // DBC removed HELM_CMD — silently drop.
    final payload = dbc.packMessage(msg, {
      'AUX_Relay_Cmd': _auxRelayOn ? 1.0 : 0.0,
      'Boat_Mode': _boatMode == BoatModeCmd.driving ? 1.0 : 0.0,
    });
    if (_demoMode) {
      // Demo mode has no bus — we just echo the command into our local
      // value cache so the UI feels responsive.
      final decoded = dbc.decodeAll(msg, payload);
      _values.addAll(decoded);
      return;
    }
    final engine = _engine;
    if (engine == null) return;
    engine.sendFrame(msg.id, payload);
  }

  // ── Snapshot polling ──

  void _startPolling() {
    // 30 Hz — higher than any DBC frame rate, so we never miss a refresh.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _pollSnapshot();
    });
  }

  /// Walk the engine's per-CAN-id message buffer, grab any frame whose ID
  /// the DBC defines, and decode every signal in it. The snapshot holds
  /// the *latest* row per CAN ID, so one sweep keeps every signal fresh.
  void _pollSnapshot() {
    final engine = _engine;
    if (engine == null) return;
    final seq = engine.sequence;
    if (seq == _lastSequence) return;
    _lastSequence = seq;

    final snap = engine.snapshotPtr;
    if (snap == null) return;
    final s = snap.ref;
    final count = s.messageCount;

    var changed = false;
    for (var i = 0; i < count; i++) {
      final row = s.messages[i];
      final id = row.canId;
      final msg = dbc.messageById(id);
      if (msg == null) continue;
      final dlc = row.dlc;
      if (dlc == 0) continue;
      final data = Uint8List(dlc);
      for (var b = 0; b < dlc; b++) {
        data[b] = row.data[b];
      }
      _rawFrames[id] = data;
      final decoded = dbc.decodeAll(msg, data);
      if (decoded.isNotEmpty) {
        _values.addAll(decoded);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ── Demo simulation ──
  //
  // The in-process simulator generates plausible helm state directly into
  // the value cache. It doesn't re-pack frames byte-for-byte — that's the
  // CLI simulator's job (bin/throttle_sim.dart), which drives a real vcan
  // interface through can_socket and exercises the full decode stack.

  final Random _rng = Random();
  int _simTicks = 0;
  double _simThrottle = 0.0; // -5.12 .. 5.11 per DBC
  double _simSog = 0.0; // m/s
  double _simCog = 0.0; // radians, 0..2π
  double _simLat = 47.6062; // Seattle — every maritime demo starts here
  double _simLon = -122.3321;

  void _resetSimState() {
    _simTicks = 0;
    _simThrottle = 0.0;
    _simSog = 0.0;
    _simCog = pi; // heading south
    _simLat = 47.6062;
    _simLon = -122.3321;
    _values.clear();
    _rawFrames.clear();
  }

  void _simulateTick() {
    _simTicks++;

    // Gentle oscillating throttle, 0.1 Hz.
    _simThrottle = 1.5 + sin(_simTicks * 0.02) * 1.3;
    // Slightly-lagged speed response.
    final targetSog = _simThrottle * 2.5;
    _simSog += (targetSog - _simSog) * 0.05;
    if (_simSog < 0) _simSog = 0;
    // Heading drifts with a meandering sine.
    _simCog = (pi + sin(_simTicks * 0.005) * 0.4) % (2 * pi);
    // Move the boat along its current heading.
    final latStep = _simSog * cos(_simCog) * 1e-6;
    final lonStep = _simSog * sin(_simCog) * 1e-6;
    _simLat = (_simLat + latStep).clamp(-89.9, 89.9);
    _simLon = (_simLon + lonStep).clamp(-179.9, 179.9);

    // HELM_00 — fault bits clean, throttle driven, tilt request
    // cycling NO REQUEST → TILT UP → NO REQUEST → TILT DOWN so the
    // engine-trim indicator actually exercises in demo mode.
    _values['Throttle'] = _simThrottle;
    final tiltPhase = (_simTicks ~/ 40) % 4;
    _values['Tilt_Req'] = switch (tiltPhase) {
      1 => 2, // TILT UP
      3 => 1, // TILT DOWN
      _ => 0, // NO REQUEST
    };
    _values['Batt_Status'] = 0;
    _values['Reset_Faults'] = 0;
    _values['MAIN_Relay_Status'] = 1;
    _values['AUX_Relay_Status'] = _auxRelayOn ? 1 : 0;
    _values['HVIL_Relay_Status'] = _boatMode == BoatModeCmd.driving ? 1 : 0;
    _values['HVIL_Return_Sense'] = _boatMode == BoatModeCmd.driving ? 1 : 0;
    _values['Estop'] = 0;
    _values['Key'] = 1;
    _values['StartStop'] = 1;
    _values['Flt_SDcard'] = 0;
    _values['Flt_ThrottleSensor'] = 0;
    _values['Flt_InternalComm'] = 0;
    _values['Flt_GPS'] = 0;
    _values['Flt_DataUpload'] = 0;
    _values['Flt_CAN'] = 0;
    _values['Flt_ANR'] = 0;
    _values['Sys_Timer'] = (_simTicks % 65536).toDouble();

    // HELM_01 — identification, held constant.
    _values['SW_Major'] = 2;
    _values['SW_Minor'] = 1;
    _values['Serial_Number'] = 1176;

    // COG_SOG_RAPID
    _values['SOG'] = _simSog;
    _values['COG'] = _simCog;
    _values['COG_Reference'] = 0; // TRUE north

    // POS_RAPID
    _values['Latitude'] = _simLat;
    _values['Longitude'] = _simLon;

    // Sprinkle a bit of jitter on one fault to show the indicators react.
    if (_simTicks % 60 == 0) {
      _values['Flt_DataUpload'] = (_rng.nextDouble() < 0.2) ? 1 : 0;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
