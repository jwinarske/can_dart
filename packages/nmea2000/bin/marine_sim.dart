// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// bin/marine_sim.dart — Marine traffic simulator for NMEA 2000.
//
// Spawns virtual NMEA 2000 devices on a vcan interface. Each device is an
// Nmea2000Ecu instance that claims an address, responds to mandatory PGN
// requests, and emits realistic sensor data at spec-defined rates.
//
// Setup:
//   sudo modprobe vcan
//   sudo ip link add dev vcan0 type vcan
//   sudo ip link set up vcan0
//
// Run:
//   cd packages/nmea2000 && dart run nmea2000:marine_sim
//   dart run nmea2000:marine_sim --scenario=heavy_weather
//   dart run nmea2000:marine_sim --iface=vcan1 --scenario=anchored

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:nmea2000/nmea2000.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const _deg2rad = math.pi / 180.0;
const _knotsToMs = 0.5144;

// ── CLI ──────────────────────────────────────────────────────────────────────

class _Opts {
  final String iface;
  final String scenario;

  _Opts({required this.iface, required this.scenario});

  static _Opts parse(List<String> args) {
    String iface = 'vcan0';
    String scenario = 'coastal_cruise';

    for (final a in args) {
      if (a == '--help' || a == '-h') {
        stdout.writeln('Usage: dart run nmea2000:marine_sim [options]\n');
        stdout.writeln('Options:');
        stdout.writeln('  --iface=<name>      CAN interface (default: vcan0)');
        stdout.writeln(
            '  --scenario=<name>   Scenario preset (default: coastal_cruise)');
        stdout.writeln(
            '                      Options: anchored, coastal_cruise, heavy_weather');
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
          if (!['anchored', 'coastal_cruise', 'heavy_weather'].contains(v)) {
            throw ArgumentError(
                'unknown scenario "$v" (anchored, coastal_cruise, heavy_weather)');
          }
          scenario = v;
        default:
          throw ArgumentError('unknown option: --$k');
      }
    }
    return _Opts(iface: iface, scenario: scenario);
  }
}

// ── Simulated boat state ─────────────────────────────────────────────────────

class SimState {
  // Position (degrees).
  double lat = 47.6062;
  double lon = -122.3321;

  // Navigation.
  double heading = 0; // radians
  double sog = 0; // m/s
  double stw = 0; // m/s
  double cog = 0; // radians

  // Wind.
  double windSpeedApparent = 0; // m/s
  double windAngleApparent = 0; // radians

  // Depth.
  double depth = 10; // meters

  // Engine.
  double engineRpm = 0;
  double oilPressure = 0; // Pa
  double coolantTemp = 273.15 + 80; // K
  double fuelRate = 0; // m^3/h
  double totalHours = 12345.0; // seconds
  double tiltTrim = 0; // percent

  // Transmission.
  int gear = 1; // 0=forward, 1=neutral, 2=reverse

  // Battery.
  double batteryVoltage = 12.2; // V
  double batteryCurrent = 0; // A
  double batteryTemp = 273.15 + 25; // K

  // Rudder.
  double rudderAngle = 0; // radians

  // Fuel level.
  double fuelLevel = 80; // 0-100 %

  // Magnetic variation.
  double magneticVariation = -16.0 * _deg2rad; // radians (Puget Sound ~-16 deg)

  // Rate of turn (radians/s).
  double rateOfTurn = 0;
}

// ── Scenario configuration ───────────────────────────────────────────────────

class _ScenarioCfg {
  final double rpmTarget;
  final double sogTarget; // m/s
  final double headingCenter; // radians
  final double headingNoise; // radians amplitude
  final double windSpeedMin; // m/s
  final double windSpeedMax; // m/s
  final double windAngleCenter; // radians
  final double windAngleNoise; // radians
  final double depthMin; // m
  final double depthMax; // m
  final double depthPeriod; // seconds for sinusoidal cycle
  final double batteryBase; // V
  final double fuelStart; // %
  final double rudderAmplitude; // radians
  final int gear; // 0=fwd, 1=neutral, 2=reverse

  const _ScenarioCfg({
    required this.rpmTarget,
    required this.sogTarget,
    required this.headingCenter,
    required this.headingNoise,
    required this.windSpeedMin,
    required this.windSpeedMax,
    required this.windAngleCenter,
    required this.windAngleNoise,
    required this.depthMin,
    required this.depthMax,
    required this.depthPeriod,
    required this.batteryBase,
    required this.fuelStart,
    required this.rudderAmplitude,
    required this.gear,
  });
}

