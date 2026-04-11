/// An OBD-II Parameter ID definition.
class ObdPid {
  /// PID number (e.g., 0x0C for engine RPM).
  final int pid;

  /// Human-readable name.
  final String name;

  /// Physical unit.
  final String unit;

  /// Number of response data bytes.
  final int bytes;

  /// Minimum displayable value.
  final double min;

  /// Maximum displayable value.
  final double max;

  /// Decode raw bytes to physical value.
  final double Function(List<int> data) decode;

  const ObdPid({
    required this.pid,
    required this.name,
    required this.unit,
    required this.bytes,
    required this.min,
    required this.max,
    required this.decode,
  });
}

/// Standard OBD-II Mode 01 PIDs.
final obdPids = <int, ObdPid>{
  0x04: ObdPid(
    pid: 0x04,
    name: 'Engine Load',
    unit: '%',
    bytes: 1,
    min: 0,
    max: 100,
    decode: (d) => d[0] * 100.0 / 255.0,
  ),
  0x05: ObdPid(
    pid: 0x05,
    name: 'Coolant Temp',
    unit: '\u00B0C',
    bytes: 1,
    min: -40,
    max: 215,
    decode: (d) => d[0] - 40.0,
  ),
  0x06: ObdPid(
    pid: 0x06,
    name: 'Short Fuel Trim B1',
    unit: '%',
    bytes: 1,
    min: -100,
    max: 99.2,
    decode: (d) => (d[0] - 128) * 100.0 / 128.0,
  ),
  0x0B: ObdPid(
    pid: 0x0B,
    name: 'Intake MAP',
    unit: 'kPa',
    bytes: 1,
    min: 0,
    max: 255,
    decode: (d) => d[0].toDouble(),
  ),
  0x0C: ObdPid(
    pid: 0x0C,
    name: 'Engine RPM',
    unit: 'rpm',
    bytes: 2,
    min: 0,
    max: 16383.75,
    decode: (d) => ((d[0] * 256) + d[1]) / 4.0,
  ),
  0x0D: ObdPid(
    pid: 0x0D,
    name: 'Vehicle Speed',
    unit: 'km/h',
    bytes: 1,
    min: 0,
    max: 255,
    decode: (d) => d[0].toDouble(),
  ),
  0x0E: ObdPid(
    pid: 0x0E,
    name: 'Timing Advance',
    unit: '\u00B0',
    bytes: 1,
    min: -64,
    max: 63.5,
    decode: (d) => d[0] / 2.0 - 64.0,
  ),
  0x0F: ObdPid(
    pid: 0x0F,
    name: 'Intake Air Temp',
    unit: '\u00B0C',
    bytes: 1,
    min: -40,
    max: 215,
    decode: (d) => d[0] - 40.0,
  ),
  0x10: ObdPid(
    pid: 0x10,
    name: 'MAF Rate',
    unit: 'g/s',
    bytes: 2,
    min: 0,
    max: 655.35,
    decode: (d) => ((d[0] * 256) + d[1]) / 100.0,
  ),
  0x11: ObdPid(
    pid: 0x11,
    name: 'Throttle Position',
    unit: '%',
    bytes: 1,
    min: 0,
    max: 100,
    decode: (d) => d[0] * 100.0 / 255.0,
  ),
  0x1C: ObdPid(
    pid: 0x1C,
    name: 'OBD Standard',
    unit: '',
    bytes: 1,
    min: 0,
    max: 255,
    decode: (d) => d[0].toDouble(),
  ),
  0x1F: ObdPid(
    pid: 0x1F,
    name: 'Run Time',
    unit: 's',
    bytes: 2,
    min: 0,
    max: 65535,
    decode: (d) => ((d[0] * 256) + d[1]).toDouble(),
  ),
  0x2F: ObdPid(
    pid: 0x2F,
    name: 'Fuel Level',
    unit: '%',
    bytes: 1,
    min: 0,
    max: 100,
    decode: (d) => d[0] * 100.0 / 255.0,
  ),
  0x33: ObdPid(
    pid: 0x33,
    name: 'Barometric Pressure',
    unit: 'kPa',
    bytes: 1,
    min: 0,
    max: 255,
    decode: (d) => d[0].toDouble(),
  ),
  0x46: ObdPid(
    pid: 0x46,
    name: 'Ambient Air Temp',
    unit: '\u00B0C',
    bytes: 1,
    min: -40,
    max: 215,
    decode: (d) => d[0] - 40.0,
  ),
  0x5C: ObdPid(
    pid: 0x5C,
    name: 'Oil Temp',
    unit: '\u00B0C',
    bytes: 1,
    min: -40,
    max: 210,
    decode: (d) => d[0] - 40.0,
  ),
};

/// Decode a DTC code from two bytes.
String decodeDtc(int byte0, int byte1) {
  const prefixes = ['P', 'C', 'B', 'U'];
  final prefix = prefixes[(byte0 >> 6) & 0x03];
  final digit1 = (byte0 >> 4) & 0x03;
  final digit2 = byte0 & 0x0F;
  final digit3 = (byte1 >> 4) & 0x0F;
  final digit4 = byte1 & 0x0F;
  return '$prefix$digit1${digit2.toRadixString(16).toUpperCase()}'
      '${digit3.toRadixString(16).toUpperCase()}'
      '${digit4.toRadixString(16).toUpperCase()}';
}

/// Decode a VIN from 17 bytes of ASCII.
String decodeVin(List<int> bytes) {
  return String.fromCharCodes(bytes.where((b) => b >= 0x20 && b <= 0x7E));
}
