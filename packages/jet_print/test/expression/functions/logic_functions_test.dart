// Built-in logic functions (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/logic_functions.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src) {
  final JetFunctionRegistry r = JetFunctionRegistry();
  registerLogicFunctions(r);
  return Expression.parse(src).evaluate(RowEvalContext(functions: r));
}

void main() {
  test('IF returns the chosen branch', () {
    expect(_eval("IF(true, 'a', 'b')"), const JetString('a'));
    expect(_eval("IF(false, 'a', 'b')"), const JetString('b'));
  });

  test('IF with a non-boolean condition is an error', () {
    expect(_eval("IF(1, 'a', 'b')"), isA<JetError>());
    expect(_eval("IF(true, 'a')"), isA<JetError>());
  });

  test('COALESCE returns the first non-null argument', () {
    expect(_eval('COALESCE(null, null, 3)'), const JetNumber(3));
    expect(_eval("COALESCE('x', 'y')"), const JetString('x'));
    expect(_eval('COALESCE(null, null)'), const JetNull());
  });

  test('ISNULL tests for null', () {
    expect(_eval('ISNULL(null)'), const JetBool(true));
    expect(_eval('ISNULL(0)'), const JetBool(false));
  });
}
