/// Token types for DBC file parsing.
enum TokenType {
  keyword,    // VERSION, NS_, BS_, BU_, BO_, SG_, CM_, BA_DEF_, BA_, VAL_, etc.
  identifier, // node names, signal names, message names
  integer,    // integer literal (possibly negative)
  float_,     // floating-point literal
  string,     // quoted string "..."
  colon,      // :
  pipe,       // |
  at,         // @
  plus,       // +
  minus,      // -
  comma,      // ,
  semicolon,  // ;
  lparen,     // (
  rparen,     // )
  lbracket,   // [
  rbracket,   // ]
  eof,        // end of input
}

/// A token from DBC file lexing.
class Token {
  final TokenType type;
  final String value;
  final int line;
  final int column;

  const Token(this.type, this.value, this.line, this.column);

  @override
  String toString() => 'Token($type, "$value", $line:$column)';
}

/// DBC keywords recognized by the tokenizer.
const _keywords = {
  'VERSION', 'NS_', 'BS_', 'BU_', 'BO_', 'SG_', 'CM_', 'BA_DEF_',
  'BA_DEF_DEF_', 'BA_', 'VAL_', 'VAL_TABLE_', 'SG_MUL_VAL_',
  'BO_TX_BU_', 'SIG_GROUP_', 'SIG_VALTYPE_', 'EV_', 'ENVVAR_DATA_',
  'SGTYPE_', 'SGTYPE_VAL_', 'BA_REL_', 'BA_DEF_REL_', 'BA_SGTYPE_',
  'BA_SGTYPE_REL_', 'NS_DESC_', 'FILTER',
};

/// Tokenizer for DBC files.
///
/// Converts raw DBC text into a stream of [Token]s for the parser.
class DbcTokenizer {
  final String _source;
  int _pos = 0;
  int _line = 1;
  int _col = 1;

  DbcTokenizer(this._source);

  /// Tokenize the entire source into a list of tokens.
  List<Token> tokenize() {
    final tokens = <Token>[];
    while (true) {
      final token = _nextToken();
      tokens.add(token);
      if (token.type == TokenType.eof) break;
    }
    return tokens;
  }

  Token _nextToken() {
    _skipWhitespaceAndComments();

    if (_pos >= _source.length) {
      return Token(TokenType.eof, '', _line, _col);
    }

    final ch = _source[_pos];

    // Single-character tokens
    switch (ch) {
      case ':': return _single(TokenType.colon);
      case '|': return _single(TokenType.pipe);
      case '@': return _single(TokenType.at);
      case ',': return _single(TokenType.comma);
      case ';': return _single(TokenType.semicolon);
      case '(': return _single(TokenType.lparen);
      case ')': return _single(TokenType.rparen);
      case '[': return _single(TokenType.lbracket);
      case ']': return _single(TokenType.rbracket);
    }

    // String literal
    if (ch == '"') return _readString();

    // Number (including negative)
    if (_isDigit(ch) || (ch == '-' && _pos + 1 < _source.length && _isDigitOrDot(_source[_pos + 1]))) {
      return _readNumber();
    }

    // Plus sign (standalone, not part of number)
    if (ch == '+') return _single(TokenType.plus);
    if (ch == '-') return _single(TokenType.minus);

    // Identifier or keyword
    if (_isIdentStart(ch)) return _readIdentifier();

    // Unknown character — skip it
    _advance();
    return _nextToken();
  }

  Token _single(TokenType type) {
    final token = Token(type, _source[_pos], _line, _col);
    _advance();
    return token;
  }

  Token _readString() {
    final startLine = _line;
    final startCol = _col;
    _advance(); // skip opening "

    final buf = StringBuffer();
    while (_pos < _source.length && _source[_pos] != '"') {
      if (_source[_pos] == '\\' && _pos + 1 < _source.length) {
        _advance();
        switch (_source[_pos]) {
          case 'n':  buf.write('\n');
          case 't':  buf.write('\t');
          case '\\': buf.write('\\');
          case '"':  buf.write('"');
          default:   buf.write(_source[_pos]);
        }
      } else {
        buf.write(_source[_pos]);
      }
      _advance();
    }
    if (_pos < _source.length) _advance(); // skip closing "
    return Token(TokenType.string, buf.toString(), startLine, startCol);
  }

  Token _readNumber() {
    final startLine = _line;
    final startCol = _col;
    final start = _pos;
    var isFloat = false;

    if (_source[_pos] == '-' || _source[_pos] == '+') _advance();

    while (_pos < _source.length && _isDigit(_source[_pos])) {
      _advance();
    }

    if (_pos < _source.length && _source[_pos] == '.') {
      isFloat = true;
      _advance();
      while (_pos < _source.length && _isDigit(_source[_pos])) {
        _advance();
      }
    }

    // Scientific notation
    if (_pos < _source.length && (_source[_pos] == 'e' || _source[_pos] == 'E')) {
      isFloat = true;
      _advance();
      if (_pos < _source.length && (_source[_pos] == '+' || _source[_pos] == '-')) {
        _advance();
      }
      while (_pos < _source.length && _isDigit(_source[_pos])) {
        _advance();
      }
    }

    final value = _source.substring(start, _pos);
    return Token(
      isFloat ? TokenType.float_ : TokenType.integer,
      value,
      startLine,
      startCol,
    );
  }

  Token _readIdentifier() {
    final startLine = _line;
    final startCol = _col;
    final start = _pos;

    while (_pos < _source.length && _isIdentChar(_source[_pos])) {
      _advance();
    }

    final value = _source.substring(start, _pos);
    final type = _keywords.contains(value) ? TokenType.keyword : TokenType.identifier;
    return Token(type, value, startLine, startCol);
  }

  void _skipWhitespaceAndComments() {
    while (_pos < _source.length) {
      final ch = _source[_pos];

      // Whitespace
      if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
        _advance();
        continue;
      }

      // Line comment //
      if (ch == '/' && _pos + 1 < _source.length && _source[_pos + 1] == '/') {
        while (_pos < _source.length && _source[_pos] != '\n') {
          _advance();
        }
        continue;
      }

      break;
    }
  }

  void _advance() {
    if (_pos < _source.length) {
      if (_source[_pos] == '\n') {
        _line++;
        _col = 1;
      } else {
        _col++;
      }
      _pos++;
    }
  }

  bool _isDigit(String ch) => ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;
  bool _isDigitOrDot(String ch) => _isDigit(ch) || ch == '.';
  bool _isIdentStart(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 0x41 && c <= 0x5A) || // A-Z
           (c >= 0x61 && c <= 0x7A) || // a-z
           c == 0x5F;                   // _
  }
  bool _isIdentChar(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 0x41 && c <= 0x5A) || // A-Z
           (c >= 0x61 && c <= 0x7A) || // a-z
           (c >= 0x30 && c <= 0x39) || // 0-9
           c == 0x5F;                   // _
  }
}
