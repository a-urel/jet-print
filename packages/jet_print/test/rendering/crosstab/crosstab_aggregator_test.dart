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
  List<CrosstabGroup>? columnGroups,
  List<CrosstabMeasure>? measures,
}) =>
    Crosstab(
      id: 'ct1',
      rowGroups: rowGroups ??
          const <CrosstabGroup>[
            CrosstabGroup(id: 'g/r', name: 'Region', expression: r'$F{region}'),
            CrosstabGroup(id: 'g/c2', name: 'City', expression: r'$F{city}'),
          ],
      columnGroups: columnGroups ??
          const <CrosstabGroup>[
            CrosstabGroup(
                id: 'g/q', name: 'Quarter', expression: r'$F{quarter}'),
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

  group('min/max subtotals (SC-002)', () {
    // min and max are associative: the min (or max) of a subtotal's raw rows
    // always equals the min (or max) of its children's own mins (or maxes).
    // That means these two calculations, unlike average/first/last, CANNOT
    // distinguish a correct raw fold from a wrong rollup-of-children
    // implementation -- both produce the same number here. They are still
    // worth asserting (a mis-wired accumulator, a dropped row, or a wrong
    // cell key would still show up as a wrong number), but a pass here is not
    // evidence that subtotals are folded from raw rows.
    test('min is correct at a two-level subtotal and the grand total', () {
      final CrosstabMatrix m = _run(
        _ct(measures: <CrosstabMeasure>[
          _sum.copyWith(aggregate: JetCalculation.min),
        ]),
        rows,
      );
      // North: Istanbul/Q1 120, Ankara/Q1 80, Istanbul/Q2 140 -> min 80.
      expect(_cell(m, <String>['North'], <String>[]), 80);
      // Grand total over all four rows (120, 80, 140, 50) -> min 50.
      expect(_cell(m, <String>[], <String>[]), 50);
    });

    test('max is correct at a two-level subtotal and the grand total', () {
      final CrosstabMatrix m = _run(
        _ct(measures: <CrosstabMeasure>[
          _sum.copyWith(aggregate: JetCalculation.max),
        ]),
        rows,
      );
      // North: 120, 80, 140 -> max 140.
      expect(_cell(m, <String>['North'], <String>[]), 140);
      // Grand total over all four rows -> max 140 too (still North's row).
      expect(_cell(m, <String>[], <String>[]), 140);
    });
  });

  group('first/last subtotals (SC-002)', () {
    // Unlike min/max, `first`/`last` are order-sensitive: the first (or
    // last) raw row folded into a subtotal is whichever row arrived
    // first/last in STREAM order, regardless of which child group it belongs
    // to. A wrong implementation that instead rolled up each child's own
    // first/last -- combined in the axis's SORTED order (a natural mistake if
    // subtotals were computed as a post-pass over the already-sorted display
    // axis, rather than folded from raw rows as they stream) -- would
    // silently disagree whenever the chronologically-first/last row of a
    // group belongs to a child that does not also sort first/last
    // alphabetically. This fixture is built so that is exactly the case, at
    // both the region subtotal and the grand total, so a wrong
    // sorted-order-rollup implementation fails every assertion below.
    final List<DataRow> ordered = <DataRow>[
      _row('South', 'Cairo', 'Q1', 5), // position 1: earliest overall
      _row('North', 'Zurich', 'Q1', 10), // position 2: earliest within North
      _row('North', 'Amsterdam', 'Q1', 20), // position 3
      _row('North', 'Amsterdam', 'Q1', 30), // position 4: latest within North
      // ... and latest overall.
    ];

    test(
        'first is the chronologically-first row of the subtotal, not the '
        "alphabetically-first child's first row", () {
      final CrosstabMatrix m = _run(
        _ct(measures: <CrosstabMeasure>[
          _sum.copyWith(aggregate: JetCalculation.first),
        ]),
        ordered,
      );
      // Leaf sanity: each city's own first is unambiguous.
      expect(_cell(m, <String>['North', 'Zurich'], <String>[]), 10);
      expect(_cell(m, <String>['North', 'Amsterdam'], <String>[]), 20);
      // North's subtotal must be Zurich's row (10) -- the first row folded
      // into North in stream order -- even though "Amsterdam" sorts before
      // "Zurich" on the (alphabetically-ascending) city axis. A sorted-order
      // rollup combining {Amsterdam.first: 20, Zurich.first: 10} in that
      // order would report the first child processed, Amsterdam's 20 --
      // wrong.
      expect(_cell(m, <String>['North'], <String>[]), 10);
      // The grand total must be Cairo's row (5) -- the true first row of the
      // whole stream -- even though "North" sorts before "South" on the
      // region axis. A sorted-order rollup would fold North's own first
      // (whatever that computes to) before ever reaching South's 5 -- wrong.
      expect(_cell(m, <String>[], <String>[]), 5);
    });

    test(
        'last is the chronologically-last row of the subtotal, not the '
        "alphabetically-last child's last row", () {
      final CrosstabMatrix m = _run(
        _ct(measures: <CrosstabMeasure>[
          _sum.copyWith(aggregate: JetCalculation.last),
        ]),
        ordered,
      );
      // Leaf sanity: each city's own last is unambiguous.
      expect(_cell(m, <String>['North', 'Zurich'], <String>[]), 10);
      expect(_cell(m, <String>['North', 'Amsterdam'], <String>[]), 30);
      // North's subtotal must be Amsterdam's second row (30) -- the last row
      // folded into North in stream order -- even though "Zurich" sorts after
      // "Amsterdam" on the city axis. A sorted-order rollup combining
      // {Amsterdam.last: 30, Zurich.last: 10} in that order would report
      // whichever child is processed last, Zurich's 10 -- wrong.
      expect(_cell(m, <String>['North'], <String>[]), 30);
      // The grand total must be 30 (North/Amsterdam's second row, the true
      // last row of the whole stream), not South's 5.
      expect(_cell(m, <String>[], <String>[]), 30);
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
    // Each group's own showTotal gates the prefix that collapses THAT
    // group away (Jasper semantics: the city group's total aggregates
    // across cities within a region; the region group's total -- being
    // the outermost -- aggregates across regions, i.e. the grand total).
    // Prefix length k is gated by groups[k].showTotal; the full-length leaf
    // prefix is always folded, ungated. A single-level axis cannot
    // distinguish this from the (wrong) "last kept level" rule, because
    // with one group, groups[0] is simultaneously "the only level" and "the
    // outermost level" under both readings -- these two-level tests are
    // what pin it down.
    test('a group\'s own showTotal gates collapsing that group, not its parent',
        () {
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
      // City.showTotal (true, default) gates collapsing City -> the
      // Region-only prefix (City's own total) is folded.
      expect(_cell(m, <String>['North'], <String>['Q1']), 200);
      // Region.showTotal (false) gates collapsing Region -> the grand
      // total (Region's own total, since Region is outermost) is not.
      expect(_cell(m, <String>[], <String>[]), isNull);
      // The leaf is always folded regardless.
      expect(_cell(m, <String>['North', 'Istanbul'], <String>['Q1']), 120);
    });

    test(
        'the reverse split (outermost true, innermost false) proves the '
        'bijection, not just the direction', () {
      final CrosstabMatrix m = _run(
        _ct(rowGroups: const <CrosstabGroup>[
          CrosstabGroup(id: 'g/r', name: 'Region', expression: r'$F{region}'),
          CrosstabGroup(
              id: 'g/c2',
              name: 'City',
              expression: r'$F{city}',
              showTotal: false),
        ]),
        rows,
      );
      // Region.showTotal (true, default) gates the grand total -> present.
      expect(_cell(m, <String>[], <String>[]), 390);
      // City.showTotal (false) gates the Region-only prefix -> absent. The
      // "last kept level" rule would gate this by Region (true) instead and
      // wrongly produce 200 here.
      expect(_cell(m, <String>['North'], <String>['Q1']), isNull);
      // The leaf is always folded regardless.
      expect(_cell(m, <String>['North', 'Istanbul'], <String>['Q1']), 120);
    });

    test('string-keyed groups sort lexicographically ("10" before "9")', () {
      // This pins the STRING-keyed case only -- it does not exercise typed
      // (numeric) comparison, since every field in this fixture's row-group
      // expression is JetFieldType.string, so the key is a JetString either
      // way. A stringified comparator would pass this test too; see the
      // numeric-keyed test below for the case that actually distinguishes
      // typed comparison from a stringified one.
      final List<DataRow> stringKeyed = <DataRow>[
        _row('9', 'x', 'Q1', 1),
        _row('10', 'x', 'Q1', 1),
      ];
      final CrosstabMatrix m = _run(_ct(), stringKeyed);
      // '9' and '10' are strings here, so they sort as strings: '10' first.
      expect(m.rowAxis.map((CrosstabAxisNode n) => n.pathKey),
          <String>['10', '9']);
    });

    test('numeric-keyed groups sort by number, not by digit string', () {
      // Unlike the string-keyed test above, a numeric group key makes typed
      // and string order disagree: numerically 9 < 10, but as digit strings
      // '10' < '9'. Only a comparator that consults the typed JetValue (not
      // its stringified pathKey/label) can produce ['9', '10'] here.
      const List<FieldDef> numericFields = <FieldDef>[
        FieldDef('region', type: JetFieldType.integer),
        FieldDef('city', type: JetFieldType.string),
        FieldDef('quarter', type: JetFieldType.string),
        FieldDef('amount', type: JetFieldType.double),
      ];
      DataRow numericRow(int region, String city, String quarter, num amount) =>
          DataRow(
            fields: numericFields,
            values: <String, Object?>{
              'region': region,
              'city': city,
              'quarter': quarter,
              'amount': amount,
            },
          );
      final List<DataRow> numeric = <DataRow>[
        numericRow(9, 'x', 'Q1', 1),
        numericRow(10, 'x', 'Q1', 1),
      ];
      final CrosstabMatrix m = _run(_ct(), numeric);
      // JetValue's all-double model stringifies 9/10 as '9.0'/'10.0' (see
      // value.dart's `_doubleToString`) -- the point here is the ORDER
      // (numeric 9 before 10), not the exact text.
      expect(m.rowAxis.map((CrosstabAxisNode n) => n.pathKey),
          <String>['9.0', '10.0']);
    });

    test(
        "column-axis showTotal gates that column group's own collapse "
        '(mirrors the row-axis rule, wired to columnGroups instead)', () {
      // Same fixture as "a group's own showTotal gates collapsing that group,
      // not its parent" above, but with Region/City moved onto the COLUMN
      // axis and Quarter left as the (single-level) row axis. This exercises
      // `_prefixes(colPath, ct.columnGroups)` specifically -- a mis-wiring
      // that fed it `ct.rowGroups` instead would survive every other test in
      // this file, since they only vary rowGroups.
      final CrosstabMatrix m = _run(
        _ct(
          rowGroups: const <CrosstabGroup>[
            CrosstabGroup(
                id: 'g/q', name: 'Quarter', expression: r'$F{quarter}'),
          ],
          columnGroups: const <CrosstabGroup>[
            CrosstabGroup(
                id: 'g/r',
                name: 'Region',
                expression: r'$F{region}',
                showTotal: false),
            CrosstabGroup(id: 'g/c2', name: 'City', expression: r'$F{city}'),
          ],
        ),
        rows,
      );
      // City's own showTotal (true, default) gates collapsing City -> the
      // Region-only column (City's own total) is folded: North's Q1 rows
      // (Istanbul 120 + Ankara 80) sum to 200.
      expect(_cell(m, <String>['Q1'], <String>['North']), 200);
      // Region's own showTotal (false), being outermost on the COLUMN axis,
      // gates the column-axis grand total -> absent.
      expect(_cell(m, <String>[], <String>[]), isNull);
      // The leaf is always folded regardless.
      expect(_cell(m, <String>['Q1'], <String>['North', 'Istanbul']), 120);
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
  });

  group('cardinality', () {
    test('below the threshold, no cardinality diagnostic is raised', () {
      // Pins the threshold from below: without this test, a threshold of 0
      // (which would warn on every crosstab, however small) would still
      // leave the whole suite green, since only the above-threshold test
      // asserted anything about diagnostics.
      final CrosstabMatrix m = _run(_ct(), rows);
      expect(m.diagnostics, isEmpty);
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
