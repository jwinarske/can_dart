/// Byte order of a CAN signal.
enum ByteOrder {
  /// Intel byte order (little-endian).
  littleEndian,

  /// Motorola byte order (big-endian).
  bigEndian,
}

/// Value type of a CAN signal.
enum ValueType {
  /// Unsigned integer.
  unsigned,

  /// Signed integer.
  signed,
}

/// Multiplexing type of a CAN signal.
enum MultiplexType {
  /// Not multiplexed.
  none,

  /// This signal is the multiplexer selector.
  multiplexer,

  /// This signal is multiplexed by the selector.
  multiplexed,
}

/// A signal definition from a DBC file.
class DbcSignal {
  /// Signal name.
  final String name;

  /// Start bit position.
  final int startBit;

  /// Bit length of the signal.
  final int length;

  /// Byte order (Intel = little-endian, Motorola = big-endian).
  final ByteOrder byteOrder;

  /// Signed or unsigned.
  final ValueType valueType;

  /// Scale factor: physical = raw * factor + offset.
  final double factor;

  /// Offset: physical = raw * factor + offset.
  final double offset;

  /// Minimum physical value.
  final double minimum;

  /// Maximum physical value.
  final double maximum;

  /// Physical unit string.
  final String unit;

  /// Receiving nodes.
  final List<String> receivers;

  /// Optional comment.
  String? comment;

  /// Value descriptions (enum mappings).
  Map<int, String>? valueDescriptions;

  /// Multiplexing type.
  final MultiplexType multiplexType;

  /// Multiplexer value (only valid when multiplexType == multiplexed).
  final int? multiplexValue;

  DbcSignal({
    required this.name,
    required this.startBit,
    required this.length,
    required this.byteOrder,
    required this.valueType,
    required this.factor,
    required this.offset,
    required this.minimum,
    required this.maximum,
    required this.unit,
    required this.receivers,
    this.comment,
    this.valueDescriptions,
    this.multiplexType = MultiplexType.none,
    this.multiplexValue,
  });

  @override
  String toString() =>
      'DbcSignal($name, start=$startBit, len=$length, '
      '${byteOrder == ByteOrder.littleEndian ? "LE" : "BE"}, '
      '${valueType == ValueType.signed ? "signed" : "unsigned"}, '
      'factor=$factor, offset=$offset, [$minimum..$maximum] $unit)';
}
