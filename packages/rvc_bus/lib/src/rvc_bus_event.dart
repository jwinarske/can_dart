// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

import 'rvc_device_info.dart';

/// Sealed event hierarchy for RV-C bus topology changes.
///
/// Exhaustive switch example:
///   registry.events.listen((e) => switch (e) {
///     RvcDeviceAppeared(:final device)       => onNew(device),
///     RvcDeviceDisappeared(:final address)    => onGone(address),
///     RvcDeviceWentOffline(:final address)    => onOffline(address),
///     RvcDeviceCameOnline(:final device)      => onOnline(device),
///   });
sealed class RvcBusEvent {
  const RvcBusEvent();
}

/// A device appeared on the bus for the first time (new source address seen).
final class RvcDeviceAppeared extends RvcBusEvent {
  const RvcDeviceAppeared(this.device);
  final RvcDeviceInfo device;

  @override
  String toString() => 'RvcDeviceAppeared($device)';
}

/// A device disappeared from the bus (removed after timeout with no recovery).
final class RvcDeviceDisappeared extends RvcBusEvent {
  const RvcDeviceDisappeared(this.address);
  final int address;

  @override
  String toString() =>
      'RvcDeviceDisappeared(0x${address.toRadixString(16).padLeft(2, '0')})';
}

/// A known device stopped responding (heartbeat timeout).
/// The device is still in the registry with [RvcDeviceStatus.offline].
final class RvcDeviceWentOffline extends RvcBusEvent {
  const RvcDeviceWentOffline(this.address);
  final int address;

  @override
  String toString() =>
      'RvcDeviceWentOffline(0x${address.toRadixString(16).padLeft(2, '0')})';
}

/// A previously-offline device started sending frames again.
final class RvcDeviceCameOnline extends RvcBusEvent {
  const RvcDeviceCameOnline(this.device);
  final RvcDeviceInfo device;

  @override
  String toString() => 'RvcDeviceCameOnline($device)';
}
