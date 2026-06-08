// VariableCalculator uses an injected EvalContext factory (007b).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/report_group.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/variable_calculator.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';

/// A context whose field lookups always return 99, to prove injection is used.
class _FixedContext implements EvalContext {
  _FixedContext(this.functions);
  @override
  final JetFunctionRegistry functions;
  @override
  JetValue resolveField(String name) => const JetNumber(99);
  @override
  JetValue resolveParam(String name) => const JetNull();
  @override
  JetValue resolveVariable(String name) => const JetNull();
}

void main() {
  test('injected factory replaces the default RowEvalContext', () {
    EvalContext factory({
      DataRow? row,
      Map<String, Object?> params = const <String, Object?>{},
      Map<String, JetValue> variables = const <String, JetValue>{},
      required JetFunctionRegistry functions,
    }) =>
        _FixedContext(functions);

    final VariableCalculator calc = VariableCalculator(
      variables: const <ReportVariable>[
        ReportVariable(name: 'v', expression: r'$F{x}'),
      ],
      groups: const <ReportGroup>[],
      functions: JetFunctionRegistry(),
      contextFactory: factory,
    )..start();
    calc.advance(DataRow(
      fields: const <FieldDef>[FieldDef('x', type: JetFieldType.integer)],
      values: <String, Object?>{'x': 1},
    ));
    // The real field is 1, but the injected context returns 99.
    expect(calc.valueOf('v'), const JetNumber(99));
  });
}
