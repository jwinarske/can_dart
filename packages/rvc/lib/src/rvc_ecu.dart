// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// RvcEcu — RV-C device layer on top of J1939Ecu.
//
// Wraps J1939Ecu with RV-C NAME defaults (industry group 0 = Global).
// No heartbeat, no mandatory PGN responder, no Fast Packet registration.
// RV-C is pure J1939 single-frame + BAM.

import 'dart:async';
import 'dart:typed_data';

import 'package:can_codec/can_codec.dart';
import 'package:j1939/j1939.dart';

import 'rvc_registry.dart';

/// An RV-C ECU node with RV-C protocol defaults.
///
/// RV-C is simpler than NMEA 2000: no heartbeat, no mandatory PGN
/// auto-responder, no Fast Packet transport. All DGNs are single-frame
/// (8 bytes) or use J1939 BAM for multi-packet.
class RvcEcu {
  RvcEcu._({
    required J1939Ecu ecu,
    required this.registry,
  }) : _ecu = ecu;

  final J1939Ecu _ecu;

  /// The DGN definition registry for this ECU.
  final RvcRegistry registry;

  bool _disposed = false;

  // -- Factory ----------------------------------------------------------------

  /// Create an RV-C node.
  ///
  /// Creates a [J1939Ecu] with RV-C NAME defaults (industry group 0 = Global),
  /// waits for address claim, and returns an [RvcEcu] wrapper.
  ///
  /// Throws [StateError] on native create failure.
  /// Throws [TimeoutException] if address claim does not settle within
  /// [claimTimeout].
  static Future<RvcEcu> create({
    required String ifname,
    int address = 0x80,
    int identityNumber = 1,
    int manufacturerCode = 0x7FF,
    int deviceFunction = 0,
    int deviceClass = 0,
    int functionInstance = 0,
    int ecuInstance = 0,
    int vehicleSystemInstance = 0,
    RvcRegistry? registry,
    Duration claimTimeout = const Duration(seconds: 3),
  }) async {
    final reg = registry ?? RvcRegistry.standard();

    final ecu = J1939Ecu.createFull(
      ifname: ifname,
      address: address,
      identityNumber: identityNumber,
      manufacturerCode: manufacturerCode,
      industryGroup: 0, // RV-C typically uses 0 (Global)
      deviceFunction: deviceFunction,
      deviceClass: deviceClass,
      functionInstance: functionInstance,
      ecuInstance: ecuInstance,
      vehicleSystemInstance: vehicleSystemInstance,
    );

    final rvc = RvcEcu._(ecu: ecu, registry: reg);

    // Wait for address claim before returning.
    final claimEvent = await ecu.addressEvents.first.timeout(claimTimeout);
    if (claimEvent is AddressClaimFailed) {
      ecu.dispose();
      throw StateError('RV-C address claim failed on "$ifname"');
    }

    return rvc;
  }

  // -- Public API -------------------------------------------------------------

  /// The underlying J1939Ecu for direct frame access.
  J1939Ecu get ecu => _ecu;

  /// All ECU events (frames, claims, errors, DM1).
  Stream<J1939Event> get events => _ecu.events;

  /// Received CAN frames.
  Stream<FrameReceived> get frames => _ecu.frames;

  /// Frames matching a specific DGN (alias for PGN in RV-C).
  Stream<FrameReceived> framesForDgn(int dgn) => _ecu.framesForPgn(dgn);

  /// Current claimed address (0xFE if not claimed).
  int get address => _ecu.address;

  /// Whether an address has been successfully claimed.
  bool get addressClaimed => _ecu.addressClaimed;

  // -- Command helpers --------------------------------------------------------

  /// Send a raw command DGN.
  ///
  /// Encodes the [data] payload and sends it to [dest] with the given
  /// [priority].
  Future<void> sendCommand(
    int dgn, {
    required int priority,
    required int dest,
    required Uint8List data,
  }) {
    return _ecu.send(dgn, priority: priority, dest: dest, data: data);
  }

  /// Encode field values from the registry and send as a command DGN.
  ///
  /// Looks up the [dgn] in the registry, encodes the [values] map into a
  /// CAN payload, and sends it to [dest].
  ///
  /// Throws [ArgumentError] if the DGN is not found in the registry.
  Future<void> sendCommandFields(
    int dgn, {
    required int dest,
    required Map<String, dynamic> values,
    int priority = 6,
  }) {
    final def = registry.lookup(dgn);
    if (def == null) {
      throw ArgumentError('DGN 0x${dgn.toRadixString(16)} not in registry');
    }
    final data = encode(values, def);
    return _ecu.send(dgn, priority: priority, dest: dest, data: data);
  }

  // -- Lifecycle --------------------------------------------------------------

  /// Release all resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ecu.dispose();
  }
}
