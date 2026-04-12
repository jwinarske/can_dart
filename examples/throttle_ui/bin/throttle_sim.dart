// throttle_sim — synthetic Throttle CAN traffic for vcan validation of the
// throttle_ui Flutter app.
//
// What it does:
//   * Parses ThrottleStandardIDs.dbc from disk (NOT via Flutter assets,
//     because this is a pure-Dart CLI — runs via `dart run`).
//   * Opens a raw CAN socket (defaults to vcan0) via the can_socket
//     package, exactly like charger_sim does.
//   * Periodically encodes HELM_00 / HELM_01 / POS_RAPID / COG_SOG_RAPID
//     frames using the parsed DBC signal layouts — so any schema change
//     (bit widths, factors, new signals) flows through automatically.
//   * Listens for HELM_CMD frames from the dashboard, decodes the
//     AUX_Relay_Cmd and Boat_Mode signals, and reflects them in the
//     simulated boat state (so toggling AUX/DRIVE in the UI moves real
//     numbers on the bus).
//
// Run it:
//   sudo modprobe vcan && sudo ip link add dev vcan0 type vcan && \
//   sudo ip link set up vcan0
//   dart run throttle_ui:throttle_sim --interface vcan0
//
// Then start the Flutter app and pick `vcan0` on the connection screen.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:can_dbc/can_dbc.dart';
import 'package:can_socket/can_socket.dart';

import 'package:throttle_ui/can/boat_dbc.dart';

const String _usage = '''
throttle_sim — drives synthetic Throttle CAN frames onto a (v)CAN interface.

Usage:
  dart run throttle_ui:throttle_sim [options]

Options:
  -i, --interface <name>   CAN interface to write to (default: vcan0)
  -r, --rate-hz <hz>       Base tick rate; HELM_00 and COG_SOG_RAPID publish
                           at this rate (default: 10)
      --dbc <path>         Path to ThrottleStandardIDs.dbc (defaults to the
                           file bundled under assets/dbc/)
      --quiet              Don't log every transmitted frame
  -h, --help               Show this help

Bring vcan0 up on Linux first:
  sudo modprobe vcan
  sudo ip link add dev vcan0 type vcan
  sudo ip link set up vcan0
''';

class _Options {
  String interface_ = 'vcan0';
  int rateHz = 10;
  String? dbcPath;
  bool quiet = false;
}

_Options _parseArgs(List<String> args) {
  final opts = _Options();
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? takeValue(String long, [String? short]) {
      if (a == long || (short != null && a == short)) {
        if (i + 1 >= args.length) {
          stderr.writeln('Missing value for $a');
          exit(64);
        }
        return args[++i];
      }
      if (a.startsWith('$long=')) return a.substring(long.length + 1);
      return null;
    }

    if (a == '-h' || a == '--help') {
      stdout.write(_usage);
      exit(0);
    }
    if (a == '--quiet') {
      opts.quiet = true;
      continue;
    }
    final iface = takeValue('--interface', '-i');
    if (iface != null) {
      opts.interface_ = iface;
      continue;
    }
    final rate = takeValue('--rate-hz', '-r');
    if (rate != null) {
      final parsed = int.tryParse(rate);
      if (parsed == null || parsed <= 0) {
        stderr.writeln('Invalid --rate-hz value: $rate');
        exit(64);
      }
      opts.rateHz = parsed;
      continue;
    }
    final dbc = takeValue('--dbc');
    if (dbc != null) {
      opts.dbcPath = dbc;
      continue;
    }
    stderr.writeln('Unknown argument: $a');
    stderr.writeln(_usage);
    exit(64);
  }
  return opts;
}

/// Mutable simulation state — shared between the periodic emitter and the
/// HELM_CMD reader.
class _SimState {
  // Boat kinematics.
  double throttle = 0.0; // DBC-domain value (-5.12..5.11)
  double sog = 0.0; // m/s
  double cog = pi; // radians, 0..2π (pointing south)
  double lat = 47.6062; // Seattle. Of course.
  double lon = -122.3321;

  // Most-recent inbound command state.
  bool auxRelayCmd = false;
  bool drivingMode = false;