const _scenarios = {
  'anchored': _ScenarioCfg(
    rpmTarget: 0,
    sogTarget: 0,
    headingCenter: 180 * _deg2rad,
    headingNoise: 0.5 * _deg2rad,
    windSpeedMin: 3,
    windSpeedMax: 5,
    windAngleCenter: 45 * _deg2rad,
    windAngleNoise: 5 * _deg2rad,
    depthMin: 9.7,
    depthMax: 10.3,
    depthPeriod: 30,
    batteryBase: 12.2,
    fuelStart: 80,
    rudderAmplitude: 0,
    gear: 1,
  ),
  'coastal_cruise': _ScenarioCfg(
    rpmTarget: 2500,
    sogTarget: 4.1,
    headingCenter: 135 * _deg2rad,
    headingNoise: 2 * _deg2rad,
    windSpeedMin: 8,
    windSpeedMax: 10,
    windAngleCenter: 60 * _deg2rad,
    windAngleNoise: 8 * _deg2rad,
    depthMin: 5,
    depthMax: 50,
    depthPeriod: 60,
    batteryBase: 14.2,
    fuelStart: 65,
    rudderAmplitude: 3 * _deg2rad,
    gear: 0,
  ),
  'heavy_weather': _ScenarioCfg(
    rpmTarget: 3000,
    sogTarget: 6.2,
    headingCenter: 90 * _deg2rad,
    headingNoise: 5 * _deg2rad,
    windSpeedMin: 13,
    windSpeedMax: 18,
    windAngleCenter: 40 * _deg2rad,
    windAngleNoise: 10 * _deg2rad,
    depthMin: 20,
    depthMax: 80,
    depthPeriod: 45,
    batteryBase: 14.4,
    fuelStart: 45,
    rudderAmplitude: 8 * _deg2rad,
    gear: 0,
  ),
};

// ── Physics update ───────────────────────────────────────────────────────────

class _SimEngine {
  final SimState state;
  final _ScenarioCfg cfg;
  final math.Random _rng;
  double _t = 0; // elapsed seconds
  double _windWalk = 0; // wind speed random walk state
  double _windAngleWalk = 0; // wind angle random walk state

  _SimEngine(this.state, this.cfg, this._rng) {
    // Initialize state from scenario.
    state.engineRpm = cfg.rpmTarget;
    state.sog = cfg.sogTarget;
    state.stw = cfg.sogTarget * 0.95;
    state.cog = cfg.headingCenter;
    state.heading = cfg.headingCenter;
    state.fuelLevel = cfg.fuelStart;
    state.gear = cfg.gear;
    state.depth = (cfg.depthMin + cfg.depthMax) / 2;
    state.batteryVoltage = cfg.batteryBase;
    state.windSpeedApparent = (cfg.windSpeedMin + cfg.windSpeedMax) / 2;
    state.windAngleApparent = cfg.windAngleCenter;
  }

  /// Gaussian random using Box-Muller.
  double _gaussian() {
    double u, v, s;
    do {
      u = _rng.nextDouble() * 2 - 1;
      v = _rng.nextDouble() * 2 - 1;
      s = u * u + v * v;
    } while (s >= 1 || s == 0);
    return u * math.sqrt(-2 * math.log(s) / s);
  }

