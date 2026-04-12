// DBC codec round-trip test. No widget test yet — the helm UI needs a
// rootBundle-loaded DBC asset, which is awkward to stub in a unit test,
// so we cover the critical bit-packing path instead. If this passes,
// signal encode/decode is symmetric and the UI layer is trustworthy.

import 'dart:io';
import 'dart:typed_data';

import 'package:can_dbc/can_dbc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throttle_ui/can/boat_dbc.dart';
import 'package:throttle_ui/can/dbc_codec.dart';

DbcSignal _sig({
  required int startBit,
  required int length,
  ByteOrder order = ByteOrder.littleEndian,
  ValueType type = ValueType.unsigned,
  double factor = 1,
  double offset = 0,
}) => DbcSignal(
  name: 'x',
  startBit: startBit,
  length: length,
  byteOrder: order,
  valueType: type,
  factor: factor,
  offset: offset,
  minimum: -1e9,
  maximum: 1e9,
  unit: '',
  receivers: const [],
);

void main() {
  test('intel unsigned round trip across byte boundary', () {
    final sig = _sig(startBit: 4, length: 12);
    final buf = Uint8List(8);
    encodeSignal(sig, 1234, buf);
    expect(decodeSignal(sig, buf), 1234);
  });

  test('intel signed 10-bit with factor (mirrors HELM_00.Throttle)', () {
    final sig = _sig(
      startBit: 8,
      length: 10,
      type: ValueType.signed,
      factor: 0.01,
    );
    final buf = Uint8List(8);
    encodeSignal(sig, -2.37, buf);
    final decoded = decodeSignal(sig, buf)!;
    expect((decoded + 2.37).abs() < 1e-9, isTrue);
  });

  test('intel signed 32-bit with tiny factor (mirrors POS_RAPID.Latitude)', () {
    final sig = _sig(
      startBit: 0,
      length: 32,
      type: ValueType.signed,
      factor: 1e-7,
    );
    final buf = Uint8List(8);
    encodeSignal(sig, 47.6062, buf);
    final decoded = decodeSignal(sig, buf)!;
    expect((decoded - 47.6062).abs() < 1e-6, isTrue);
  });

  test('unsigned 16-bit at byte-aligned offset', () {
    final sig = _sig(startBit: 16, length: 16);
    final buf = Uint8List(8);
    encodeSignal(sig, 0xABCD.toDouble(), buf);
    expect(decodeSignal(sig, buf), 0xABCD);
  });

  test('decode returns null on short buffer', () {
    final sig = _sig(startBit: 0, length: 16);
    final buf = Uint8List(1);
    expect(decodeSignal(sig, buf), isNull);
  });

  test('parses the real ThrottleStandardIDs.dbc and round-trips HELM_00', () {
    final file = File('assets/dbc/ThrottleStandardIDs.dbc');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'DBC asset missing — pubspec.yaml out of sync?',
    );
    final db = DbcParser().parse(file.readAsStringSync());
    final dbc = BoatDbc.fromDatabase(db);

    // Every message the UI and simulator depend on must exist.
    for (final name in const [
      'HELM_00',
      'HELM_01',
      'HELM_CMD',
      'POS_RAPID',
      'COG_SOG_RAPID',
    ]) {
      expect(dbc.message(name), isNotNull, reason: '$name missing in DBC');
    }

    // HELM_00 round trip — signed throttle + assorted flags.
    final helm00 = dbc.message('HELM_00')!;
    final packed = dbc.packMessage(helm00, {
      'Throttle': -1.23,
      'Key': 1,
      'MAIN_Relay_Status': 1,
      'AUX_Relay_Status': 1,
      'HVIL_Relay_Status': 0,
      'StartStop': 1,
      'Sys_Timer': 42,
      'Flt_CAN': 0,
    });
    expect(packed.length, helm00.length);
    final decoded = dbc.decodeAll(helm00, packed);
    expect((decoded['Throttle']! - -1.23).abs() < 1e-9, isTrue);
    expect(decoded['Key'], 1);
    expect(decoded['MAIN_Relay_Status'], 1);
    expect(decoded['AUX_Relay_Status'], 1);
    expect(decoded['HVIL_Relay_Status'], 0);
    expect(decoded['StartStop'], 1);
    expect(decoded['Sys_Timer'], 42);

    // POS_RAPID round trip — int32 with 1e-7 factor.
    final pos = dbc.message('POS_RAPID')!;
    final buf = dbc.packMessage(pos, {
      'Latitude': 47.6062,
      'Longitude': -122.3321,
    });
    final back = dbc.decodeAll(pos, buf);
    expect((back['Latitude']! - 47.6062).abs() < 1e-6, isTrue);
    expect((back['Longitude']! - -122.3321).abs() < 1e-6, isTrue);
  });
}
