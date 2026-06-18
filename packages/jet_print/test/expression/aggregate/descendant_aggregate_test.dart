library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/descendant_aggregate.dart';
import 'package:jet_print/src/expression/aggregate/variable_accumulator.dart';
import 'package:jet_print/src/expression/value.dart';

// Build a customer row carrying orders → lines, lines holding `lineTotal`.
DataRow _customer(List<List<double>> ordersOfLineTotals) => DataRow(
      fields: const <FieldDef>[
        FieldDef('orders', type: JetFieldType.collection, fields: <FieldDef>[
          FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
            FieldDef('lineTotal', type: JetFieldType.double),
          ]),
        ]),
      ],
      values: <String, Object?>{
        'orders': <Map<String, Object?>>[
          for (final List<double> lines in ordersOfLineTotals)
            <String, Object?>{
              'lines': <Map<String, Object?>>[
                for (final double t in lines)
                  <String, Object?>{'lineTotal': t},
              ],
            },
        ],
      },
    );

// A row's named collection as DataRows (mirrors the filler's childRowsOf, minus
// diagnostics). Returns [] when the field is absent or not a list of maps.
List<DataRow> _childRows(DataRow row, String name) {
  final Object? raw = row.field(name);
  if (raw is! List) return const <DataRow>[];
  final FieldDef declared = row.fields.firstWhere(
    (FieldDef f) => f.name == name,
    orElse: () => const FieldDef(''),
  );
  return <DataRow>[
    for (final Object? entry in raw)
      if (entry is Map)
        DataRow(
          fields: declared.fields,
          values: entry.map((Object? k, Object? v) =>
              MapEntry<String, Object?>(k.toString(), v)),
        ),
  ];
}

JetValue _lineTotal(DataRow leaf) => JetValue.from(leaf.field('lineTotal'));

void main() {
  test('flat SUM folds every descendant leaf across two collection levels', () {
    final VariableAccumulator acc = VariableAccumulator(JetCalculation.sum);
    foldDescendantLeaves(
      rows: <DataRow>[
        _customer(<List<double>>[
          <double>[10, 20],
          <double>[5],
        ]),
      ],
      path: <String>['orders', 'lines'],
      acc: acc,
      eval: _lineTotal,
      childRowsOf: _childRows,
    );
    expect((acc.value as JetNumber).value, 35.0);
  });

  test('flat AVG is sum over all leaves ÷ leaf count (not avg-of-averages)', () {
    final VariableAccumulator acc = VariableAccumulator(JetCalculation.average);
    foldDescendantLeaves(
      rows: <DataRow>[
        _customer(<List<double>>[
          <double>[10, 20], // order avg 15
          <double>[60], // order avg 60; avg-of-avgs would be 37.5
        ]),
      ],
      path: <String>['orders', 'lines'],
      acc: acc,
      eval: _lineTotal,
      childRowsOf: _childRows,
    );
    expect((acc.value as JetNumber).value, (10 + 20 + 60) / 3);
  });

  test('an empty path folds over the rows themselves (one-level case)', () {
    final VariableAccumulator acc = VariableAccumulator(JetCalculation.sum);
    foldDescendantLeaves(
      rows: <DataRow>[
        DataRow(
            fields: const <FieldDef>[FieldDef('lineTotal', type: JetFieldType.double)],
            values: <String, Object?>{'lineTotal': 7.0}),
        DataRow(
            fields: const <FieldDef>[FieldDef('lineTotal', type: JetFieldType.double)],
            values: <String, Object?>{'lineTotal': 3.0}),
      ],
      path: const <String>[],
      acc: acc,
      eval: _lineTotal,
      childRowsOf: _childRows,
    );
    expect((acc.value as JetNumber).value, 10.0);
  });

  test('empty descendant collections fold nothing (SUM 0)', () {
    final VariableAccumulator acc = VariableAccumulator(JetCalculation.sum);
    foldDescendantLeaves(
      rows: <DataRow>[_customer(const <List<double>>[])],
      path: <String>['orders', 'lines'],
      acc: acc,
      eval: _lineTotal,
      childRowsOf: _childRows,
    );
    expect((acc.value as JetNumber).value, 0.0);
  });
}
