/// NMEA 2000 bus topology tracker and device registry.
///
/// Attach a [BusRegistry] to an [Nmea2000Ecu] and listen to [BusEvent]s
/// for reactive device discovery:
///
/// ```dart
/// final registry = BusRegistry(ecu);
/// registry.events.listen((e) => switch (e) {
///   DeviceAppeared(:final device) => addToList(device),
///   DeviceDisappeared(:final address) => removeFromList(address),
///   DeviceInfoUpdated(:final device) => updateList(device),
///   DeviceWentOffline(:final address) => markOffline(address),
///   DeviceCameOnline(:final device) => markOnline(device),
///   ClaimConflict(:final address) => logConflict(address),
/// });
/// ```
library;

export 'src/bus_event.dart';
export 'src/bus_registry.dart';
export 'src/device_info.dart';
