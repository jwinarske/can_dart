// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Parse a DBC string and print the message/signal tree.
library;

import 'package:can_dbc/can_dbc.dart';

void main() {
  final db = DbcParser().parse('''
VERSION "1.0"
BU_: ECU1 ECU2

BO_ 256 EngineData: 8 ECU1
 SG_ EngineSpeed : 0|16@1+ (0.25,0) [0|16383.75] "rpm" ECU2
 SG_ EngineTemp : 16|8@1- (1,-40) [-40|215] "degC" ECU2
 SG_ IdleFlag : 24|1@1+ (1,0) [0|1] "" ECU2

CM_ SG_ 256 EngineSpeed "Current engine speed in rpm";
VAL_ 256 IdleFlag 0 "Running" 1 "Idle" ;
''');

  print('DBC version: ${db.version}');
  print('Nodes: ${db.nodes.map((n) => n.name).join(', ')}');
  print('');

  for (final msg in db.messages) {
    print(
      'Message 0x${msg.id.toRadixString(16)} "${msg.name}" '
      '(${msg.length} bytes, from ${msg.transmitter})',
    );
    for (final sig in msg.signals) {
      print(
        '  ${sig.name}: bits ${sig.startBit}..${sig.startBit + sig.length - 1}'
        ' factor=${sig.factor} offset=${sig.offset}'
        ' [${sig.minimum}..${sig.maximum}] "${sig.unit}"',
      );
    }
  }
}
