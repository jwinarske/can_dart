import 'dart:ffi';

import 'ffi/structs.dart';

/// A CAN bus hardware filter.
///
/// Frames are accepted if: `received_can_id & canMask == canId & canMask`.
class CanFilter {
  /// The CAN ID to match.
  final int canId;

  /// The mask to apply.
  final int canMask;

  const CanFilter({required this.canId, required this.canMask});

  /// Accept only exact CAN ID matches (standard frame).
  factory CanFilter.exact(int id) => CanFilter(canId: id, canMask: 0x7FF);

  /// Accept only exact extended CAN ID matches.
  factory CanFilter.exactExtended(int id) =>
      CanFilter(canId: id | 0x80000000, canMask: 0x9FFFFFFF);

  /// Accept all frames (pass-through filter).
  static const passAll = CanFilter(canId: 0, canMask: 0);

  /// Write this filter into a native can_filter struct.
  void toNative(Pointer<CanFilterNative> ptr) {
    ptr.ref.canId = canId;
    ptr.ref.canMask = canMask;
  }

  @override
  String toString() =>
      'CanFilter(id: 0x${canId.toRadixString(16)}, mask: 0x${canMask.toRadixString(16)})';
}
