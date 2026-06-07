// Built-in math functions (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/math_functions.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src) {
  final JetFunctionRegistry r = JetFunctionRegistry();
  registerMathFunctions(r);
  return Expression.parse(src).evaluate(RowEvalContext(functions: r));
}

void main() {
  test('ABS', () {
    expect(_eval('ABS(-5)'), const JetNumber(5));
    expect(_eval('ABS(5)'), const JetNumber(5));
  });

  test('ROUND with default and explicit digits', () {
    expect(_eval('ROUND(2.567)'), const JetNumber(3));
    expect(_eval('ROUND(2.567, 2)'), const JetNumber(2.57));
  });

  test('ROUND with out-of-range digits is an error (not a silent NaN)', () {
    expect(_eval('ROUND(2.5, 400)'), isA<JetError>());
  });

  test('CEIL and FLOOR', () {
    expect(_eval('CEIL(2.1)'), const JetNumber(3));
    expect(_eval('FLOOR(2.9)'), const JetNumber(2));
  });

  test('MIN and MAX are variadic', () {
    expect(_eval('MIN(3, 1, 2)'), const JetNumber(1));
    expect(_eval('MAX(3, 1, 2)'), const JetNumber(3));
    expect(_eval('MIN(7)'), const JetNumber(7));
  });

  test('non-number args are errors', () {
    expect(_eval("ABS('x')"), isA<JetError>());
    expect(_eval('MIN()'), isA<JetError>());
    expect(_eval('ABS(1, 2)'), isA<JetError>());
    expect(_eval("MIN(1, 'x', 2)"), isA<JetError>()); // mid-list non-number
  });
}
