// Entry point for the NMEA 2000 multi-function instrument display.
//
// Connects to a CAN bus (or runs in demo mode), decodes NMEA 2000 PGNs,
// and renders gauges and readouts on multiple pages. A NavigationBar at
// the bottom switches between Nav, Wind, Depth, Engine, Electrical,
// Heading, and Bus pages.

import 'package:flutter/material.dart';

import 'screens/bus_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/depth_screen.dart';
import 'screens/electrical_screen.dart';
import 'screens/engine_screen.dart';
import 'screens/heading_screen.dart';
import 'screens/nav_screen.dart';
import 'screens/wind_screen.dart';
import 'services/n2k_service.dart';
import 'theme/maritime_theme.dart';

void main() {
  runApp(const InstrumentDisplayApp());
}

class InstrumentDisplayApp extends StatelessWidget {
  const InstrumentDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NMEA 2000 Instrument Display',
      debugShowCheckedModeBanner: false,
      theme: buildMaritimeTheme(),
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
  final N2kService _service = N2kService();
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
        backgroundColor: MaritimePalette.deepHull,
        body: ConnectionScreen(service: _service, onConnected: _onConnected),
      );
    }

    return Scaffold(
      backgroundColor: MaritimePalette.deepHull,
      body: _buildPage(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pageIndex,
        onDestinationSelected: (i) => setState(() => _pageIndex = i),
        backgroundColor: MaritimePalette.midHull,
        indicatorColor: MaritimePalette.brass.withValues(alpha: 0.3),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.navigation_outlined),
            selectedIcon: Icon(Icons.navigation),
            label: 'Nav',
          ),
          NavigationDestination(
            icon: Icon(Icons.air_outlined),
            selectedIcon: Icon(Icons.air),
            label: 'Wind',
          ),
          NavigationDestination(
            icon: Icon(Icons.water_outlined),
            selectedIcon: Icon(Icons.water),
            label: 'Depth',
          ),
          NavigationDestination(
            icon: Icon(Icons.engineering_outlined),
            selectedIcon: Icon(Icons.engineering),
            label: 'Engine',
          ),
          NavigationDestination(
            icon: Icon(Icons.electric_bolt_outlined),
            selectedIcon: Icon(Icons.electric_bolt),
            label: 'Elec',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Heading',
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
      0 => NavScreen(service: _service),
      1 => WindScreen(service: _service),
      2 => DepthScreen(service: _service),
      3 => EngineScreen(service: _service),
      4 => ElectricalScreen(service: _service),
      5 => HeadingScreen(service: _service),
      6 => BusScreen(service: _service),
      _ => NavScreen(service: _service),
    };
  }
}
