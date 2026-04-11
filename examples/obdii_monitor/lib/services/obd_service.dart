import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:can_engine/can_engine.dart';

import '../models/obd_pid.dart';

/// OBD-II service modes.
class ObdMode {
  static const int showCurrentData = 0x01;
  static const int showFreezeFrame = 0x02;
  static const int showStoredDtc = 0x03;
  static const int clearDtc = 0x04;
  static const int showPendingDtc = 0x07;
  static const int vehicleInfo = 0x09;
}

/// Live PID value.
class PidValue {
  final ObdPid pid;
  final double value;
  final DateTime timestamp;

  PidValue({required this.pid, required this.value, required this.timestamp});
}

/// Connection state.
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// OBD-II service layer.
///
/// Manages the connection to a CAN interface and provides high-level
/// OBD-II operations: PID polling, DTC read/clear, VIN request.
///
/// Call [connectDemo] for simulation mode — generates realistic fake
/// data without requiring a CAN interface.
class ObdService {
  CanEngine? _engine;
  ConnectionState _state = ConnectionState.disconnected;
  String? _errorMessage;
  Timer? _pollTimer;
  bool _demoMode = false;

  // Live PID values
  final Map<int, PidValue> _pidValues = {};
  final _pidController = StreamController<Map<int, PidValue>>.broadcast();

  // PIDs to poll
  List<int> _activePids = [0x0C, 0x0D, 0x05, 0x04, 0x11, 0x2F];

  // Simulation state
  final _rng = Random();
  double _simRpm = 800;
  double _simSpeed = 0;
  double _simCoolant = 20;
  double _simLoad = 15;
  double _simThrottle = 0;
  double _simFuel = 75;
  double _simIntakeTemp = 25;
  double _simMaf = 2.5;
  double _simTimingAdv = 10;
  double _simBarometric = 101;
  double _simOilTemp = 20;
  double _simRuntime = 0;
  _DrivingPhase _simPhase = _DrivingPhase.idle;
  double _simPhaseTime = 0;

  // State
  ConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isDemoMode => _demoMode;
  Stream<Map<int, PidValue>> get pidStream => _pidController.stream;
  Map<int, PidValue> get currentValues => Map.unmodifiable(_pidValues);

  /// The active PIDs being polled.
  List<int> get activePids => List.unmodifiable(_activePids);
  set activePids(List<int> pids) {
    _activePids = List.of(pids);
  }

  /// Connect to a CAN interface.
  Future<bool> connect(String interface_) async {
    if (_state == ConnectionState.connected) return true;

    _state = ConnectionState.connecting;
    _errorMessage = null;
    _demoMode = false;

    try {
      _engine = CanEngine();
      final result = _engine!.start(interface_);
      if (result < 0) {
        _state = ConnectionState.error;
        _errorMessage = 'Failed to start engine: ${_engine!.lastError}';
        _engine!.dispose();
        _engine = null;
        return false;
      }

      // Open ISO-TP channel for multi-frame OBD-II (DTC, VIN)
      final isotpResult = _engine!.isotpOpen(txId: 0x7E0, rxId: 0x7E8);
      if (isotpResult < 0) {
        // Non-fatal — ISO-TP may not be available (missing kernel module)
        // Single-frame PID polling still works via raw CAN
      }

      _state = ConnectionState.connected;
      _startPolling();
      return true;
    } catch (e) {
      _state = ConnectionState.error;
      _errorMessage = e.toString();
      _engine?.dispose();
      _engine = null;
      return false;
    }
  }

