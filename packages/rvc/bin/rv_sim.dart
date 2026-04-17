// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// bin/rv_sim.dart — RV-C traffic simulator for vcan.
//
// Spawns virtual RV-C devices on a vcan interface. Each device is an RvcEcu
// instance that claims an address, broadcasts status DGNs at realistic rates,
// and responds to command DGNs.
//
// Setup:
//   sudo modprobe vcan
//   sudo ip link add dev vcan0 type vcan
//   sudo ip link set up vcan0
//
// Run:
//   cd packages/rvc && dart run rvc:rv_sim
//   dart run rvc:rv_sim --scenario=boondocking
//   dart run rvc:rv_sim --iface=vcan1 --scenario=traveling

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rvc/rvc.dart';

// ── CLI ──────────────────────────────────────────────────────────────────────

class _Opts {
  final String iface;
  final String scenario;

  _Opts({required this.iface, required this.scenario});

  static _Opts parse(List<String> args) {
    String iface = 'vcan0';
    String scenario = 'shore_power';

    for (final a in args) {
      if (a == '--help' || a == '-h') {
        stdout.writeln('Usage: dart run rvc:rv_sim [options]\n');
        stdout.writeln('Options:');
        stdout.writeln('  --iface=<name>      CAN interface (default: vcan0)');
        stdout.writeln(
            '  --scenario=<name>   Scenario preset (default: shore_power)');
        stdout.writeln(
            '                      Options: shore_power, boondocking, traveling');
        exit(0);
      }
      final eq = a.indexOf('=');
      if (!a.startsWith('--') || eq < 0) {
        throw ArgumentError('bad arg "$a" (expected --key=value)');
      }
      final k = a.substring(2, eq);
      final v = a.substring(eq + 1);
      switch (k) {
        case 'iface':
          iface = v;
        case 'scenario':
          if (!['shore_power', 'boondocking', 'traveling'].contains(v)) {
            throw ArgumentError(
                'unknown scenario "$v" (shore_power, boondocking, traveling)');
          }
          scenario = v;
        default:
          throw ArgumentError('unknown option: --$k');
      }
    }
    return _Opts(iface: iface, scenario: scenario);
  }
}

// ── HVAC zone state ─────────────────────────────────────────────────────────

class HvacZone {
  double currentTemp; // degrees C
  double setpointHeat; // degrees C
  double setpointCool; // degrees C
  int operatingMode; // 0=off, 1=cool, 2=heat, 3=auto, 4=fanOnly
  int fanMode; // 0=auto, 1=on
  int fanSpeed; // 0=auto, 1=low, 2=medium, 3=high

  HvacZone({
    required this.currentTemp,
    required this.setpointHeat,
    required this.setpointCool,
    this.operatingMode = 0,
    this.fanMode = 0,
    this.fanSpeed = 0,
  });
}

// ── Lighting zone state ──────────────────────────────────────────────────────

class LightZone {
  double brightness; // 0-100 %
  bool on;

  LightZone({required this.brightness, required this.on});
}

// ── Simulated RV state ──────────────────────────────────────────────────────

class _SimState {
  // Battery.
  double batteryVoltage = 12.6; // V
  double batteryCurrent = 0; // A (positive = charging)
  double batterySoc = 50; // %
  double batteryTemp = 25; // degrees C
  double batterySoh = 95; // %
  double batteryCapacity = 200; // Ah

  // Tanks (0-100%).
  double freshWater = 50;
  double grayWater = 20;
  double blackWater = 10;
  double propane = 50;

  // Tank capacities in liters.
  static const double freshWaterCapacity = 300;
  static const double grayWaterCapacity = 200;
  static const double blackWaterCapacity = 150;
  static const double propaneCapacity = 80;

  // HVAC.
  late List<HvacZone> hvacZones;
  double ambientTemp = 30; // degrees C

  // Lighting.
  late List<LightZone> lightZones;

  // Generator.
  bool generatorRunning = false;
  double generatorRpm = 0;
  double generatorHours = 1234.5;
  int generatorStatus = 0; // 0=stopped, 1=running

  // Charger.
  double chargeVoltage = 0;
  double chargeCurrent = 0;
  int chargerState = 0; // 0=disabled
  bool chargerEnabled = false;

  // Inverter.
  bool inverterEnabled = false;
  double inverterDcVoltage = 12.6;
  int inverterStatus = 0; // 0=disabled, 1=enabled

  // Shore power.
  bool shorePowerConnected = false;
  double shorePowerVoltage = 0;
  double shorePowerCurrent = 0;
  double shorePowerFrequency = 0;

