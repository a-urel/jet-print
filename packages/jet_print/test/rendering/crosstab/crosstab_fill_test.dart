// Task 11: wiring a crosstab into the filler. `emitNode`'s CrosstabNode arm
// stays a permanent no-op (see `report_filler.dart`); a crosstab is instead
// registered before the row loop, folded during it, and spliced in after —
// these tests exercise that register/fold/splice path end to end.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/data/jet_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

import 'crosstab_fixtures.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 100, height: 10);

FillResult _fillResult(ReportDefinition def, JetDataSource source) =>
    ReportFiller().fillDefinition(def, source);

FilledReport _fill(ReportDefinition def, JetDataSource source) =>
    _fillResult(def, source).report;

// A one-element per-row detail band, so a non-crosstab sibling actually
// produces bands during the row walk.
Band _detailBand() => const Band(
      id: 'detail',
      type: BandType.detail,
      height: 10,
      elements: <ReportElement>[
        TextElement(id: 'd', bounds: _r, text: '', expression: r'$F{region}'),
      ],
    );

ReportDefinition _defWithCrosstab({required bool after, bool visible = true}) {
  final Crosstab ct = baseCrosstab.copyWith(
    visible: visible ? const BoolProperty() : const BoolProperty(value: false),
  );
  final List<ScopeNode> children = after
      ? <ScopeNode>[BandNode(_detailBand()), CrosstabNode(ct)]
      : <ScopeNode>[CrosstabNode(ct), BandNode(_detailBand())];
  return ReportDefinition(
    name: 'ct-fill',
    page: PageFormat.a4Portrait,
    body: ReportBody(root: DetailScope(id: 'root', children: children)),
  );
}

ReportDefinition _crosstabOnlyDef() => ReportDefinition(
      name: 'ct-only',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[CrosstabNode(baseCrosstab)],
        ),
      ),
    );

// A crosstab whose `collectionField` pools a nested `lines` collection across
// every master row: both axes collapse every child row into one cell, so the
// folded sum is the single, unambiguous signal that no row was materialized
// and dropped — it can only be right if every child row from every master row
// reached the same accumulator.
ReportDefinition _defWithNestedCrosstab() {
  const CrosstabGroup allRows = CrosstabGroup(
      id: 'g/r-all', name: 'All', expression: "'All'", showTotal: false);
  const CrosstabGroup allCols = CrosstabGroup(
      id: 'g/c-all', name: 'All', expression: "'All'", showTotal: false);
  const CrosstabMeasure sumAmount = CrosstabMeasure(
    id: 'm/amt',
    name: 'Amount',
    expression: r'$F{amount}',
    aggregate: JetCalculation.sum,
    format: '0',
  );
  const Crosstab ct = Crosstab(
    id: 'ctN',
    collectionField: 'lines',
    rowGroups: <CrosstabGroup>[allRows],
    columnGroups: <CrosstabGroup>[allCols],
    measures: <CrosstabMeasure>[sumAmount],
    style: crosstabStyle,
  );
  return ReportDefinition(
    name: 'ct-nested',
    page: PageFormat.a4Portrait,
    body: ReportBody(
      root: DetailScope(id: 'root', children: <ScopeNode>[CrosstabNode(ct)]),
    ),
  );
}

// A crosstab whose synthetic group name ("ct1#ct") collides with an
// explicitly-authored report-level group of the same name.
ReportDefinition _defWithNameCollision() => ReportDefinition(
      name: 'ct-collide',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: const <GroupLevel>[
            GroupLevel(id: 'g/collide', name: 'ct1#ct', key: "'x'"),
          ],
          children: <ScopeNode>[
            CrosstabNode(baseCrosstab),
            BandNode(_detailBand()),
          ],
        ),
      ),
    );

bool _isGroupNameCollisionDiagnostic(Diagnostic d) =>
    d.severity == DiagnosticSeverity.error &&
    d.message.contains('needs the synthetic group name');

