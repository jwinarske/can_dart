// bin/load_node.dart — J1939 stack load-testing node.
//
// A single long-running instance that claims an address on a SocketCAN
// interface and runs a mixed traffic profile (single-frame unicast, BAM
// broadcast, PGN requests, DM1 inject/clear) until SIGINT or SIGTERM.
//
// Launch N of these against one vcan interface to stress the stack; the
// companion launcher lives at tool/run_load_nodes.sh.
//
// Usage:
//   dart run j1939:load_node --id=<N> [options]
//
// Options:
//   --id=<int>            Instance id. Required. Drives NAME.identity_number
//                         and (unless --address is given) the preferred SA.
//                         Must fit in 21 bits.
//   --iface=<name>        SocketCAN interface. Default: vcan0.
//   --address=<0xNN|int>  Override preferred SA. Default: 0x80 + id mod 0x7E.
//                         Must be in [0x00, 0xFD]. The stack will re-arbitrate
//                         automatically if outranked (J1939/81).
//   --tx-hz=<float>       Unicast heartbeat rate. Default: 20.
//   --bam-period=<ms>     BAM broadcast period. Default: 2000.
//   --audit-period=<ms>   Address-claim audit request period. Default: 5000.
//   --dm1-period=<ms>     DM1 inject/clear cycle. Default: 3000.
//   --peers=<int>         # of addresses in the unicast rotation. Default: 64.
//   --stats-period=<ms>   Stats print period. Default: 5000.
//
// Exit codes:
//   0   clean shutdown
//   1   startup / FFI create failure
//   2   address claim failed (bus full or outranked everywhere)
//   64  CLI usage error

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:j1939/j1939.dart';

// ── CLI parsing ───────────────────────────────────────────────────────────────

class _Opts {
  _Opts({
    required this.id,
    required this.iface,
    required this.preferredAddress,
    required this.txHz,
    required this.bamPeriod,
    required this.auditPeriod,
    required this.dm1Period,
    required this.peers,
    required this.statsPeriod,
  });

  final int id;
  final String iface;
  final int preferredAddress;
  final double txHz;
  final Duration bamPeriod;
  final Duration auditPeriod;
  final Duration dm1Period;
  final int peers;
  final Duration statsPeriod;

  static _Opts parse(List<String> args) {
    int? id;
    String iface = 'vcan0';
    int? address;
    double txHz = 20;
    int bamMs = 2000;
    int auditMs = 5000;
    int dm1Ms = 3000;
    int peers = 64;
    int statsMs = 5000;

    for (final a in args) {
      final eq = a.indexOf('=');
      if (!a.startsWith('--') || eq < 0) {
        throw ArgumentError('bad arg "$a" (expected --key=value)');
      }
      final k = a.substring(2, eq);
      final v = a.substring(eq + 1);
      if (k == 'id') {
        id = int.parse(v);
      } else if (k == 'iface') {
        iface = v;
      } else if (k == 'address') {
        address = _parseIntAny(v);
      } else if (k == 'tx-hz') {
        txHz = double.parse(v);
      } else if (k == 'bam-period') {
        bamMs = int.parse(v);
      } else if (k == 'audit-period') {
        auditMs = int.parse(v);
      } else if (k == 'dm1-period') {
        dm1Ms = int.parse(v);
      } else if (k == 'peers') {
        peers = int.parse(v);
      } else if (k == 'stats-period') {
        statsMs = int.parse(v);
      } else {
        throw ArgumentError('unknown option: --$k');
      }
    }

    final idVal = id;
    if (idVal == null) {
      throw ArgumentError('--id=<int> is required');
    }
    if (idVal < 0 || idVal > 0x1FFFFF) {
      throw ArgumentError('--id must fit in 21 bits (NAME.identity_number)');
    }

    final addr = address ?? (0x80 + (idVal % 0x7E));
    if (addr < 0 || addr >= 0xFE) {
      throw ArgumentError(
          '--address must be in [0x00, 0xFD]; got 0x${addr.toRadixString(16)}');
    }

    if (peers < 1) {
      throw ArgumentError('--peers must be >= 1');
    }
    if (txHz <= 0 || txHz > 1000) {
      throw ArgumentError('--tx-hz must be in (0, 1000]');
    }

    return _Opts(
      id: idVal,
      iface: iface,
      preferredAddress: addr,
      txHz: txHz,
      bamPeriod: Duration(milliseconds: bamMs),
      auditPeriod: Duration(milliseconds: auditMs),
      dm1Period: Duration(milliseconds: dm1Ms),
      peers: peers,
      statsPeriod: Duration(milliseconds: statsMs),
    );
  }

  static int _parseIntAny(String v) =>
      (v.startsWith('0x') || v.startsWith('0X'))
          ? int.parse(v.substring(2), radix: 16)
          : int.parse(v);
}

