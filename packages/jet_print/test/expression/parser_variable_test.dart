// Parsing $V{} (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/lexer.dart';
import 'package:jet_print/src/expression/parser.dart';

String _parse(String src) => Parser(tokenize(src)).parseExpression().toString();

void main() {
  test('parses a variable reference', () {
    expect(_parse(r'$V{total}'), '(var total)');
  });

  test('parses a variable in an arithmetic expression', () {
    expect(_parse(r'$V{total} + $F{tax}'), '(+ (var total) (field tax))');
  });
}
