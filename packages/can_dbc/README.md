# can_dbc

Pure Dart DBC file parser and signal compiler for CAN bus databases. Parses
standard `.dbc` files into structured Dart objects and compiles signal
definitions to native FFI structs for use with `can_engine`.

## Features

- Full DBC file parsing: messages, signals, nodes, comments, value descriptions
- Standard and extended multiplexing support (`M`, `m<N>`, `m<N>M`)
- Intel (little-endian) and Motorola (big-endian) byte ordering
- Signal compilation to native C structs for zero-copy engine interop
- Extended CAN ID (29-bit) detection
- Validated against real-world DBC corpora (opendbc, j1939_dbc)

## Getting started

```yaml
dependencies:
  can_dbc: ^0.1.0
```

## Usage

### Parse a DBC file

```dart
import 'package:can_dbc/can_dbc.dart';

void main() async {
  final db = await DbcParser().parseFile('vehicle.dbc');

  print('Version: ${db.version}');
  print('Nodes: ${db.nodes.length}');
  print('Messages: ${db.messages.length}');
  print('Signals: ${db.signalCount}');
}
```

### Parse from a string

```dart
final db = DbcParser().parse('''
VERSION "1.0"
BU_: ECU1 ECU2

BO_ 100 EngineData: 8 ECU1
 SG_ EngineSpeed : 0|16@1+ (0.25,0) [0|16383.75] "rpm" ECU2
 SG_ EngineTemp : 16|8@1- (1,-40) [-40|215] "degC" ECU2

CM_ SG_ 100 EngineSpeed "Current engine speed";
VAL_ 100 EngineTemp 0 "Cold" 1 "Normal" 2 "Hot" ;
''');
```

### Access messages and signals

```dart
final msg = db.messageById(100)!;
print('${msg.name} from ${msg.transmitter}, ${msg.length} bytes');

for (final sig in msg.signals) {
  print('  ${sig.name}: ${sig.startBit}|${sig.length}'
      ' factor=${sig.factor} offset=${sig.offset}'
      ' [${sig.minimum}..${sig.maximum}] "${sig.unit}"');

  if (sig.valueDescriptions != null) {
    sig.valueDescriptions!.forEach((k, v) => print('    $k = $v'));
  }
}
```

### Multiplexed signals

```dart
for (final sig in msg.signals) {
  switch (sig.multiplexType) {
    case MultiplexType.multiplexer:
      print('${sig.name} is the mux selector');
    case MultiplexType.multiplexed:
      print('${sig.name} active when mux == ${sig.multiplexValue}');
    case MultiplexType.extendedMultiplexor:
      print('${sig.name} is a sub-mux (parent=${sig.multiplexValue})');
    case MultiplexType.none:
      break;
  }
}
```

### Compile to native structs (for can_engine)

```dart
final compiler = SignalCompiler();
final compiled = compiler.compile(db);

print('${compiled.signalCount} signals, ${compiled.messageCount} messages');

// Pass compiled.signalDefs and compiled.messageDefs to can_engine via FFI.

compiled.dispose(); // Free native memory.
```

## DBC format support

| Section | Status |
|---|---|
| `VERSION` | Parsed |
| `NS_` | Parsed |
| `BS_` | Parsed (bus speed) |
| `BU_` | Parsed (nodes with comments) |
| `BO_` / `SG_` | Parsed (messages, signals, extended IDs) |
| `CM_` | Parsed (comments on nodes, messages, signals) |
| `VAL_` | Parsed (value descriptions / enums) |
| `BA_DEF_` / `BA_` | Parsed (not yet modeled) |
| `VAL_TABLE_` | Parsed (not yet modeled) |
| `SG_MUL_VAL_` | Parsed (not yet modeled) |

## Testing

```bash
dart test

# Optional: validate against real-world DBC corpora (requires network)
CAN_DBC_NETWORK_TESTS=1 dart test
```

## License

Apache 2.0 -- see [LICENSE](LICENSE) for details.
