// Service layer between NMEA 2000 bus and the Flutter instrument display.
//
// A single ChangeNotifier that owns the Nmea2000Ecu and BusRegistry,
// subscribes to incoming frames, decodes them through the PGN registry,
// and exposes the latest signal values to widgets via [signal].
//
// Two connection modes:
//   * connect(iface) — opens a real CAN interface through Nmea2000Ecu
//   * connectDemo()  — runs an in-process simulator with synthetic data

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nmea2000/nmea2000.dart';
import 'package:nmea2000_bus/nmea2000_bus.dart';

/// Connection state for the top-level status indicator.
enum N2kConnectionState { disconnected, connecting, connected, error }

/// Service that owns the [Nmea2000Ecu] and [BusRegistry], decodes incoming
/// frames, and exposes the latest field values by name.
class N2kService extends ChangeNotifier {
  N2kService();

  Nmea2000Ecu? _ecu;
  BusRegistry? _registry;
  StreamSubscription<FrameReceived>? _frameSub;
  StreamSubscription<BusEvent>? _busSub;
  Timer? _demoTimer;

  N2kConnectionState _state = N2kConnectionState.disconnected;
  String? _errorMessage;
  bool _demoMode = false;

  // Latest decoded values keyed by field name (e.g., "latitude", "windSpeed").
  // Values are in raw NMEA 2000 units — conversion happens at display time.
  final Map<String, double> _values = {};

  // Bus devices tracked by BusRegistry.
  final Map<int, DeviceInfo> _devices = {};
  int _rxFrameCount = 0;

  // ── Getters ──

  N2kConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isDemoMode => _demoMode;
  bool get isConnected => _state == N2kConnectionState.connected;
  Map<int, DeviceInfo> get devices => Map.unmodifiable(_devices);
  int get rxFrameCount => _rxFrameCount;

  /// Get a decoded signal value by field name, or null if not yet received.
  double? signal(String name) => _values[name];

  // ── Lifecycle ──

  /// Connect to a CAN interface (e.g. "vcan0").
  Future<bool> connect(String iface) async {
    if (_state == N2kConnectionState.connected) return true;

    _state = N2kConnectionState.connecting;
    _errorMessage = null;
    _demoMode = false;
    notifyListeners();

    try {
      _ecu = await Nmea2000Ecu.create(
        ifname: iface,
        modelId: 'Instrument Display',
        softwareVersion: '0.1.0',
      );

      _registry = BusRegistry(_ecu!);
      _busSub = _registry!.events.listen(_onBusEvent);
      _frameSub = _ecu!.frames.listen(_onFrame);

      _state = N2kConnectionState.connected;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _ecu?.dispose();
      _ecu = null;
      _registry?.dispose();
      _registry = null;
      _state = N2kConnectionState.error;
      notifyListeners();
      return false;
    }
  }

  /// Run with synthetic data — no CAN interface required.
  void connectDemo() {
    if (_state == N2kConnectionState.connected) return;

    _demoMode = true;
    _state = N2kConnectionState.connected;
    _errorMessage = null;
    _values.clear();
    _devices.clear();
    _rxFrameCount = 0;
    _simTicks = 0;
    _demoTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
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
    _state = N2kConnectionState.disconnected;
    _demoMode = false;
    notifyListeners();
  }

  // ── Frame handling ──

  void _onFrame(FrameReceived frame) {
    _rxFrameCount++;
    final registry = _ecu?.registry;
    if (registry == null) return;

    final def = registry.lookup(frame.pgn);
    if (def == null) return;

    final decoded = decode(frame.data, def);
    if (decoded == null) return;

    var changed = false;
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is double) {
        _values[entry.key] = value;
        changed = true;
      } else if (value is int) {
        _values[entry.key] = value.toDouble();
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void _onBusEvent(BusEvent event) {
    switch (event) {
      case DeviceAppeared(:final device):
        _devices[device.address] = device;
      case DeviceDisappeared(:final address):
        _devices.remove(address);
      case DeviceInfoUpdated(:final device):
        _devices[device.address] = device;
      case DeviceWentOffline(:final address):
        final d = _devices[address];
        if (d != null) d.status = DeviceStatus.offline;
      case DeviceCameOnline(:final device):
        _devices[device.address] = device;
      case ClaimConflict():
        break;
    }
    notifyListeners();
  }

  // ── Demo simulation ──

  final Random _rng = Random();
  int _simTicks = 0;

  void _simulateTick() {
    _simTicks++;
    _rxFrameCount += 8; // simulate traffic

    final t = _simTicks * 0.1; // time in seconds

    // Navigation — position near Seattle
    _values['latitude'] = 47.6062 + sin(t * 0.01) * 0.001;
    _values['longitude'] = -122.3321 + cos(t * 0.008) * 0.001;
    _values['cog'] = (pi + sin(t * 0.005) * 0.4) % (2 * pi); // radians
    _values['sog'] = 3.5 + sin(t * 0.02) * 1.5; // m/s
    _values['secondsSinceMidnight'] =
        (43200.0 + _simTicks * 0.1) % 86400.0; // seconds

    // Wind
    _values['windSpeed'] = 6.0 + sin(t * 0.03) * 3.0; // m/s
    _values['windAngle'] = (0.785 + sin(t * 0.015) * 0.5) % (2 * pi); // radians
    _values['reference'] = 2; // apparent

    // Depth / speed
    _values['depth'] = 12.5 + sin(t * 0.007) * 3.0; // meters
    _values['speedWaterRef'] = 3.2 + sin(t * 0.025) * 1.2; // m/s

    // Engine
    _values['engineSpeed'] = 2200 + sin(t * 0.04) * 400; // RPM (already scaled)
    _values['oilPressure'] = 350000 + sin(t * 0.012) * 50000; // Pa
    _values['temperature'] = 358.15 + sin(t * 0.008) * 5; // K (coolant)
    _values['fuelRate'] = 0.012 + sin(t * 0.015) * 0.003; // m^3/h
    _values['totalEngineHours'] = 1250.0 * 3600; // seconds
    _values['transmissionGear'] = 0; // forward

    // Electrical
    _values['batteryVoltage'] = 12.8 + sin(t * 0.01) * 0.3; // V
    _values['batteryCurrent'] = -5.0 + sin(t * 0.02) * 8.0; // A
    _values['level'] = 72.0 + sin(t * 0.005) * 5.0; // %

    // Heading
    _values['heading'] = (pi + sin(t * 0.005) * 0.4) % (2 * pi); // radians
    _values['rate'] = sin(t * 0.03) * 0.01; // rad/s
    _values['position'] = sin(t * 0.02) * 0.15; // radians (rudder)

    // Jitter a value occasionally for realism
    if (_simTicks % 30 == 0) {
      _values['windSpeed'] =
          _values['windSpeed']! + (_rng.nextDouble() - 0.5) * 2.0;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