  /// Advance simulation by [dt] seconds (called at 10 Hz, dt=0.1).
  void tick(double dt) {
    _t += dt;

    // -- Heading: slow oscillation + damped noise.
    state.heading = cfg.headingCenter +
        cfg.headingNoise * math.sin(_t * 0.3) +
        cfg.headingNoise * 0.3 * _gaussian() * dt;

    // -- Rate of turn (derivative approximation).
    final prevHeading =
        cfg.headingCenter + cfg.headingNoise * math.sin((_t - dt) * 0.3);
    state.rateOfTurn = (state.heading - prevHeading) / dt;

    // -- Rudder: slow sinusoidal.
    state.rudderAngle = cfg.rudderAmplitude * math.sin(_t * 0.2);

    // -- SOG / COG.
    state.sog = cfg.sogTarget + 0.1 * _gaussian() * dt;
    if (state.sog < 0) state.sog = 0;
    state.cog = state.heading + 0.01 * _gaussian() * dt;
    state.stw = state.sog * (0.93 + 0.04 * math.sin(_t * 0.1));

    // -- Position integration.
    final dlat = state.sog * math.cos(state.cog) * dt / 111320.0;
    final dlon = state.sog *
        math.sin(state.cog) *
        dt /
        (111320.0 * math.cos(state.lat * _deg2rad));
    state.lat += dlat;
    state.lon += dlon;

    // -- Wind: random walk with exponential decay toward center.
    final windCenter = (cfg.windSpeedMin + cfg.windSpeedMax) / 2;
    final windRange = (cfg.windSpeedMax - cfg.windSpeedMin) / 2;
    _windWalk = _windWalk * 0.99 + _gaussian() * 0.3 * dt;
    state.windSpeedApparent =
        (windCenter + windRange * _windWalk.clamp(-1.0, 1.0))
            .clamp(cfg.windSpeedMin * 0.8, cfg.windSpeedMax * 1.2);

    _windAngleWalk = _windAngleWalk * 0.99 + _gaussian() * 0.2 * dt;
    state.windAngleApparent = cfg.windAngleCenter +
        cfg.windAngleNoise * _windAngleWalk.clamp(-2.0, 2.0);

    // -- Depth: sinusoidal + noise.
    final depthCenter = (cfg.depthMin + cfg.depthMax) / 2;
    final depthRange = (cfg.depthMax - cfg.depthMin) / 2;
    state.depth = depthCenter +
        depthRange * math.sin(_t * 2 * math.pi / cfg.depthPeriod) +
        0.1 * _gaussian();
    if (state.depth < 0.5) state.depth = 0.5;

    // -- Engine coupled dynamics.
    state.engineRpm = cfg.rpmTarget + 20 * _gaussian() * dt; // small RPM jitter
    if (state.engineRpm < 0) state.engineRpm = 0;

    // Oil pressure scales with RPM: idle ~200kPa, full ~450kPa.
    state.oilPressure = cfg.rpmTarget > 0
        ? 200000 + (state.engineRpm / 4000) * 250000 + 5000 * _gaussian() * dt
        : 0;

    // Coolant temp: ~353 K (80 C) at idle, up to 365 K (92 C) at high RPM.
    state.coolantTemp =
        273.15 + 80 + (state.engineRpm / 4000) * 12 + 0.2 * _gaussian() * dt;

    // Fuel rate: proportional to RPM^1.5 (rough diesel model), in m^3/h.
    // 2500 RPM ~ 15 L/h = 0.015 m^3/h.
    state.fuelRate = cfg.rpmTarget > 0
        ? 0.015 *
            math.pow(state.engineRpm / 2500, 1.5) *
            (1 + 0.02 * _gaussian() * dt)
        : 0;
    if (state.fuelRate < 0) state.fuelRate = 0;

    state.totalHours += dt;
    state.tiltTrim = 0 + 0.5 * math.sin(_t * 0.05); // slight oscillation

    // -- Battery.
    state.batteryVoltage =
        (cfg.rpmTarget > 0 ? 12.0 + 2.2 : 12.0) + 0.05 * _gaussian() * dt;
    state.batteryCurrent = cfg.rpmTarget > 0
        ? 15 + 2 * _gaussian() * dt // charging
        : -3 + 0.5 * _gaussian() * dt; // discharging
    state.batteryTemp = 273.15 + 25 + 0.1 * _gaussian() * dt;

    // -- Fuel level: decreases proportional to fuel rate.
    // fuelRate is m^3/h; dt is seconds. Tank ~ 200L = 0.2 m^3.
    state.fuelLevel -= (state.fuelRate / 0.2) * (dt / 3600) * 100;
    if (state.fuelLevel < 0) state.fuelLevel = 0;
  }
}

// ── PGN payload encoders (raw, no PgnDefinition dependency) ──────────────────

/// PGN 129025 — Position, Rapid Update (8 bytes, single frame).
Uint8List _encodePositionRapid(double latDeg, double lonDeg) {
  final data = Uint8List(8);
  final view = ByteData.sublistView(data);
  view.setInt32(0, (latDeg * 1e7).round(), Endian.little);
  view.setInt32(4, (lonDeg * 1e7).round(), Endian.little);
  return data;
}

/// PGN 129026 — COG & SOG, Rapid Update (8 bytes, single frame).
Uint8List _encodeCogSogRapid(
    {required int sid, required double cogRad, required double sogMs}) {
  final data = Uint8List(8);
  final view = ByteData.sublistView(data);
  data[0] = sid & 0xFF;
  // COG reference + reserved: 0 = True North, bits 2-7 reserved.
  data[1] = 0x00; // True North reference
  view.setUint16(2, (cogRad * 10000).round().clamp(0, 65534), Endian.little);
  view.setUint16(4, (sogMs * 100).round().clamp(0, 65534), Endian.little);
  data[6] = 0xFF; // reserved
  data[7] = 0xFF; // reserved
  return data;
}

