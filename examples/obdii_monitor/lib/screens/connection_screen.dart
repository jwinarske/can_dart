import 'package:flutter/material.dart';

import '../services/can_interface_scanner.dart';
import '../services/obd_service.dart';

/// Screen for connecting to a CAN interface.
///
/// Auto-detects available CAN interfaces. If none are found,
/// shows Demo Mode as the primary option.
class ConnectionScreen extends StatefulWidget {
  final ObdService obdService;
  final VoidCallback onConnected;

  const ConnectionScreen({
    super.key,
    required this.obdService,
    required this.onConnected,
  });

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  List<String> _interfaces = [];
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

    final success = await widget.obdService.connect(_selectedInterface!);

    if (!mounted) return;

    setState(() {
      _connecting = false;
      if (success) {
        widget.onConnected();
      } else {
        _error = widget.obdService.errorMessage ?? 'Connection failed';
      }
    });
  }

  void _startDemo() {
    widget.obdService.connectDemo();
    widget.onConnected();
  }

  @override
  Widget build(BuildContext context) {
    final hasInterfaces = _interfaces.isNotEmpty;

    return Scaffold(
      body: Center(
        child: Card(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.directions_car,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'OBD-II Monitor',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (hasInterfaces) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedInterface,
                    decoration: const InputDecoration(
                      labelText: 'CAN Interface',
                      prefixIcon: Icon(Icons.settings_ethernet),
                      border: OutlineInputBorder(),
                    ),
                    items: _interfaces
                        .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedInterface = v),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _connecting ? null : _connect,
                    icon: _connecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.power),
                    label: Text(_connecting ? 'Connecting...' : 'Connect'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _connecting ? null : _startDemo,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Demo Mode'),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No CAN interfaces detected.\n'
                            'Use Demo Mode to explore the app.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _startDemo,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Demo Mode'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
