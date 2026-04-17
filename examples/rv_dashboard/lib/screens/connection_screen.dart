import 'package:flutter/material.dart';

import '../services/can_interface_scanner.dart';
import '../services/rvc_service.dart';
import '../theme/cabin_theme.dart';

/// Connection screen — pick a CAN interface or fall back to the in-process
/// demo. Shown when the service is not yet connected.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    required this.service,
    required this.onConnected,
  });

  final RvcService service;
  final VoidCallback onConnected;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  List<String> _interfaces = const [];
  String? _selectedInterface;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _interfaces = CanInterfaceScanner.scan();
    if (_interfaces.isNotEmpty) {
      _selectedInterface = _interfaces.first;
    }
  }

  Future<void> _connect() async {
    if (_selectedInterface == null) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    final ok = await widget.service.connect(_selectedInterface!);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      if (ok) {
        widget.onConnected();
      } else {
        _error = widget.service.errorMessage ?? 'Connection failed';
      }
    });
  }

  void _startDemo() {
    widget.service.connectDemo();
    widget.onConnected();
  }

  @override
  Widget build(BuildContext context) {
    final hasInterfaces = _interfaces.isNotEmpty;

    return Container(
      color: CabinPalette.darkWood,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: CabinPalette.midWood,
              border: Border.all(color: CabinPalette.copper, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'RV-C DASHBOARD',
                        style: TextStyle(
                          color: CabinPalette.copperBright,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'STANDBY',
                      style: TextStyle(
                        color: CabinPalette.lampAmber,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Divider(color: CabinPalette.copper, height: 8),
                const SizedBox(height: 16),
                const Text(
                  'Select CAN interface or start demo',
                  style: TextStyle(color: CabinPalette.warmWhite, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (hasInterfaces) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedInterface,
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: CabinPalette.copper),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: CabinPalette.copper),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: CabinPalette.copperBright,
                        ),
                      ),
                    ),
                    style: const TextStyle(
                      color: CabinPalette.warmWhite,
                      fontSize: 14,
                    ),
                    dropdownColor: CabinPalette.midWood,
                    items: _interfaces
                        .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                        .toList(),
                    onChanged: _connecting
                        ? null
                        : (v) => setState(() => _selectedInterface = v),
                  ),
                  const SizedBox(height: 16),
                  _copperButton(
                    label: _connecting ? 'CONNECTING...' : 'CONNECT',
                    icon: Icons.power,
                    onTap: _connecting ? null : _connect,
                  ),
                  const SizedBox(height: 8),
                  _copperButton(
                    label: 'DEMO MODE',
                    icon: Icons.science_outlined,
                    outline: true,
                    onTap: _connecting ? null : _startDemo,
                  ),
                ] else ...[
                  const Text(
                    'No CAN interface detected.',
                    style: TextStyle(
                      color: CabinPalette.lampAmber,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _copperButton(
                    label: 'START DEMO',
                    icon: Icons.science_outlined,
                    onTap: _startDemo,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: CabinPalette.lampRed.withValues(alpha: 0.15),
                      border: Border.all(color: CabinPalette.lampRed),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: CabinPalette.lampRed,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _copperButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool outline = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: outline
              ? Colors.transparent
              : CabinPalette.copper.withValues(alpha: 0.25),
          border: Border.all(
            color: onTap == null
                ? CabinPalette.warmWhiteDim
                : CabinPalette.copperBright,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: onTap == null
                  ? CabinPalette.warmWhiteDim
                  : CabinPalette.copperBright,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: onTap == null
                    ? CabinPalette.warmWhiteDim
                    : CabinPalette.copperBright,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