  _SimState() {
    hvacZones = [
      HvacZone(
          currentTemp: 23,
          setpointHeat: 20,
          setpointCool: 24,
          operatingMode: 0,
          fanMode: 0,
          fanSpeed: 0),
      HvacZone(
          currentTemp: 22,
          setpointHeat: 20,
          setpointCool: 24,
          operatingMode: 0,
          fanMode: 0,
          fanSpeed: 0),
    ];
    lightZones = List.generate(6, (_) => LightZone(brightness: 0, on: false));
  }
}

// ── Scenario presets ────────────────────────────────────────────────────────

void _applyScenario(_SimState s, String scenario) {
  switch (scenario) {
    case 'shore_power':
      s.shorePowerConnected = true;
      s.shorePowerVoltage = 120;
      s.shorePowerCurrent = 30;
      s.shorePowerFrequency = 60;
      s.chargerEnabled = true;
      s.chargerState = 3; // bulkCharge
      s.chargeVoltage = 13.8;
      s.chargeCurrent = 25;
      s.batterySoc = 85;
      s.batteryVoltage = 13.8;
      s.batteryCurrent = 25;
      s.batteryTemp = 28;
      s.generatorRunning = false;
      s.generatorRpm = 0;
      s.generatorStatus = 0;
      s.inverterEnabled = false;
      s.inverterStatus = 0;
      s.inverterDcVoltage = 13.8;
      s.freshWater = 90;
      s.grayWater = 15;
      s.blackWater = 10;
      s.propane = 75;
      s.ambientTemp = 30;
      s.hvacZones[0]
        ..operatingMode = 1 // cool
        ..fanMode = 0
        ..fanSpeed = 2
        ..setpointHeat = 20
        ..setpointCool = 22.2
        ..currentTemp = 23.3;
      s.hvacZones[1]
        ..operatingMode = 0 // off
        ..currentTemp = 25;
      for (int i = 0; i < 3; i++) {
        s.lightZones[i]
          ..brightness = 80
          ..on = true;
      }
      for (int i = 3; i < 6; i++) {
        s.lightZones[i]
          ..brightness = 0
          ..on = false;
      }

    case 'boondocking':
      s.shorePowerConnected = false;
      s.shorePowerVoltage = 0;
      s.shorePowerCurrent = 0;
      s.shorePowerFrequency = 0;
      s.chargerEnabled = false;
      s.chargerState = 0; // disabled
      s.chargeVoltage = 0;
      s.chargeCurrent = 0;
      s.batterySoc = 65;
      s.batteryVoltage = 12.4;
      s.batteryCurrent = -8;
      s.batteryTemp = 26;
      s.generatorRunning = false;
      s.generatorRpm = 0;
      s.generatorStatus = 0;
      s.inverterEnabled = true;
      s.inverterStatus = 1;
      s.inverterDcVoltage = 12.4;
      s.freshWater = 50;
      s.grayWater = 30;
      s.blackWater = 20;
      s.propane = 40;
      s.ambientTemp = 32;
      s.hvacZones[0]
        ..operatingMode = 4 // fanOnly
        ..fanMode = 1
        ..fanSpeed = 2
        ..setpointHeat = 20
        ..setpointCool = 26
        ..currentTemp = 28;
      s.hvacZones[1]
        ..operatingMode = 0
        ..currentTemp = 30;
      s.lightZones[0]
        ..brightness = 40
        ..on = true;
      s.lightZones[1]
        ..brightness = 40
        ..on = true;
      for (int i = 2; i < 6; i++) {
        s.lightZones[i]
          ..brightness = 0
          ..on = false;
      }

    case 'traveling':
      s.shorePowerConnected = false;
      s.shorePowerVoltage = 0;
      s.shorePowerCurrent = 0;
      s.shorePowerFrequency = 0;
      s.generatorRunning = true;
      s.generatorRpm = 3600;
      s.generatorStatus = 1;
      s.chargerEnabled = true;
      s.chargerState = 4; // absorptionCharge
      s.chargeVoltage = 14.2;
      s.chargeCurrent = 15;
      s.batterySoc = 95;
      s.batteryVoltage = 14.2;
      s.batteryCurrent = 15;
      s.batteryTemp = 30;
      s.inverterEnabled = true;
      s.inverterStatus = 1;
      s.inverterDcVoltage = 14.2;
      s.freshWater = 70;
      s.grayWater = 25;
      s.blackWater = 15;
      s.propane = 60;
      s.ambientTemp = 28;
      s.hvacZones[0]
        ..operatingMode = 3 // auto
        ..fanMode = 0
        ..fanSpeed = 0
        ..setpointHeat = 21
        ..setpointCool = 23
        ..currentTemp = 22;
      s.hvacZones[1]
        ..operatingMode = 3 // auto
        ..fanMode = 0
        ..fanSpeed = 0
        ..setpointHeat = 21
        ..setpointCool = 23
        ..currentTemp = 23;
      for (int i = 0; i < 6; i++) {
        s.lightZones[i]
          ..brightness = 0
          ..on = false;
      }
  }
}

