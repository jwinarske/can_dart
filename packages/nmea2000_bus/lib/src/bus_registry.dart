import 'dart:async';
import 'dart:typed_data';

import 'package:nmea2000/nmea2000.dart';

import 'bus_event.dart';
import 'device_info.dart';

/// Tracks NMEA 2000 bus topology: which devices are present, their Product
/// Information, PGN lists, and online/offline status.
///
/// Attach to an [Nmea2000Ecu] and listen to [events] for reactive updates:
///
/// ```dart
/// final registry = BusRegistry(ecu);
/// registry.events.listen((e) => switch (e) {
///   DeviceAppeared(:final device)    => print('new: $device'),
///   DeviceDisappeared(:final address) => print('gone: $address'),
///   DeviceInfoUpdated(:final device) => print('updated: $device'),
///   DeviceWentOffline(:final address) => print('offline: $address'),
///   DeviceCameOnline(:final device)  => print('online: $device'),
///   ClaimConflict(:final address)    => print('conflict at $address'),
/// });
/// ```
///
/// Call [dispose] to stop tracking and clean up subscriptions.
class BusRegistry {
  BusRegistry(
    this._ecu, {
    Duration offlineTimeout = const Duration(seconds: 90),
    Duration removeTimeout = const Duration(seconds: 300),
  })  : _offlineTimeout = offlineTimeout,
        _removeTimeout = removeTimeout {
    _frameSub = _ecu.frames.listen(_onFrame);
    _eventSub = _ecu.events.listen(_onEvent);
    _timeoutTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkTimeouts(),
    );
  }

  final Nmea2000Ecu _ecu;
  final Duration _offlineTimeout;
  final Duration _removeTimeout;

  final Map<int, DeviceInfo> _devices = {};
  final _controller = StreamController<BusEvent>.broadcast();

  StreamSubscription<FrameReceived>? _frameSub;
  StreamSubscription<J1939Event>? _eventSub;
  Timer? _timeoutTimer;
  bool _disposed = false;

  // Pending Product Info requests — avoid spamming the same SA.
  final Set<int> _pendingProductInfoRequests = {};

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Reactive stream of bus topology changes.
  Stream<BusEvent> get events => _controller.stream;

  /// Current snapshot of all known devices, keyed by source address.
  Map<int, DeviceInfo> get devices => Map.unmodifiable(_devices);

  /// All currently online devices.
  Iterable<DeviceInfo> get onlineDevices =>
      _devices.values.where((d) => d.status == DeviceStatus.online);

  /// Look up a device by source address.
  DeviceInfo? operator [](int address) => _devices[address];

  // ── Frame handling ─────────────────────────────────────────────────────────

  void _onFrame(FrameReceived frame) {
    if (_disposed) return;

    final sa = frame.source;

    // Ignore our own frames.
    if (sa == _ecu.address) return;
    // Ignore null address.
    if (sa >= 0xFE) return;

    final device = _devices[sa];

    if (device == null) {
      // New device — first frame we've seen from this SA.
      _onNewDevice(sa, frame);
    } else {
      // Known device — update last-heard timestamp.
      device.lastHeard = DateTime.now();

      // If it was offline, bring it back online.
      if (device.status == DeviceStatus.offline) {
        device.status = DeviceStatus.online;
        _controller.add(DeviceCameOnline(device));
      }
    }

    // Dispatch specific PGNs for info extraction.
    switch (frame.pgn) {
      case 0xEE00: // AddressClaimed — contains NAME
        _onAddressClaimedFrame(sa, frame.data);
      case 126996: // Product Information
        _onProductInfoFrame(sa, frame.data);
      case 126464: // PGN List (Transmit and Receive)
        _onPgnListFrame(sa, frame.data);
    }
  }

  void _onEvent(J1939Event event) {
    // We primarily use FrameReceived in _onFrame.
    // AddressClaimed/AddressClaimFailed events are for OUR OWN claim,
    // not other devices. Other devices' claims arrive as FrameReceived
    // with PGN 0xEE00.
  }

  void _onNewDevice(int sa, FrameReceived firstFrame) {
    final device = DeviceInfo(address: sa);
    _devices[sa] = device;
    _controller.add(DeviceAppeared(device));

    // If the first frame is AddressClaimed, decode the NAME immediately.
    if (firstFrame.pgn == 0xEE00 && firstFrame.data.length >= 8) {
      device.name = N2kName.decode(firstFrame.data);
    }

    // Request Product Information and PGN List from this device.
    _requestDeviceInfo(sa);
  }

  void _requestDeviceInfo(int sa) {
    if (_pendingProductInfoRequests.contains(sa)) return;
    _pendingProductInfoRequests.add(sa);

    try {
      // Request Product Information (PGN 126996).
      _ecu.sendRequest(sa, 126996);
    } catch (_) {}

    // Delay PGN List request slightly to avoid flooding the bus.
    Future<void>.delayed(const Duration(milliseconds: 250)).then((_) {
      if (_disposed) return;
      try {
        // Request PGN List Transmit (PGN 126464).
        _ecu.sendRequest(sa, 126464);
      } catch (_) {}
      _pendingProductInfoRequests.remove(sa);
    });
  }

  // ── PGN parsers ────────────────────────────────────────────────────────────

  void _onAddressClaimedFrame(int sa, Uint8List data) {
    if (data.length < 8) return;

    final newName = N2kName.decode(data);
    final device = _devices[sa];
    if (device == null) return;

    // Detect claim conflict: same SA, different NAME.
    if (device.name.raw != 0 && device.name.raw != newName.raw) {
      final winner = newName.raw < device.name.raw ? newName : device.name;
      final loser = newName.raw < device.name.raw ? device.name : newName;
      _controller.add(ClaimConflict(
        address: sa,
        winner: winner,
        loser: loser,
      ));
    }

    device.name = newName;
    device.lastHeard = DateTime.now();
    _controller.add(DeviceInfoUpdated(device));
  }

  void _onProductInfoFrame(int sa, Uint8List data) {
    final device = _devices[sa];
    if (device == null) return;

    device.productInfo = ProductInfo.decode(data);
    device.lastHeard = DateTime.now();
    _controller.add(DeviceInfoUpdated(device));
  }

  void _onPgnListFrame(int sa, Uint8List data) {
    if (data.isEmpty) return;
    final device = _devices[sa];
    if (device == null) return;

    // First byte: 0 = transmit list, 1 = receive list.
    final isTransmit = data[0] == 0;

    // Remaining bytes: 3-byte LE PGN entries.
    final pgns = <int>[];
    for (var i = 1; i + 2 < data.length; i += 3) {
      final pgn = data[i] | (data[i + 1] << 8) | (data[i + 2] << 16);
      if (pgn != 0 && pgn != 0xFFFFFF) {
        pgns.add(pgn);
      }
    }

    if (isTransmit) {
      device.transmitPgns = pgns;
    } else {
      device.receivePgns = pgns;
    }
    device.lastHeard = DateTime.now();
    _controller.add(DeviceInfoUpdated(device));
  }

  // ── Timeout handling ───────────────────────────────────────────────────────

  void _checkTimeouts() {
    if (_disposed) return;
    final now = DateTime.now();

    final toRemove = <int>[];

    for (final entry in _devices.entries) {
      final device = entry.value;
      final elapsed = now.difference(device.lastHeard);

      if (device.status == DeviceStatus.online && elapsed > _offlineTimeout) {
        device.status = DeviceStatus.offline;
        _controller.add(DeviceWentOffline(device.address));
      }

      if (device.status == DeviceStatus.offline && elapsed > _removeTimeout) {
        toRemove.add(entry.key);
      }
    }

    for (final sa in toRemove) {
      _devices.remove(sa);
      _controller.add(DeviceDisappeared(sa));
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _frameSub?.cancel();
    _eventSub?.cancel();
    _timeoutTimer?.cancel();
    _controller.close();
  }
}
