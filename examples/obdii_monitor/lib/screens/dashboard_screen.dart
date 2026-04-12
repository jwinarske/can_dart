import 'dart:async';

import 'package:flutter/material.dart';

import '../services/obd_service.dart';
import '../widgets/gauge.dart';

/// Main dashboard screen with OBD-II gauges.
class DashboardScreen extends StatefulWidget {
  final ObdService obdService;

  const DashboardScreen({super.key, required this.obdService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late StreamSubscription<Map<int, PidValue>> _subscription;
  Map<int, PidValue> _values = {};

  @override
  void initState() {
    super.initState();
    _values = widget.obdService.currentValues;
    _subscription = widget.obdService.pidStream.listen((values) {
      setState(() => _values = values);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  double _getValue(int pid) => _values[pid]?.value ?? 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary gauges row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Gauge(
                label: 'Engine RPM',
                unit: 'rpm',
                value: _getValue(0x0C),
                min: 0,
                max: 8000,
                color: _rpmColor(_getValue(0x0C)),
              ),
              Gauge(
                label: 'Vehicle Speed',
                unit: 'km/h',
                value: _getValue(0x0D),
                min: 0,
                max: 240,
                color: Colors.blue,
              ),
              Gauge(
                label: 'Coolant Temp',
                unit: '\u00B0C',
                value: _getValue(0x05),
                min: -40,
                max: 215,
                color: _tempColor(_getValue(0x05)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Secondary gauges row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Gauge(
                label: 'Engine Load',
                unit: '%',
                value: _getValue(0x04),
                min: 0,
                max: 100,
                color: Colors.orange,
              ),
              Gauge(
                label: 'Throttle',
                unit: '%',
                value: _getValue(0x11),
                min: 0,
                max: 100,
                color: Colors.green,
              ),
              Gauge(
                label: 'Fuel Level',
                unit: '%',
                value: _getValue(0x2F),
                min: 0,
                max: 100,
                color: _fuelColor(_getValue(0x2F)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Live PID table
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Data',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: _values.entries.map((e) {
                          final pid = e.value.pid;
                          return ListTile(
                            dense: true,
                            title: Text(pid.name),
                            subtitle: Text(
                              'PID 0x${pid.pid.toRadixString(16).toUpperCase().padLeft(2, '0')}',
                            ),
                            trailing: Text(
                              '${e.value.value.toStringAsFixed(1)} ${pid.unit}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _rpmColor(double rpm) {
    if (rpm > 6000) return Colors.red;
    if (rpm > 4000) return Colors.orange;
    return Colors.green;
  }

  Color _tempColor(double temp) {
    if (temp > 110) return Colors.red;
    if (temp > 90) return Colors.orange;
    if (temp < 50) return Colors.blue;
    return Colors.green;
  }

  Color _fuelColor(double level) {
    if (level < 10) return Colors.red;
    if (level < 25) return Colors.orange;
    return Colors.green;
  }
}