  /// Start demo/simulation mode — no CAN interface needed.
  void connectDemo() {
    if (_state == ConnectionState.connected) return;

    _demoMode = true;
    _state = ConnectionState.connected;
    _errorMessage = null;

    // Reset simulation state
    _simRpm = 800;
    _simSpeed = 0;
    _simCoolant = 20;
    _simLoad = 15;
    _simThrottle = 0;
    _simFuel = 75;
    _simIntakeTemp = 25;
    _simMaf = 2.5;
    _simTimingAdv = 10;
    _simBarometric = 101;
    _simOilTemp = 20;
    _simRuntime = 0;
    _simPhase = _DrivingPhase.warmup;
    _simPhaseTime = 0;

    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _simulateTick();
    });
  }

  /// Disconnect from the CAN interface or stop demo mode.
  void disconnect() {
    _stopPolling();
    if (!_demoMode) {
      _engine?.isotpClose();
      _engine?.stop();
      _engine?.dispose();
      _engine = null;
    }
    _state = ConnectionState.disconnected;
    _demoMode = false;
    _pidValues.clear();
  }

  /// Request a single PID value.
  void requestPid(int pid) {
    if (_engine == null || _state != ConnectionState.connected) return;

    final data = Uint8List(8);
    data[0] = 0x02;
    data[1] = ObdMode.showCurrentData;
    data[2] = pid;
    _engine!.sendFrame(0x7DF, data);
  }

  /// Read DTC codes via ISO-TP (Mode 03).
  ///
  /// Returns a list of DTC code strings (e.g., ["P0300", "P0420"]).
  /// Uses ISO-TP for multi-frame responses — a vehicle with many DTCs
  /// can return more data than fits in a single CAN frame.
  Future<List<String>> requestDtcRead() async {
    if (_demoMode) {
      return ['P0300', 'P0420']; // Demo DTCs
    }
    if (_engine == null) return [];

    // ISO-TP request: Mode 03 (show stored DTCs)
    final result = _engine!.isotpSend(Uint8List.fromList([ObdMode.showStoredDtc]));
    if (result < 0) return [];

    // Receive reassembled response
    final response = _engine!.isotpRecv(timeoutMs: 2000);
    if (response.isEmpty) return [];

    // Parse: response[0] = 0x43 (positive response), response[1] = DTC count
    // Then pairs of bytes: [high, low] per DTC
    if (response[0] != ObdMode.showStoredDtc + 0x40) return [];

    final dtcCount = response[1];
    final dtcs = <String>[];
    for (var i = 0; i < dtcCount && (2 + i * 2 + 1) < response.length; i++) {
      final byte0 = response[2 + i * 2];
      final byte1 = response[2 + i * 2 + 1];
      if (byte0 == 0 && byte1 == 0) continue; // padding
      dtcs.add(decodeDtc(byte0, byte1));
    }
    return dtcs;
  }

  /// Clear DTC codes via ISO-TP (Mode 04).
  ///
  /// Returns true if the ECU acknowledged the clear.
  Future<bool> requestDtcClear() async {
    if (_demoMode) return true;
    if (_engine == null) return false;

    final result = _engine!.isotpSend(Uint8List.fromList([ObdMode.clearDtc]));
    if (result < 0) return false;

    final response = _engine!.isotpRecv(timeoutMs: 5000);
    // Positive response = 0x44
    return response.isNotEmpty && response[0] == ObdMode.clearDtc + 0x40;
  }

  /// Request VIN via ISO-TP (Mode 09, PID 02).
  ///
  /// VIN is 17 characters and requires multi-frame ISO-TP transport.
  /// Returns the VIN string, or empty on failure.
  Future<String> requestVin() async {
    if (_demoMode) return 'WBA3A5C55CF256789'; // Demo VIN
    if (_engine == null) return '';

    final result = _engine!.isotpSend(
        Uint8List.fromList([ObdMode.vehicleInfo, 0x02]));
    if (result < 0) return '';

    final response = _engine!.isotpRecv(timeoutMs: 2000);
    if (response.isEmpty) return '';

    // Response: [0x49, 0x02, count, ...VIN bytes...]
    if (response[0] != ObdMode.vehicleInfo + 0x40) return '';
    if (response.length < 4) return '';

    // VIN starts at byte 3
    return decodeVin(response.sublist(3));
  }

  /// Process an OBD-II single-frame response from the CAN bus.
  ///
  /// Used for Mode 01 PID responses received on the raw CAN socket.
  /// Multi-frame responses (DTC, VIN) use ISO-TP instead.
  void processResponse(int canId, List<int> data) {
    if (data.length < 3) return;
    if (canId < 0x7E8 || canId > 0x7EF) return;

    final mode = data[1];
    if (mode == ObdMode.showCurrentData + 0x40) {
      final pid = data[2];
      final pidDef = obdPids[pid];
      if (pidDef != null) {
        final responseData = data.sublist(3, 3 + pidDef.bytes);
        final value = pidDef.decode(responseData);
        _pidValues[pid] = PidValue(
          pid: pidDef,
          value: value,
          timestamp: DateTime.now(),
        );
        _pidController.add(Map.of(_pidValues));
      }
    }
  }

  // ── Simulation ──

  void _simulateTick() {
    const dt = 0.05; // 50ms tick
    _simPhaseTime += dt;
    _simRuntime += dt;

    // Phase transitions — simulates a realistic driving cycle
    switch (_simPhase) {
      case _DrivingPhase.warmup:
        if (_simPhaseTime > 15) _transitionTo(_DrivingPhase.idle);
      case _DrivingPhase.idle:
        if (_simPhaseTime > 5 + _rng.nextDouble() * 5) {
          _transitionTo(_DrivingPhase.accelerating);
        }
      case _DrivingPhase.accelerating:
        if (_simSpeed > 60 + _rng.nextDouble() * 40) {
          _transitionTo(_DrivingPhase.cruising);
        }
      case _DrivingPhase.cruising:
        if (_simPhaseTime > 10 + _rng.nextDouble() * 10) {
          _transitionTo(_rng.nextBool()
              ? _DrivingPhase.decelerating
              : _DrivingPhase.accelerating);
        }
      case _DrivingPhase.decelerating:
        if (_simSpeed < 5) _transitionTo(_DrivingPhase.idle);
    }

    // Update values based on phase
    final noise = () => (_rng.nextDouble() - 0.5) * 2;

    switch (_simPhase) {
      case _DrivingPhase.warmup:
        _simRpm = _lerp(_simRpm, 900 + noise() * 50, 0.05);
        _simSpeed = 0;
        _simThrottle = _lerp(_simThrottle, 0, 0.1);
        _simLoad = _lerp(_simLoad, 18 + noise() * 3, 0.05);
        _simCoolant = _lerp(_simCoolant, 90, 0.01); // slowly warming up
      case _DrivingPhase.idle:
        _simRpm = _lerp(_simRpm, 780 + noise() * 30, 0.1);
        _simSpeed = _lerp(_simSpeed, 0, 0.2);
        _simThrottle = _lerp(_simThrottle, 0, 0.15);
        _simLoad = _lerp(_simLoad, 15 + noise() * 2, 0.1);
      case _DrivingPhase.accelerating:
        _simThrottle = _lerp(_simThrottle, 45 + noise() * 20, 0.08);
        _simRpm = _lerp(_simRpm, 2500 + _simThrottle * 40 + noise() * 100, 0.06);
        _simSpeed = _lerp(_simSpeed, _simSpeed + 0.8 + noise() * 0.1, 0.1);
        _simLoad = _lerp(_simLoad, 40 + _simThrottle * 0.8 + noise() * 5, 0.08);
      case _DrivingPhase.cruising:
        final targetRpm = 1800 + _simSpeed * 12;
        _simRpm = _lerp(_simRpm, targetRpm + noise() * 50, 0.05);
        _simSpeed = _lerp(_simSpeed, _simSpeed + noise() * 0.5, 0.02);
        _simThrottle = _lerp(_simThrottle, 15 + noise() * 5, 0.08);
        _simLoad = _lerp(_simLoad, 25 + noise() * 5, 0.05);
      case _DrivingPhase.decelerating:
        _simThrottle = _lerp(_simThrottle, 0, 0.12);
        _simRpm = _lerp(_simRpm, 1200 + noise() * 100, 0.08);
        _simSpeed = _lerp(_simSpeed, _simSpeed - 1.2, 0.1);
        _simLoad = _lerp(_simLoad, 10 + noise() * 3, 0.1);
    }

    // Derived values
    _simCoolant = _lerp(_simCoolant, 88 + _simLoad * 0.15 + noise() * 0.5, 0.005);
    _simMaf = _lerp(_simMaf, _simRpm * _simLoad / 8000 + noise() * 0.3, 0.1);
    _simTimingAdv = _lerp(_simTimingAdv, 10 + _simRpm / 500 + noise(), 0.05);
    _simIntakeTemp = _lerp(_simIntakeTemp, 30 + _simLoad * 0.1 + noise() * 0.5, 0.01);
    _simOilTemp = _lerp(_simOilTemp, _simCoolant - 5 + noise() * 0.5, 0.003);
    _simBarometric = 101 + noise() * 0.2;
    _simFuel = (_simFuel - 0.0001 * _simLoad * dt).clamp(0.0, 100.0);

    // Clamp
    _simRpm = _simRpm.clamp(0, 8000);
    _simSpeed = _simSpeed.clamp(0, 240);
    _simCoolant = _simCoolant.clamp(-40, 215);
    _simLoad = _simLoad.clamp(0, 100);
    _simThrottle = _simThrottle.clamp(0, 100);

    // Publish active PIDs
    final now = DateTime.now();
    for (final pidId in _activePids) {
      final pidDef = obdPids[pidId];
      if (pidDef == null) continue;

      final value = switch (pidId) {
        0x04 => _simLoad,
        0x05 => _simCoolant,
        0x0B => _simBarometric * 0.6 + _simLoad * 0.4, // intake MAP
        0x0C => _simRpm,
        0x0D => _simSpeed,
        0x0E => _simTimingAdv,
        0x0F => _simIntakeTemp,
        0x10 => _simMaf,
        0x11 => _simThrottle,
        0x1F => _simRuntime,
        0x2F => _simFuel,
        0x33 => _simBarometric,
        0x46 => _simIntakeTemp - 5,
        0x5C => _simOilTemp,
        _ => 0.0,
      };

      _pidValues[pidId] = PidValue(
        pid: pidDef,
        value: value.clamp(pidDef.min, pidDef.max),
        timestamp: now,
      );
    }

    _pidController.add(Map.of(_pidValues));
  }

  void _transitionTo(_DrivingPhase phase) {
    _simPhase = phase;
    _simPhaseTime = 0;
  }

  static double _lerp(double current, double target, double rate) {
    return current + (target - current) * rate;
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_activePids.isEmpty) return;
      final pidIdx = DateTime.now().millisecondsSinceEpoch ~/ 100;
      final pid = _activePids[pidIdx % _activePids.length];
      requestPid(pid);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Dispose resources.
  void dispose() {
    disconnect();
    _pidController.close();
  }
}

enum _DrivingPhase {
  warmup,
  idle,
  accelerating,
  cruising,
  decelerating,
}
