import 'device_info.dart';

/// Sealed event hierarchy for bus topology changes.
///
/// Exhaustive switch example:
///   registry.events.listen((e) => switch (e) {
///     DeviceAppeared(:final device)                    => onNew(device),
///     DeviceDisappeared(:final address)                => onGone(address),
///     DeviceInfoUpdated(:final device)                 => onUpdate(device),
///     DeviceWentOffline(:final address)                => onOffline(address),
///     DeviceCameOnline(:final device)                  => onOnline(device),
///     ClaimConflict(:final address, :final winner)     => onConflict(address),
///   });
sealed class BusEvent {
  const BusEvent();
}

/// A device appeared on the bus for the first time (new source address seen).
final class DeviceAppeared extends BusEvent {
  const DeviceAppeared(this.device);
  final DeviceInfo device;

  @override
  String toString() => 'DeviceAppeared($device)';
}

/// A device disappeared from the bus (removed after timeout with no recovery).
final class DeviceDisappeared extends BusEvent {
  const DeviceDisappeared(this.address);
  final int address;

  @override
  String toString() =>
      'DeviceDisappeared(0x${address.toRadixString(16).padLeft(2, '0')})';
}

/// A device's cached info was updated (Product Info or PGN List received).
final class DeviceInfoUpdated extends BusEvent {
  const DeviceInfoUpdated(this.device);
  final DeviceInfo device;

  @override
  String toString() => 'DeviceInfoUpdated($device)';
}

/// A known device stopped responding (heartbeat timeout).
/// The device is still in the registry with [DeviceStatus.offline].
final class DeviceWentOffline extends BusEvent {
  const DeviceWentOffline(this.address);
  final int address;

  @override
  String toString() =>
      'DeviceWentOffline(0x${address.toRadixString(16).padLeft(2, '0')})';
}

/// A previously-offline device started sending frames again.
final class DeviceCameOnline extends BusEvent {
  const DeviceCameOnline(this.device);
  final DeviceInfo device;

  @override
  String toString() => 'DeviceCameOnline($device)';
}

/// An address claim conflict was observed — two NAMEs competing for the same SA.
final class ClaimConflict extends BusEvent {
  const ClaimConflict({
    required this.address,
    required this.winner,
    required this.loser,
  });

  final int address;
  final N2kName winner;
  final N2kName loser;

  @override
  String toString() =>
      'ClaimConflict(0x${address.toRadixString(16).padLeft(2, '0')} '
      'winner=$winner loser=$loser)';
}
