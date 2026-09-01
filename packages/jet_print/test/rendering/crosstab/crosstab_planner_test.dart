// The crosstab planner: matrix to bands (Task 9).
//
// The correctness property that matters most here is that every total band and
// every total column addresses a path prefix the *aggregator* actually folded
// (`_prefixes` in `crosstab_aggregator.dart`: prefix length `k` is gated by
// `groups[k].showTotal`). The `∑ agrees with the aggregator` group below pins
// that against the real aggregator over real rows, with power-of-two amounts so
// that every subset sum is unique — any mis-addressed lookup yields a different
// number rather than a coincidentally equal one.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_aggregator.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_matrix.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_planner.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';

import 'crosstab_fixtures.dart';

// ---------------------------------------------------------------------------
// Hand-built fixtures
// ---------------------------------------------------------------------------

/// [axisNode], scoped under this file's original helper name.
CrosstabAxisNode _n(
  String k, {
  int depth = 0,
  List<CrosstabAxisNode> children = const <CrosstabAxisNode>[],
}) =>
    axisNode(k, depth: depth, children: children);

const CrosstabMeasure _amount = amountMeasure;

const CrosstabMeasure _units = CrosstabMeasure(
  id: 'm/u',
  name: 'Units',
  expression: r'$F{units}',
  aggregate: JetCalculation.sum,
);

// The base fixtures deliberately switch every total OFF, so the plain-shape
// tests below pin the no-total shape exactly; the totals group switches them
// back on.
const CrosstabGroup _gRegion = regionGroup;
const CrosstabGroup _gCity = CrosstabGroup(
    id: 'g/city', name: 'City', expression: r'$F{city}', showTotal: false);
const CrosstabGroup _gQuarter = quarterGroup;
const CrosstabGroup _gYear = CrosstabGroup(
    id: 'g/y', name: 'Year', expression: r'$F{year}', showTotal: false);

const CrosstabStyle _style = crosstabStyle;

/// A single-level crosstab, 50pt columns, 100pt row labels, no totals.
const Crosstab ct = baseCrosstab;

/// North/South x Q1/Q2, fully populated.
final CrosstabMatrix matrix = CrosstabMatrix(
  rowAxis: <CrosstabAxisNode>[_n('North'), _n('South')],
  columnAxis: <CrosstabAxisNode>[_n('Q1'), _n('Q2')],
  measures: const <CrosstabMeasure>[_amount],
  cells: <CrosstabCellKey, JetValue>{
    const CrosstabCellKey(<String>['North'], <String>['Q1'], 'm/a'):
        const JetNumber(120),
    const CrosstabCellKey(<String>['North'], <String>['Q2'], 'm/a'):
        const JetNumber(140),
    const CrosstabCellKey(<String>['South'], <String>['Q1'], 'm/a'):
        const JetNumber(80),
    const CrosstabCellKey(<String>['South'], <String>['Q2'], 'm/a'):
        const JetNumber(110),
  },
);

/// South x Q2 is missing — the empty-cell case.
final CrosstabMatrix sparseMatrix = CrosstabMatrix(
  rowAxis: matrix.rowAxis,
  columnAxis: matrix.columnAxis,
  measures: const <CrosstabMeasure>[_amount],
  cells: <CrosstabCellKey, JetValue>{
    const CrosstabCellKey(<String>['South'], <String>['Q1'], 'm/a'):
        const JetNumber(80),
  },
);

/// Two column levels: 2025 over Q1/Q2 — for the header-span assertion.
final Crosstab ct2 =
    ct.copyWith(columnGroups: <CrosstabGroup>[_gYear, _gQuarter]);
final CrosstabMatrix matrix2 = CrosstabMatrix(
  rowAxis: <CrosstabAxisNode>[_n('North')],
  columnAxis: <CrosstabAxisNode>[
    _n('2025', children: <CrosstabAxisNode>[
      _n('Q1', depth: 1),
      _n('Q2', depth: 1),
    ]),
  ],
  measures: const <CrosstabMeasure>[_amount],
  cells: <CrosstabCellKey, JetValue>{
    const CrosstabCellKey(<String>['North'], <String>['2025', 'Q1'], 'm/a'):
        const JetNumber(120),
    const CrosstabCellKey(<String>['North'], <String>['2025', 'Q2'], 'm/a'):
        const JetNumber(140),
  },
);

/// Two row levels — for the indent assertions.
final Crosstab ctRows2 =
    ct.copyWith(rowGroups: <CrosstabGroup>[_gRegion, _gCity]);