/// PGN 129029 — GNSS Position Data (43 bytes, fast packet).
Uint8List _encodeGnssPosition({
  required int sid,
  required double latDeg,
  required double lonDeg,
  required double altitudeM,
  required int daysSince1970,
  required double secondsSinceMidnight,
}) {
  final data = Uint8List(43);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = sid & 0xFF;
  view.setUint16(1, daysSince1970, Endian.little);
  view.setUint32(3, (secondsSinceMidnight * 10000).round(), Endian.little);
  // Latitude: 64-bit signed, resolution 1e-16 degrees.
  final latRaw = (latDeg * 1e16).round();
  view.setInt64(7, latRaw, Endian.little);
  // Longitude: 64-bit signed, resolution 1e-16 degrees.
  final lonRaw = (lonDeg * 1e16).round();
  view.setInt64(15, lonRaw, Endian.little);
  // Altitude: 64-bit signed, resolution 1e-6 m.
  view.setInt64(23, (altitudeM * 1e6).round(), Endian.little);
  // Type/method/integrity nibbles.
  data[31] = 0x15; // GPS, GNSS fix, no RAIM
  data[32] = 12; // number of SVs
  view.setInt16(33, 120, Endian.little); // HDOP * 100
  view.setInt16(35, 150, Endian.little); // PDOP * 100
  view.setInt32(37, 0, Endian.little); // geoidal separation * 100
  data[41] = 1; // number of reference stations
  data[42] = 0xFF; // reference station info (NA)
  return data;
}

/// PGN 129033 — Time & Date (8 bytes, single frame).
Uint8List _encodeTimeDate() {
  final now = DateTime.now().toUtc();
  final epoch = DateTime.utc(1970, 1, 1);
  final daysSince1970 = now.difference(epoch).inDays;
  final midnight = DateTime.utc(now.year, now.month, now.day);
  final secsSinceMidnight = now.difference(midnight).inMilliseconds / 1000.0;

  final data = Uint8List(8);
  final view = ByteData.sublistView(data);
  view.setUint16(0, daysSince1970, Endian.little);
  view.setUint32(2, (secsSinceMidnight * 10000).round(), Endian.little);
  view.setInt16(6, -480, Endian.little); // local offset in minutes (UTC-8)
  return data;
}

/// PGN 127258 — Magnetic Variation (6 bytes, single frame).
Uint8List _encodeMagneticVariation(
    {required int sid, required double variationRad}) {
  final data = Uint8List(8);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = sid & 0xFF;
  data[1] = 0x01; // source = WMM (automatic)
  // Days since epoch for variation date — use current.
  final now = DateTime.now().toUtc();
  final epoch = DateTime.utc(1970, 1, 1);
  view.setUint16(2, now.difference(epoch).inDays, Endian.little);
  view.setInt16(4, (variationRad * 10000).round(), Endian.little);
  return data;
}

/// PGN 130306 — Wind Data (6 bytes, single frame).
Uint8List _encodeWindData(
    {required int sid,
    required double speedMs,
    required double angleRad,
    int reference = 2}) {
  // reference: 2 = Apparent
  final data = Uint8List(8);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = sid & 0xFF;
  view.setUint16(1, (speedMs * 100).round().clamp(0, 65534), Endian.little);
  view.setUint16(3, (angleRad * 10000).round().clamp(0, 65534), Endian.little);
  data[5] = reference & 0x07; // wind reference (3 bits) + reserved
  return data;
}

/// PGN 128267 — Water Depth (5 bytes, single frame).
Uint8List _encodeWaterDepth(
    {required int sid, required double depthM, double offsetM = 0}) {
  final data = Uint8List(8);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = sid & 0xFF;
  view.setUint32(1, (depthM * 100).round().clamp(0, 0xFFFFFFFE), Endian.little);
  view.setInt16(5, (offsetM * 1000).round(), Endian.little);
  return data;
}

/// PGN 128259 — Speed, Water Referenced (6 bytes, single frame).
Uint8List _encodeSpeedWaterRef({required int sid, required double stwMs}) {
  final data = Uint8List(8);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = sid & 0xFF;
  view.setUint16(1, (stwMs * 100).round().clamp(0, 65534), Endian.little);
  // Bytes 3-4: STW ground ref (NA).
  // Byte 5: type (0 = paddle wheel).
  data[5] = 0x00;
  return data;
}

/// PGN 127250 — Vessel Heading (8 bytes, single frame).
Uint8List _encodeVesselHeading(
    {required int sid,
    required double headingRad,
    required double deviationRad,
    required double variationRad}) {
  final data = Uint8List(8);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = sid & 0xFF;
  view.setUint16(
      1, (headingRad * 10000).round().clamp(0, 65534), Endian.little);
  view.setInt16(3, (deviationRad * 10000).round(), Endian.little);
  view.setInt16(5, (variationRad * 10000).round(), Endian.little);
  data[7] = 0x00; // reference = magnetic
  return data;
}

