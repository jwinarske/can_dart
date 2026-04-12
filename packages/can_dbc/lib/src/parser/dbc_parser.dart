import 'dart:io';

import '../model/dbc_database.dart';
import '../model/dbc_message.dart';
import '../model/dbc_node.dart';
import '../model/dbc_signal.dart';
import 'dbc_tokenizer.dart';

/// Exception thrown on DBC parse errors.
class DbcParseException implements Exception {
  final String message;
  final int line;
  final int column;

  DbcParseException(this.message, this.line, this.column);

  @override
  String toString() => 'DbcParseException: $message at $line:$column';
}

/// Recursive descent parser for DBC files.
///
/// Handles: VERSION, NS_, BS_, BU_, BO_, SG_, CM_, BA_DEF_, BA_DEF_DEF_,
/// BA_, VAL_, VAL_TABLE_, SIG_GROUP_, SIG_VALTYPE_, BO_TX_BU_,
/// multiplexed signals (`M`, `m<N>`, and extended `m<N>M`).
class DbcParser {
  late List<Token> _tokens;
  int _pos = 0;

  // Parsed state
  String _version = '';
  int _busSpeed = 0;
  final List<DbcNode> _nodes = [];
  final List<DbcMessage> _messages = [];
  final Map<String, DbcNode> _nodeMap = {};
  final Map<int, DbcMessage> _messageMap = {};

  /// Parse a DBC string and return a [DbcDatabase].
  DbcDatabase parse(String source) {
    _tokens = DbcTokenizer(source).tokenize();
    _pos = 0;
    _version = '';
    _busSpeed = 0;
    _nodes.clear();
    _messages.clear();
    _nodeMap.clear();
    _messageMap.clear();

    while (!_isAtEnd) {
      _parseSection();
    }

    return DbcDatabase(
      version: _version,
      nodes: List.of(_nodes),
      messages: List.of(_messages),
      busSpeed: _busSpeed,
    );
  }

  /// Parse a DBC file from disk.
  Future<DbcDatabase> parseFile(String path) async {
    final content = await File(path).readAsString();
    return parse(content);
  }

  // --- Section dispatch ---

  void _parseSection() {
    if (_isAtEnd) return;

    final token = _current;

    if (token.type == TokenType.keyword) {
      switch (token.value) {
        case 'VERSION':
          _parseVersion();
        case 'NS_':
          _parseNs();
        case 'BS_':
          _parseBs();
        case 'BU_':
          _parseBu();
        case 'BO_':
          _parseBo();
        case 'CM_':
          _parseCm();
        case 'BA_DEF_':
          _parseBaDef();
        case 'BA_DEF_DEF_':
          _parseBaDefDef();
        case 'BA_':
          _parseBa();
        case 'VAL_':
          _parseVal();
        case 'VAL_TABLE_':
          _parseValTable();
        case 'SIG_GROUP_':
          _parseSigGroup();
        case 'SIG_VALTYPE_':
          _parseSigValType();
        case 'BO_TX_BU_':
          _parseBoTxBu();
        case 'SG_MUL_VAL_':
          _parseSgMulVal();
        default:
          _advance(); // skip unknown keyword
      }
    } else {
      _advance(); // skip unexpected token
    }
  }

  // --- VERSION ---

  void _parseVersion() {
    _expectKeyword('VERSION');
    if (_check(TokenType.string)) {
      _version = _current.value;
      _advance();
    }
  }

  // --- NS_ (new symbols) ---

  void _parseNs() {
    _expectKeyword('NS_');
    _skip(TokenType.colon);
    // The NS_ section is a list of optional-symbol names (NS_DESC_, CM_,
    // BA_DEF_, VAL_, SG_MUL_VAL_, ...). Many of these names are also in
    // the tokenizer's keyword set, so naively skipping only identifiers
    // would leave them in the stream and _parseSection would mis-dispatch
    // them as real sections (e.g. CM_ would be parsed as a comment and
    // silently consume everything up to the next semicolon).
    //
    // Skip every token until we reach the start of the next real section.
    // BS_ (bus speed), BU_ (nodes), and BO_ (message) are the only three
    // section starters that can never legitimately appear inside an NS_
    // symbol list, so they are safe stop sentinels.
    while (!_isAtEnd) {
      if (_current.type == TokenType.keyword) {
        final v = _current.value;
        if (v == 'BS_' || v == 'BU_' || v == 'BO_') break;
      }
      _advance();
    }
  }