final CrosstabMatrix matrixRows2 = CrosstabMatrix(
  rowAxis: <CrosstabAxisNode>[
    _n('North', children: <CrosstabAxisNode>[
      _n('Ankara', depth: 1),
      _n('Istanbul', depth: 1),
    ]),
    _n('South', children: <CrosstabAxisNode>[_n('Izmir', depth: 1)]),
  ],
  columnAxis: <CrosstabAxisNode>[_n('Q1'), _n('Q2')],
  measures: const <CrosstabMeasure>[_amount],
  cells: <CrosstabCellKey, JetValue>{
    const CrosstabCellKey(<String>['North', 'Ankara'], <String>['Q1'], 'm/a'):
        const JetNumber(1),
  },
);

/// The same matrix over a different measure list. The planner prints the
/// **matrix's** measures (they are what was folded, and what `sliceColumns`
/// built its columns from), so a fixture that overrides a measure must
/// override it on both sides.
CrosstabMatrix _reMeasured(CrosstabMatrix m, List<CrosstabMeasure> measures) =>
    CrosstabMatrix(
      rowAxis: m.rowAxis,
      columnAxis: m.columnAxis,
      measures: measures,
      cells: m.cells,
    );

/// Eight columns — forces several slices at a 220pt page width.
final CrosstabMatrix wideMatrix = CrosstabMatrix(
  rowAxis: <CrosstabAxisNode>[_n('North')],
  columnAxis: <CrosstabAxisNode>[for (int i = 0; i < 8; i++) _n('Q$i')],
  measures: const <CrosstabMeasure>[_amount],
  cells: <CrosstabCellKey, JetValue>{
    for (int i = 0; i < 8; i++)
      CrosstabCellKey(const <String>['North'], <String>['Q$i'], 'm/a'):
          JetNumber(i.toDouble()),
  },
);

// ---------------------------------------------------------------------------
// Aggregator-backed fixture (the addressing-agreement check)
// ---------------------------------------------------------------------------

/// The smallest context that resolves `$F{}` against a row and nothing else.
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

const List<FieldDef> _fields = <FieldDef>[
  FieldDef('region', type: JetFieldType.string),
  FieldDef('city', type: JetFieldType.string),
  FieldDef('year', type: JetFieldType.string),
  FieldDef('quarter', type: JetFieldType.string),
  FieldDef('amount', type: JetFieldType.double),
];

DataRow _row(
        String region, String city, String year, String quarter, num amount) =>
    DataRow(
      fields: _fields,
      values: <String, Object?>{
        'region': region,
        'city': city,
        'year': year,
        'quarter': quarter,
        'amount': amount,
      },
    );

/// A full 3-city x 2-year x 2-quarter cross product whose amounts are distinct
/// powers of two, so **every subset sum is unique**: a total that addressed the
/// wrong prefix would print a different number, never a coincidentally right
/// one.
final List<DataRow> _totalRows = <DataRow>[
  for (final (int i, (String region, String city, String year, String quarter))
      in <(String, String, String, String)>[
    ('North', 'Istanbul', '2025', 'Q1'),
    ('North', 'Istanbul', '2025', 'Q2'),
    ('North', 'Istanbul', '2026', 'Q1'),
    ('North', 'Istanbul', '2026', 'Q2'),
    ('North', 'Ankara', '2025', 'Q1'),
    ('North', 'Ankara', '2025', 'Q2'),
    ('North', 'Ankara', '2026', 'Q1'),
    ('North', 'Ankara', '2026', 'Q2'),
    ('South', 'Izmir', '2025', 'Q1'),
    ('South', 'Izmir', '2025', 'Q2'),
    ('South', 'Izmir', '2026', 'Q1'),
    ('South', 'Izmir', '2026', 'Q2'),
  ].indexed)
    _row(region, city, year, quarter, 1 << i),
];

/// Every level totalled, on both axes.
final Crosstab ctTotals = Crosstab(
  id: 'ct1',
  rowGroups: <CrosstabGroup>[
    _gRegion.copyWith(showTotal: true),
    _gCity.copyWith(showTotal: true),
  ],
  columnGroups: <CrosstabGroup>[
    _gYear.copyWith(showTotal: true),
    _gQuarter.copyWith(showTotal: true),
  ],
  measures: const <CrosstabMeasure>[_amount],
  style: _style,
);

CrosstabMatrix _aggregate(Crosstab spec, List<DataRow> rows) {
  final CrosstabAggregation agg =
      CrosstabAggregation(spec, makeContext: (DataRow r) => _RowContext(r));
  for (final DataRow r in rows) {
    agg.fold(r);
  }
  return agg.build();
}

// ---------------------------------------------------------------------------
// Plan readers
// ---------------------------------------------------------------------------

