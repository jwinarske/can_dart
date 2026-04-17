// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

// Nmea2000Ecu — NMEA 2000 device layer on top of J1939Ecu.
//
// Wraps J1939Ecu with marine NAME defaults (industry group 4, device class
// 120=Display, device function 130=Display), registers Fast Packet PGNs
// with the C++ transport layer, transmits a periodic Heartbeat (PGN 126993),
// and auto-responds to ISO Requests for Product Information (126996),
// Configuration Information (126998), and PGN List (126464).

import 'dart:async';
import 'dart:typed_data';

import 'package:j1939/j1939.dart';

import 'package:can_codec/can_codec.dart';
import 'group_function.dart';
import 'group_function_codec.dart';
import 'nmea2000_registry.dart';
import 'pgns/mandatory.dart';

/// NMEA 2000 device class constants (Appendix B).
class N2kDeviceClass {
  static const int display = 120;
}

/// NMEA 2000 device function constants (Appendix B).
class N2kDeviceFunction {
  static const int display = 130;
}

/// An NMEA 2000 ECU node with marine protocol defaults and mandatory PGN
/// auto-responder.
class Nmea2000Ecu {
  Nmea2000Ecu._({
    required J1939Ecu ecu,
    required this.registry,
    required this.modelId,
    required this.softwareVersion,
    required this.modelVersion,
    required this.modelSerialCode,
    required this.certificationLevel,
    required this.loadEquivalency,
  }) : _ecu = ecu;

  final J1939Ecu _ecu;

  /// The PGN definition registry for this ECU.
  final Nmea2000Registry registry;

  // Product Information fields (PGN 126996).
  final String modelId;
  final String softwareVersion;
  final String modelVersion;
  final String modelSerialCode;
  final int certificationLevel;
  final int loadEquivalency;

  Timer? _heartbeatTimer;
  StreamSubscription<FrameReceived>? _requestSub;
  StreamSubscription<FrameReceived>? _groupFunctionSub;
  int _heartbeatSeq = 0;
  int _uniqueId = 0;
  bool _disposed = false;

  // Group Function client: pending request → completer map.
  // Key: "$targetPgn:$replyFunctionCode:$sourceSa" or "$targetPgn:$replyFunctionCode"
  final _pendingGf = <String, Completer<Uint8List>>{};

  // Group Function server: per-function-code handlers.
  GroupFunctionHandler? _readFieldsHandler;
  GroupFunctionHandler? _writeFieldsHandler;
  GroupFunctionHandler? _commandHandler;

  // ── Factory ────────────────────────────────────────────────────────────────

