// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Minimal RV-C example -- query the DGN registry.
library;

import 'package:rvc/src/rvc_registry.dart';

void main() {
  final registry = RvcRegistry.standard();
  print('Loaded ${registry.dgnNumbers.length} DGNs');

  for (final dgn in registry.allDgns) {
    print('  DGN 0x${dgn.pgn.toRadixString(16)}: ${dgn.name} '
        '(${dgn.fields.length} fields, ${dgn.dataLength} bytes)');
  }
}