// ── Stats ─────────────────────────────────────────────────────────────────────

class _Stats {
  int rxFrames = 0;
  int txSingle = 0;
  int bamCompleted = 0;
  int bamFailed = 0;
  int requests = 0;
  int dm1Received = 0;
  int claimEvents = 0;
  int errors = 0;
}

// ── main ──────────────────────────────────────────────────────────────────────

Future<void> main(List<String> argv) async {
  final _Opts opts;
  try {
    opts = _Opts.parse(argv);
  } on ArgumentError catch (e) {
    stderr.writeln('load_node: ${e.message}');
    stderr.writeln('usage: dart run j1939:load_node --id=<N> [options]');
    exit(64);
  } on FormatException catch (e) {
    stderr.writeln('load_node: bad numeric value (${e.message})');
    stderr.writeln('usage: dart run j1939:load_node --id=<N> [options]');
    exit(64);
  }

  final stats = _Stats();
  final shutdown = Completer<void>();
  final rand = math.Random(opts.id);

  String tagPre(int sa) =>
      '[id=${opts.id} sa=0x${sa.toRadixString(16).padLeft(2, '0').toUpperCase()}]';

  void requestShutdown(String reason) {
    if (!shutdown.isCompleted) {
      stderr.writeln('${tagPre(0)} shutting down: $reason');
      shutdown.complete();
    }
  }

  // Graceful-shutdown plumbing. unawaited: these listen for the whole run.
  unawaited(ProcessSignal.sigint
      .watch()
      .first
      .then((_) => requestShutdown('SIGINT')));
  unawaited(ProcessSignal.sigterm
      .watch()
      .first
      .then((_) => requestShutdown('SIGTERM')));

  // ── Create the ECU (spawns C++ RX + ASIO threads) ─────────────────────
  final J1939Ecu ecu;
  try {
    ecu = J1939Ecu.create(
      ifname: opts.iface,
      address: opts.preferredAddress,
      identityNumber: opts.id,
      manufacturerCode: 0x7FF, // reserved / self-assigned (dev/test)
      industryGroup: 0,
    );
  } on StateError catch (e) {
    stderr.writeln('${tagPre(opts.preferredAddress)} create failed: $e');
    exit(1);
  }

  // ── Wait for the initial address-claim decision ────────────────────────
  //
  // Subscribing to addressEvents synchronously before awaiting ensures we
  // don't race with the first claim event from the C++ RX thread, which is
  // posted ~250 ms after j1939_create returns.
  final int claimedSa;
  try {
    final claimEvent =
        await ecu.addressEvents.first.timeout(const Duration(seconds: 3));
    switch (claimEvent) {
      case AddressClaimed(:final address):
        claimedSa = address;
      case AddressClaimFailed():
        stderr.writeln('${tagPre(opts.preferredAddress)} '
            'address claim failed (bus full or outranked everywhere)');
        ecu.dispose();
        exit(2);
      default:
        // addressEvents only emits AddressClaimed / AddressClaimFailed.
        throw StateError('unexpected addressEvents value: $claimEvent');
    }
  } on TimeoutException {
    stderr.writeln('${tagPre(opts.preferredAddress)} address claim timed out');
    ecu.dispose();
    exit(2);
  }

  final tag = tagPre(claimedSa);
  stdout.writeln('$tag claimed address '
      '(preferred=0x${opts.preferredAddress.toRadixString(16).padLeft(2, '0').toUpperCase()})');

  // ── Event handlers for the lifetime of the run ─────────────────────────
  final subs = <StreamSubscription<void>>[];

  subs.add(ecu.events.listen((e) {
    switch (e) {
      case FrameReceived():
        stats.rxFrames++;
      case AddressClaimed():
        // Subsequent claims (e.g. from audit responses) — informational.
        stats.claimEvents++;
      case AddressClaimFailed():
        // Post-initial-claim failure: treat as fatal for this instance.
        requestShutdown('address revoked by peer');
      case EcuError(:final errorCode):
        stats.errors++;
        stderr.writeln('$tag EcuError errno=$errorCode');
      case Dm1Received(:final source, :final spn, :final fmi):
        stats.dm1Received++;
        stdout.writeln('$tag DM1 from '
            '0x${source.toRadixString(16).padLeft(2, '0').toUpperCase()} '
            'spn=$spn fmi=$fmi');
    }
  }) as StreamSubscription<void>);

  // ── Timer: unicast heartbeat (single-frame, 6 bytes) ───────────────────
  //
  // PGN ProprietaryA (0xEF00) is PDU1 (destination-specific) — exercises
  // the unicast single-frame TX path. Rotates through the peer address
  // range; skips ourselves.
  //
  // Payload: [version=1][our-id-low][seq32 LE]
  var seq = 0;
  final heartbeatInterval =
      Duration(microseconds: (1e6 / opts.txHz).round().clamp(1000, 1000000));
  subs.add(
    Stream<void>.periodic(heartbeatInterval).listen((_) async {
      if (shutdown.isCompleted) return;
      final destSa = 0x80 + (seq % opts.peers) % 0x7E;
      seq++;
      if (destSa == claimedSa) return;
      final buf = Uint8List(6);
      buf[0] = 0x01;
      buf[1] = opts.id & 0xFF;
      buf[2] = (seq) & 0xFF;
      buf[3] = (seq >> 8) & 0xFF;
      buf[4] = (seq >> 16) & 0xFF;
      buf[5] = (seq >> 24) & 0xFF;
      try {
        await ecu.send(Pgn.proprietaryA, priority: 6, dest: destSa, data: buf);
        stats.txSingle++;
      } on StateError {
        stats.errors++;
      }
    }),
  );

  // ── Timer: BAM broadcast (multi-packet) ────────────────────────────────
  //
  // PGN SoftwareId (0xFEDA) is PDU2 (broadcast) — exercises the BAM
  // coroutine path on the ASIO thread. Payload size jittered in [20, 60]
  // so the transport layer sees varied N_packets.
  subs.add(
    Stream<void>.periodic(opts.bamPeriod).listen((_) async {
      if (shutdown.isCompleted) return;
      final len = 20 + rand.nextInt(41); // 20..60
      final buf = Uint8List(len);
      for (var i = 0; i < len; i++) {
        buf[i] = (opts.id + i) & 0xFF;
      }
      try {
        await ecu.send(Pgn.softwareId,
            priority: 6, dest: kBroadcast, data: buf);
        stats.bamCompleted++;
      } on StateError catch (e) {
        stats.bamFailed++;
        stderr.writeln('$tag BAM failed: $e');
      }
    }),
  );

  // ── Timer: address-claim audit (broadcast request for PGN EE00) ────────
  subs.add(
    Stream<void>.periodic(opts.auditPeriod).listen((_) {
      if (shutdown.isCompleted) return;
      try {
        ecu.sendRequest(kBroadcast, Pgn.addressClaimed);
        stats.requests++;
      } on StateError catch (e) {
        stderr.writeln('$tag audit request failed: $e');
        stats.errors++;
      }
    }),
  );

  // ── Timer: DM1 inject / clear cycle ────────────────────────────────────
  //
  // SPN/FMI derived from instance id so peers can distinguish the source
  // in their Dm1Received events.
  final dm1Spn = 100 + (opts.id % 1000);
  final dm1Fmi = 1 + (opts.id % 31);
  var dm1Active = false;
  subs.add(
    Stream<void>.periodic(opts.dm1Period).listen((_) {
      if (shutdown.isCompleted) return;
      if (dm1Active) {
        ecu.clearDm1Faults();
      } else {
        ecu.addDm1Fault(spn: dm1Spn, fmi: dm1Fmi, occurrence: 1);
      }
      dm1Active = !dm1Active;
    }),
  );

  // ── Timer: periodic stats print ────────────────────────────────────────
  var lastRx = 0;
  var lastTx = 0;
  var lastBam = 0;
  subs.add(
    Stream<void>.periodic(opts.statsPeriod).listen((_) {
      if (shutdown.isCompleted) return;
      final rxD = stats.rxFrames - lastRx;
      final txD = stats.txSingle - lastTx;
      final bamD = stats.bamCompleted - lastBam;
      lastRx = stats.rxFrames;
      lastTx = stats.txSingle;
      lastBam = stats.bamCompleted;
      final win = (opts.statsPeriod.inMilliseconds / 1000).toStringAsFixed(0);
      stdout.writeln('$tag stats/${win}s rx=$rxD tx=$txD bam=$bamD '
          '| totals rx=${stats.rxFrames} tx=${stats.txSingle} '
          'bam=${stats.bamCompleted} bamErr=${stats.bamFailed} '
          'req=${stats.requests} dm1=${stats.dm1Received} '
          'claims=${stats.claimEvents} errs=${stats.errors}');
    }),
  );

  // ── Run until shutdown ─────────────────────────────────────────────────
  stdout.writeln('$tag running — Ctrl-C or SIGTERM to stop');
  await shutdown.future;

  // ── Teardown ───────────────────────────────────────────────────────────
  for (final s in subs) {
    await s.cancel();
  }
  ecu.clearDm1Faults();
  ecu.dispose();
  stdout.writeln('$tag final totals rx=${stats.rxFrames} tx=${stats.txSingle} '
      'bam=${stats.bamCompleted} bamErr=${stats.bamFailed} '
      'req=${stats.requests} dm1=${stats.dm1Received} '
      'claims=${stats.claimEvents} errs=${stats.errors}');
}
