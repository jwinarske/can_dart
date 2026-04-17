// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// RV-C bus topology tracker and device registry.
///
/// Attach an [RvcBusRegistry] to an [RvcEcu] and listen to [RvcBusEvent]s
/// for reactive device discovery:
///
/// ```dart
/// final registry = RvcBusRegistry(ecu);
/// registry.events.listen((e) => switch (e) {
///   RvcDeviceAppeared(:final device)    => addToList(device),
///   RvcDeviceDisappeared(:final address) => removeFromList(address),
///   RvcDeviceWentOffline(:final address) => markOffline(address),
///   RvcDeviceCameOnline(:final device)  => markOnline(device),
/// });
/// ```
library;

export 'src/rvc_bus_event.dart';
export 'src/rvc_bus_registry.dart';
export 'src/rvc_device_info.dart';