// ── Physics tick (called at 2 Hz) ───────────────────────────────────────────

class _SimEngine {
  final _SimState s;
  final math.Random _rng;

  _SimEngine(this.s, this._rng);

  double _noise() => (_rng.nextDouble() - 0.5) * 2;

  void tick(double dt) {
    final charging =
        s.chargerEnabled && (s.shorePowerConnected || s.generatorRunning);

    // -- Battery voltage.
    final lightsOn = s.lightZones.where((z) => z.on).length;
    final hvacLoad = s.hvacZones.where((z) => z.operatingMode != 0).length;
    final load =
        lightsOn * 0.3 + hvacLoad * 2.0 + (s.inverterEnabled ? 1.0 : 0.0);
    if (charging) {
      // Charging: voltage floats between 13.2 and 14.4.
      final target = s.chargerState == 3 ? 14.4 : 13.8;
      s.batteryVoltage +=
          (target - s.batteryVoltage) * 0.02 * dt + 0.01 * _noise() * dt;
      s.batteryCurrent = s.chargeCurrent + 0.5 * _noise() * dt;
      s.batterySoc += 0.05 * dt;
    } else {
      // Discharging.
      s.batteryVoltage -= 0.01 * load * dt + 0.005 * _noise() * dt;
      s.batteryCurrent = -(load * 2 + 1) + 0.3 * _noise() * dt;
      s.batterySoc -= 0.02 * load * dt;
    }
    s.batteryVoltage = s.batteryVoltage.clamp(10.5, 15.0);
    s.batterySoc = s.batterySoc.clamp(0, 100);
    s.batteryTemp += 0.001 * _noise() * dt;
    s.batteryTemp = s.batteryTemp.clamp(15, 50);

    // -- Inverter DC voltage tracks battery.
    if (s.inverterEnabled) {
      s.inverterDcVoltage = s.batteryVoltage + 0.01 * _noise();
    }

    // -- Charger tracks power source state.
    if (!charging) {
      s.chargeVoltage = 0;
      s.chargeCurrent = 0;
      if (!s.chargerEnabled) s.chargerState = 0;
    } else {
      s.chargeVoltage = s.batteryVoltage + 0.1 + 0.02 * _noise();
    }

    // -- Tanks.
    s.freshWater -= 0.005 * dt;
    s.grayWater += 0.003 * dt;
    s.blackWater += 0.002 * dt;
    // Propane decreases when heating.
    final heating =
        s.hvacZones.any((z) => z.operatingMode == 2 || z.operatingMode == 5);
    if (heating) {
      s.propane -= 0.01 * dt;
    } else {
      s.propane -= 0.001 * dt;
    }
    s.freshWater = s.freshWater.clamp(0, 100);
    s.grayWater = s.grayWater.clamp(0, 100);
    s.blackWater = s.blackWater.clamp(0, 100);
    s.propane = s.propane.clamp(0, 100);

    // -- HVAC: current temps drift toward setpoint or ambient.
    for (final zone in s.hvacZones) {
      switch (zone.operatingMode) {
        case 1: // cool
          if (zone.currentTemp > zone.setpointCool) {
            zone.currentTemp -= 0.05 * dt;
          }
        case 2: // heat
          if (zone.currentTemp < zone.setpointHeat) {
            zone.currentTemp += 0.05 * dt;
          }
        case 3: // auto
          if (zone.currentTemp > zone.setpointCool) {
            zone.currentTemp -= 0.05 * dt;
          } else if (zone.currentTemp < zone.setpointHeat) {
            zone.currentTemp += 0.05 * dt;
          }
        default: // off or fanOnly — drift toward ambient
          if (zone.currentTemp < s.ambientTemp) {
            zone.currentTemp += 0.01 * dt;
          } else if (zone.currentTemp > s.ambientTemp) {
            zone.currentTemp -= 0.01 * dt;
          }
      }
      zone.currentTemp += 0.005 * _noise() * dt;
    }

    // -- Generator hours.
    if (s.generatorRunning) {
      s.generatorHours += dt / 3600.0;
      s.generatorRpm = 3600 + 5 * _noise();
    }
  }
}