JetInMemoryDataSource _rows4() => JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{'region': 'North', 'quarter': 'Q1', 'amount': 10},
      <String, Object?>{'region': 'North', 'quarter': 'Q2', 'amount': 5},
      <String, Object?>{'region': 'South', 'quarter': 'Q1', 'amount': 7},
      <String, Object?>{'region': 'South', 'quarter': 'Q2', 'amount': 3},
    ]);

// Two master rows, each with two `lines` entries of amount 100 — 400 total
// only if the crosstab pools all four child rows across both master rows.
JetInMemoryDataSource _rowsWithLines() =>
    JetInMemoryDataSource(<Map<String, Object?>>[
      for (int i = 0; i < 2; i++)
        <String, Object?>{
          'lines': <Map<String, Object?>>[
            <String, Object?>{'amount': 100},
            <String, Object?>{'amount': 100},
          ],
        },
    ]);

JetInMemoryDataSource _rowsN(int n) =>
    JetInMemoryDataSource(<Map<String, Object?>>[
      for (int i = 0; i < n; i++)
        <String, Object?>{
          'region': i.isEven ? 'North' : 'South',
          'quarter': i % 4 < 2 ? 'Q1' : 'Q2',
          'amount': i,
        },
    ]);

List<String> _cellTexts(FilledReport r) => <String>[
      for (final FilledBand b in r.bands)
        for (final ReportElement e in b.elements)
          if (e is TextElement) e.text,
    ];

