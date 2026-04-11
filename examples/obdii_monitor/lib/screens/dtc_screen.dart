import 'package:flutter/material.dart';

import '../services/obd_service.dart';

/// DTC (Diagnostic Trouble Codes) screen.
class DtcScreen extends StatefulWidget {
  final ObdService obdService;

  const DtcScreen({super.key, required this.obdService});

  @override
  State<DtcScreen> createState() => _DtcScreenState();
}

class _DtcScreenState extends State<DtcScreen> {
  final List<String> _dtcCodes = [];
  bool _reading = false;
  String? _status;

  Future<void> _readDtc() async {
    setState(() {
      _reading = true;
      _status = 'Requesting DTCs via ISO-TP...';
      _dtcCodes.clear();
    });

    final dtcs = await widget.obdService.requestDtcRead();

    if (!mounted) return;
    setState(() {
      _reading = false;
      _dtcCodes.addAll(dtcs);
      _status = dtcs.isEmpty
          ? 'No DTCs found'
          : '${dtcs.length} DTC${dtcs.length == 1 ? '' : 's'} found';
    });
  }

  Future<void> _clearDtc() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear DTCs'),
        content: const Text(
          'This will clear all stored diagnostic trouble codes and '
          'reset associated freeze frame data. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _status = 'Clearing DTCs...');
    final success = await widget.obdService.requestDtcClear();

    if (!mounted) return;
    setState(() {
      if (success) {
        _dtcCodes.clear();
        _status = 'DTCs cleared';
      } else {
        _status = 'Failed to clear DTCs';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: _reading ? null : _readDtc,
                icon: const Icon(Icons.search),
                label: const Text('Read DTCs'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _clearDtc,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear DTCs'),
              ),
              const SizedBox(width: 16),
              if (_status != null)
                Text(
                  _status!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: _dtcCodes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No DTCs stored',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Press "Read DTCs" to scan for trouble codes',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _dtcCodes.length,
                      itemBuilder: (context, index) {
                        final code = _dtcCodes[index];
                        return ListTile(
                          leading: Icon(
                            Icons.warning_amber,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          title: Text(code),
                          subtitle: Text(_dtcDescription(code)),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _dtcDescription(String code) {
    // Common DTC descriptions
    const descriptions = {
      'P0300': 'Random/Multiple Cylinder Misfire Detected',
      'P0301': 'Cylinder 1 Misfire Detected',
      'P0420': 'Catalyst System Efficiency Below Threshold',
      'P0171': 'System Too Lean (Bank 1)',
      'P0172': 'System Too Rich (Bank 1)',
      'P0442': 'Evaporative Emission System Leak Detected (small leak)',
    };
    return descriptions[code] ?? 'No description available';
  }
}
