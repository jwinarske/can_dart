// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:rvc/rvc.dart';

import 'rvc_bus_event.dart';
import 'rvc_device_info.dart';

/// Tracks RV-C bus topology: which devices are present, their NAME identity,
/// and online/offline status.
///
/// Attach to an [RvcEcu] and listen to [events] for reactive updates:
///
/// ```dart
/// final registry = RvcBusRegistry(ecu);
/// registry.events.listen((e) => switch (e) {
///   RvcDeviceAppeared(:final device)    => print('new: $device'),
///   RvcDeviceDisappeared(:final address) => print('gone: $address'),
///   RvcDeviceWentOffline(:final address) => print('offline: $address'),
///   RvcDeviceCameOnline(:final device)  => print('online: $device'),
/// });
/// ```
///
/// Call [dispose] to stop tracking and clean up subscriptions.
class RvcBusRegistry {
  RvcBusRegistry(
    this._ecu, {
    Duration offlineTimeout = const Duration(seconds: 90),
    Duration removeTimeout = const Duration(seconds: 300),
  })  : _offlineTimeout = offlineTimeout,
        _removeTimeout = removeTimeout {
    _frameSub = _ecu.frames.listen(_onFrame);
    _timeoutTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkTimeouts(),
    );
  }

  final RvcEcu _ecu;
  final Duration _offlineTimeout;
  final Duration _removeTimeout;

  final Map<int, RvcDeviceInfo> _devices = {};
  final _controller = StreamController<RvcBusEvent>.broadcast();

  StreamSubscription<FrameReceived>? _frameSub;
  Timer? _timeoutTimer;
  bool _disposed = false;

  // -- Public API -------------------------------------------------------------

  /// Reactive stream of bus topology changes.
  Stream<RvcBusEvent> get events => _controller.stream;

  /// Current snapshot of all known devices, keyed by source address.
  Map<int, RvcDeviceInfo> get devices => Map.unmodifiable(_devices);

  /// All currently online devices.
  Iterable<RvcDeviceInfo> get onlineDevices =>
      _devices.values.where((d) => d.status == RvcDeviceStatus.online);

  /// Look up a device by source address.
  RvcDeviceInfo? operator [](int address) => _devices[address];

  // -- Frame handling ---------------------------------------------------------

  void _onFrame(FrameReceived frame) {
    if (_disposed) return;

    final sa = frame.source;

    // Ignore our own frames.
    if (sa == _ecu.address) return;
    // Ignore null address (0xFE = Cannot Claim, 0xFF = Global).
    if (sa >= 0xFE) return;

    final device = _devices[sa];

    if (device == null) {
      // New device — first frame we've seen from this SA.
      _onNewDevice(sa, frame);
    } else {
      // Known device — update last-heard timestamp.
      device.lastHeard = DateTime.now();

      // If it was offline, bring it back online.
      if (device.status == RvcDeviceStatus.offline) {
        device.status = RvcDeviceStatus.online;
        _controller.add(RvcDeviceCameOnline(device));
      }
    }

    // Decode AddressClaimed (PGN 0xEE00) — the only mandatory identity PGN.
    if (frame.pgn == 0xEE00) {
      _onAddressClaimedFrame(sa, frame.data);
    }
  }

  void _onNewDevice(int sa, FrameReceived firstFrame) {
    final device = RvcDeviceInfo(address: sa);
    _devices[sa] = device;

    // If the first frame is AddressClaimed, decode the NAME immediately.
    if (firstFrame.pgn == 0xEE00 && firstFrame.data.length >= 8) {
      device.name = RvcName.decode(firstFrame.data);
    }

    _controller.add(RvcDeviceAppeared(device));
  }

  void _onAddressClaimedFrame(int sa, Uint8List data) {
    if (data.length < 8) return;

    final device = _devices[sa];
    if (device == null) return;

    device.name = RvcName.decode(data);
    device.lastHeard = DateTime.now();
  }

  // -- Timeout handling -------------------------------------------------------

  void _checkTimeouts() {
    if (_disposed) return;
    final now = DateTime.now();

    final toRemove = <int>[];

    for (final entry in _devices.entries) {
      final device = entry.value;
      final elapsed = now.difference(device.lastHeard);

      if (device.status == RvcDeviceStatus.online &&
          elapsed > _offlineTimeout) {
        device.status = RvcDeviceStatus.offline;
        _controller.add(RvcDeviceWentOffline(device.address));
      }

      if (device.status == RvcDeviceStatus.offline &&
          elapsed > _removeTimeout) {
        toRemove.add(entry.key);
      }
    }

    for (final sa in toRemove) {
      _devices.remove(sa);
      _controller.add(RvcDeviceDisappeared(sa));
    }
  }

  // -- Lifecycle --------------------------------------------------------------

  /// Release all resources and close the event stream.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _frameSub?.cancel();
    _timeoutTimer?.cancel();
    _controller.close();
  }
}