List<FilledBand> _headers(CrosstabPlan p) => p.bands
    .where((FilledBand b) => b.type == BandType.groupHeader)
    .toList(growable: false);

List<FilledBand> _details(CrosstabPlan p) => p.bands
    .where((FilledBand b) => b.type == BandType.detail)
    .toList(growable: false);

List<TextElement> _textsOf(FilledBand b) =>
    b.elements.whereType<TextElement>().toList(growable: false);

List<String> _labelsOf(FilledBand b) =>
    <String>[for (final TextElement e in _textsOf(b)) e.text];

/// The row-label text of a detail band (the element whose id ends `/label`).
String _rowLabel(FilledBand b) =>
    _textsOf(b).firstWhere((TextElement e) => e.id.endsWith('/label')).text;

/// The cell texts of a detail band, in column order (everything but the label).
List<String> _rowCells(FilledBand b) => <String>[
      for (final TextElement e in _textsOf(b))
        if (!e.id.endsWith('/label')) e.text,
    ];

FilledBand _rowNamed(CrosstabPlan p, String label) =>
    _details(p).firstWhere((FilledBand b) => _rowLabel(b) == label);

List<String> _allIds(CrosstabPlan p) => <String>[
      for (final FilledBand band in p.bands)
        for (final ReportElement e in band.elements) e.id,
    ];

