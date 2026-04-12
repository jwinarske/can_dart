// Entry point for the Flutter helm dashboard.
//
// Loads ThrottleStandardIDs.dbc (shipped as a Flutter asset) at startup,
// constructs a ThrottleService around it, and hands that service to the
// connection or helm screen. Every widget references signals by their DBC
// name, so swapping the .dbc file and hot-restarting is enough to track
// schema changes — no regenerated code.
//
// The whole UI renders inside a fixed 480×272 logical viewport — the
// native resolution of the target Winstar WF43HSIAEDNNB display — and a
// FittedBox scales that up to fill whatever window the host provides.

import 'package:flutter/material.dart';

import 'can/boat_dbc.dart';
import 'can/boat_dbc_asset_loader.dart';
import 'screens/connection_screen.dart';
import 'screens/helm_screen.dart';
import 'services/throttle_service.dart';
import 'theme/maritime_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbc = await loadBoatDbcFromAsset();
  runApp(ThrottleApp(dbc: dbc));
}

class ThrottleApp extends StatelessWidget {
  const ThrottleApp({super.key, required this.dbc});

  final BoatDbc dbc;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Throttle UI',
      debugShowCheckedModeBanner: false,
      theme: buildMaritimeTheme(),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: AspectRatio(
            aspectRatio: kPhysicalDisplaySize.aspectRatio,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: kPhysicalDisplaySize.width,
                height: kPhysicalDisplaySize.height,
                child: _AppShell(dbc: dbc),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell({required this.dbc});

  final BoatDbc dbc;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  late final ThrottleService _service = ThrottleService(widget.dbc);
  bool _connected = false;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void _onConnected() => setState(() => _connected = true);

  @override
  Widget build(BuildContext context) {
    if (!_connected) {
      return ConnectionScreen(service: _service, onConnected: _onConnected);
    }
    return HelmScreen(service: _service);
  }
}