void main() {
  group('crosstab fill', () {
    test('a crosstab after the detail band prints once, after every row', () {
      final FilledReport r = _fill(_defWithCrosstab(after: true), _rows4());
      final List<BandType> types =
          r.bands.map((FilledBand b) => b.type).toList();
      expect(types.where((BandType t) => t == BandType.detail).length,
          greaterThan(4),
          reason: '4 data rows plus the crosstab rows');
      expect(types.indexOf(BandType.groupHeader),
          greaterThan(types.indexOf(BandType.detail)));
      expect(
          types.where((BandType t) => t == BandType.groupFooter), hasLength(1));
    });

    test('a crosstab before the detail band prints once, before every row', () {
      final FilledReport r = _fill(_defWithCrosstab(after: false), _rows4());
      final List<BandType> types =
          r.bands.map((FilledBand b) => b.type).toList();
      expect(types.first, BandType.groupHeader,
          reason: 'the crosstab header opens the body');
    });

    test('a crosstab-only body still prints the crosstab once', () {
      final FilledReport r = _fill(_crosstabOnlyDef(), _rows4());
      expect(r.bands.where((FilledBand b) => b.type == BandType.groupFooter),
          hasLength(1));
    });

    test('the synthetic group reaches the FilledReport', () {
      final FilledReport r = _fill(_defWithCrosstab(after: true), _rows4());
      expect(
          r.syntheticGroups.map((GroupLevel g) => g.name), <String>['ct1#ct']);
    });

    test('visible: false skips the crosstab entirely', () {
      final FilledReport r =
          _fill(_defWithCrosstab(after: true, visible: false), _rows4());
      expect(r.bands.where((FilledBand b) => b.group != null), isEmpty);
      expect(r.syntheticGroups, isEmpty);
    });

    test('collectionField pools a nested collection across master rows', () {
      // Two master rows, each with two line items; the crosstab folds all four.
      final FilledReport r = _fill(_defWithNestedCrosstab(), _rowsWithLines());
      expect(_cellTexts(r), contains('400')); // 100+100+100+100
    });

    test('folding retains no rows: a 20k-row source fills without buffering',
        () {
      // Guards the design decision. If this ever needs to materialize rows it
      // will show up as a memory spike, not a failure — keep the row count
      // high enough to be meaningful but fast.
      final FilledReport r =
          _fill(_defWithCrosstab(after: true), _rowsN(20000));
      expect(r.bands, isNotEmpty);
    });

    test(
        'two before-loop crosstabs splice in registration order, not '
        'reversed', () {
      // A single before-loop crosstab can't tell "insert at reservedIndex"
      // apart from "insert at reservedIndex, uncorrected for earlier
      // insertions" — both place its bands at the front. Two before-loop
      // crosstabs both register `reservedIndex == 0` (neither has moved
      // `bands` yet), so only a second insertion that fails to shift by the
      // first's band count would reverse them.
      final Crosstab ctA = baseCrosstab.copyWith(id: 'ctA');
      final Crosstab ctB = baseCrosstab.copyWith(id: 'ctB');
      final ReportDefinition def = ReportDefinition(
        name: 'ct-two-before',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              CrosstabNode(ctA),
              CrosstabNode(ctB),
              BandNode(_detailBand()),
            ],
          ),
        ),
      );
      final FilledReport r = _fill(def, _rows4());
      final List<String> groupsInOrder = <String>[
        for (final FilledBand b in r.bands)
          if (b.group != null) b.group!,
      ];
      expect(groupsInOrder, <String>['ctA#ct', 'ctA#ct', 'ctB#ct', 'ctB#ct']);
      expect(r.bands.first.group, 'ctA#ct',
          reason: 'ctA was registered first, so its bands open the body');
    });

    test('a group-name collision routes the PLAN diagnostic to the sink', () {
      // planCrosstab raises an error when its synthetic group name
      // ("ct1#ct") is already taken by a report-level group.
      final ReportDiagnostics diagnostics =
          _fillResult(_defWithNameCollision(), _rows4()).diagnostics;
      expect(diagnostics.entries.any(_isGroupNameCollisionDiagnostic), isTrue);
    });

    test(
        'a group-name collision is reported even over an EMPTY source — '
        'planCrosstab raises it before it ever looks at the matrix', () {
      // planCrosstab's collision check (crosstab_planner.dart) runs before it
      // touches the aggregated matrix at all, so it must fire whether or not
      // any row was ever folded. A plan/splice step that only ran on the
      // `hadRows` path would report this with 4 rows and silently drop it
      // with 0 — an observable, data-dependent difference in diagnostics for
      // the exact same authored report.
      final ReportDiagnostics diagnostics = _fillResult(_defWithNameCollision(),
          JetInMemoryDataSource(const <Map<String, Object?>>[])).diagnostics;
      expect(diagnostics.entries.any(_isGroupNameCollisionDiagnostic), isTrue);
    });

    test('a 50k+ cell matrix routes the MATRIX diagnostic to the sink', () {
      // The aggregator's cardinality warning (crosstab_aggregator.dart's
      // `_cellCountWarningThreshold`) is on `matrix.diagnostics`, which
      // `planCrosstab` deliberately does not fold into `plan.diagnostics` — so
      // this only reaches the sink if the filler routes BOTH sources.
      const CrosstabGroup uniqueRow = CrosstabGroup(
          id: 'g/i', name: 'I', expression: r'$F{i}', showTotal: false);
      const CrosstabGroup oneCol = CrosstabGroup(
          id: 'g/c', name: 'C', expression: "'c'", showTotal: false);
      const CrosstabMeasure count = CrosstabMeasure(
        id: 'm/n',
        name: 'N',
        expression: r'$F{amount}',
        aggregate: JetCalculation.sum,
      );
      const Crosstab ctBig = Crosstab(
        id: 'ctBig',
        rowGroups: <CrosstabGroup>[uniqueRow],
        columnGroups: <CrosstabGroup>[oneCol],
        measures: <CrosstabMeasure>[count],
        style: crosstabStyle,
      );
      final ReportDefinition def = ReportDefinition(
        name: 'ct-cardinality',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[CrosstabNode(ctBig)],
          ),
        ),
      );
      final JetInMemoryDataSource rows =
          JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 0; i < 50005; i++) <String, Object?>{'i': i, 'amount': 1},
      ]);
      final ReportDiagnostics diagnostics = _fillResult(def, rows).diagnostics;
      expect(
        diagnostics.entries.any((Diagnostic d) =>
            d.severity == DiagnosticSeverity.warning &&
            d.message.contains('produced') &&
            d.message.contains('cells')),
        isTrue,
      );
    });
  });
}
