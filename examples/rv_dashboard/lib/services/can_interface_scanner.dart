import 'dart:io';

/// Scans for available CAN network interfaces on the system.
///
/// Checks /sys/class/net/*/type for CAN interfaces (type 280 = ARPHRD_CAN).
class CanInterfaceScanner {
  /// Returns a list of available CAN interface names (e.g., ["can0", "vcan0"]).
  static List<String> scan() {
    final interfaces = <String>[];

    try {
      final netDir = Directory('/sys/class/net');
      if (!netDir.existsSync()) return interfaces;

      for (final entry in netDir.listSync()) {
        if (entry is! Directory) continue;
        final name = entry.path.split('/').last;
        final typeFile = File('${entry.path}/type');
        if (!typeFile.existsSync()) continue;

        final type = typeFile.readAsStringSync().trim();
        // ARPHRD_CAN = 280
        if (type == '280') {
          interfaces.add(name);
        }
      }
    } catch (_) {
      // Permission errors, etc. — return what we have.
    }

    interfaces.sort();
    return interfaces;
  }
}
