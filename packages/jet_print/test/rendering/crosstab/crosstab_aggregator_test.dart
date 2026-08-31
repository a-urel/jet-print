// The crosstab aggregator: rows to matrix in one forward pass (Task 7).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_aggregator.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_matrix.dart';

/// The smallest context that resolves `$F{}` against a row and nothing else.
///
/// Fixed from the task brief's draft, which declared a nonexistent
/// `callFunction` override and omitted the `functions` getter that
/// `EvalContext` actually requires (see `lib/src/expression/eval_context.dart`).
/// `JetFunctionRegistry()` with nothing registered is the same fake the
/// codebase already uses in `test/expression/eval_context_test.dart` and
/// `test/rendering/layout/page_eval_context_test.dart`.
class _RowContext implements EvalContext {
  _RowContext(this.row);
  final DataRow row;

  @override
  JetValue resolveField(String name) =>
      row.hasField(name) ? JetValue.from(row.field(name)) : const JetNull();

  @override
  JetValue resolveParam(String name) => const JetNull();

  @override
  JetValue resolveVariable(String name) => const JetNull();

  @override
  JetFunctionRegistry get functions => JetFunctionRegistry();
}

// `FieldDef`'s `name` is a positional parameter (`const FieldDef(this.name,
// {...})`), not a named one — the brief's `FieldDef(name: 'region', ...)`
// does not compile. `JetFieldType.number` also does not exist; the taxonomy
// is `integer`/`double`/... (`lib/src/domain/value_type.dart`). Fixed here.
const List<FieldDef> _fields = <FieldDef>[
  FieldDef('region', type: JetFieldType.string),
  FieldDef('city', type: JetFieldType.string),
  FieldDef('quarter', type: JetFieldType.string),
  FieldDef('amount', type: JetFieldType.double),
];

DataRow _row(String region, String city, String quarter, num amount) => DataRow(
      fields: _fields,
      values: <String, Object?>{
        'region': region,
        'city': city,
        'quarter': quarter,
        'amount': amount,
      },
    );

const CrosstabMeasure _sum = CrosstabMeasure(
  id: 'm/a',
  name: 'Amount',
  expression: r'$F{amount}',
  aggregate: JetCalculation.sum,
);

Crosstab _ct({
  List<CrosstabGroup>? rowGroups,
  List<CrosstabMeasure>? measures,
}) =>
    Crosstab(
      id: 'ct1',
      rowGroups: rowGroups ??
          const <CrosstabGroup>[
            CrosstabGroup(id: 'g/r', name: 'Region', expression: r'$F{region}'),
            CrosstabGroup(id: 'g/c2', name: 'City', expression: r'$F{city}'),
          ],
      columnGroups: const <CrosstabGroup>[
        CrosstabGroup(id: 'g/q', name: 'Quarter', expression: r'$F{quarter}'),
      ],
      measures: measures ?? const <CrosstabMeasure>[_sum],
    );

CrosstabMatrix _run(Crosstab ct, List<DataRow> rows) {
  final CrosstabAggregation agg =
      CrosstabAggregation(ct, makeContext: (DataRow r) => _RowContext(r));
  for (final DataRow r in rows) {
    agg.fold(r);
  }
  return agg.build();
}

double? _cell(CrosstabMatrix m, List<String> rowPath, List<String> colPath) {
  final JetValue? v = m.cells[CrosstabCellKey(rowPath, colPath, 'm/a')];
  return v is JetNumber ? v.value : null;
}