/// PGN 127251 — Rate of Turn (5 bytes, single frame).
Uint8List _encodeRateOfTurn({required int sid, required double rateRadS}) {
  final data = Uint8List(8);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = sid & 0xFF;
  // Rate in 1/32 of 1e-6 rad/s.
  view.setInt32(1, (rateRadS * 32 * 1e6).round(), Endian.little);
  return data;
}

/// PGN 127488 — Engine Parameters, Rapid Update (8 bytes, single frame).
Uint8List _encodeEngineRapid(
    {required int instance, required double rpm, required double tiltTrim}) {
  final data = Uint8List(8);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  view.setUint16(
      1, (rpm * 4).round().clamp(0, 65534), Endian.little); // 0.25 RPM/bit
  data[3] = 0xFF; // boost pressure (NA)
  data[4] = 0xFF;
  view.setInt16(
      5, (tiltTrim * 100).round(), Endian.little); // 1% per bit? Use signed.
  return data;
}

/// PGN 127489 — Engine Parameters, Dynamic (26 bytes, fast packet).
Uint8List _encodeEngineDynamic({
  required int instance,
  required double oilPressurePa,
  required double oilTempK,
  required double coolantTempK,
  required double fuelRateM3h,
  required double totalHoursS,
}) {
  final data = Uint8List(26);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  view.setUint16(1, (oilPressurePa / 100).round().clamp(0, 65534),
      Endian.little); // 100 Pa/bit (hPa)
  view.setUint16(
      3,
      ((oilTempK - 273.15 + 40) * 10).round().clamp(0, 65534),
      Endian
          .little); // 0.1K, offset -40 not used; use resolution 0.1 deg with offset
  view.setUint16(5, (coolantTempK * 100).round().clamp(0, 65534),
      Endian.little); // 0.01K/bit
  // Alternator voltage at byte 7 (NA).
  // Fuel rate at byte 9: 0.1 L/h per bit = 0.0001 m^3/h per bit.
  view.setInt16(
      9, (fuelRateM3h * 10000).round().clamp(-32767, 32767), Endian.little);
  // Total engine hours at byte 11: 1s per bit.
  view.setUint32(11, totalHoursS.round().clamp(0, 0xFFFFFFFE), Endian.little);
  // Coolant pressure at byte 15 (NA).
  // Fuel pressure at byte 17 (NA).
  // Discrete status 1 at byte 19 (all zeros = OK).
  data[19] = 0x00;
  data[20] = 0x00;
  // Discrete status 2 at byte 21.
  data[21] = 0x00;
  data[22] = 0x00;
  // Percent engine load at byte 23 (NA).
  // Percent engine torque at byte 24 (NA).
  return data;
}

/// PGN 127493 — Transmission Parameters, Dynamic (8 bytes, single frame).
Uint8List _encodeTransmission(
    {required int instance, required int gear, required double oilPressurePa}) {
  final data = Uint8List(8);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  data[1] = gear & 0x03; // 2-bit gear + reserved
  view.setUint16(
      2, (oilPressurePa / 100).round().clamp(0, 65534), Endian.little);
  // Oil temp at byte 4 (NA).
  // Discrete status at byte 6.
  data[6] = 0x00;
  return data;
}

/// PGN 127508 — Battery Status (8 bytes, single frame).
Uint8List _encodeBatteryStatus({
  required int instance,
  required double voltageV,
  required double currentA,
  required double tempK,
}) {
  final data = Uint8List(8);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  view.setUint16(
      1, (voltageV * 100).round().clamp(0, 65534), Endian.little); // 0.01V/bit
  view.setInt16(3, (currentA * 10).round().clamp(-32767, 32767),
      Endian.little); // 0.1A/bit
  view.setUint16(
      5, (tempK * 100).round().clamp(0, 65534), Endian.little); // 0.01K/bit
  data[7] = 0xFF; // SID (NA)
  return data;
}

/// PGN 127245 — Rudder (8 bytes, single frame).
Uint8List _encodeRudder({required int instance, required double angleRad}) {
  final data = Uint8List(8);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  data[1] = 0xFF; // directionOrder (NA)
  view.setInt16(2, (angleRad * 10000).round(), Endian.little);
  // Bytes 4-5: angle order (NA).
  return data;
}

