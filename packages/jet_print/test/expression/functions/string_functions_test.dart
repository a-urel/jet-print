// Built-in string functions (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/string_functions.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src) {
  final JetFunctionRegistry r = JetFunctionRegistry();
  registerStringFunctions(r);
  return Expression.parse(src).evaluate(RowEvalContext(functions: r));
}

void main() {
  test('UPPER / LOWER / TRIM', () {
    expect(_eval("UPPER('aB')"), const JetString('AB'));
    expect(_eval("LOWER('aB')"), const JetString('ab'));
    expect(_eval("TRIM('  hi  ')"), const JetString('hi'));
  });

  test('LENGTH returns a number', () {
    expect(_eval("LENGTH('abc')"), const JetNumber(3));
  });

  test('CONCAT stringifies and joins any args', () {
    expect(_eval("CONCAT('a', 'b', 'c')"), const JetString('abc'));
    expect(_eval("CONCAT('n=', 5)"), const JetString('n=5.0'));
    expect(_eval("CONCAT('x', null)"), const JetString('x'));
  });

  test('SUBSTRING with start and optional length, clamped', () {
    expect(_eval("SUBSTRING('abcdef', 1, 3)"), const JetString('bcd'));
    expect(_eval("SUBSTRING('abcdef', 4)"), const JetString('ef'));
    expect(_eval("SUBSTRING('abc', 1, 99)"), const JetString('bc')); // clamped
  });

  test('type errors', () {
    expect(_eval('UPPER(5)'), isA<JetError>());
    expect(_eval("LENGTH(5)"), isA<JetError>());
    expect(_eval("SUBSTRING('abc', 'x')"), isA<JetError>());
  });
}
