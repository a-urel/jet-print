// End-to-end: calculator + element expression with $V{} (spec 005b).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/report_group.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/variable_calculator.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/built_in_functions.dart';
import 'package:jet_print/src/expression/value.dart';

const List<FieldDef> _schema = <FieldDef>[
  FieldDef('category', type: JetFieldType.string),
  FieldDef('amount', type: JetFieldType.double),
];

DataRow _row(String cat, double amt) => DataRow(
      fields: _schema,
      values: <String, Object?>{'category': cat, 'amount': amt},
    );

void main() {
  test('group subtotals, grand total, and a \$V-formatted element value', () {
    final JetFunctionRegistry fns = JetFunctionRegistry();
    registerBuiltInFunctions(fns);

    final VariableCalculator calc = VariableCalculator(
      variables: const <ReportVariable>[
        ReportVariable(
          name: 'catTotal',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
          resetScope: VariableResetScope.group,
          resetGroup: 'category',
        ),
        ReportVariable(
          name: 'grand',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
        ),
        ReportVariable(
          name: 'rowCount',
          expression: '1',
          calculation: JetCalculation.count,
        ),
      ],
      groups: const <ReportGroup>[
        ReportGroup(name: 'category', expression: r'$F{category}'),
      ],
      functions: fns,
    )..start();

    final List<DataRow> rows = <DataRow>[
      _row('A', 10),
      _row('A', 5),
      _row('B', 20),
    ];

    // An element expression a designer might bind to a footer cell.
    final Expression footer = Expression.parse(
        r"CONCAT('Subtotal: ', FORMAT($V{catTotal}, '#,##0.00'))");

    final List<String> footerValues = <String>[];
    for (final DataRow row in rows) {
      calc.advance(row);
      final JetValue v = footer.evaluate(RowEvalContext(
        row: row,
        variables: calc.values,
        functions: fns,
      ));
      footerValues.add((v as JetString).value);
    }

    // Running subtotals: A=10, A=15, then B resets to 20.
    expect(footerValues, <String>[
      'Subtotal: 10.00',
      'Subtotal: 15.00',
      'Subtotal: 20.00',
    ]);
    expect(calc.valueOf('grand'), const JetNumber(35)); // 10+5+20
    expect(calc.valueOf('rowCount'), const JetNumber(3));
  });
}