/// PGN 127505 — Fluid Level (8 bytes, single frame).
Uint8List _encodeFluidLevel(
    {required int instance,
    required int fluidType,
    required double levelPct,
    required double capacityL}) {
  final data = Uint8List(8);
  data.fillRange(0, data.length, 0xFF);
  final view = ByteData.sublistView(data);
  // Byte 0: instance (4 bits) + fluid type (4 bits).
  data[0] = ((fluidType & 0x0F) << 4) | (instance & 0x0F);
  view.setInt16(
      1, (levelPct * 250).round().clamp(0, 25000), Endian.little); // 0.004%/bit
  view.setUint32(3, (capacityL * 10).round().clamp(0, 0xFFFFFFFE),
      Endian.little); // 0.1L/bit
  return data;
}

// ── Virtual device descriptor ────────────────────────────────────────────────

class _DeviceSpec {
  final String name;
  final int address;
  final int identityNumber;
  final String modelId;
  final int deviceClass;
  final int deviceFunction;

  const _DeviceSpec({
    required this.name,
    required this.address,
    required this.identityNumber,
    required this.modelId,
    required this.deviceClass,
    required this.deviceFunction,
  });
}

const _devices = [
  _DeviceSpec(
    name: 'GPS Receiver',
    address: 0x20,
    identityNumber: 1001,
    modelId: 'Sim GPS',
    deviceClass: 60, // Navigation
    deviceFunction: 145, // Navigation satellite receiver
  ),
  _DeviceSpec(
    name: 'Wind Sensor',
    address: 0x30,
    identityNumber: 1002,
    modelId: 'Sim Wind',
    deviceClass: 85, // External Environment
    deviceFunction: 170, // Wind instrument
  ),
  _DeviceSpec(
    name: 'Depth Transducer',
    address: 0x40,
    identityNumber: 1003,
    modelId: 'Sim Depth/Speed',
    deviceClass: 75, // Sensor Communication Interface
    deviceFunction: 155, // Speed/depth sensor
  ),
  _DeviceSpec(
    name: 'Heading Sensor',
    address: 0x50,
    identityNumber: 1004,
    modelId: 'Sim Heading',
    deviceClass: 60, // Navigation
    deviceFunction: 140, // Heading sensor
  ),
  _DeviceSpec(
    name: 'Engine Gateway',
    address: 0x60,
    identityNumber: 1005,
    modelId: 'Sim Engine',
    deviceClass: 50, // Propulsion
    deviceFunction: 160, // Engine gateway
  ),
  _DeviceSpec(
    name: 'Battery Monitor',
    address: 0x70,
    identityNumber: 1006,
    modelId: 'Sim Battery',
    deviceClass: 35, // Electrical Generation
    deviceFunction: 170, // Battery
  ),
  _DeviceSpec(
    name: 'Rudder Sensor',
    address: 0x28,
    identityNumber: 1007,
    modelId: 'Sim Rudder',
    deviceClass: 40, // Steering and Control
    deviceFunction: 155, // Rudder
  ),
  _DeviceSpec(
    name: 'Fluid Level',
    address: 0x38,
    identityNumber: 1008,
    modelId: 'Sim Fluid',
    deviceClass: 75, // Sensor Communication Interface
    deviceFunction: 175, // Fluid level sensor
  ),
];

// ── Fast Packet PGN registration ─────────────────────────────────────────────

/// PGNs used by the sim that require fast packet transport.
const _simFastPacketPgns = [
  129029, // GNSS Position Data
  127489, // Engine Parameters, Dynamic
];

// ── main ─────────────────────────────────────────────────────────────────────

