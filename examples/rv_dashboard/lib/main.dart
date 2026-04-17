// Entry point for the RV-C monitoring and control dashboard.
//
// Connects to a CAN bus (or runs in demo mode), decodes RV-C DGNs,
// and renders status readouts and control panels on multiple pages.
// A NavigationBar at the bottom switches between Power, Tanks, Climate,
// Lighting, Systems, and Bus pages.

import 'package:flutter/material.dart';

import 'screens/bus_screen.dart';
import 'screens/climate_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/lighting_screen.dart';
import 'screens/power_screen.dart';
import 'screens/systems_screen.dart';
import 'screens/tanks_screen.dart';
import 'services/rvc_service.dart';
import 'theme/cabin_theme.dart';

void main() {
  runApp(const RvDashboardApp());
}

class RvDashboardApp extends StatelessWidget {
  const RvDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RV-C Dashboard',
      debugShowCheckedModeBanner: false,
      theme: buildCabinTheme(),
      home: const _AppShell(),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final RvcService _service = RvcService();
  bool _connected = false;
  int _pageIndex = 0;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void _onConnected() => setState(() => _connected = true);

  @override
  Widget build(BuildContext context) {
    if (!_connected) {
      return Scaffold(
        backgroundColor: CabinPalette.darkWood,
        body: ConnectionScreen(service: _service, onConnected: _onConnected),
      );
    }

    return Scaffold(
      backgroundColor: CabinPalette.darkWood,
      body: _buildPage(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pageIndex,
        onDestinationSelected: (i) => setState(() => _pageIndex = i),
        backgroundColor: CabinPalette.midWood,
        indicatorColor: CabinPalette.copper.withValues(alpha: 0.3),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.battery_charging_full_outlined),
            selectedIcon: Icon(Icons.battery_charging_full),
            label: 'Power',
          ),
          NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: 'Tanks',
          ),
          NavigationDestination(
            icon: Icon(Icons.thermostat_outlined),
            selectedIcon: Icon(Icons.thermostat),
            label: 'Climate',
          ),
          NavigationDestination(
            icon: Icon(Icons.lightbulb_outlined),
            selectedIcon: Icon(Icons.lightbulb),
            label: 'Lighting',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Systems',
          ),
          NavigationDestination(
            icon: Icon(Icons.device_hub_outlined),
            selectedIcon: Icon(Icons.device_hub),
            label: 'Bus',
          ),
        ],
      ),
    );
  }

  Widget _buildPage() {
    return switch (_pageIndex) {
      0 => PowerScreen(service: _service),
      1 => TanksScreen(service: _service),
      2 => ClimateScreen(service: _service),
      3 => LightingScreen(service: _service),
      4 => SystemsScreen(service: _service),
      5 => BusScreen(service: _service),
      _ => PowerScreen(service: _service),
    };
  }
}