  // --- BS_ (bus speed) ---

  void _parseBs() {
    _expectKeyword('BS_');
    _skip(TokenType.colon);
    if (_check(TokenType.integer)) {
      _busSpeed = int.parse(_current.value);
      _advance();
    }
    // Skip any remaining tokens until next section
    while (!_isAtEnd && !_isSection) {
      _advance();
    }
  }

  // --- BU_ (nodes) ---

  void _parseBu() {
    _expectKeyword('BU_');
    _skip(TokenType.colon);
    while (!_isAtEnd && _current.type == TokenType.identifier) {
      final node = DbcNode(name: _current.value);
      _nodes.add(node);
      _nodeMap[node.name] = node;
      _advance();
    }
  }

  // --- BO_ (message) + SG_ (signals) ---

  void _parseBo() {
    _expectKeyword('BO_');

    final rawId = _expectInt();
    final isExtended = rawId & 0x80000000 != 0;
    final id = rawId & 0x1FFFFFFF;

    final name = _expectIdentifier();
    _skip(TokenType.colon);
    final length = _expectInt();
    final transmitter = _check(TokenType.identifier) ? _expectIdentifier() : '';

    final message = DbcMessage(
      id: id,
      isExtended: isExtended,
      name: name,
      length: length,
      transmitter: transmitter,
    );

    // Parse signals
    while (!_isAtEnd && _checkKeyword('SG_')) {
      final signal = _parseSg();
      message.signals.add(signal);
    }

    _messages.add(message);
    _messageMap[rawId] = message;
  }

  DbcSignal _parseSg() {
    _expectKeyword('SG_');

    final name = _expectIdentifier();

    // Multiplexing indicator
    var muxType = MultiplexType.none;
    int? muxValue;

    if (_check(TokenType.identifier)) {
      final muxStr = _current.value;
      if (muxStr == 'M') {
        // Root multiplexer.
        muxType = MultiplexType.multiplexer;
        _advance();
      } else if (muxStr == 'm') {
        // Bare "m" (no explicit value) — a multiplexed signal whose
        // selector value is defined elsewhere via SG_MUL_VAL_ extended
        // multiplexing. Cantools accepts this and it appears in
        // real-world DBC files (e.g. vw_pq.dbc in opendbc).
        muxType = MultiplexType.multiplexed;
        _advance();
      } else if (muxStr.startsWith('m') && muxStr.length > 1) {
        // Either `m<N>` (leaf multiplexed) or `m<N>M` (extended mux —
        // both multiplexed by <N> and itself a selector for children,
        // e.g. OBD2.dbc's per-service PID selectors).
        final isExtended = muxStr.endsWith('M');
        final numPart =
            isExtended
                ? muxStr.substring(1, muxStr.length - 1)
                : muxStr.substring(1);
        final parsed = int.tryParse(numPart);
        if (parsed != null) {
          muxType =
              isExtended
                  ? MultiplexType.extendedMultiplexor
                  : MultiplexType.multiplexed;
          muxValue = parsed;
          _advance();
        }
      }
    }

    _expect(TokenType.colon);

    final startBit = _expectInt();
    _expect(TokenType.pipe);
    final bitLength = _expectInt();
    _expect(TokenType.at);

    // Byte order + value type: 0+ (BE unsigned), 1+ (LE unsigned),
    // 0- (BE signed), 1- (LE signed)
    final orderChar = _expectInt();
    final byteOrder =
        orderChar == 1 ? ByteOrder.littleEndian : ByteOrder.bigEndian;

    ValueType valueType;
    if (_check(TokenType.plus)) {
      valueType = ValueType.unsigned;
      _advance();
    } else if (_check(TokenType.minus)) {
      valueType = ValueType.signed;
      _advance();
    } else {
      valueType = ValueType.unsigned;
    }

    // Factor and offset: (factor,offset)
    _expect(TokenType.lparen);
    final factor = _expectDouble();
    _expect(TokenType.comma);
    final offset = _expectDouble();
    _expect(TokenType.rparen);

    // Min and max: [min|max]
    _expect(TokenType.lbracket);
    final minimum = _expectDouble();
    _expect(TokenType.pipe);
    final maximum = _expectDouble();
    _expect(TokenType.rbracket);

    // Unit string
    final unit = _check(TokenType.string) ? _expectString() : '';

    // Receivers
    final receivers = <String>[];
    while (!_isAtEnd && _current.type == TokenType.identifier) {
      receivers.add(_current.value);
      _advance();
      if (_check(TokenType.comma)) _advance();
    }

    return DbcSignal(
      name: name,
      startBit: startBit,
      length: bitLength,
      byteOrder: byteOrder,
      valueType: valueType,
      factor: factor,
      offset: offset,
      minimum: minimum,
      maximum: maximum,
      unit: unit,
      receivers: receivers,
      multiplexType: muxType,
      multiplexValue: muxValue,
    );
  }

