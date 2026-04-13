import 'dart:typed_data';

/// Device online/offline status.
enum DeviceStatus { online, offline }

/// Decoded J1939/NMEA 2000 64-bit NAME field.
///
/// The NAME is broadcast in the AddressClaimed PGN (0xEE00) as 8 bytes
/// little-endian. Lower numeric value = higher priority in claim arbitration.
class N2kName {
  const N2kName({
    this.identityNumber = 0,
    this.manufacturerCode = 0x7FF,
    this.functionInstance = 0,
    this.ecuInstance = 0,
    this.deviceFunction = 0,
    this.deviceClass = 0,
    this.arbitraryAddress = true,
    this.industryGroup = 0,
    this.systemInstance = 0,
  });

  final int identityNumber; // 21 bits
  final int manufacturerCode; // 11 bits
  final int functionInstance; // 5 bits
  final int ecuInstance; // 3 bits
  final int deviceFunction; // 8 bits
  final int deviceClass; // 7 bits (called vehicle_system in J1939)
  final bool arbitraryAddress; // 1 bit
  final int industryGroup; // 3 bits
  final int systemInstance; // 4 bits

  /// Decode from 8 bytes little-endian (as received in AddressClaimed PGN).
  factory N2kName.decode(Uint8List data) {
    if (data.length < 8) return const N2kName();
    int raw = 0;
    for (var i = 0; i < 8; i++) {
      raw |= data[i] << (i * 8);
    }
    return N2kName.fromRaw(raw);
  }

  /// Decode from a 64-bit raw integer.
  factory N2kName.fromRaw(int raw) {
    return N2kName(
      identityNumber: raw & 0x1FFFFF,
      manufacturerCode: (raw >> 21) & 0x7FF,
      functionInstance: (raw >> 32) & 0x1F,
      ecuInstance: (raw >> 37) & 0x07,
      deviceFunction: (raw >> 40) & 0xFF,
      deviceClass: (raw >> 49) & 0x7F,
      arbitraryAddress: ((raw >> 56) & 0x1) == 1,
      industryGroup: (raw >> 57) & 0x07,
      systemInstance: (raw >> 60) & 0x0F,
    );
  }

  /// Encode to 64-bit raw integer.
  int get raw =>
      (identityNumber & 0x1FFFFF) |
      ((manufacturerCode & 0x7FF) << 21) |
      ((functionInstance & 0x1F) << 32) |
      ((ecuInstance & 0x07) << 37) |
      (deviceFunction << 40) |
      ((deviceClass & 0x7F) << 49) |
      ((arbitraryAddress ? 1 : 0) << 56) |
      ((industryGroup & 0x07) << 57) |
      ((systemInstance & 0x0F) << 60);

  /// Industry group name for display.
  String get industryGroupName {
    switch (industryGroup) {
      case 0:
        return 'Global';
      case 1:
        return 'Highway';
      case 2:
        return 'Agriculture';
      case 3:
        return 'Construction';
      case 4:
        return 'Marine';
      case 5:
        return 'Industrial';
      default:
        return 'Unknown($industryGroup)';
    }
  }

  @override
  String toString() => 'N2kName(mfr=$manufacturerCode id=$identityNumber '
      'fn=$deviceFunction cls=$deviceClass '
      '${industryGroupName.toLowerCase()})';
}

/// Decoded Product Information (PGN 126996).
class ProductInfo {
  const ProductInfo({
    this.nmea2000Version = 0,
    this.productCode = 0,
    this.modelId = '',
    this.softwareVersion = '',
    this.modelVersion = '',
    this.modelSerialCode = '',
    this.certificationLevel = 0,
    this.loadEquivalency = 0,
  });

  final int nmea2000Version;
  final int productCode;
  final String modelId;
  final String softwareVersion;
  final String modelVersion;
  final String modelSerialCode;
  final int certificationLevel;
  final int loadEquivalency;

  /// Decode from a Product Information PGN payload (134 bytes).
  factory ProductInfo.decode(Uint8List data) {
    if (data.length < 134) {
      return const ProductInfo();
    }
    final view = ByteData.sublistView(data);
    return ProductInfo(
      nmea2000Version: view.getUint16(0, Endian.little),
      productCode: view.getUint16(2, Endian.little),
      modelId: _extractString(data, 4, 32),
      softwareVersion: _extractString(data, 36, 32),
      modelVersion: _extractString(data, 68, 32),
      modelSerialCode: _extractString(data, 100, 32),
      certificationLevel: data[132],
      loadEquivalency: data[133],
    );
  }

  @override
  String toString() => 'ProductInfo("$modelId" v$softwareVersion)';
}

/// Information about a single device on the NMEA 2000 bus.
class DeviceInfo {
  DeviceInfo({
    required this.address,
    N2kName? name,
    this.productInfo,
    List<int>? transmitPgns,
    List<int>? receivePgns,
    DateTime? lastHeard,
    this.status = DeviceStatus.online,
  })  : name = name ?? const N2kName(),
        transmitPgns = transmitPgns ?? const [],
        receivePgns = receivePgns ?? const [],
        lastHeard = lastHeard ?? DateTime.now();

  final int address;
  N2kName name;
  ProductInfo? productInfo;
  List<int> transmitPgns;
  List<int> receivePgns;
  DateTime lastHeard;
  DeviceStatus status;

  @override
  String toString() {
    final sa = address.toRadixString(16).padLeft(2, '0').toUpperCase();
    final model = productInfo?.modelId ?? '?';
    return 'Device(0x$sa "$model" $status $name)';
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Extract a fixed-length ASCII string, trimming trailing 0xFF and 0x00.
String _extractString(Uint8List data, int offset, int length) {
  if (offset + length > data.length) return '';
  var end = offset + length;
  while (end > offset && (data[end - 1] == 0xFF || data[end - 1] == 0x00)) {
    end--;
  }
  return String.fromCharCodes(data, offset, end);
}