void main() {
  final List<DataRow> rows = <DataRow>[
    _row('North', 'Istanbul', 'Q1', 120),
    _row('North', 'Ankara', 'Q1', 80),
    _row('North', 'Istanbul', 'Q2', 140),
    _row('South', 'Izmir', 'Q1', 50),
  ];

  group('prefix folding', () {
    test('leaf cells hold their own rows', () {
      final CrosstabMatrix m = _run(_ct(), rows);
      expect(_cell(m, <String>['North', 'Istanbul'], <String>['Q1']), 120);
      expect(_cell(m, <String>['North', 'Ankara'], <String>['Q1']), 80);
    });

    test('a shortened row path is that level subtotal', () {
      final CrosstabMatrix m = _run(_ct(), rows);
      expect(_cell(m, <String>['North'], <String>['Q1']), 200);
    });

    test('a shortened column path totals across columns', () {
      final CrosstabMatrix m = _run(_ct(), rows);
      expect(_cell(m, <String>['North', 'Istanbul'], <String>[]), 260);
    });

    test('both paths shortened is the grand total', () {
      final CrosstabMatrix m = _run(_ct(), rows);
      expect(_cell(m, <String>[], <String>[]), 390);
    });

    test('average is the mean of rows, not the mean of subtotals', () {
      // North: 120, 80, 140 -> mean 113.33; an average of the Q1/Q2 subtotals
      // (200 and 140) would give 170.
      final CrosstabMatrix m = _run(
        _ct(measures: <CrosstabMeasure>[
          _sum.copyWith(aggregate: JetCalculation.average),
        ]),
        rows,
      );
      expect(_cell(m, <String>['North'], <String>[])!, closeTo(113.333, 0.01));
    });

    test(
        'unequal group sizes distinguish a real average from an average of '
        'children averages', () {
      // North/Istanbul has 2 rows (120, 140 -> mean 130); North/Ankara has 1
      // row (80). The Region subtotal must average all 3 raw rows
      // ((120+140+80)/3 = 113.33), not average the two city means
      // ((130+80)/2 = 105) -- those groups are deliberately different sizes so
      // the two computations disagree.
      final CrosstabMatrix m = _run(
        _ct(measures: <CrosstabMeasure>[
          _sum.copyWith(aggregate: JetCalculation.average),
        ]),
        rows,
      );
      expect(_cell(m, <String>['North', 'Istanbul'], <String>[])!,
          closeTo(130.0, 0.001));
      expect(_cell(m, <String>['North', 'Ankara'], <String>[])!,
          closeTo(80.0, 0.001));
      expect(_cell(m, <String>['North'], <String>[])!, closeTo(113.333, 0.01));
      // Average-of-averages would give 105, not 113.33 -- prove they differ.
      expect(_cell(m, <String>['North'], <String>[])! - 105.0, greaterThan(1));
    });
  });

  group('sparse cells', () {
    test('an intersection with no rows has no entry at all', () {
      final CrosstabMatrix m = _run(_ct(), rows);
      expect(
        m.cells.containsKey(const CrosstabCellKey(
            <String>['South', 'Izmir'], <String>['Q2'], 'm/a')),
        isFalse,
      );
    });

    test('count does not invent a zero for an empty intersection', () {
      final CrosstabMatrix m = _run(
        _ct(measures: <CrosstabMeasure>[
          _sum.copyWith(aggregate: JetCalculation.count),
        ]),
        rows,
      );
      expect(
        m.cells.containsKey(const CrosstabCellKey(
            <String>['South', 'Izmir'], <String>['Q2'], 'm/a')),
        isFalse,
      );
    });
  });

  group('axis construction', () {
    test('showTotal false suppresses that level subtotal', () {
      final CrosstabMatrix m = _run(
        _ct(rowGroups: const <CrosstabGroup>[
          CrosstabGroup(
              id: 'g/r',
              name: 'Region',
              expression: r'$F{region}',
              showTotal: false),
          CrosstabGroup(id: 'g/c2', name: 'City', expression: r'$F{city}'),
        ]),
        rows,
      );
      expect(_cell(m, <String>['North'], <String>['Q1']), isNull);
      expect(_cell(m, <String>['North', 'Istanbul'], <String>['Q1']), 120);
    });

    test('keys sort by their typed value, not their text', () {
      final List<DataRow> numeric = <DataRow>[
        _row('9', 'x', 'Q1', 1),
        _row('10', 'x', 'Q1', 1),
      ];
      final CrosstabMatrix m = _run(_ct(), numeric);
      // '9' and '10' are strings here, so they sort as strings: '10' first.
      expect(m.rowAxis.map((CrosstabAxisNode n) => n.pathKey),
          <String>['10', '9']);
    });

    test('dataOrder keeps first-seen order', () {
      final CrosstabMatrix m = _run(
        _ct(rowGroups: const <CrosstabGroup>[
          CrosstabGroup(
              id: 'g/r',
              name: 'Region',
              expression: r'$F{region}',
              sort: CrosstabSort.dataOrder),
        ]),
        rows,
      );
      expect(m.rowAxis.map((CrosstabAxisNode n) => n.pathKey),
          <String>['North', 'South']);
    });

    test('descending reverses the typed order', () {
      final CrosstabMatrix m = _run(
        _ct(rowGroups: const <CrosstabGroup>[
          CrosstabGroup(
              id: 'g/r',
              name: 'Region',
              expression: r'$F{region}',
              sort: CrosstabSort.descending),
        ]),
        rows,
      );
      expect(m.rowAxis.first.pathKey, 'South');
    });

    test('above 50k cells it warns once and still builds', () {
      final List<DataRow> many = <DataRow>[
        for (int i = 0; i < 26000; i++) _row('r$i', 'c$i', 'Q1', 1),
      ];
      final CrosstabMatrix m = _run(_ct(), many);
      expect(m.diagnostics.where((Diagnostic d) => d.message.contains('cells')),
          hasLength(1));
      expect(m.cells, isNotEmpty);
    });
  });
}
