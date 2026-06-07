// Built-in FORMAT function via intl (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/format_functions.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src) {
  final JetFunctionRegistry r = JetFunctionRegistry();
  registerFormatFunctions(r);
  return Expression.parse(src).evaluate(RowEvalContext(functions: r));
}

void main() {
  test('formats a number with a pattern', () {
    expect(_eval("FORMAT(1234.5, '#,##0.00')"), const JetString('1,234.50'));
  });

  test('rejects a non-number/non-date first argument', () {
    // The date happy path is exercised end-to-end in the Task 13 integration
    // test (a JetDate param); 005a expressions have no date literal syntax.
    expect(_eval("FORMAT('x', '#,##0')"), isA<JetError>());
  });

  test('arity and pattern-type errors', () {
    expect(_eval('FORMAT(5)'), isA<JetError>());
    expect(_eval('FORMAT(5, 5)'), isA<JetError>());
  });
}