// ── DGN payload encoders ────────────────────────────────────────────────────

/// Encode voltage as uint16 LE with resolution 0.05 V.
int _voltageRaw(double v) => (v / 0.05).round().clamp(0, 0xFFFF);

/// Encode temperature (Celsius) as uint16 LE: (value + 273) / 0.03125.
int _tempRaw(double celsius) =>
    ((celsius + 273) / 0.03125).round().clamp(0, 0xFFFF);

/// DC Source Status 1 — instance, priority, voltage, current.
Uint8List _encodeDcSourceStatus1({
  required int instance,
  required double voltage,
  required double current,
}) {
  final data = Uint8List(8);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  // devicePriority(4) + reserved(4) = 0x0F (priority 0, reserved all 1s).
  data[1] = 0xF0;
  view.setUint16(2, _voltageRaw(voltage), Endian.little);
  // dcCurrent: resolution 0.001 A, offset -2000000.
  final currentRaw = ((current + 2000000) / 0.001).round().clamp(0, 0xFFFFFFFF);
  view.setUint32(4, currentRaw, Endian.little);
  return data;
}

/// DC Source Status 2 — instance, priority, temperature, SOC, time remaining.
Uint8List _encodeDcSourceStatus2({
  required int instance,
  required double tempCelsius,
  required double soc,
  required int timeRemainingMin,
}) {
  final data = Uint8List(8);
  data.fillRange(0, 8, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  data[1] = 0xF0;
  view.setUint16(2, _tempRaw(tempCelsius), Endian.little);
  data[4] = (soc / 0.5).round().clamp(0, 0xFA);
  view.setUint16(5, timeRemainingMin.clamp(0, 0xFFFF), Endian.little);
  data[7] = 0xFF; // reserved
  return data;
}

/// DC Source Status 3 — instance, priority, SOH, capacity.
Uint8List _encodeDcSourceStatus3({
  required int instance,
  required double soh,
  required int capacityAh,
}) {
  final data = Uint8List(8);
  data.fillRange(0, 8, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  data[1] = 0xF0;
  data[2] = (soh / 0.5).round().clamp(0, 0xFA);
  view.setUint16(3, capacityAh.clamp(0, 0xFFFF), Endian.little);
  // bytes 5-7 reserved (already 0xFF)
  return data;
}

/// Tank Status — instance, reserved, level, capacity.
Uint8List _encodeTankStatus({
  required int instance,
  required double levelPct,
  required double capacityLiters,
}) {
  final data = Uint8List(8);
  data.fillRange(0, 8, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  data[1] = 0xFF; // reserved
  view.setUint16(2, (levelPct / 0.5).round().clamp(0, 0xFFFF), Endian.little);
  view.setUint16(
      4, (capacityLiters / 0.1).round().clamp(0, 0xFFFF), Endian.little);
  // bytes 6-7 reserved (already 0xFF)
  return data;
}

/// Thermostat Status 1.
Uint8List _encodeThermostatStatus1({
  required int instance,
  required int operatingMode,
  required int fanMode,
  required int fanSpeed,
  required double setpointHeatC,
  required double setpointCoolC,
}) {
  final data = Uint8List(8);
  data.fillRange(0, 8, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  // byte 1: operatingMode(4) | fanMode(4)
  data[1] = (operatingMode & 0x0F) | ((fanMode & 0x0F) << 4);
  // byte 2: scheduleMode(4) | fanSpeed(4)
  data[2] = 0x00 | ((fanSpeed & 0x0F) << 4); // scheduleMode = 0 (disabled)
  view.setUint16(3, _tempRaw(setpointHeatC), Endian.little);
  view.setUint16(5, _tempRaw(setpointCoolC), Endian.little);
  data[7] = 0xFF; // reserved
  return data;
}

/// DC Dimmer Status 3.
Uint8List _encodeDcDimmerStatus3({
  required int instance,
  required int group,
  required double brightness,
  required bool on,
}) {
  final data = Uint8List(8);
  data.fillRange(0, 8, 0xFF);
  data[0] = instance & 0xFF;
  data[1] = group & 0xFF;
  data[2] = (brightness / 0.5).round().clamp(0, 200);
  // enable: 2 bits at bit 24. 0=off, 1=on.
  // delayDuration: 6 bits at bit 26.
  data[3] = (on ? 1 : 0) | (0x00 << 2); // enable | delayDuration=0
  // bytes 4-7 reserved (already 0xFF)
  return data;
}

/// Generator Status 1.
Uint8List _encodeGeneratorStatus1({
  required int instance,
  required int operatingStatus,
  required double rpm,
  required double hours,
}) {
  final data = Uint8List(8);
  data.fillRange(0, 8, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  // byte 1: operatingStatus(4) | reserved(4)
  data[1] = (operatingStatus & 0x0F) | 0xF0;
  view.setUint16(2, (rpm / 0.125).round().clamp(0, 0xFFFF), Endian.little);
  view.setUint32(4, (hours / 0.05).round().clamp(0, 0xFFFFFFFF), Endian.little);
  return data;
}

/// Charger Status.
Uint8List _encodeChargerStatus({
  required int instance,
  required double chargeVoltage,
  required double chargeCurrent,
  required int operatingState,
}) {
  final data = Uint8List(8);
  data.fillRange(0, 8, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  view.setUint16(
      1, (chargeVoltage / 0.05).round().clamp(0, 0xFFFF), Endian.little);
  // chargeCurrent: resolution 0.05, offset -1600.
  view.setUint16(3, ((chargeCurrent + 1600) / 0.05).round().clamp(0, 0xFFFF),
      Endian.little);
  data[5] = 0xFF; // chargePercentCurrent (NA)
  // byte 6: operatingState(4) | defaultState(2) | autoRechargeEnable(2)
  data[6] = (operatingState & 0x0F) | (0x01 << 4) | (0x01 << 6);
  data[7] = 0xFF; // forceCharge + reserved
  return data;
}

/// Inverter Status.
Uint8List _encodeInverterStatus({
  required int instance,
  required int operatingStatus,
  required bool enabled,
  required double dcVoltage,
}) {
  final data = Uint8List(8);
  data.fillRange(0, 8, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  // byte 1: operatingStatus(4) | inverterEnable(2) | reserved(2)
  data[1] = (operatingStatus & 0x0F) |
      ((enabled ? 1 : 0) << 4) |
      (0x03 << 6); // reserved bits = 1
  view.setUint16(2, _voltageRaw(dcVoltage), Endian.little);
  // bytes 4-7 reserved (already 0xFF)
  return data;
}

// ── Virtual device descriptor ───────────────────────────────────────────────

class _DeviceSpec {
  final String name;
  final int address;
  final int identityNumber;
  final int deviceFunction;

  const _DeviceSpec({
    required this.name,
    required this.address,
    required this.identityNumber,
    required this.deviceFunction,
  });
}

const _devices = [
  _DeviceSpec(
    name: 'Battery BMS',
    address: 0x20,
    identityNumber: 2001,
    deviceFunction: 34,
  ),
  _DeviceSpec(
    name: 'Tank Sensors',
    address: 0x30,
    identityNumber: 2002,
    deviceFunction: 38,
  ),
  _DeviceSpec(
    name: 'Thermostat',
    address: 0x40,
    identityNumber: 2003,
    deviceFunction: 20,
  ),
  _DeviceSpec(
    name: 'Lighting',
    address: 0x50,
    identityNumber: 2004,
    deviceFunction: 40,
  ),
  _DeviceSpec(
    name: 'Generator',
    address: 0x60,
    identityNumber: 2005,
    deviceFunction: 30,
  ),
  _DeviceSpec(
    name: 'Charger/Inverter',
    address: 0x70,
    identityNumber: 2006,
    deviceFunction: 32,
  ),
];

// ── main ────────────────────────────────────────────────────────────────────

Future<void> main(List<String> argv) async {
  final _Opts opts;
  try {
    opts = _Opts.parse(argv);
  } on ArgumentError catch (e) {
    stderr.writeln('rv_sim: ${e.message}');
    stderr.writeln(
        'usage: dart run rvc:rv_sim [--iface=vcan0] [--scenario=shore_power]');
    exit(64);
  }

  final state = _SimState();
  _applyScenario(state, opts.scenario);
  final rng = math.Random(opts.scenario.hashCode);
  final engine = _SimEngine(state, rng);

  // Shutdown plumbing.
  final shutdown = Completer<void>();
  void requestShutdown() {
    if (!shutdown.isCompleted) shutdown.complete();
  }

  unawaited(ProcessSignal.sigint.watch().first.then((_) => requestShutdown()));
  unawaited(ProcessSignal.sigterm.watch().first.then((_) => requestShutdown()));

  // -- Startup banner.
  stdout.writeln('');
  stdout.writeln('=== RV-C Traffic Simulator ===');
  stdout.writeln('  Interface: ${opts.iface}');
  stdout.writeln('  Scenario:  ${opts.scenario}');
  stdout.writeln('');
  stdout.writeln('Spawning virtual devices...');

  // -- Create ECUs sequentially.
  final ecus = <RvcEcu>[];
  final ecuNames = <String>[];

  for (final spec in _devices) {
    try {
      final ecu = await RvcEcu.create(
        ifname: opts.iface,
        address: spec.address,
        identityNumber: spec.identityNumber,
        deviceFunction: spec.deviceFunction,
      );
      ecus.add(ecu);
      ecuNames.add(spec.name);
      final sa = ecu.address.toRadixString(16).padLeft(2, '0').toUpperCase();
      stdout.writeln('  [OK] ${spec.name.padRight(20)} addr=0x$sa');
    } catch (e) {
      stderr.writeln('  [FAIL] ${spec.name.padRight(20)} $e');
    }
    // Short delay between creates to avoid bus contention during claims.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  if (ecus.isEmpty) {
    stderr.writeln('\nNo devices created. Exiting.');
    exit(1);
  }

  stdout.writeln('');
  stdout.writeln('${ecus.length}/${_devices.length} devices active. '
      'Transmitting... (Ctrl-C to stop)');
  stdout.writeln('');

  // Map ECU names to their RvcEcu for easy lookup.
  RvcEcu? findEcu(String name) {
    final idx = ecuNames.indexOf(name);
    return idx >= 0 ? ecus[idx] : null;
  }

  // Helper: safe send that ignores errors on disposed ECU.
  Future<void> safeSend(RvcEcu? ecu, int dgn,
      {required int priority, required Uint8List data}) async {
    if (ecu == null) return;
    try {
      await ecu.sendCommand(dgn,
          priority: priority, dest: kBroadcast, data: data);
    } catch (_) {}
  }

  // -- Command listeners (subscriptions to cancel on shutdown).
  final subs = <StreamSubscription<dynamic>>[];

  // Thermostat: listen for Thermostat Command 1 (0x1FEF9).
  final thermostat = findEcu('Thermostat');
  if (thermostat != null) {
    subs.add(thermostat.framesForDgn(0x1FEF9).listen((frame) {
      final d = frame.data;
      if (d.length < 7) return;
      final instance = d[0];
      if (instance >= state.hvacZones.length) return;
      final zone = state.hvacZones[instance];
      final opMode = d[1] & 0x0F;
      final fMode = (d[1] >> 4) & 0x0F;
      final fSpeed = (d[2] >> 4) & 0x0F;
      zone.operatingMode = opMode;
      zone.fanMode = fMode;
      zone.fanSpeed = fSpeed;
      final view = ByteData.sublistView(d);
      final heatRaw = view.getUint16(3, Endian.little);
      final coolRaw = view.getUint16(5, Endian.little);
      if (heatRaw != 0xFFFF) {
        zone.setpointHeat = heatRaw * 0.03125 - 273;
      }
      if (coolRaw != 0xFFFF) {
        zone.setpointCool = coolRaw * 0.03125 - 273;
      }
    }));
  }

  // Lighting: listen for DC Dimmer Command 2 (0x1FEDB).
  final lighting = findEcu('Lighting');
  if (lighting != null) {
    subs.add(lighting.framesForDgn(0x1FEDB).listen((frame) {
      final d = frame.data;
      if (d.length < 4) return;
      final instance = d[0];
      if (instance >= state.lightZones.length) return;
      final zone = state.lightZones[instance];
      final brightnessRaw = d[2];
      final cmd = d[3] & 0x03;
      if (brightnessRaw != 0xFF) {
        zone.brightness = (brightnessRaw * 0.5).clamp(0, 100);
      }
      switch (cmd) {
        case 0: // off
          zone.on = false;
        case 1: // on
          zone.on = true;
        case 2: // toggle
          zone.on = !zone.on;
      }
    }));
  }

  // Generator: listen for Generator Command (0x1FE97).
  final generator = findEcu('Generator');
  if (generator != null) {
    subs.add(generator.framesForDgn(0x1FE97).listen((frame) {
      final d = frame.data;
      if (d.length < 2) return;
      final cmd = (d[1]) & 0x0F;
      switch (cmd) {
        case 0: // stop
        case 2: // emergency stop
          state.generatorRunning = false;
          state.generatorRpm = 0;
          state.generatorStatus = 0;
          // If charger was running off generator, disable.
          if (!state.shorePowerConnected) {
            state.chargerState = state.chargerEnabled ? 1 : 0;
            state.chargeCurrent = 0;
            state.chargeVoltage = 0;
          }
        case 1: // start
          state.generatorRunning = true;
          state.generatorRpm = 3600;
          state.generatorStatus = 1;
          // If charger is enabled, start charging.
          if (state.chargerEnabled) {
            state.chargerState = 3; // bulk
            state.chargeCurrent = 20;
            state.chargeVoltage = state.batteryVoltage + 0.5;
          }
      }
    }));
  }

  // Charger/Inverter: listen for Charger Command (0x1FEA0).
  final chargerInv = findEcu('Charger/Inverter');
  if (chargerInv != null) {
    subs.add(chargerInv.framesForDgn(0x1FEA0).listen((frame) {
      final d = frame.data;
      if (d.length < 3) return;
      // chargeEnable at bits 12-13 of the payload (byte 1 bits 4-5).
      final enableBits = (d[1] >> 4) & 0x03;
      switch (enableBits) {
        case 0: // disable
          state.chargerEnabled = false;
          state.chargerState = 0;
          state.chargeCurrent = 0;
          state.chargeVoltage = 0;
        case 1: // enable
          state.chargerEnabled = true;
          if (state.shorePowerConnected || state.generatorRunning) {
            state.chargerState = 3; // bulk
            state.chargeCurrent = 25;
            state.chargeVoltage = state.batteryVoltage + 0.5;
          } else {
            state.chargerState = 1; // enabled but no source
          }
      }
    }));

    // Inverter Command (0x1FE9D).
    subs.add(chargerInv.framesForDgn(0x1FE9D).listen((frame) {
      final d = frame.data;
      if (d.length < 2) return;
      final enableBits = (d[1]) & 0x03;
      switch (enableBits) {
        case 0: // disable
          state.inverterEnabled = false;
          state.inverterStatus = 0;
        case 1: // enable
          state.inverterEnabled = true;
          state.inverterStatus = 1;
      }
    }));
  }

  // -- Tick counter for rate division (base tick = 2 Hz).
  var tickCount = 0;
  // Tank instance cycling counter for 0.5 Hz across 4 instances.
  var tankInstance = 0;

  // -- 2 Hz simulation + transmission tick.
  subs.add(
    Stream<void>.periodic(const Duration(milliseconds: 500)).listen((_) async {
      if (shutdown.isCompleted) return;
      tickCount++;

      // Update physics.
      engine.tick(0.5);

      final bms = findEcu('Battery BMS');
      final tanks = findEcu('Tank Sensors');
      final therm = findEcu('Thermostat');
      final light = findEcu('Lighting');
      final gen = findEcu('Generator');
      final chgInv = findEcu('Charger/Inverter');

      // Battery BMS: DC Source Status 1 at 1 Hz (every 2 ticks).
      if (tickCount % 2 == 0) {
        await safeSend(bms, 0x1FFFD,
            priority: 6,
            data: _encodeDcSourceStatus1(
              instance: 0,
              voltage: state.batteryVoltage,
              current: state.batteryCurrent,
            ));
      }

      // Battery BMS: DC Source Status 2 at 0.5 Hz (every 4 ticks).
      if (tickCount % 4 == 0) {
        final timeRemaining = state.batterySoc > 5
            ? (state.batterySoc /
                    100 *
                    state.batteryCapacity /
                    (state.batteryCurrent.abs().clamp(0.1, 1000)) *
                    60)
                .round()
            : 0;
        await safeSend(bms, 0x1FFFC,
            priority: 6,
            data: _encodeDcSourceStatus2(
              instance: 0,
              tempCelsius: state.batteryTemp,
              soc: state.batterySoc,
              timeRemainingMin: timeRemaining,
            ));
      }

      // Battery BMS: DC Source Status 3 at 0.2 Hz (every 10 ticks).
      if (tickCount % 10 == 0) {
        await safeSend(bms, 0x1FFFB,
            priority: 6,
            data: _encodeDcSourceStatus3(
              instance: 0,
              soh: state.batterySoh,
              capacityAh: state.batteryCapacity.round(),
            ));
      }

      // Tank Sensors: Tank Status at 0.5 Hz — cycle through 4 instances.
      if (tickCount % 4 == 0) {
        final levels = [
          state.freshWater,
          state.blackWater,
          state.grayWater,
          state.propane,
        ];
        final capacities = [
          _SimState.freshWaterCapacity,
          _SimState.blackWaterCapacity,
          _SimState.grayWaterCapacity,
          _SimState.propaneCapacity,
        ];
        await safeSend(tanks, 0x1FFB7,
            priority: 6,
            data: _encodeTankStatus(
              instance: tankInstance,
              levelPct: levels[tankInstance],
              capacityLiters: capacities[tankInstance],
            ));
        tankInstance = (tankInstance + 1) % 4;
      }

      // Thermostat: Thermostat Status 1 at 1 Hz (every 2 ticks) — 2 zones.
      if (tickCount % 2 == 0) {
        for (int i = 0; i < state.hvacZones.length; i++) {
          final zone = state.hvacZones[i];
          await safeSend(therm, 0x1FFE2,
              priority: 6,
              data: _encodeThermostatStatus1(
                instance: i,
                operatingMode: zone.operatingMode,
                fanMode: zone.fanMode,
                fanSpeed: zone.fanSpeed,
                setpointHeatC: zone.setpointHeat,
                setpointCoolC: zone.setpointCool,
              ));
        }
      }

      // Lighting: DC Dimmer Status 3 at 0.5 Hz (every 4 ticks) — 6 zones.
      if (tickCount % 4 == 0) {
        for (int i = 0; i < state.lightZones.length; i++) {
          final zone = state.lightZones[i];
          await safeSend(light, 0x1FEDE,
              priority: 6,
              data: _encodeDcDimmerStatus3(
                instance: i,
                group: 0,
                brightness: zone.brightness,
                on: zone.on,
              ));
        }
      }

      // Generator: Generator Status 1 at 1 Hz (every 2 ticks).
      if (tickCount % 2 == 0) {
        await safeSend(gen, 0x1FFDC,
            priority: 6,
            data: _encodeGeneratorStatus1(
              instance: 0,
              operatingStatus: state.generatorStatus,
              rpm: state.generatorRpm,
              hours: state.generatorHours,
            ));
      }

      // Charger: Charger Status at 1 Hz (every 2 ticks).
      if (tickCount % 2 == 0) {
        await safeSend(chgInv, 0x1FFC7,
            priority: 6,
            data: _encodeChargerStatus(
              instance: 0,
              chargeVoltage: state.chargeVoltage,
              chargeCurrent: state.chargeCurrent,
              operatingState: state.chargerState,
            ));
      }

      // Inverter: Inverter Status at 1 Hz (every 2 ticks).
      if (tickCount % 2 == 0) {
        await safeSend(chgInv, 0x1FFC4,
            priority: 6,
            data: _encodeInverterStatus(
              instance: 0,
              operatingStatus: state.inverterStatus,
              enabled: state.inverterEnabled,
              dcVoltage: state.inverterDcVoltage,
            ));
      }
    }),
  );

  // -- Stats print every 5 seconds.
  subs.add(
    Stream<void>.periodic(const Duration(seconds: 5)).listen((_) {
      if (shutdown.isCompleted) return;
      final vStr = state.batteryVoltage.toStringAsFixed(1);
      final socStr = state.batterySoc.toStringAsFixed(1);
      final freshStr = state.freshWater.toStringAsFixed(0);
      final grayStr = state.grayWater.toStringAsFixed(0);
      final blackStr = state.blackWater.toStringAsFixed(0);
      final propStr = state.propane.toStringAsFixed(0);
      final z0Temp = state.hvacZones[0].currentTemp.toStringAsFixed(1);
      final z1Temp = state.hvacZones[1].currentTemp.toStringAsFixed(1);
      final genStr = state.generatorRunning
          ? 'RUN@${state.generatorRpm.toStringAsFixed(0)}'
          : 'OFF';
      final chgStr = _chargerStateLabel(state.chargerState);
      final invStr = state.inverterEnabled ? 'ON' : 'OFF';
      stdout.writeln('BATT=${vStr}V/$socStr% '
          'TANKS:FW=$freshStr GW=$grayStr BW=$blackStr LP=$propStr '
          'HVAC:${z0Temp}C/${z1Temp}C '
          'GEN=$genStr CHG=$chgStr INV=$invStr');
    }),
  );

  // -- Wait for shutdown.
  await shutdown.future;

  stdout.writeln('\nShutting down...');
  for (final s in subs) {
    await s.cancel();
  }
  for (final ecu in ecus) {
    ecu.dispose();
  }
  stdout.writeln('All devices stopped.');
}

String _chargerStateLabel(int state) {
  switch (state) {
    case 0:
      return 'disabled';
    case 1:
      return 'enabled';
    case 2:
      return 'fault';
    case 3:
      return 'bulk';
    case 4:
      return 'absorption';
    case 5:
      return 'float';
    case 6:
      return 'equalize';
    default:
      return 'unknown';
  }
}
