// End-to-end: parse + evaluate realistic expressions with built-ins (005a).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/built_in_functions.dart';
import 'package:jet_print/src/expression/value.dart';

DataRow _invoiceLine() => DataRow(
      fields: const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('price', type: JetFieldType.double),
        FieldDef('name', type: JetFieldType.string),
      ],
      values: <String, Object?>{'qty': 3, 'price': 4.5, 'name': 'Widget'},
    );

JetValue _eval(String src, {DataRow? row, Map<String, Object?>? params}) {
  final JetFunctionRegistry r = JetFunctionRegistry();
  registerBuiltInFunctions(r);
  return Expression.parse(src).evaluate(RowEvalContext(
    row: row,
    params: params ?? const <String, Object?>{},
    functions: r,
  ));
}

void main() {
  test('registerBuiltInFunctions wires all four families', () {
    final JetFunctionRegistry r = JetFunctionRegistry();
    registerBuiltInFunctions(r);
    for (final String name in <String>[
      'ABS', 'ROUND', 'MIN', 'MAX', 'CEIL', 'FLOOR', // math
      'UPPER', 'LOWER', 'TRIM', 'LENGTH', 'CONCAT', 'SUBSTRING', // string
      'IF', 'COALESCE', 'ISNULL', // logic
      'FORMAT', // format
    ]) {
      expect(r.lookup(name), isNotNull, reason: 'missing $name');
    }
  });

  test('computes a formatted line total', () {
    expect(
      _eval(r"FORMAT(ROUND($F{qty} * $F{price}, 2), '#,##0.00')",
          row: _invoiceLine()),
      const JetString('13.50'),
    );
  });

  test('builds a conditional label', () {
    expect(
      _eval(r"CONCAT(UPPER($F{name}), $F{qty} > 1 ? 's' : '')",
          row: _invoiceLine()),
      const JetString('WIDGETs'),
    );
  });

  test('coalesces a null field to a default and formats it', () {
    final DataRow row = DataRow(
      fields: const <FieldDef>[FieldDef('discount', type: JetFieldType.double)],
      values: <String, Object?>{'discount': null},
    );
    expect(_eval(r'COALESCE($F{discount}, 0)', row: row), const JetNumber(0));
  });

  test('formats a date param', () {
    expect(
      _eval(r"FORMAT($P{date}, 'yyyy-MM-dd')",
          params: <String, Object?>{'date': DateTime(2026, 6, 7)}),
      const JetString('2026-06-07'),
    );
  });

  test('a broken sub-expression renders as an error value, not a throw', () {
    expect(_eval(r'$F{qty} / 0', row: _invoiceLine()), isA<JetError>());
  });
}
