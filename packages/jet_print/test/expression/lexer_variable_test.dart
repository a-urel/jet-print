// $V{} variable-reference lexing (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/lexer.dart';
import 'package:jet_print/src/expression/token.dart';

void main() {
  test('lexes a variable reference with its name', () {
    final List<Token> tokens = tokenize(r'$V{total}');
    expect(tokens.first.type, TokenType.variableRef);
    expect(tokens.first.literal, 'total');
  });

  test('field, param and variable references coexist', () {
    expect(
        tokenize(r'$F{a} $P{b} $V{c}').map((Token t) => t.type).toList(),
        <TokenType>[
          TokenType.fieldRef,
          TokenType.paramRef,
          TokenType.variableRef,
          TokenType.eof,
        ]);
  });
}
