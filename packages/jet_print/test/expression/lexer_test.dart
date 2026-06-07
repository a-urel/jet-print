// Lexer: String -> List<Token> (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/expression_exception.dart';
import 'package:jet_print/src/expression/lexer.dart';
import 'package:jet_print/src/expression/token.dart';

List<TokenType> _types(String src) =>
    tokenize(src).map((Token t) => t.type).toList();

void main() {
  group('tokenize', () {
    test('emits an eof token for empty input', () {
      expect(_types(''), <TokenType>[TokenType.eof]);
    });

    test('lexes field and param references with their names', () {
      final List<Token> tokens = tokenize(r'$F{qty} $P{tax}');
      expect(tokens[0].type, TokenType.fieldRef);
      expect(tokens[0].literal, 'qty');
      expect(tokens[1].type, TokenType.paramRef);
      expect(tokens[1].literal, 'tax');
      expect(tokens.last.type, TokenType.eof);
    });

    test('lexes number literals as doubles', () {
      expect(tokenize('5').first.literal, 5.0);
      expect(tokenize('2.5').first.literal, 2.5);
    });

    test('lexes single- and double-quoted strings with escapes', () {
      expect(tokenize("'hi'").first.literal, 'hi');
      expect(tokenize('"a\\"b"').first.literal, 'a"b');
    });

    test('lexes boolean and null keywords', () {
      expect(_types('true false null'), <TokenType>[
        TokenType.trueLiteral,
        TokenType.falseLiteral,
        TokenType.nullLiteral,
        TokenType.eof
      ]);
    });

    test('lexes identifiers (function names)', () {
      final Token t = tokenize('ROUND').first;
      expect(t.type, TokenType.identifier);
      expect(t.lexeme, 'ROUND');
    });

    test('lexes one- and two-character operators', () {
      expect(_types('+ - * / % == != < <= > >= && || ! ? : , ( )'), <TokenType>[
        TokenType.plus,
        TokenType.minus,
        TokenType.star,
        TokenType.slash,
        TokenType.percent,
        TokenType.equalEqual,
        TokenType.bangEqual,
        TokenType.less,
        TokenType.lessEqual,
        TokenType.greater,
        TokenType.greaterEqual,
        TokenType.andAnd,
        TokenType.orOr,
        TokenType.bang,
        TokenType.question,
        TokenType.colon,
        TokenType.comma,
        TokenType.leftParen,
        TokenType.rightParen,
        TokenType.eof,
      ]);
    });

    test('skips whitespace between tokens', () {
      expect(_types('  5\t+\n6 '), <TokenType>[
        TokenType.number,
        TokenType.plus,
        TokenType.number,
        TokenType.eof,
      ]);
    });

    test('throws on an unterminated string', () {
      expect(() => tokenize("'oops"), throwsA(isA<ExpressionException>()));
    });

    test('throws on an unterminated reference', () {
      expect(() => tokenize(r'$F{qty'), throwsA(isA<ExpressionException>()));
    });

    test('throws on an unexpected character', () {
      expect(() => tokenize('5 @ 6'), throwsA(isA<ExpressionException>()));
    });

    test('throws on a bad reference sigil (e.g. unsupported \$X)', () {
      expect(() => tokenize(r'$X{total}'), throwsA(isA<ExpressionException>()));
    });

    test('throws on an empty reference name', () {
      expect(() => tokenize(r'$F{}'), throwsA(isA<ExpressionException>()));
    });

    test('lexes a leading-dot number', () {
      expect(tokenize('.5').first.literal, 0.5);
    });

    test('throws on a bare "=" (not "==")', () {
      expect(() => tokenize('5 = 6'), throwsA(isA<ExpressionException>()));
    });

    test('throws on a bare "&" (not "&&")', () {
      expect(() => tokenize('1 & 2'), throwsA(isA<ExpressionException>()));
    });
  });
}
