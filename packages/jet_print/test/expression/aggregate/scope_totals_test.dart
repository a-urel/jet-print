library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/domain/scope_total.dart';
import 'package:jet_print/src/expression/aggregate/scope_totals.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';

void main() {
  test('prepares an aggregate total into name + calc + argument', () {
    final specs = prepareScopeTotals(const <ScopeTotal>[
      ScopeTotal('orderTotal', r'SUM($F{lineTotal})'),
    ]);
    expect(specs, hasLength(1));
    expect(specs.single.name, 'orderTotal');
    expect(specs.single.calculation, JetCalculation.sum);
    final ctx = RowEvalContext(
      row: DataRow(
        fields: const <FieldDef>[
          FieldDef('lineTotal', type: JetFieldType.double),
        ],
        values: <String, Object?>{'lineTotal': 4.0},
      ),
      functions: JetFunctionRegistry(),
    );
    expect((specs.single.argument.evaluate(ctx) as JetNumber).value, 4.0);
  });

  test('keeps the whole inner of an expression-argument aggregate', () {
    final specs = prepareScopeTotals(const <ScopeTotal>[
      ScopeTotal('t', r'SUM($F{qty} * $F{unitPrice})'),
    ]);
    expect(specs.single.calculation, JetCalculation.sum);
    final ctx = RowEvalContext(
      row: DataRow(
        fields: const <FieldDef>[
          FieldDef('qty', type: JetFieldType.integer),
          FieldDef('unitPrice', type: JetFieldType.double),
        ],
        values: <String, Object?>{'qty': 2, 'unitPrice': 3.0},
      ),
      functions: JetFunctionRegistry(),
    );
    expect((specs.single.argument.evaluate(ctx) as JetNumber).value, 6.0);
  });

  test('a non-aggregate or unparseable expression is skipped (returns no spec)',
      () {
    expect(
      prepareScopeTotals(const <ScopeTotal>[ScopeTotal('t', r'$F{x} + 1')]),
      isEmpty,
    );
    expect(
      prepareScopeTotals(const <ScopeTotal>[ScopeTotal('t', r'SUM(')]),
      isEmpty,
    );
  });
}
