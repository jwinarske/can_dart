// Copyright 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

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