Future<void> main(List<String> argv) async {
  final _Opts opts;
  try {
    opts = _Opts.parse(argv);
  } on ArgumentError catch (e) {
    stderr.writeln('marine_sim: ${e.message}');
    stderr.writeln(
        'usage: dart run nmea2000:marine_sim [--iface=vcan0] [--scenario=coastal_cruise]');
    exit(64);
  }

  final cfg = _scenarios[opts.scenario]!;
  final state = SimState();
  final rng = math.Random(opts.scenario.hashCode);
  final engine = _SimEngine(state, cfg, rng);

  // Shutdown plumbing.
  final shutdown = Completer<void>();
  void requestShutdown() {
    if (!shutdown.isCompleted) shutdown.complete();
  }

  unawaited(ProcessSignal.sigint.watch().first.then((_) => requestShutdown()));
  unawaited(ProcessSignal.sigterm.watch().first.then((_) => requestShutdown()));

  // Register fast packet PGNs with the C++ transport layer.
  for (final pgn in _simFastPacketPgns) {
    J1939Ecu.setPgnTransport(pgn, 1); // 1 = fast_packet
  }

  // -- Startup banner.
  stdout.writeln('');
  stdout.writeln('=== NMEA 2000 Marine Traffic Simulator ===');
  stdout.writeln('  Interface: ${opts.iface}');
  stdout.writeln('  Scenario:  ${opts.scenario}');
  stdout.writeln('  Position:  ${state.lat.toStringAsFixed(4)}N, '
      '${state.lon.abs().toStringAsFixed(4)}W');
  stdout.writeln('');
  stdout.writeln('Spawning virtual devices...');

  // -- Create ECUs sequentially.
  final ecus = <Nmea2000Ecu>[];
  final ecuNames = <String>[];

  for (final spec in _devices) {
    try {
      final ecu = await Nmea2000Ecu.create(
        ifname: opts.iface,
        address: spec.address,
        identityNumber: spec.identityNumber,
        modelId: spec.modelId,
        deviceClass: spec.deviceClass,
        deviceFunction: spec.deviceFunction,
      );
      ecus.add(ecu);
      ecuNames.add(spec.name);
      final sa = ecu.address.toRadixString(16).padLeft(2, '0').toUpperCase();
      stdout.writeln(
          '  [OK] ${spec.name.padRight(18)} addr=0x$sa  ${spec.modelId}');
    } catch (e) {
      stderr.writeln('  [FAIL] ${spec.name.padRight(18)} $e');
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

  // Map ECU names to their Nmea2000Ecu for easy lookup.
  Nmea2000Ecu? findEcu(String name) {
    final idx = ecuNames.indexOf(name);
    return idx >= 0 ? ecus[idx] : null;
  }

  // -- SID counters (per-device sequence IDs).
  var sid = 0;

  // -- Tick counters for rate division (base tick = 10 Hz).
  var tickCount = 0;

  // Helper: safe send that ignores errors.
  Future<void> safeSend(Nmea2000Ecu? ecu, int pgn,
      {required int priority,
      required int dest,
      required Uint8List data}) async {
    if (ecu == null) return;
    try {
      await ecu.send(pgn, priority: priority, dest: dest, data: data);
    } catch (_) {}
  }

  // -- 10 Hz simulation + transmission tick.
  final subs = <StreamSubscription<void>>[];

  subs.add(
    Stream<void>.periodic(const Duration(milliseconds: 100)).listen((_) async {
      if (shutdown.isCompleted) return;
      tickCount++;
      sid = (sid + 1) & 0xFF;

      // Update physics.
      engine.tick(0.1);

      final gps = findEcu('GPS Receiver');
      final wind = findEcu('Wind Sensor');
      final depthDev = findEcu('Depth Transducer');
      final heading = findEcu('Heading Sensor');
      final engineDev = findEcu('Engine Gateway');
      final battery = findEcu('Battery Monitor');
      final rudder = findEcu('Rudder Sensor');
      final fluid = findEcu('Fluid Level');

      // GPS: PGN 129025 + 129026 at 10 Hz.
      await safeSend(gps, 129025,
          priority: 2,
          dest: kBroadcast,
          data: _encodePositionRapid(state.lat, state.lon));
      await safeSend(gps, 129026,
          priority: 2,
          dest: kBroadcast,
          data: _encodeCogSogRapid(
              sid: sid, cogRad: state.cog, sogMs: state.sog));

      // Heading: PGN 127250 at 10 Hz.
      await safeSend(heading, 127250,
          priority: 2,
          dest: kBroadcast,
          data: _encodeVesselHeading(
              sid: sid,
              headingRad: state.heading,
              deviationRad: 0,
              variationRad: state.magneticVariation));

      // Engine: PGN 127488 at 10 Hz.
      await safeSend(engineDev, 127488,
          priority: 2,
          dest: kBroadcast,
          data: _encodeEngineRapid(
              instance: 0, rpm: state.engineRpm, tiltTrim: state.tiltTrim));

      // Rudder: PGN 127245 at 10 Hz.
      await safeSend(rudder, 127245,
          priority: 2,
          dest: kBroadcast,
          data: _encodeRudder(instance: 0, angleRad: state.rudderAngle));

      // Wind: PGN 130306 at ~4 Hz (every 2-3 ticks).
      if (tickCount % 3 == 0) {
        await safeSend(wind, 130306,
            priority: 2,
            dest: kBroadcast,
            data: _encodeWindData(
                sid: sid,
                speedMs: state.windSpeedApparent,
                angleRad: state.windAngleApparent));
      }

      // Heading: PGN 127251 Rate of Turn at ~4 Hz.
      if (tickCount % 3 == 0) {
        await safeSend(heading, 127251,
            priority: 2,
            dest: kBroadcast,
            data: _encodeRateOfTurn(sid: sid, rateRadS: state.rateOfTurn));
      }

      // Depth: PGN 128267 + 128259 at 2 Hz (every 5 ticks).
      if (tickCount % 5 == 0) {
        await safeSend(depthDev, 128267,
            priority: 2,
            dest: kBroadcast,
            data: _encodeWaterDepth(sid: sid, depthM: state.depth));
        await safeSend(depthDev, 128259,
            priority: 2,
            dest: kBroadcast,
            data: _encodeSpeedWaterRef(sid: sid, stwMs: state.stw));
      }

      // Engine: PGN 127489 + 127493 at 2 Hz (every 5 ticks).
      if (tickCount % 5 == 0) {
        await safeSend(engineDev, 127489,
            priority: 5,
            dest: kBroadcast,
            data: _encodeEngineDynamic(
                instance: 0,
                oilPressurePa: state.oilPressure,
                oilTempK: 273.15 + 85,
                coolantTempK: state.coolantTemp,
                fuelRateM3h: state.fuelRate,
                totalHoursS: state.totalHours));
        await safeSend(engineDev, 127493,
            priority: 5,
            dest: kBroadcast,
            data: _encodeTransmission(
                instance: 0,
                gear: state.gear,
                oilPressurePa: state.oilPressure));
      }

      // Battery: PGN 127508 at 1 Hz (every 10 ticks).
      if (tickCount % 10 == 0) {
        await safeSend(battery, 127508,
            priority: 6,
            dest: kBroadcast,
            data: _encodeBatteryStatus(
                instance: 0,
                voltageV: state.batteryVoltage,
                currentA: state.batteryCurrent,
                tempK: state.batteryTemp));
      }

      // GPS: PGN 129029 at 1 Hz (every 10 ticks).
      if (tickCount % 10 == 0) {
        final now = DateTime.now().toUtc();
        final epoch = DateTime.utc(1970, 1, 1);
        final days = now.difference(epoch).inDays;
        final midnight = DateTime.utc(now.year, now.month, now.day);
        final secs = now.difference(midnight).inMilliseconds / 1000.0;
        await safeSend(gps, 129029,
            priority: 3,
            dest: kBroadcast,
            data: _encodeGnssPosition(
                sid: sid,
                latDeg: state.lat,
                lonDeg: state.lon,
                altitudeM: 5.0,
                daysSince1970: days,
                secondsSinceMidnight: secs));
      }

      // GPS: PGN 129033 Time & Date at 1 Hz (every 10 ticks).
      if (tickCount % 10 == 0) {
        await safeSend(gps, 129033,
            priority: 3, dest: kBroadcast, data: _encodeTimeDate());
      }

      // GPS: PGN 127258 Magnetic Variation at ~0.1 Hz (every 100 ticks).
      if (tickCount % 100 == 0) {
        await safeSend(gps, 127258,
            priority: 6,
            dest: kBroadcast,
            data: _encodeMagneticVariation(
                sid: sid, variationRad: state.magneticVariation));
      }

      // Fluid: PGN 127505 at 0.4 Hz (every 25 ticks = 2.5s).
      if (tickCount % 25 == 0) {
        await safeSend(fluid, 127505,
            priority: 6,
            dest: kBroadcast,
            data: _encodeFluidLevel(
                instance: 0,
                fluidType: 0, // 0 = fuel
                levelPct: state.fuelLevel,
                capacityL: 200));
      }
    }),
  );

  // -- Stats print every 5 seconds.
  subs.add(
    Stream<void>.periodic(const Duration(seconds: 5)).listen((_) {
      if (shutdown.isCompleted) return;
      final hdgDeg = (state.heading / _deg2rad).toStringAsFixed(1);
      final sogKts = (state.sog / _knotsToMs).toStringAsFixed(1);
      final windKts = (state.windSpeedApparent / _knotsToMs).toStringAsFixed(1);
      final windAngDeg =
          (state.windAngleApparent / _deg2rad).toStringAsFixed(0);
      final depthStr = state.depth.toStringAsFixed(1);
      final rpmStr = state.engineRpm.toStringAsFixed(0);
      final voltStr = state.batteryVoltage.toStringAsFixed(1);
      final fuelStr = state.fuelLevel.toStringAsFixed(1);
      final rudDeg = (state.rudderAngle / _deg2rad).toStringAsFixed(1);
      stdout.writeln('HDG=${hdgDeg}deg SOG=${sogKts}kts '
          'WIND=${windKts}kts@${windAngDeg}deg '
          'DEPTH=${depthStr}m RPM=$rpmStr '
          'BATT=${voltStr}V FUEL=$fuelStr% RUD=${rudDeg}deg '
          'POS=${state.lat.toStringAsFixed(5)},${state.lon.toStringAsFixed(5)}');
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
