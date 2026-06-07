// Parser: tokens -> Expr, tested via canonical toString (spec 005a).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/expression_exception.dart';
import 'package:jet_print/src/expression/lexer.dart';
import 'package:jet_print/src/expression/parser.dart';

String _parse(String src) => Parser(tokenize(src)).parseExpression().toString();

void main() {
  group('Parser', () {
    test('parses a primary literal/reference', () {
      expect(_parse('5'), '5.0');
      expect(_parse(r'$F{qty}'), '(field qty)');
      expect(_parse(r'$P{tax}'), '(param tax)');
      expect(_parse("'hi'"), "'hi'");
      expect(_parse('true'), 'true');
      expect(_parse('null'), 'JetNull()');
    });

    test('multiplicative binds tighter than additive', () {
      expect(_parse('1 + 2 * 3'), '(+ 1.0 (* 2.0 3.0))');
    });

    test('parentheses override precedence', () {
      expect(_parse('(1 + 2) * 3'), '(* (+ 1.0 2.0) 3.0)');
    });

    test('left-associates same-precedence operators', () {
      expect(_parse('1 - 2 - 3'), '(- (- 1.0 2.0) 3.0)');
    });

    test('parses unary minus and not', () {
      expect(_parse('-5'), '(- 5.0)');
      expect(_parse('!true'), '(! true)');
    });

    test('comparison and equality precedence', () {
      expect(_parse('1 < 2 == true'), '(== (< 1.0 2.0) true)');
    });

    test('logical and binds tighter than or', () {
      expect(
          _parse('a() || b() && c()'), '(|| (call a) (&& (call b) (call c)))');
    });

    test('ternary is lowest precedence and right-associative', () {
      expect(_parse('true ? 1 : false ? 2 : 3'),
          '(if true 1.0 (if false 2.0 3.0))');
    });

    test('parses function calls with zero, one and many args', () {
      expect(_parse('NOW()'), '(call NOW)');
      expect(_parse('ABS(-5)'), '(call ABS (- 5.0))');
      expect(_parse('MAX(1, 2, 3)'), '(call MAX 1.0 2.0 3.0)');
    });

    test('parses a realistic expression', () {
      expect(_parse(r'ROUND($F{qty} * $F{price}, 2)'),
          '(call ROUND (* (field qty) (field price)) 2.0)');
    });

    test('nested ternary in the then-branch position', () {
      expect(_parse('a() ? b() ? 1 : 2 : 3'),
          '(if (call a) (if (call b) 1.0 2.0) 3.0)');
    });

    test('throws on a trailing operator', () {
      expect(() => _parse('1 +'), throwsA(isA<ExpressionException>()));
    });

    test('throws on an unbalanced parenthesis', () {
      expect(() => _parse('(1 + 2'), throwsA(isA<ExpressionException>()));
    });

    test('throws on trailing tokens after a complete expression', () {
      expect(() => _parse('1 2'), throwsA(isA<ExpressionException>()));
    });
  });
}
