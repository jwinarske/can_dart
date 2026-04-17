// Service layer between RV-C bus and the Flutter dashboard.
//
// A single ChangeNotifier that owns the RvcEcu and RvcBusRegistry,
// subscribes to incoming frames, decodes them through the DGN registry,
// and exposes the latest signal values to widgets via [signal].
//
// Two connection modes:
//   * connect(iface) — opens a real CAN interface through RvcEcu
//   * connectDemo()  — runs an in-process simulator with synthetic data

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:can_codec/can_codec.dart' as codec;
import 'package:rvc/rvc.dart';
import 'package:rvc_bus/rvc_bus.dart';

/// Connection state for the top-level status indicator.
enum RvcConnectionState { disconnected, connecting, connected, error }

/// Service that owns the [RvcEcu] and [RvcBusRegistry], decodes incoming
/// frames, and exposes the latest field values keyed by
/// "dgn:instance:fieldName".
class RvcService extends ChangeNotifier {
  RvcService();

  RvcEcu? _ecu;
  RvcBusRegistry? _registry;
  StreamSubscription<FrameReceived>? _frameSub;
  StreamSubscription<RvcBusEvent>? _busSub;
  Timer? _demoTimer;

  RvcConnectionState _state = RvcConnectionState.disconnected;
  String? _errorMessage;
  bool _demoMode = false;

  // Latest decoded values keyed by "dgn:instance:fieldName".
  final Map<String, double> _values = {};

  // Bus devices tracked by RvcBusRegistry.
  final Map<int, RvcDeviceInfo> _devices = {};
  int _rxFrameCount = 0;

  // -- Getters ----------------------------------------------------------------

  RvcConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isDemoMode => _demoMode;
  bool get isConnected => _state == RvcConnectionState.connected;
  Map<int, RvcDeviceInfo> get devices => Map.unmodifiable(_devices);
  int get rxFrameCount => _rxFrameCount;

  /// Get a decoded signal value by DGN, instance, and field name.
  double? signal(int dgn, int instance, String field) =>
      _values['$dgn:$instance:$field'];

  // -- Lifecycle --------------------------------------------------------------

  /// Connect to a CAN interface (e.g. "vcan0").
  Future<bool> connect(String iface) async {
    if (_state == RvcConnectionState.connected) return true;

    _state = RvcConnectionState.connecting;
    _errorMessage = null;
    _demoMode = false;
    notifyListeners();

    try {
      _ecu = await RvcEcu.create(
        ifname: iface,
        deviceFunction: 10, // Display
      );

      _registry = RvcBusRegistry(_ecu!);
      _busSub = _registry!.events.listen(_onBusEvent);
      _frameSub = _ecu!.frames.listen(_onFrame);

      _state = RvcConnectionState.connected;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _ecu?.dispose();
      _ecu = null;
      _registry?.dispose();
      _registry = null;
      _state = RvcConnectionState.error;
      notifyListeners();
      return false;
    }
  }