  /// Create an NMEA 2000 display node.
  ///
  /// Registers Fast Packet PGNs with the C++ transport layer, creates a
  /// J1939Ecu with marine NAME defaults, waits for address claim, starts
  /// the heartbeat timer, and registers the mandatory PGN auto-responder.
  ///
  /// Throws [StateError] on native create failure.
  /// Throws [TimeoutException] if address claim doesn't settle within
  /// [claimTimeout].
  static Future<Nmea2000Ecu> create({
    required String ifname,
    int address = 0x80,
    int identityNumber = 1,
    int manufacturerCode = 2046, // Self/test
    int deviceClass = N2kDeviceClass.display,
    int deviceFunction = N2kDeviceFunction.display,
    String modelId = 'N2K Display',
    String softwareVersion = '0.1.0',
    String modelVersion = '',
    String modelSerialCode = '',
    int certificationLevel = 0,
    int loadEquivalency = 1,
    Nmea2000Registry? registry,
    Duration heartbeatPeriod = const Duration(seconds: 60),
    Duration claimTimeout = const Duration(seconds: 3),
  }) async {
    final reg = registry ?? Nmea2000Registry.standard();

    // Register all Fast Packet PGNs with the C++ layer so the RX loop
    // routes them through the Fast Packet reassembler.
    for (final pgn in reg.fastPacketPgns) {
      J1939Ecu.setPgnTransport(pgn, 1); // 1 = fast_packet
    }

    final ecu = J1939Ecu.createFull(
      ifname: ifname,
      address: address,
      identityNumber: identityNumber,
      manufacturerCode: manufacturerCode,
      industryGroup: 4, // Marine
      deviceClass: deviceClass,
      deviceFunction: deviceFunction,
    );

    final n2k = Nmea2000Ecu._(
      ecu: ecu,
      registry: reg,
      modelId: modelId,
      softwareVersion: softwareVersion,
      modelVersion: modelVersion,
      modelSerialCode: modelSerialCode,
      certificationLevel: certificationLevel,
      loadEquivalency: loadEquivalency,
    );

    // Wait for address claim before starting timers.
    final claimEvent = await ecu.addressEvents.first.timeout(claimTimeout);
    if (claimEvent is AddressClaimFailed) {
      ecu.dispose();
      throw StateError('NMEA 2000 address claim failed on "$ifname"');
    }

    n2k._startHeartbeat(heartbeatPeriod);
    n2k._startAutoResponder();
    n2k._startGroupFunctionListener();
    return n2k;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// The underlying J1939Ecu for direct frame access.
  J1939Ecu get ecu => _ecu;

  /// All ECU events (frames, claims, errors, DM1).
  Stream<J1939Event> get events => _ecu.events;

  /// Reassembled frames (single-frame and Fast Packet).
  Stream<FrameReceived> get frames => _ecu.frames;

  /// Frames matching a specific PGN.
  Stream<FrameReceived> framesForPgn(int pgn) => _ecu.framesForPgn(pgn);

  /// Current claimed address (0xFE if not claimed).
  int get address => _ecu.address;

  /// Whether an address has been successfully claimed.
  bool get addressClaimed => _ecu.addressClaimed;

  /// Send a PGN. Transport (single / FP / BAM) is selected automatically
  /// by the C++ layer based on the registered PGN transport type.
  Future<void> send(int pgn,
      {required int priority, required int dest, required Uint8List data}) {
    return _ecu.send(pgn, priority: priority, dest: dest, data: data);
  }

  /// Send an ISO Request (PGN 0xEA00) for [requestedPgn].
  void sendRequest(int dest, int requestedPgn) {
    _ecu.sendRequest(dest, requestedPgn);
  }

  // ── Heartbeat ──────────────────────────────────────────────────────────────

  void _startHeartbeat(Duration period) {
    // Send immediately, then repeat.
    _sendHeartbeat();
    _heartbeatTimer = Timer.periodic(period, (_) => _sendHeartbeat());
  }

  void _sendHeartbeat() {
    if (_disposed) return;
    final data = encode({
      'dataTransmitOffset': 600000, // 60s × 10 ms resolution
      'sequenceCounter': _heartbeatSeq & 0xFF,
      'class1CanState': 0, // normal
      'class2CanState': 0, // normal
      'noProductInfoYet': 0,
    }, heartbeatPgn);
    _heartbeatSeq++;
    try {
      _ecu.send(126993, priority: 7, dest: kBroadcast, data: data);
    } catch (_) {
      // Heartbeat failure is non-fatal.
    }
  }

  // ── Auto-responder ─────────────────────────────────────────────────────────

  void _startAutoResponder() {
    // Listen for ISO Request frames (PGN 59904 = 0xEA00) directed at us
    // or broadcast.
    _requestSub = _ecu.framesForPgn(Pgn.requestPgn).listen((frame) {
      if (frame.data.length < 3) return;
      final requestedPgn =
          frame.data[0] | (frame.data[1] << 8) | (frame.data[2] << 16);
      _handleIsoRequest(requestedPgn, frame.source);
    });
  }

  void _handleIsoRequest(int requestedPgn, int requester) {
    switch (requestedPgn) {
      case 126996:
        _sendProductInfo();
      case 126998:
        _sendConfigInfo();
      case 126464:
        _sendPgnList();
      default:
        _sendIsoAck(requestedPgn, requester, nack: true);
    }
  }

  void _sendProductInfo() {
    final data = encode({
      'nmea2000Version': 2100, // NMEA 2000 version 2.100
      'productCode': 0xFFFF, // unknown
      'modelId': modelId,
      'softwareVersionCode': softwareVersion,
      'modelVersion': modelVersion,
      'modelSerialCode': modelSerialCode,
      'certificationLevel': certificationLevel,
      'loadEquivalency': loadEquivalency,
    }, productInformationPgn);
    try {
      _ecu.send(126996, priority: 6, dest: kBroadcast, data: data);
    } catch (_) {}
  }

  void _sendConfigInfo() {
    final data = encode({
      'installationDescription1Length': 0,
      'installationDescription1': '',
      'installationDescription2Length': 0,
      'installationDescription2': '',
    }, configurationInformationPgn);
    try {
      _ecu.send(126998, priority: 6, dest: kBroadcast, data: data);
    } catch (_) {}
  }

  void _sendPgnList() {
    // PGN List (Transmit): first byte = 0 (transmit list), then 3-byte
    // LE PGN entries for every PGN in our registry.
    final pgns = registry.pgnNumbers.toList()..sort();
    final payload = Uint8List(1 + pgns.length * 3);
    payload[0] = 0; // transmit list
    for (var i = 0; i < pgns.length; i++) {
      final pgn = pgns[i];
      payload[1 + i * 3] = pgn & 0xFF;
      payload[2 + i * 3] = (pgn >> 8) & 0xFF;
      payload[3 + i * 3] = (pgn >> 16) & 0xFF;
    }
    try {
      _ecu.send(126464, priority: 6, dest: kBroadcast, data: payload);
    } catch (_) {}
  }

  void _sendIsoAck(int pgn, int dest, {required bool nack}) {
    final data = encode({
      'control': nack ? 1 : 0, // 0=ACK, 1=NAK
      'groupFunction': 0xFF,
      'addressAcknowledged': dest,
      'pgnAcknowledged': pgn,
    }, isoAcknowledgmentPgn);
    try {
      _ecu.send(59392, priority: 6, dest: dest, data: data);
    } catch (_) {}
  }

  // ── Group Function client ───────────────────────────────────────────────────

  /// Send a Command (function 1) to [targetSa] and wait for Acknowledge.
  ///
  /// [fields] are field-number/value pairs for the target PGN.
  /// Returns the parsed Acknowledge. Throws [TimeoutException] if no reply.
  Future<GroupFunctionAck> command({
    required int targetSa,
    required int pgn,
    required List<FieldPair> fields,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final payload = encodeCommand(pgn: pgn, fields: fields);
    final key = '$pgn:${GroupFunctionCode.acknowledge.value}:$targetSa';
    final completer = Completer<Uint8List>();
    _pendingGf[key] = completer;

    try {
      await _ecu.send(kGroupFunctionPgn,
          priority: 3, dest: targetSa, data: payload);
      final reply = await completer.future.timeout(timeout);
      return decodeAcknowledge(reply) ??
          GroupFunctionAck(pgn: pgn, pgnError: PgnErrorCode.pgnNotSupported);
    } on TimeoutException {
      _pendingGf.remove(key);
      rethrow;
    }
  }

  /// Send a Read Fields (function 3) request and wait for Read Fields Reply.
  ///
  /// [fieldNumbers] are 1-based field indices within the target PGN.
  Future<ReadFieldsReply> readFields({
    required int targetSa,
    required int pgn,
    required List<int> fieldNumbers,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final uid = (_uniqueId++) & 0xFF;
    final payload = encodeReadFields(
        pgn: pgn, uniqueId: uid, requestedFieldNumbers: fieldNumbers);
    final key = '$pgn:${GroupFunctionCode.readFieldsReply.value}:$targetSa';
    final completer = Completer<Uint8List>();
    _pendingGf[key] = completer;

    try {
      await _ecu.send(kGroupFunctionPgn,
          priority: 3, dest: targetSa, data: payload);
      final reply = await completer.future.timeout(timeout);
      return decodeReadFieldsReply(reply) ??
          ReadFieldsReply(pgn: pgn, fields: []);
    } on TimeoutException {
      _pendingGf.remove(key);
      rethrow;
    }
  }

  /// Send a Write Fields (function 5) request and wait for Write Fields Reply.
  ///
  /// [fields] are field-number/value pairs to write.
  Future<WriteFieldsReply> writeFields({
    required int targetSa,
    required int pgn,
    required List<FieldPair> fields,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final uid = (_uniqueId++) & 0xFF;
    final payload = encodeWriteFields(pgn: pgn, uniqueId: uid, fields: fields);
    final key = '$pgn:${GroupFunctionCode.writeFieldsReply.value}:$targetSa';
    final completer = Completer<Uint8List>();
    _pendingGf[key] = completer;

    try {
      await _ecu.send(kGroupFunctionPgn,
          priority: 3, dest: targetSa, data: payload);
      final reply = await completer.future.timeout(timeout);
      return decodeWriteFieldsReply(reply) ??
          WriteFieldsReply(pgn: pgn, fields: []);
    } on TimeoutException {
      _pendingGf.remove(key);
      rethrow;
    }
  }

  // ── Group Function server ─────────────────────────────────────────────────

  /// Register a handler for incoming Read Fields (function 3) requests.
  ///
  /// The handler receives a [GroupFunctionRequest] and should call
  /// [GroupFunctionRequest.replyWithFields] or [GroupFunctionRequest.reject].
  set onReadFields(GroupFunctionHandler? handler) =>
      _readFieldsHandler = handler;

  /// Register a handler for incoming Write Fields (function 5) requests.
  set onWriteFields(GroupFunctionHandler? handler) =>
      _writeFieldsHandler = handler;

  /// Register a handler for incoming Command (function 1) requests.
  set onCommand(GroupFunctionHandler? handler) => _commandHandler = handler;

  // ── Group Function listener ───────────────────────────────────────────────

  void _startGroupFunctionListener() {
    _groupFunctionSub =
        _ecu.framesForPgn(kGroupFunctionPgn).listen(_onGroupFunction);
  }

  void _onGroupFunction(FrameReceived frame) {
    if (_disposed || frame.data.isEmpty) return;
    final code = decodeFunctionCode(frame.data);
    if (code == null) return;
    final targetPgn = decodeTargetPgn(frame.data);

    switch (code) {
      // Replies to our client requests.
      case GroupFunctionCode.acknowledge:
        _completePending(
            '$targetPgn:${code.value}:${frame.source}', frame.data);
      case GroupFunctionCode.readFieldsReply:
        _completePending(
            '$targetPgn:${code.value}:${frame.source}', frame.data);
      case GroupFunctionCode.writeFieldsReply:
        _completePending(
            '$targetPgn:${code.value}:${frame.source}', frame.data);

      // Incoming requests to our server.
      case GroupFunctionCode.command:
        _dispatchServerRequest(code, targetPgn, frame);
      case GroupFunctionCode.readFields:
        _dispatchServerRequest(code, targetPgn, frame);
      case GroupFunctionCode.writeFields:
        _dispatchServerRequest(code, targetPgn, frame);

      // Request (function 0) is handled differently — it's a transmission
      // rate change request, not a field-level operation. Ignored for now.
      case GroupFunctionCode.request:
        break;
    }
  }

  void _completePending(String key, Uint8List data) {
    final completer = _pendingGf.remove(key);
    if (completer != null && !completer.isCompleted) {
      completer.complete(Uint8List.fromList(data));
    }
  }

  void _dispatchServerRequest(
      GroupFunctionCode code, int targetPgn, FrameReceived frame) {
    final fields = decodeIncomingFieldPairs(frame.data);
    final request = GroupFunctionRequest(
      functionCode: code,
      pgn: targetPgn,
      requesterSa: frame.source,
      fields: fields,
      sendReply: (replyCode, pgn, payload) {
        try {
          _ecu.send(kGroupFunctionPgn,
              priority: 3,
              dest: frame.source,
              data: Uint8List.fromList(payload));
        } catch (_) {}
      },
    );

    GroupFunctionHandler? handler;
    switch (code) {
      case GroupFunctionCode.command:
        handler = _commandHandler;
      case GroupFunctionCode.readFields:
        handler = _readFieldsHandler;
      case GroupFunctionCode.writeFields:
        handler = _writeFieldsHandler;
      default:
        break;
    }

    if (handler != null) {
      handler(request);
    } else {
      // Default: reject with PGN not supported.
      request.reject(PgnErrorCode.pgnNotSupported);
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _heartbeatTimer?.cancel();
    _requestSub?.cancel();
    _groupFunctionSub?.cancel();
    // Complete any pending client requests with errors.
    for (final completer in _pendingGf.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Nmea2000Ecu disposed'));
      }
    }
    _pendingGf.clear();
    _ecu.dispose();
  }
}
