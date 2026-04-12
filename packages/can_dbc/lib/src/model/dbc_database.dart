import 'dbc_message.dart';
import 'dbc_node.dart';

/// A parsed DBC database containing messages, signals, and nodes.
class DbcDatabase {
  /// DBC version string.
  final String version;

  /// Node (ECU) definitions.
  final List<DbcNode> nodes;

  /// Message definitions.
  final List<DbcMessage> messages;

  /// Bus speed (from BS_ section), 0 if not specified.
  final int busSpeed;

  DbcDatabase({
    this.version = '',
    List<DbcNode>? nodes,
    List<DbcMessage>? messages,
    this.busSpeed = 0,
  }) : nodes = nodes ?? [],
       messages = messages ?? [];

  /// Look up a message by CAN ID.
  DbcMessage? messageById(int canId) {
    for (final msg in messages) {
      if (msg.id == canId) return msg;
    }
    return null;
  }

  /// Total number of signals across all messages.
  int get signalCount =>
      messages.fold(0, (sum, msg) => sum + msg.signals.length);

  @override
  String toString() =>
      'DbcDatabase(version=$version, ${nodes.length} nodes, '
      '${messages.length} messages, $signalCount signals)';
}
