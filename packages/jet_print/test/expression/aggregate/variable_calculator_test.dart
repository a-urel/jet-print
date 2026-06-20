// VariableCalculator: running totals, group resets, breaks (spec 005b).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/report_group.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/variable_calculator.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';

DataRow _row(String cat, double amount) => DataRow(
      fields: const <FieldDef>[
        FieldDef('category', type: JetFieldType.string),
        FieldDef('amount', type: JetFieldType.double),
      ],
      values: <String, Object?>{'category': cat, 'amount': amount},
    );

DataRow _rowAny(String cat, Object? amount) => DataRow(
      fields: const <FieldDef>[
        FieldDef('category', type: JetFieldType.string),
        FieldDef('amount', type: JetFieldType.double),
      ],
      values: <String, Object?>{'category': cat, 'amount': amount},
    );

VariableCalculator _calc() => VariableCalculator(
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
      ],
      groups: const <ReportGroup>[
        ReportGroup(name: 'category', expression: r'$F{category}'),
      ],
      functions: JetFunctionRegistry(),
    );

void main() {
  test('group total resets on a break; grand total runs through', () {
    final VariableCalculator c = _calc()..start();
    // A,10 -> A,5 -> B,3
    c.advance(_row('A', 10));
    expect(c.valueOf('catTotal'), const JetNumber(10));
    expect(c.valueOf('grand'), const JetNumber(10));

    c.advance(_row('A', 5));
    expect(c.valueOf('catTotal'), const JetNumber(15)); // running within A
    expect(c.valueOf('grand'), const JetNumber(15));
    expect(c.brokenGroups, isEmpty);

    c.advance(_row('B', 3));
    expect(c.brokenGroups, <String>{'category'}); // category changed A->B
    expect(c.valueOf('catTotal'), const JetNumber(3)); // reset, then +3
    expect(c.valueOf('grand'), const JetNumber(18)); // grand keeps running
  });

  test('exposes all current values', () {
    final VariableCalculator c = _calc()..start();
    c.advance(_row('A', 4));
    expect(c.values, <String, JetValue>{
      'catTotal': const JetNumber(4),
      'grand': const JetNumber(4),
    });
  });

  test('a variable may reference an earlier variable via \$V{}', () {
    final VariableCalculator c = VariableCalculator(
      variables: const <ReportVariable>[
        ReportVariable(name: 'base', expression: r'$F{amount}'),
        ReportVariable(name: 'doubled', expression: r'$V{base} * 2'),
      ],
      groups: const <ReportGroup>[],
      functions: JetFunctionRegistry(),
    )..start();
    c.advance(_row('A', 7));
    expect(c.valueOf('doubled'), const JetNumber(14));
  });

  test('the first row never reports a break', () {
    final VariableCalculator c = _calc()..start();
    c.advance(_row('A', 1));
    expect(c.brokenGroups, isEmpty);
  });

  test('an outer break cascades; an inner-only break does not', () {
    DataRow row(String region, String cat, double amt) => DataRow(
          fields: const <FieldDef>[
            FieldDef('region', type: JetFieldType.string),
            FieldDef('category', type: JetFieldType.string),
            FieldDef('amount', type: JetFieldType.double),
          ],
          values: <String, Object?>{
            'region': region,
            'category': cat,
            'amount': amt,
          },
        );
    final VariableCalculator c = VariableCalculator(
      variables: const <ReportVariable>[
        ReportVariable(
          name: 'regionTotal',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
          resetScope: VariableResetScope.group,
          resetGroup: 'region',
        ),
        ReportVariable(
          name: 'catTotal',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
          resetScope: VariableResetScope.group,
          resetGroup: 'category',
        ),
      ],
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'), // outer
        ReportGroup(name: 'category', expression: r'$F{category}'), // inner
      ],
      functions: JetFunctionRegistry(),
    )..start();

    c.advance(row('North', 'A', 1));
    c.advance(row('North', 'B', 2)); // inner-only break (category A->B)
    expect(c.brokenGroups, <String>{'category'});
    expect(c.valueOf('regionTotal'), const JetNumber(3)); // outer survives
    expect(c.valueOf('catTotal'), const JetNumber(2)); // inner reset, then +2

    c.advance(row('South', 'B', 4)); // outer break (region N->S) cascades inner
    expect(c.brokenGroups, <String>{'region', 'category'});
    expect(c.valueOf('regionTotal'), const JetNumber(4)); // reset, then +4
    expect(
        c.valueOf('catTotal'), const JetNumber(4)); // cascaded reset, then +4
  });

  test('start() re-seeds mid-session; valueOf of an undeclared name is JetNull',
      () {
    final VariableCalculator c = _calc()..start();
    c.advance(_row('A', 9));
    expect(c.valueOf('grand'), const JetNumber(9));
    expect(c.valueOf('nope'), const JetNull()); // undeclared

    c.start(); // re-seed
    expect(c.valueOf('grand'), const JetNull());
    expect(c.valueOf('catTotal'), const JetNull());
    expect(c.brokenGroups, isEmpty);
  });

  test('aggregateSkips counts wrong-type folds and is monotonic across a '
      'group break (reset does not lower it)', () {
    final VariableCalculator c = _calc()..start();
    c.advance(_rowAny('A', 10.0));
    expect(c.aggregateSkips, 0);
    // 'oops' folds into BOTH catTotal (group sum) and grand (report sum) -> +2.
    c.advance(_rowAny('A', 'oops'));
    expect(c.aggregateSkips, 2);
    // Group break resets catTotal's accumulator; the monotonic skip total must
    // NOT drop.
    c.advance(_rowAny('B', 3.0));
    expect(c.brokenGroups, <String>{'category'});
    expect(c.aggregateSkips, greaterThanOrEqualTo(2));
  });
}
