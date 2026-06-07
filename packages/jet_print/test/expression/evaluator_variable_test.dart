// Evaluating $V{} against context variables (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src, Map<String, JetValue> variables) =>
    Expression.parse(src).evaluate(RowEvalContext(
      variables: variables,
      functions: JetFunctionRegistry(),
    ));

void main() {
  test('resolves a variable to its current value', () {
    expect(
        _eval(r'$V{total}', <String, JetValue>{'total': const JetNumber(42)}),
        const JetNumber(42));
  });

  test('a missing variable resolves to JetNull', () {
    expect(_eval(r'$V{missing}', const <String, JetValue>{}), const JetNull());
  });

  test('variables compose with fields/arithmetic', () {
    expect(
      _eval(r'$V{subtotal} + 1',
          <String, JetValue>{'subtotal': const JetNumber(9)}),
      const JetNumber(10),
    );
  });
}