  /// Run with synthetic data — no CAN interface required.
  void connectDemo() {
    if (_state == RvcConnectionState.connected) return;

    _demoMode = true;
    _state = RvcConnectionState.connected;
    _errorMessage = null;
    _values.clear();
    _devices.clear();
    _rxFrameCount = 0;
    _simTicks = 0;
    _demoTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _simulateTick();
    });
    notifyListeners();
  }

  /// Disconnect and clean up.
  void disconnect() {
    _demoTimer?.cancel();
    _demoTimer = null;
    _frameSub?.cancel();
    _frameSub = null;
    _busSub?.cancel();
    _busSub = null;
    _registry?.dispose();
    _registry = null;
    if (!_demoMode) {
      _ecu?.dispose();
      _ecu = null;
    }
    _values.clear();
    _devices.clear();
    _rxFrameCount = 0;
    _state = RvcConnectionState.disconnected;
    _demoMode = false;
    notifyListeners();
  }

  /// Send a command DGN via the ECU.
  Future<void> sendCommand(
    int dgn, {
    required int dest,
    required Uint8List data,
    int priority = 6,
  }) async {
    if (_ecu == null) return;
    await _ecu!.sendCommand(dgn, priority: priority, dest: dest, data: data);
  }

  /// Encode field values and send a command DGN.
  Future<void> sendCommandFields(
    int dgn, {
    required int dest,
    required Map<String, dynamic> values,
    int priority = 6,
  }) async {
    if (_ecu == null) return;
    await _ecu!.sendCommandFields(
      dgn,
      dest: dest,
      values: values,
      priority: priority,
    );
  }

  // -- Frame handling ---------------------------------------------------------

  void _onFrame(FrameReceived frame) {
    _rxFrameCount++;
    final registry = _ecu?.registry;
    if (registry == null) return;

    final def = registry.lookup(frame.pgn);
    if (def == null) return;

    final decoded = codec.decode(frame.data, def);
    if (decoded == null) return;

    // Extract instance from decoded fields (first byte in most RV-C DGNs).
    final instanceRaw = decoded['instance'];
    final instance = instanceRaw is int
        ? instanceRaw
        : (instanceRaw as double?)?.toInt();

    var changed = false;
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is double) {
        final key = '${def.pgn}:${instance ?? 0}:${entry.key}';
        _values[key] = value;
        changed = true;
      } else if (value is int) {
        final key = '${def.pgn}:${instance ?? 0}:${entry.key}';
        _values[key] = value.toDouble();
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void _onBusEvent(RvcBusEvent event) {
    switch (event) {
      case RvcDeviceAppeared(:final device):
        _devices[device.address] = device;
      case RvcDeviceDisappeared(:final address):
        _devices.remove(address);
      case RvcDeviceWentOffline(:final address):
        final d = _devices[address];
        if (d != null) d.status = RvcDeviceStatus.offline;
      case RvcDeviceCameOnline(:final device):
        _devices[device.address] = device;
    }
    notifyListeners();
  }

  // -- Demo simulation --------------------------------------------------------

  final Random _rng = Random();
  int _simTicks = 0;

  void _simulateTick() {
    _simTicks++;
    _rxFrameCount += 6;

    final t = _simTicks * 0.2; // time in seconds

    // DC Source Status 1 (0x1FFFD) — battery instance 0
    _values['131069:0:instance'] = 0;
    _values['131069:0:dcVoltage'] = 12.8 + sin(t * 0.01) * 0.3;
    _values['131069:0:dcCurrent'] = -5.0 + sin(t * 0.02) * 8.0;

    // DC Source Status 2 (0x1FFFC) — battery instance 0
    _values['131068:0:instance'] = 0;
    _values['131068:0:sourceTemperature'] = 25.0 + sin(t * 0.005) * 3.0;
    _values['131068:0:stateOfCharge'] = 72.0 + sin(t * 0.003) * 5.0;
    _values['131068:0:timeRemaining'] = 480 + sin(t * 0.002) * 60;

    // Tank Status (0x1FFB7) — 4 tanks
    _values['130999:0:level'] = 65.0 + sin(t * 0.004) * 3.0; // Fresh
    _values['130999:1:level'] = 30.0 + sin(t * 0.003) * 5.0; // Gray
    _values['130999:2:level'] = 15.0 + sin(t * 0.002) * 4.0; // Black
    _values['130999:3:level'] = 55.0 + sin(t * 0.005) * 2.0; // Propane

    // Thermostat Status 1 (0x1FFE2) — 2 zones
    _values['131042:0:instance'] = 0;
    _values['131042:0:operatingMode'] = 1; // cool
    _values['131042:0:fanMode'] = 0; // auto
    _values['131042:0:fanSpeed'] = 2; // medium
    _values['131042:0:setpointHeat'] = 20.0;
    _values['131042:0:setpointCool'] = 24.0;

    _values['131042:1:instance'] = 1;
    _values['131042:1:operatingMode'] = 2; // heat
    _values['131042:1:fanMode'] = 1; // on
    _values['131042:1:fanSpeed'] = 1; // low
    _values['131042:1:setpointHeat'] = 22.0;
    _values['131042:1:setpointCool'] = 26.0;

    // Simulated ambient temperatures (not a real DGN — demo only)
    _values['131042:0:ambientTemp'] = 23.0 + sin(t * 0.008) * 1.5;
    _values['131042:1:ambientTemp'] = 22.0 + sin(t * 0.006) * 1.0;

    // DC Dimmer Status 3 (0x1FEDE) — 6 zones
    for (int i = 0; i < 6; i++) {
      _values['130782:$i:instance'] = i.toDouble();
      _values['130782:$i:brightness'] = (i < 3)
          ? 80.0 + sin(t * 0.01 + i) * 5.0
          : 0.0;
      _values['130782:$i:enable'] = (i < 3) ? 1 : 0;
    }

    // Generator Status 1 (0x1FFDC)
    final genRunning = (_simTicks % 200) < 100;
    _values['131036:0:instance'] = 0;
    _values['131036:0:operatingStatus'] = genRunning ? 1 : 0;
    _values['131036:0:engineSpeed'] = genRunning
        ? 3600.0 + sin(t * 0.05) * 50.0
        : 0.0;
    _values['131036:0:engineHours'] = 1250.0 + _simTicks * 0.0001;

    // Inverter Status (0x1FFC4)
    _values['130948:0:instance'] = 0;
    _values['130948:0:operatingStatus'] = 1; // enabled
    _values['130948:0:dcVoltage'] = 12.6 + sin(t * 0.012) * 0.2;

    // Charger Status (0x1FFC7)
    _values['130951:0:instance'] = 0;
    _values['130951:0:chargeVoltage'] = 14.2 + sin(t * 0.01) * 0.1;
    _values['130951:0:chargeCurrent'] = 15.0 + sin(t * 0.015) * 3.0;
    _values['130951:0:operatingState'] = genRunning
        ? 3
        : 5; // bulk when gen running, float otherwise

    // Jitter a value occasionally for realism.
    if (_simTicks % 30 == 0) {
      _values['131069:0:dcVoltage'] =
          _values['131069:0:dcVoltage']! + (_rng.nextDouble() - 0.5) * 0.2;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