void main() {
  group('plan shape', () {
    test('emits header bands, row bands, and a closing footer', () {
      final CrosstabPlan plan = planCrosstab(ct, matrix, availableWidth: 500);
      expect(
        plan.bands.map((FilledBand b) => b.type),
        <BandType>[
          BandType.groupHeader,
          BandType.detail,
          BandType.detail,
          BandType.groupFooter,
        ],
      );
      expect(plan.bands.first.height, 20); // headerRowHeight
      expect(plan.bands[1].height, 14); // rowHeight
      expect(plan.bands.last.height, 0);
      expect(plan.bands.last.elements, isEmpty);
      expect(plan.diagnostics, isEmpty);
    });

    test('the closing footer is emitted once, after the last slice', () {
      final CrosstabPlan plan =
          planCrosstab(ct, wideMatrix, availableWidth: 220);
      expect(
        plan.bands.where((FilledBand b) => b.type == BandType.groupFooter),
        hasLength(1),
      );
      expect(plan.bands.last.type, BandType.groupFooter);
    });

    test('exactly one synthetic group, with reprint and startNewPage', () {
      final CrosstabPlan plan = planCrosstab(ct, matrix, availableWidth: 500);
      expect(plan.syntheticGroups, hasLength(1));
      final GroupLevel g = plan.syntheticGroups.single;
      expect(g.id, 'ct1#ct');
      expect(g.name, 'ct1#ct');
      expect(g.key, "'ct1'");
      expect(g.reprintHeaderOnEachPage, isTrue);
      expect(g.startNewPage, isTrue);
    });

    test('only header and footer bands carry the synthetic group name', () {
      final CrosstabPlan plan =
          planCrosstab(ct, wideMatrix, availableWidth: 220);
      for (final FilledBand b in plan.bands) {
        expect(
          b.group,
          b.type == BandType.detail ? isNull : 'ct1#ct',
          reason: 'band ${b.type.name}',
        );
      }
    });

    test('a colliding user group name is an error diagnostic', () {
      final CrosstabPlan plan = planCrosstab(ct, matrix,
          availableWidth: 500, takenGroupNames: <String>{'ct1#ct'});
      expect(
        plan.diagnostics.map((Diagnostic d) => d.message),
        anyElement(contains('group name')),
      );
      expect(
        plan.diagnostics.map((Diagnostic d) => d.severity),
        contains(DiagnosticSeverity.error),
      );
      // Still planned: render-don't-crash.
      expect(plan.syntheticGroups, hasLength(1));
      expect(_details(plan), isNotEmpty);
    });

    test('an empty matrix plans nothing at all', () {
      final CrosstabPlan plan = planCrosstab(
        ct,
        const CrosstabMatrix(
          rowAxis: <CrosstabAxisNode>[],
          columnAxis: <CrosstabAxisNode>[],
          measures: <CrosstabMeasure>[_amount],
          cells: <CrosstabCellKey, JetValue>{},
        ),
        availableWidth: 500,
      );
      expect(plan.bands, isEmpty);
    });

    test('slicing diagnostics are forwarded', () {
      // budget = 60 - 100 < 0: no leaf fits, which sliceColumns warns about.
      final CrosstabPlan plan = planCrosstab(ct, matrix, availableWidth: 60);
      expect(
        plan.diagnostics.map((Diagnostic d) => d.message),
        anyElement(contains('wider than the page body')),
      );
    });
  });

  group('column headers', () {
    test('one header band per column-group level', () {
      expect(_headers(planCrosstab(ct, matrix, availableWidth: 500)),
          hasLength(1));
      expect(_headers(planCrosstab(ct2, matrix2, availableWidth: 500)),
          hasLength(2));
    });

    test('a header cell spans the leaves beneath it', () {
      // Year 2025 over Q1 and Q2, one measure of 50pt -> a 100pt header cell,
      // starting after the 100pt row-label column.
      final CrosstabPlan plan = planCrosstab(ct2, matrix2, availableWidth: 500);
      final TextElement top = _textsOf(_headers(plan).first).single;
      expect(top.text, '2025');
      expect(top.bounds.x, 100);
      expect(top.bounds.width, 100);
      expect(top.bounds.height, 20);
      expect(top.id, 'ct1/s0/h0/c0');
    });

    test('the innermost header level is one cell per leaf', () {
      final CrosstabPlan plan = planCrosstab(ct2, matrix2, availableWidth: 500);
      final List<TextElement> inner = _textsOf(_headers(plan)[1]);
      expect(inner.map((TextElement e) => e.text), <String>['Q1', 'Q2']);
      expect(inner.map((TextElement e) => e.bounds.x), <double>[100, 150]);
      expect(inner.map((TextElement e) => e.bounds.width), <double>[50, 50]);
      expect(inner.map((TextElement e) => e.id),
          <String>['ct1/s0/h1/c0', 'ct1/s0/h1/c1']);
    });

    test('a measure-name band appears only when there are 2+ measures', () {
      expect(_headers(planCrosstab(ct, matrix, availableWidth: 500)),
          hasLength(1));

      final Crosstab two =
          ct.copyWith(measures: <CrosstabMeasure>[_amount, _units]);
      final CrosstabMatrix twoM = CrosstabMatrix(
        rowAxis: matrix.rowAxis,
        columnAxis: matrix.columnAxis,
        measures: const <CrosstabMeasure>[_amount, _units],
        cells: const <CrosstabCellKey, JetValue>{},
      );
      final CrosstabPlan plan = planCrosstab(two, twoM, availableWidth: 500);
      final List<FilledBand> headers = _headers(plan);
      expect(headers, hasLength(2));
      expect(_labelsOf(headers[1]),
          <String>['Amount', 'Units', 'Amount', 'Units']);
      expect(_textsOf(headers[1]).first.id, 'ct1/s0/hm/c0');
      // A leaf now spans both of its measure columns.
      expect(_textsOf(headers[0]).first.bounds.width, 100);
    });

    test(
        'a header level with no cells in a slice still emits a full-height, '
        'empty band', () {
      // A slice holding ONLY the grand-total column has no ancestor at the
      // inner (Quarter) level for that leaf -- `_ancestorId` returns null --
      // so that level's header band for this slice carries zero elements.
      // `headerBands` still emits it at the usual `headerRowHeight` (see its
      // dartdoc): keeping every header level's height uniform across slices
      // is what lets a horizontal-continuation page's header block still line
      // up level-for-level with every other slice's.
      final Crosstab spec = Crosstab(
        id: 'ct1',
        rowGroups: const <CrosstabGroup>[_gRegion],
        columnGroups: <CrosstabGroup>[
          _gYear.copyWith(showTotal: true),
          _gQuarter,
        ],
        measures: const <CrosstabMeasure>[_amount],
        style: _style,
      );
      final CrosstabMatrix m = CrosstabMatrix(
        rowAxis: <CrosstabAxisNode>[_n('North')],
        columnAxis: <CrosstabAxisNode>[
          _n('2025', children: <CrosstabAxisNode>[
            _n('Q1', depth: 1),
            _n('Q2', depth: 1),
          ]),
        ],
        measures: const <CrosstabMeasure>[_amount],
        cells: const <CrosstabCellKey, JetValue>{},
      );
      // budget = 170 - 100 = 70: one 50pt leaf per slice. Q1, Q2 and the
      // grand total (reserved for Q2's slice but too big to join it) each end
      // up alone: [Q1] [Q2] [grand total].
      final CrosstabPlan plan = planCrosstab(spec, m, availableWidth: 170);
      final List<FilledBand> headers = _headers(plan);
      expect(headers, hasLength(6)); // 2 levels x 3 slices
      final FilledBand yearLevelLastSlice = headers[4];
      final FilledBand quarterLevelLastSlice = headers[5];
      expect(_labelsOf(yearLevelLastSlice), <String>['Total']);
      expect(quarterLevelLastSlice.elements, isEmpty);
      expect(quarterLevelLastSlice.height, _style.headerRowHeight);
    });
  });

  group('row walk', () {
    test('an inner node prints a label-only row, a leaf prints cells', () {
      final CrosstabPlan plan =
          planCrosstab(ctRows2, matrixRows2, availableWidth: 500);
      final List<FilledBand> rows = _details(plan);
      expect(rows.map(_rowLabel),
          <String>['North', 'Ankara', 'Istanbul', 'South', 'Izmir']);
      expect(_rowCells(rows[0]), isEmpty); // North: label only
      expect(_rowCells(rows[1]), hasLength(2)); // Ankara: two columns
    });

    test('a leaf row is indented by its depth', () {
      final CrosstabPlan plan =
          planCrosstab(ctRows2, matrixRows2, availableWidth: 500);
      final List<FilledBand> rows = _details(plan);
      final TextElement north = _textsOf(rows[0]).first;
      final TextElement ankara = _textsOf(rows[1]).first;
      expect(north.bounds.x, 0);
      expect(north.bounds.width, 100);
      expect(ankara.bounds.x, 12); // depth 1 * rowLabelIndent
      expect(ankara.bounds.width, 88); // the label column, less the indent
      expect(ankara.id, 'ct1/s0/r1/label');
    });

    test('cells sit after the row-label column, one per slice column', () {
      final CrosstabPlan plan = planCrosstab(ct, matrix, availableWidth: 500);
      final FilledBand north = _details(plan).first;
      final List<TextElement> cells = _textsOf(north)
          .where((TextElement e) => !e.id.endsWith('/label'))
          .toList();
      expect(cells.map((TextElement e) => e.text), <String>['120.0', '140.0']);
      expect(cells.map((TextElement e) => e.bounds.x), <double>[100, 150]);
      expect(cells.map((TextElement e) => e.bounds.width), <double>[50, 50]);
      expect(cells.map((TextElement e) => e.id),
          <String>['ct1/s0/r0/c0/mm/a', 'ct1/s0/r0/c1/mm/a']);
    });

    test('an empty intersection prints an empty string, not a zero', () {
      final CrosstabPlan plan =
          planCrosstab(ct, sparseMatrix, availableWidth: 500);
      final Iterable<String> texts = plan.bands
          .expand((FilledBand b) => b.elements)
          .whereType<TextElement>()
          .map((TextElement e) => e.text);
      expect(texts, contains(''));
      expect(texts, isNot(contains('0')));
      expect(texts, isNot(contains('0.0')));
    });

    test('a measure format is applied to the cell value', () {
      final CrosstabMeasure formatted =
          _amount.copyWith(format: () => '#,##0.00');
      final CrosstabPlan plan = planCrosstab(
        ct.copyWith(measures: <CrosstabMeasure>[formatted]),
        _reMeasured(matrix, <CrosstabMeasure>[formatted]),
        availableWidth: 500,
      );
      expect(_rowCells(_details(plan).first), <String>['120.00', '140.00']);
    });
  });

  group('styling', () {
    test('an unstyled crosstab emits no shapes', () {
      final CrosstabPlan plan = planCrosstab(ct, matrix, availableWidth: 500);
      expect(
        plan.bands
            .expand((FilledBand b) => b.elements)
            .whereType<ShapeElement>(),
        isEmpty,
      );
    });

    test('a styled cell emits its box behind its text', () {
      const JetBoxStyle box = JetBoxStyle(fill: JetColor(0xFFEEEEEE));
      final Crosstab styled =
          ct.copyWith(style: _style.copyWith(cellBox: () => box));
      final CrosstabPlan plan =
          planCrosstab(styled, matrix, availableWidth: 500);
      final FilledBand north = _details(plan).first;
      // label (no headerBox) then box/text per cell.
      expect(north.elements.map((ReportElement e) => e.id), <String>[
        'ct1/s0/r0/label',
        'ct1/s0/r0/c0/mm/a/box',
        'ct1/s0/r0/c0/mm/a',
        'ct1/s0/r0/c1/mm/a/box',
        'ct1/s0/r0/c1/mm/a',
      ]);
      final ShapeElement shape = north.elements.whereType<ShapeElement>().first;
      expect(shape.kind, ShapeKind.rectangle);
      expect(shape.style, box);
      expect(shape.bounds.x, 100);
      expect(shape.bounds.width, 50);
    });

    test("a measure's own box style overrides the crosstab's", () {
      const JetBoxStyle mine = JetBoxStyle(fill: JetColor(0xFF00FF00));
      final CrosstabMeasure overridden =
          _amount.copyWith(cellBoxStyle: () => mine);
      final Crosstab styled = ct.copyWith(
        style: _style.copyWith(
            cellBox: () => const JetBoxStyle(fill: JetColor(0xFFEEEEEE))),
        measures: <CrosstabMeasure>[overridden],
      );
      final CrosstabPlan plan = planCrosstab(
        styled,
        _reMeasured(matrix, <CrosstabMeasure>[overridden]),
        availableWidth: 500,
      );
      expect(
        _details(plan).first.elements.whereType<ShapeElement>().first.style,
        mine,
      );
    });

    test(
        'measure cells and total values are right-aligned; total labels stay '
        'left (spec A §3)', () {
      final CrosstabMatrix m = _aggregate(ctTotals, _totalRows);
      final CrosstabPlan plan = planCrosstab(ctTotals, m, availableWidth: 600);
      TextElement valueOf(FilledBand b) =>
          _textsOf(b).firstWhere((TextElement e) => !e.id.endsWith('/label'));
      TextElement labelOf(FilledBand b) =>
          _textsOf(b).firstWhere((TextElement e) => e.id.endsWith('/label'));

      // An ordinary (non-total) measure cell.
      final FilledBand istanbul = _rowNamed(plan, 'Istanbul');
      expect(valueOf(istanbul).style.align, JetTextAlign.right);

      // A total row's VALUE cells right-align, same as an ordinary cell...
      final FilledBand totalNorth = _rowNamed(plan, 'Total North');
      expect(valueOf(totalNorth).style.align, JetTextAlign.right);
      // ...but its own LABEL stays left-aligned.
      expect(labelOf(totalNorth).style.align, JetTextAlign.left);

      // The grand total: same pattern.
      final FilledBand grandTotal = _rowNamed(plan, 'Total');
      expect(valueOf(grandTotal).style.align, JetTextAlign.right);
      expect(labelOf(grandTotal).style.align, JetTextAlign.left);
    });
  });

  group('slicing', () {
    test('element ids are deterministic and slice-scoped', () {
      final CrosstabPlan a = planCrosstab(ct, matrix, availableWidth: 500);
      final CrosstabPlan b = planCrosstab(ct, matrix, availableWidth: 500);
      expect(_allIds(a), equals(_allIds(b)));
      expect(_allIds(a), everyElement(startsWith('ct1/s0/')));
    });

    test('a narrow page produces slice-1 bands after slice-0 bands', () {
      final CrosstabPlan plan =
          planCrosstab(ct, wideMatrix, availableWidth: 220);
      final List<String> ids = _allIds(plan);
      expect(ids.where((String i) => i.contains('/s1/')), isNotEmpty);
      expect(
        ids.indexWhere((String i) => i.contains('/s1/')),
        greaterThan(ids.lastIndexWhere((String i) => i.contains('/s0/'))),
      );
    });

    test('every slice repeats the header bands and every row', () {
      // budget = 220 - 100 = 120 -> two 50pt columns per slice, 8 columns -> 4.
      final CrosstabPlan plan =
          planCrosstab(ct, wideMatrix, availableWidth: 220);
      expect(_headers(plan), hasLength(4));
      expect(_details(plan), hasLength(4)); // one row (North) x 4 slices
      expect(_labelsOf(_headers(plan).first), <String>['Q0', 'Q1']);
      expect(_labelsOf(_headers(plan)[3]), <String>['Q6', 'Q7']);
    });
  });

  group('totals', () {
    test('a total column is appended per level whose group allows it', () {
      final CrosstabMatrix m = _aggregate(ctTotals, _totalRows);
      final CrosstabPlan plan = planCrosstab(ctTotals, m, availableWidth: 600);
      final List<FilledBand> headers = _headers(plan);
      expect(headers, hasLength(2));
      // Level 0: each year spans Q1, Q2 and its own subtotal (3 x 50pt); the
      // grand total is a depth-0 leaf with a single 50pt cell.
      expect(_labelsOf(headers[0]), <String>['2025', '2026', 'Total']);
      expect(_textsOf(headers[0]).map((TextElement e) => e.bounds.width),
          <double>[150, 150, 50]);
      // Level 1: the grand-total column has no level-1 ancestor, so no cell.
      expect(_labelsOf(headers[1]),
          <String>['Q1', 'Q2', 'Total 2025', 'Q1', 'Q2', 'Total 2026']);
    });

    test('total rows appear on leaving a node, then the grand total', () {
      final CrosstabMatrix m = _aggregate(ctTotals, _totalRows);
      final CrosstabPlan plan = planCrosstab(ctTotals, m, availableWidth: 600);
      expect(_details(plan).map(_rowLabel), <String>[
        'North',
        'Ankara',
        'Istanbul',
        'Total North',
        'South',
        'Izmir',
        'Total South',
        'Total',
      ]);
    });

    test('an innermost row level has no per-node total', () {
      // rowGroups[1] (City) forbids totals, so no "Total North" row; rowGroups[0]
      // (Region) still allows the grand total.
      final Crosstab spec = ctTotals.copyWith(rowGroups: <CrosstabGroup>[
        _gRegion.copyWith(showTotal: true),
        _gCity
      ]);
      final CrosstabMatrix m = _aggregate(spec, _totalRows);
      final CrosstabPlan plan = planCrosstab(spec, m, availableWidth: 600);
      expect(_details(plan).map(_rowLabel), <String>[
        'North',
        'Ankara',
        'Istanbul',
        'South',
        'Izmir',
        'Total',
      ]);
    });

    test('showTotal false on the outermost group drops the grand total', () {
      final Crosstab spec = ctTotals.copyWith(
        rowGroups: <CrosstabGroup>[_gRegion, _gCity.copyWith(showTotal: true)],
        columnGroups: <CrosstabGroup>[
          _gYear,
          _gQuarter.copyWith(showTotal: true)
        ],
      );
      final CrosstabMatrix m = _aggregate(spec, _totalRows);
      final CrosstabPlan plan = planCrosstab(spec, m, availableWidth: 600);
      expect(_details(plan).map(_rowLabel), isNot(contains('Total')));
      expect(_details(plan).map(_rowLabel), contains('Total North'));
      expect(_labelsOf(_headers(plan)[0]), <String>['2025', '2026']);
      expect(_labelsOf(_headers(plan)[1]),
          <String>['Q1', 'Q2', 'Total 2025', 'Q1', 'Q2', 'Total 2026']);
    });

    test('totalLabel overrides the summation default', () {
      final Crosstab spec = ctTotals.copyWith(
        rowGroups: <CrosstabGroup>[
          _gRegion.copyWith(showTotal: true, totalLabel: () => 'All regions'),
          _gCity.copyWith(showTotal: true, totalLabel: () => 'Region total'),
        ],
      );
      final CrosstabMatrix m = _aggregate(spec, _totalRows);
      final CrosstabPlan plan = planCrosstab(spec, m, availableWidth: 600);
      expect(_details(plan).map(_rowLabel),
          containsAll(<String>['Region total', 'All regions']));
    });

    test(
        'an explicit totalLabel on a column-axis group synthesises '
        'value-identical subtotal nodes, each still addressed at its own '
        "parent's path", () {
      // With an explicit totalLabel, `_totalLabel` ignores the parent's own
      // label, so EVERY subtotal `CrosstabAxisNode` this level synthesises
      // shares the identical label/key/pathKey/depth/children/isTotal --
      // i.e. two such nodes (one per parent, "2025" and "2026" here) are
      // VALUE-EQUAL. `_augmentColumns`' leaf map is keyed by IDENTITY exactly
      // so these don't collide and clobber each other's cell address; a
      // value-keyed map would let the second overwrite the first, losing
      // "2025"'s total. The row-axis totalLabel test above can't cover this:
      // no nodes are synthesised on the row axis.
      final CrosstabGroup namedQuarter =
          _gQuarter.copyWith(showTotal: true, totalLabel: () => 'Subtotal');
      final Crosstab spec = Crosstab(
        id: 'ct1',
        rowGroups: const <CrosstabGroup>[_gRegion],
        columnGroups: <CrosstabGroup>[_gYear, namedQuarter],
        measures: const <CrosstabMeasure>[_amount],
        style: _style,
      );
      final CrosstabMatrix m = CrosstabMatrix(
        rowAxis: <CrosstabAxisNode>[_n('North')],
        columnAxis: <CrosstabAxisNode>[
          _n('2025', children: <CrosstabAxisNode>[
            _n('Q1', depth: 1),
            _n('Q2', depth: 1),
          ]),
          _n('2026', children: <CrosstabAxisNode>[
            _n('Q1', depth: 1),
            _n('Q2', depth: 1),
          ]),
        ],
        measures: const <CrosstabMeasure>[_amount],
        cells: <CrosstabCellKey, JetValue>{
          // Addressed at each PARENT's own path -- what a subtotal column
          // reads. Distinct values so a clobbered/shared entry is visible.
          const CrosstabCellKey(<String>['North'], <String>['2025'], 'm/a'):
              const JetNumber(999),
          const CrosstabCellKey(<String>['North'], <String>['2026'], 'm/a'):
              const JetNumber(888),
        },
      );
      final CrosstabPlan plan = planCrosstab(spec, m, availableWidth: 600);
      final List<FilledBand> headers = _headers(plan);
      expect(headers, hasLength(2));
      // Both subtotal columns carry the SAME label -- the value-identity
      // collision this test targets.
      expect(_labelsOf(headers[1]),
          <String>['Q1', 'Q2', 'Subtotal', 'Q1', 'Q2', 'Subtotal']);
      // Yet each resolves to its OWN parent's aggregated value, not a
      // shared/clobbered one -- proof the leaf map is identity-keyed.
      expect(_rowCells(_details(plan).first),
          <String>['', '', '999.0', '', '', '888.0']);
    });

    test('the grand-total column is a trailing depth-0 leaf sliceColumns sees',
        () {
      // The reservation rule in sliceColumns only fires for a trailing depth-0
      // `isTotal` leaf. budget = 300 - 100 = 200 = four 50pt columns. With four
      // data leaves and the reservation honoured, the last data leaf moves down
      // so the total joins it: [Q1 Q2 Q3] [Q4 Total]. An implementation that
      // synthesised the grand total as anything else (a deeper node, or not
      // last) would pack [Q1 Q2 Q3 Q4] [Total] instead.
      final Crosstab spec = Crosstab(
        id: 'ct1',
        rowGroups: const <CrosstabGroup>[_gRegion],
        columnGroups: <CrosstabGroup>[_gQuarter.copyWith(showTotal: true)],
        measures: const <CrosstabMeasure>[_amount],
        style: _style,
      );
      final CrosstabMatrix m = CrosstabMatrix(
        rowAxis: <CrosstabAxisNode>[_n('North')],
        columnAxis: <CrosstabAxisNode>[
          for (int i = 1; i <= 4; i++) _n('Q$i'),
        ],
        measures: const <CrosstabMeasure>[_amount],
        cells: const <CrosstabCellKey, JetValue>{},
      );
      final CrosstabPlan plan = planCrosstab(spec, m, availableWidth: 300);
      final List<FilledBand> headers = _headers(plan);
      expect(headers, hasLength(2));
      expect(_labelsOf(headers[0]), <String>['Q1', 'Q2', 'Q3']);
      expect(_labelsOf(headers[1]), <String>['Q4', 'Total']);
      expect(plan.diagnostics, isEmpty);
    });
  });

  group('∑ agrees with the aggregator', () {
    test('every printed cell resolves — no total addresses an unfolded prefix',
        () {
      // The fixture is a full cross product with every level totalled, so every
      // (row prefix x column prefix) the planner can address was folded. A
      // single empty string here means the planner asked for a cell the
      // aggregator never wrote.
      final CrosstabMatrix m = _aggregate(ctTotals, _totalRows);
      final CrosstabPlan plan = planCrosstab(ctTotals, m, availableWidth: 600);
      for (final FilledBand b in _details(plan)) {
        if (_rowCells(b).isEmpty) continue; // inner label-only row
        expect(_rowCells(b), isNot(contains('')), reason: _rowLabel(b));
      }
    });

    test('total rows and columns carry the aggregator\'s own prefix values',
        () {
      final CrosstabMatrix m = _aggregate(ctTotals, _totalRows);
      final CrosstabPlan plan = planCrosstab(ctTotals, m, availableWidth: 600);
      // Columns, in order: 2025/Q1, 2025/Q2, Total 2025, 2026/Q1, 2026/Q2,
      // Total 2026, Total. Amounts are 1<<i over the row order declared in
      // _totalRows.
      expect(_rowCells(_rowNamed(plan, 'Istanbul')), <String>[
        '1.0', '2.0', '3.0', // 1+2
        '4.0', '8.0', '12.0', // 4+8
        '15.0', // 1+2+4+8
      ]);
      expect(_rowCells(_rowNamed(plan, 'Total North')), <String>[
        '17.0', '34.0', '51.0', // 1+16, 2+32, 17+34
        '68.0', '136.0', '204.0', // 4+64, 8+128, 68+136
        '255.0', // 1..128
      ]);
      expect(_rowCells(_rowNamed(plan, 'Total')).last, '4095.0'); // 1..2048

      // And each of those is exactly what the aggregator holds at the prefix
      // the planner claims to be printing.
      expect(
          m.cells[const CrosstabCellKey(
              <String>['North', 'Istanbul'], <String>['2025'], 'm/a')],
          const JetNumber(3));
      expect(
          m.cells[const CrosstabCellKey(<String>['North'], <String>[], 'm/a')],
          const JetNumber(255));
      expect(m.cells[const CrosstabCellKey(<String>[], <String>[], 'm/a')],
          const JetNumber(4095));
    });
  });
}