  // --- CM_ (comments) ---

  void _parseCm() {
    _expectKeyword('CM_');

    if (_checkKeyword('SG_')) {
      _advance();
      final msgId = _expectInt();
      final sigName = _expectIdentifier();
      final comment = _expectString();
      _skip(TokenType.semicolon);

      final msg = _messageMap[msgId];
      if (msg != null) {
        for (final sig in msg.signals) {
          if (sig.name == sigName) {
            sig.comment = comment;
            break;
          }
        }
      }
    } else if (_checkKeyword('BO_')) {
      _advance();
      final msgId = _expectInt();
      final comment = _expectString();
      _skip(TokenType.semicolon);

      _messageMap[msgId]?.comment = comment;
    } else if (_checkKeyword('BU_')) {
      _advance();
      final nodeName = _expectIdentifier();
      final comment = _expectString();
      _skip(TokenType.semicolon);

      _nodeMap[nodeName]?.comment = comment;
    } else {
      // Global comment or unknown — skip to semicolon
      if (_check(TokenType.string)) {
        _advance();
      }
      _skipToSemicolon();
    }
  }

  // --- BA_DEF_ (attribute definitions) ---

  void _parseBaDef() {
    _expectKeyword('BA_DEF_');
    _skipToSemicolon();
  }

  // --- BA_DEF_DEF_ (attribute definition defaults) ---

  void _parseBaDefDef() {
    _expectKeyword('BA_DEF_DEF_');
    _skipToSemicolon();
  }

  // --- BA_ (attribute values) ---

  void _parseBa() {
    _expectKeyword('BA_');
    _skipToSemicolon();
  }

  // --- VAL_ (value descriptions / enums) ---

  void _parseVal() {
    _expectKeyword('VAL_');

    if (_check(TokenType.integer)) {
      final msgId = _expectInt();
      final sigName = _expectIdentifier();
      final values = _parseValueDescriptions();

      final msg = _messageMap[msgId];
      if (msg != null) {
        for (final sig in msg.signals) {
          if (sig.name == sigName) {
            sig.valueDescriptions = values;
            break;
          }
        }
      }
    } else {
      // VAL_ for environment variables or VAL_TABLE_ reference
      _skipToSemicolon();
    }
  }

  Map<int, String> _parseValueDescriptions() {
    final map = <int, String>{};
    while (!_isAtEnd && !_check(TokenType.semicolon)) {
      if (_check(TokenType.integer)) {
        final key = _expectInt();
        final value = _expectString();
        map[key] = value;
      } else {
        break;
      }
    }
    _skip(TokenType.semicolon);
    return map;
  }

  // --- VAL_TABLE_ ---

