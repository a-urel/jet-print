/// The expression parser: recursive descent over [Token]s producing an [Expr]
/// AST (spec 005a). Internal to the expression seam.
library;

import 'ast.dart';
import 'expression_exception.dart';
import 'token.dart';
import 'value.dart';

/// Parses a token stream into an [Expr] tree.
///
/// Grammar (lowest to highest precedence):
/// `ternary → or → and → equality → comparison → additive → multiplicative →
/// unary → primary`. Throws [ExpressionException] on any syntax error,
/// including tokens left over after a complete expression.
class Parser {
  /// Creates a parser over [_tokens] (which must end with a [TokenType.eof]).
  Parser(this._tokens)
      : assert(_tokens.isNotEmpty && _tokens.last.type == TokenType.eof,
            'Parser requires a token list ending with TokenType.eof');

  final List<Token> _tokens;
  int _pos = 0;

  Token get _peek => _tokens[_pos];
  Token get _previous => _tokens[_pos - 1];
  bool get _isAtEnd => _peek.type == TokenType.eof;

  /// Parses a single complete expression, requiring all input to be consumed.
  Expr parseExpression() {
    final Expr expr = _ternary();
    if (!_isAtEnd) {
      throw ExpressionException(
          'Unexpected token "${_peek.lexeme}" after expression');
    }
    return expr;
  }

  bool _match(TokenType type) {
    if (_peek.type == type) {
      _pos++;
      return true;
    }
    return false;
  }

  Token _consume(TokenType type, String message) {
    if (_peek.type == type) {
      _pos++;
      return _previous;
    }
    throw ExpressionException('$message (got "${_peek.lexeme}")');
  }

  Expr _ternary() {
    final Expr condition = _or();
    if (_match(TokenType.question)) {
      final Expr thenBranch = _ternary();
      _consume(TokenType.colon, 'Expected ":" in conditional');
      final Expr elseBranch = _ternary();
      return ConditionalExpr(condition, thenBranch, elseBranch);
    }
    return condition;
  }

  Expr _or() {
    Expr expr = _and();
    while (_match(TokenType.orOr)) {
      expr = BinaryExpr(BinaryOp.or, expr, _and());
    }
    return expr;
  }

  Expr _and() {
    Expr expr = _equality();
    while (_match(TokenType.andAnd)) {
      expr = BinaryExpr(BinaryOp.and, expr, _equality());
    }
    return expr;
  }

  Expr _equality() {
    Expr expr = _comparison();
    while (true) {
      if (_match(TokenType.equalEqual)) {
        expr = BinaryExpr(BinaryOp.equal, expr, _comparison());
      } else if (_match(TokenType.bangEqual)) {
        expr = BinaryExpr(BinaryOp.notEqual, expr, _comparison());
      } else {
        return expr;
      }
    }
  }

  Expr _comparison() {
    Expr expr = _additive();
    while (true) {
      if (_match(TokenType.less)) {
        expr = BinaryExpr(BinaryOp.less, expr, _additive());
      } else if (_match(TokenType.lessEqual)) {
        expr = BinaryExpr(BinaryOp.lessEqual, expr, _additive());
      } else if (_match(TokenType.greater)) {
        expr = BinaryExpr(BinaryOp.greater, expr, _additive());
      } else if (_match(TokenType.greaterEqual)) {
        expr = BinaryExpr(BinaryOp.greaterEqual, expr, _additive());
      } else {
        return expr;
      }
    }
  }

  Expr _additive() {
    Expr expr = _multiplicative();
    while (true) {
      if (_match(TokenType.plus)) {
        expr = BinaryExpr(BinaryOp.add, expr, _multiplicative());
      } else if (_match(TokenType.minus)) {
        expr = BinaryExpr(BinaryOp.subtract, expr, _multiplicative());
      } else {
        return expr;
      }
    }
  }

  Expr _multiplicative() {
    Expr expr = _unary();
    while (true) {
      if (_match(TokenType.star)) {
        expr = BinaryExpr(BinaryOp.multiply, expr, _unary());
      } else if (_match(TokenType.slash)) {
        expr = BinaryExpr(BinaryOp.divide, expr, _unary());
      } else if (_match(TokenType.percent)) {
        expr = BinaryExpr(BinaryOp.modulo, expr, _unary());
      } else {
        return expr;
      }
    }
  }

  Expr _unary() {
    if (_match(TokenType.minus)) {
      return UnaryExpr(UnaryOp.negate, _unary());
    }
    if (_match(TokenType.bang)) {
      return UnaryExpr(UnaryOp.not, _unary());
    }
    return _primary();
  }

  Expr _primary() {
    final Token token = _peek;
    switch (token.type) {
      case TokenType.number:
        _pos++;
        return LiteralExpr(JetNumber(token.literal! as double));
      case TokenType.string:
        _pos++;
        return LiteralExpr(JetString(token.literal! as String));
      case TokenType.trueLiteral:
        _pos++;
        return const LiteralExpr(JetBool(true));
      case TokenType.falseLiteral:
        _pos++;
        return const LiteralExpr(JetBool(false));
      case TokenType.nullLiteral:
        _pos++;
        return const LiteralExpr(JetNull());
      case TokenType.fieldRef:
        _pos++;
        return FieldRefExpr(token.literal! as String);
      case TokenType.paramRef:
        _pos++;
        return ParamRefExpr(token.literal! as String);
      case TokenType.identifier:
        return _call();
      case TokenType.leftParen:
        _pos++;
        final Expr expr = _ternary();
        _consume(TokenType.rightParen, 'Expected ")" after expression');
        return expr;
      // TokenType is an open enum; this default catches any token that cannot
      // start an expression (operators, ')', ':', ',', eof).
      default:
        throw ExpressionException(
            'Expected an expression but found "${token.lexeme}"');
    }
  }

  Expr _call() {
    final String name =
        _consume(TokenType.identifier, 'Expected a name').lexeme;
    _consume(TokenType.leftParen, 'Expected "(" after function name "$name"');
    final List<Expr> args = <Expr>[];
    if (_peek.type != TokenType.rightParen) {
      args.add(_ternary());
      while (_match(TokenType.comma)) {
        args.add(_ternary());
      }
    }
    _consume(TokenType.rightParen, 'Expected ")" after arguments to "$name"');
    return CallExpr(name, args);
  }
}
