/// A node (ECU) definition from a DBC file.
class DbcNode {
  /// The node name.
  final String name;

  /// Optional comment.
  String? comment;

  DbcNode({required this.name, this.comment});

  @override
  String toString() => 'DbcNode($name)';
}