  void _parseValTable() {
    _expectKeyword('VAL_TABLE_');
    _skipToSemicolon();
  }

  // --- SIG_GROUP_ ---

  void _parseSigGroup() {
    _expectKeyword('SIG_GROUP_');
    _skipToSemicolon();
  }

  // --- SIG_VALTYPE_ ---

  void _parseSigValType() {
    _expectKeyword('SIG_VALTYPE_');
    _skipToSemicolon();
  }

  // --- BO_TX_BU_ ---

  void _parseBoTxBu() {
    _expectKeyword('BO_TX_BU_');
    _skipToSemicolon();
  }

  // --- SG_MUL_VAL_ ---

  void _parseSgMulVal() {
    _expectKeyword('SG_MUL_VAL_');
    _skipToSemicolon();
  }

  // --- Token helpers ---

  Token get _current => _tokens[_pos];
  bool get _isAtEnd => _pos >= _tokens.length || _current.type == TokenType.eof;

  bool get _isSection =>
      _current.type == TokenType.keyword &&
      const {
        'VERSION',
        'NS_',
        'BS_',
        'BU_',
        'BO_',
        'CM_',
        'BA_DEF_',
        'BA_DEF_DEF_',
        'BA_',
        'VAL_',
        'VAL_TABLE_',
        'SIG_GROUP_',
        'SIG_VALTYPE_',
        'BO_TX_BU_',
        'SG_MUL_VAL_',
        'EV_',
      }.contains(_current.value);

  void _advance() {
    if (!_isAtEnd) _pos++;
  }

  bool _check(TokenType type) => !_isAtEnd && _current.type == type;

  bool _checkKeyword(String keyword) =>
      _check(TokenType.keyword) && _current.value == keyword;

  void _expect(TokenType type) {
    if (!_check(type)) {
      _error('Expected $type, got ${_current.type} ("${_current.value}")');
    }
    _advance();
  }

  void _expectKeyword(String keyword) {
    if (!_checkKeyword(keyword)) {
      _error('Expected keyword "$keyword", got "${_current.value}"');
    }
    _advance();
  }

  String _expectIdentifier() {
    if (!_check(TokenType.identifier)) {
      _error('Expected identifier, got ${_current.type} ("${_current.value}")');
    }
    final value = _current.value;
    _advance();
    return value;
  }

  String _expectString() {
    if (!_check(TokenType.string)) {
      _error('Expected string, got ${_current.type} ("${_current.value}")');
    }
    final value = _current.value;
    _advance();
    return value;
  }

  int _expectInt() {
    if (_check(TokenType.integer)) {
      final value = int.parse(_current.value);
      _advance();
      return value;
    }
    if (_check(TokenType.float_)) {
      // Some DBC files use floats where ints expected
      final value = double.parse(_current.value).toInt();
      _advance();
      return value;
    }
    _error('Expected integer, got ${_current.type} ("${_current.value}")');
  }

  double _expectDouble() {
    if (_check(TokenType.float_) || _check(TokenType.integer)) {
      final value = double.parse(_current.value);
      _advance();
      return value;
    }
    // Handle negative numbers: minus followed by number
    if (_check(TokenType.minus)) {
      _advance();
      if (_check(TokenType.float_) || _check(TokenType.integer)) {
        final value = -double.parse(_current.value);
        _advance();
        return value;
      }
      _error('Expected number after minus');
    }
    if (_check(TokenType.plus)) {
      _advance();
      if (_check(TokenType.float_) || _check(TokenType.integer)) {
        final value = double.parse(_current.value);
        _advance();
        return value;
      }
      _error('Expected number after plus');
    }
    _error('Expected number, got ${_current.type} ("${_current.value}")');
  }

  void _skip(TokenType type) {
    if (_check(type)) _advance();
  }

  void _skipToSemicolon() {
    while (!_isAtEnd && !_check(TokenType.semicolon)) {
      _advance();
    }
    _skip(TokenType.semicolon);
  }

  Never _error(String message) {
    throw DbcParseException(message, _current.line, _current.column);
  }
}