  int ticks = 0;
}

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);

  // ── Load DBC ──
  final dbcPath = opts.dbcPath ?? _defaultDbcPath();
  final dbcFile = File(dbcPath);
  if (!dbcFile.existsSync()) {
    stderr.writeln('DBC file not found: $dbcPath');
    stderr.writeln('Pass --dbc <path> to override.');
    exit(1);
  }
  final DbcDatabase parsed;
  try {
    parsed = DbcParser().parse(dbcFile.readAsStringSync());
  } on DbcParseException catch (e) {
    stderr.writeln('Failed to parse $dbcPath: $e');
    exit(1);
  }
  final dbc = BoatDbc.fromDatabase(parsed);

  // Grab handles for the messages we're going to emit. If any are missing
  // we abort rather than silently drop — the simulator is supposed to
  // exercise the whole pipeline, so a missing signal is a hard error for
  // this tool even though the UI tolerates it.
  final helm00 = _requireMsg(dbc, 'HELM_00');
  final helm01 = _requireMsg(dbc, 'HELM_01');
  final cogSog = _requireMsg(dbc, 'COG_SOG_RAPID');
  final posRapid = _requireMsg(dbc, 'POS_RAPID');
  final helmCmd = _requireMsg(dbc, 'HELM_CMD');

  // ── Open socket ──
  late final CanSocket socket;
  try {
    socket = CanSocket(opts.interface_);
  } on CanSocketException catch (e) {
    stderr.writeln('Failed to open ${opts.interface_}: $e');
    stderr.writeln('Is the interface up? Try:');
    stderr.writeln('  sudo ip link set up ${opts.interface_}');
    exit(1);
  }

  final state = _SimState();
  final rng = Random();

  stdout.writeln('throttle_sim → ${opts.interface_} @ ${opts.rateHz} Hz');
  stdout.writeln(
    '  DBC : $dbcPath '
    '(${parsed.messages.length} messages, ${parsed.signalCount} signals)',
  );
  stdout.writeln('  TX  : HELM_00 HELM_01 POS_RAPID COG_SOG_RAPID');
  stdout.writeln('  RX  : HELM_CMD (AUX_Relay_Cmd, Boat_Mode)');
  stdout.writeln('Ctrl-C to stop.');

  // ── Inbound HELM_CMD listener ──
  final cmdSub = socket.frameStream.listen(
    (frame) {
      if (frame.id != helmCmd.id) return;
      if (frame.data.length < helmCmd.length) return;
      final decoded = dbc.decodeAll(helmCmd, Uint8List.fromList(frame.data));
      final aux = decoded['AUX_Relay_Cmd'];
      final mode = decoded['Boat_Mode'];
      if (aux != null) state.auxRelayCmd = aux > 0.5;
      if (mode != null) state.drivingMode = mode > 0.5;
      if (!opts.quiet) {
        stdout.writeln(
          '  ⇐ HELM_CMD AUX=${state.auxRelayCmd ? "ON" : "OFF"} '
          'MODE=${state.drivingMode ? "DRIVING" : "CHARGING"}',
        );
      }
    },
    onError: (e) {
      stderr.writeln('frameStream error: $e');
    },
  );

  // ── Periodic emitter ──
  void send(int id, Uint8List data, {bool extended = false, String? label}) {
    final frame = CanFrame(id: id, data: data, isExtended: extended);
    try {
      socket.send(frame);
      if (!opts.quiet && label != null) {
        stdout.writeln('  → $label');
      }
    } on CanSocketException catch (e) {
      stderr.writeln('send($label) failed: $e');
    }
  }

  void tick(Timer t) {
    state.ticks++;

    // Drive kinematics: throttle slowly oscillates, SOG lags behind,
    // heading meanders, position advances along current heading.
    state.throttle = 1.5 + sin(state.ticks * 0.02) * 1.3;
    final target = state.throttle * 2.5;
    state.sog += (target - state.sog) * 0.05;
    if (state.sog < 0) state.sog = 0;
    state.cog = (pi + sin(state.ticks * 0.005) * 0.4) % (2 * pi);
    state.lat = (state.lat + state.sog * cos(state.cog) * 1e-6).clamp(
      -89.9,
      89.9,
    );
    state.lon = (state.lon + state.sog * sin(state.cog) * 1e-6).clamp(
      -179.9,
      179.9,
    );

    // HELM_00: throttle + fault flags + relay state. Every tick.
    send(
      helm00.id,
      dbc.packMessage(helm00, {
        'Throttle': state.throttle,
        'Tilt_Req': 0,
        'Key': 1,
        'StartStop': 1,
        'MAIN_Relay_Status': 1,
        'AUX_Relay_Status': state.auxRelayCmd ? 1 : 0,
        'HVIL_Relay_Status': state.drivingMode ? 1 : 0,
        'HVIL_Return_Sense': state.drivingMode ? 1 : 0,
        'Estop': 0,
        'Sys_Timer': (state.ticks % 65536).toDouble(),
        'Flt_DataUpload': (rng.nextDouble() < 0.01)
            ? 1
            : 0, // occasional flicker
      }),
      label: 'HELM_00',
    );

    // COG_SOG_RAPID. Every tick.
    send(
      cogSog.id,
      dbc.packMessage(cogSog, {
        'SOG': state.sog,
        'COG': state.cog,
        'COG_Reference': 0, // TRUE north
      }),
      label: 'COG_SOG_RAPID',
    );

    // POS_RAPID. Half rate — GPS fix is slower.
    if (state.ticks % 5 == 0) {
      send(
        posRapid.id,
        dbc.packMessage(posRapid, {
          'Latitude': state.lat,
          'Longitude': state.lon,
        }),
        label: 'POS_RAPID',
      );
    }

    // HELM_01 (ID + SW version). 1 Hz.
    if (state.ticks % 10 == 0) {
      send(
        helm01.id,
        dbc.packMessage(helm01, {
          'SW_Major': 2,
          'SW_Minor': 1,
          'Serial_Number': 1176,
        }),
        label: 'HELM_01',
      );
    }
  }

  final periodMs = (1000 / opts.rateHz).round();
  final timer = Timer.periodic(Duration(milliseconds: periodMs), tick);

  // ── Graceful shutdown ──
  Future<void> shutdown(ProcessSignal sig) async {
    stdout.writeln('\nReceived $sig, shutting down…');
    timer.cancel();
    await cmdSub.cancel();
    socket.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);
}

DbcMessage _requireMsg(BoatDbc dbc, String name) {
  final msg = dbc.message(name);
  if (msg == null) {
    stderr.writeln(
      'DBC is missing required message "$name" — simulator cannot run.',
    );
    exit(1);
  }
  return msg;
}

/// Default DBC location: next to this script under assets/dbc/. Works for
/// both `dart run throttle_ui:throttle_sim` (run from the example root)
/// and `dart run bin/throttle_sim.dart` (run from any cwd inside the
/// package).
String _defaultDbcPath() {
  // Prefer the asset path relative to the current working directory.
  final relative = File('assets/dbc/ThrottleStandardIDs.dbc').absolute.path;
  if (File(relative).existsSync()) return relative;

  // Fallback: resolve relative to this script's directory.
  final scriptDir = File.fromUri(Platform.script).parent;
  final next = File(
    '${scriptDir.path}/../assets/dbc/ThrottleStandardIDs.dbc',
  ).absolute.path;
  return next;
}
