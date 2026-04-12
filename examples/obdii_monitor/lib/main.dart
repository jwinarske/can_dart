import 'package:flutter/material.dart';

import 'screens/connection_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/dtc_screen.dart';
import 'screens/pid_browser_screen.dart';
import 'services/obd_service.dart';

void main() {
  runApp(const ObdiiMonitorApp());
}

class ObdiiMonitorApp extends StatelessWidget {
  const ObdiiMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OBD-II Monitor',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final ObdService _obdService = ObdService();
  bool _connected = false;
  int _selectedIndex = 0;

  @override
  void dispose() {
    _obdService.dispose();
    super.dispose();
  }

  void _onConnected() {
    setState(() => _connected = true);
  }

  void _disconnect() {
    _obdService.disconnect();
    setState(() {
      _connected = false;
      _selectedIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_connected) {
      return ConnectionScreen(
        obdService: _obdService,
        onConnected: _onConnected,
      );
    }

    final screens = [
      DashboardScreen(obdService: _obdService),
      DtcScreen(obdService: _obdService),
      PidBrowserScreen(obdService: _obdService),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('OBD-II Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.power_off),
            tooltip: 'Disconnect',
            onPressed: _disconnect,
          ),
        ],
      ),
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.warning_amber), label: 'DTCs'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'PIDs'),
        ],
      ),
    );
  }
}
