/// The expression lexer: turns a source string into a list of [Token]s
/// (spec 005a). Internal to the expression seam.
library;

import 'expression_exception.dart';
import 'token.dart';

/// Tokenizes [source] into a list ending with a [TokenType.eof] token.
///
/// Throws [ExpressionException] on an unterminated string/reference or an
/// unexpected character. In 005a only `$F{...}` and `$P{...}` references are
/// recognized; any other `$X{...}` sigil (e.g. `$V`) is an error.
List<Token> tokenize(String source) => _Lexer(source).scanAll();

class _Lexer {
  _Lexer(this._src);

  final String _src;
  int _pos = 0;
  final List<Token> _tokens = <Token>[];

  List<Token> scanAll() {
    while (!_isAtEnd) {
      _skipWhitespace();
      if (_isAtEnd) break;
      _scanToken();
    }
    _tokens.add(const Token(TokenType.eof, ''));
    return _tokens;
  }

  bool get _isAtEnd => _pos >= _src.length;
  String get _peek => _src[_pos];
  String _peekAt(int offset) =>
      _pos + offset < _src.length ? _src[_pos + offset] : '';

  void _skipWhitespace() {
    while (!_isAtEnd && _peek.trim().isEmpty) {
      _pos++;
    }
  }

  void _scanToken() {
    final String c = _peek;
    if (c == r'$') {
      _scanReference();
    } else if (_isDigit(c) || (c == '.' && _isDigit(_peekAt(1)))) {
      _scanNumber();
    } else if (c == "'" || c == '"') {
      _scanString(c);
    } else if (_isAlpha(c)) {
      _scanIdentifier();
    } else {
      _scanOperator();
    }
  }

  void _scanReference() {
    // $F{name}, $P{name} or $V{name}
    final String sigil = _peekAt(1);
    final TokenType type;
    if (sigil == 'F') {
      type = TokenType.fieldRef;
    } else if (sigil == 'P') {
      type = TokenType.paramRef;
    } else if (sigil == 'V') {
      type = TokenType.variableRef;
    } else {
      throw ExpressionException(
        'Unsupported reference "\$$sigil" at position $_pos '
        '(expected \$F{...}, \$P{...} or \$V{...})',
      );
    }
    if (_peekAt(2) != '{') {
      throw ExpressionException(
          'Expected "{" after "\$$sigil" at position $_pos');
    }
    final int start = _pos;
    _pos += 3; // consume $, sigil, {
    final StringBuffer name = StringBuffer();
    while (!_isAtEnd && _peek != '}') {
      name.write(_peek);
      _pos++;
    }
    if (_isAtEnd) {
      throw ExpressionException('Unterminated reference starting at $start');
    }
    if (name.isEmpty) {
      throw ExpressionException('Empty reference name at position $start');
    }
    _pos++; // consume }
    _tokens.add(Token(type, _src.substring(start, _pos), name.toString()));
  }

  void _scanNumber() {
    final int start = _pos;
    while (!_isAtEnd && _isDigit(_peek)) {
      _pos++;
    }
    if (!_isAtEnd && _peek == '.' && _isDigit(_peekAt(1))) {
      _pos++; // consume .
      while (!_isAtEnd && _isDigit(_peek)) {
        _pos++;
      }
    }
    final String lexeme = _src.substring(start, _pos);
    _tokens.add(Token(TokenType.number, lexeme, double.parse(lexeme)));
  }

  void _scanString(String quote) {
    final int start = _pos;
    _pos++; // consume opening quote
    final StringBuffer value = StringBuffer();
    while (!_isAtEnd && _peek != quote) {
      if (_peek == r'\') {
        _pos++;
        if (_isAtEnd) {
          throw ExpressionException(
              'Unterminated escape at position ${_pos - 1}');
        }
        final String esc = _peek;
        value.write(switch (esc) {
          'n' => '\n',
          't' => '\t',
          r'\' => r'\',
          "'" => "'",
          '"' => '"',
          _ => esc,
        });
        _pos++;
      } else {
        value.write(_peek);
        _pos++;
      }
    }
    if (_isAtEnd) {
      throw ExpressionException('Unterminated string starting at $start');
    }
    _pos++; // consume closing quote
    _tokens.add(
        Token(TokenType.string, _src.substring(start, _pos), value.toString()));
  }

  void _scanIdentifier() {
    final int start = _pos;
    while (!_isAtEnd && _isAlphaNumeric(_peek)) {
      _pos++;
    }
    final String lexeme = _src.substring(start, _pos);
    final TokenType type = switch (lexeme) {
      'true' => TokenType.trueLiteral,
      'false' => TokenType.falseLiteral,
      'null' => TokenType.nullLiteral,
      _ => TokenType.identifier,
    };
    _tokens.add(Token(type, lexeme));
  }

  void _scanOperator() {
    final String c = _peek;
    final String next = _peekAt(1);
    Token two(TokenType t) => Token(t, _src.substring(_pos, _pos + 2));
    Token one(TokenType t) => Token(t, c);

    final Token token;
    switch (c) {
      case '+':
        token = one(TokenType.plus);
      case '-':
        token = one(TokenType.minus);
      case '*':
        token = one(TokenType.star);
      case '/':
        token = one(TokenType.slash);
      case '%':
        token = one(TokenType.percent);
      case ',':
        token = one(TokenType.comma);
      case '(':
        token = one(TokenType.leftParen);
      case ')':
        token = one(TokenType.rightParen);
      case '?':
        token = one(TokenType.question);
      case ':':
        token = one(TokenType.colon);
      case '=' when next == '=':
        token = two(TokenType.equalEqual);
      case '!' when next == '=':
        token = two(TokenType.bangEqual);
      case '!':
        token = one(TokenType.bang);
      case '<' when next == '=':
        token = two(TokenType.lessEqual);
      case '<':
        token = one(TokenType.less);
      case '>' when next == '=':
        token = two(TokenType.greaterEqual);
      case '>':
        token = one(TokenType.greater);
      case '&' when next == '&':
        token = two(TokenType.andAnd);
      case '|' when next == '|':
        token = two(TokenType.orOr);
      default:
        throw ExpressionException(
            'Unexpected character "$c" at position $_pos');
    }
    _pos += token.lexeme.length;
    _tokens.add(token);
  }

  static bool _isDigit(String c) =>
      c.isNotEmpty && c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  static bool _isAlpha(String c) {
    if (c.isEmpty) return false;
    final int u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || c == '_';
  }

  static bool _isAlphaNumeric(String c) => _isAlpha(c) || _isDigit(c);
}
