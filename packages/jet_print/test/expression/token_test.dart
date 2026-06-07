// Token vocabulary + ExpressionException (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/expression_exception.dart';
import 'package:jet_print/src/expression/token.dart';

void main() {
  test('ExpressionException carries a message and is an Exception', () {
    const ExpressionException e = ExpressionException('bad');
    expect(e, isA<Exception>());
    expect(e.message, 'bad');
    expect(e.toString(), contains('bad'));
  });

  test('Token exposes type, lexeme and optional literal', () {
    const Token t = Token(TokenType.number, '5', 5.0);
    expect(t.type, TokenType.number);
    expect(t.lexeme, '5');
    expect(t.literal, 5.0);
    expect(t.toString(), contains('number'));
  });

  test('TokenType enumerates the operator and literal kinds', () {
    // A representative spread — the lexer/parser depend on these existing.
    expect(
        TokenType.values,
        containsAll(<TokenType>[
          TokenType.number,
          TokenType.string,
          TokenType.fieldRef,
          TokenType.paramRef,
          TokenType.identifier,
          TokenType.plus,
          TokenType.andAnd,
          TokenType.question,
          TokenType.eof,
        ]));
  });
}
