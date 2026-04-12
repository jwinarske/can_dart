import 'dart:async';

import 'package:flutter/material.dart';

import '../models/obd_pid.dart';
import '../services/obd_service.dart';

/// PID browser screen — browse and monitor all available PIDs.
class PidBrowserScreen extends StatefulWidget {
  final ObdService obdService;

  const PidBrowserScreen({super.key, required this.obdService});

  @override
  State<PidBrowserScreen> createState() => _PidBrowserScreenState();
}

class _PidBrowserScreenState extends State<PidBrowserScreen> {
  late StreamSubscription<Map<int, PidValue>> _subscription;
  Map<int, PidValue> _values = {};
  final Set<int> _selectedPids = {};

  @override
  void initState() {
    super.initState();
    _values = widget.obdService.currentValues;
    _selectedPids.addAll(widget.obdService.activePids);
    _subscription = widget.obdService.pidStream.listen((values) {
      setState(() => _values = values);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  void _togglePid(int pid) {
    setState(() {
      if (_selectedPids.contains(pid)) {
        _selectedPids.remove(pid);
      } else {
        _selectedPids.add(pid);
      }
      widget.obdService.activePids = _selectedPids.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sortedPids = obdPids.values.toList()
      ..sort((a, b) => a.pid.compareTo(b.pid));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OBD-II PIDs — ${_selectedPids.length} active',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Toggle PIDs to add/remove from active polling',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: sortedPids.length,
                itemBuilder: (context, index) {
                  final pid = sortedPids[index];
                  final isActive = _selectedPids.contains(pid.pid);
                  final value = _values[pid.pid];

                  return ListTile(
                    leading: Switch(
                      value: isActive,
                      onChanged: (_) => _togglePid(pid.pid),
                    ),
                    title: Text(pid.name),
                    subtitle: Text(
                      'PID 0x${pid.pid.toRadixString(16).toUpperCase().padLeft(2, '0')} '
                      '· ${pid.unit.isEmpty ? "—" : "${pid.min}..${pid.max} ${pid.unit}"}',
                    ),
                    trailing: value != null
                        ? Text(
                            '${value.value.toStringAsFixed(1)} ${pid.unit}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          )
                        : Text(
                            '---',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
