/// Pure Dart DBC file parser and signal compiler for CAN bus databases.
///
/// Parses DBC files into a structured [DbcDatabase] and compiles
/// signal definitions into packed native structs for consumption
/// by `can_engine`.
library;

export 'src/model/dbc_database.dart';
export 'src/model/dbc_message.dart';
export 'src/model/dbc_node.dart';
export 'src/model/dbc_signal.dart';
export 'src/parser/dbc_parser.dart';
export 'src/compiler/signal_compiler.dart';
export 'src/compiler/native_structs.dart';
