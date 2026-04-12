// Flutter-only asset loader for BoatDbc. Lives in its own file so that
// boat_dbc.dart stays pure Dart and can be imported by the CLI simulator
// without pulling in package:flutter (which breaks `dart run`).

import 'package:can_dbc/can_dbc.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'boat_dbc.dart';

/// Load [BoatDbc] from a Flutter asset. Defaults to the DBC declared in
/// pubspec.yaml. Replace the asset file and hot-restart to track schema
/// changes — no codegen required.
Future<BoatDbc> loadBoatDbcFromAsset({
  String assetPath = 'assets/dbc/ThrottleStandardIDs.dbc',
}) async {
  final source = await rootBundle.loadString(assetPath);
  final db = DbcParser().parse(source);
  return BoatDbc.fromDatabase(db);
}
