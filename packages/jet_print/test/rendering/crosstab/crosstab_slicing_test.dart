import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_matrix.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_planner.dart';

CrosstabAxisNode _leaf(String k, {bool isTotal = false}) => CrosstabAxisNode(
      key: JetString(k),
      pathKey: k,
      label: k,
      depth: 0,
      isTotal: isTotal,
    );

CrosstabMeasure _m(String id) => CrosstabMeasure(
      id: id,
      name: id,
      expression: r'$F{amount}',
      aggregate: JetCalculation.sum,
    );

CrosstabMatrix _matrix(List<CrosstabAxisNode> columnAxis, int measureCount) =>
    CrosstabMatrix(
      rowAxis: <CrosstabAxisNode>[_leaf('North')],
      columnAxis: columnAxis,
      measures: <CrosstabMeasure>[
        for (int i = 0; i < measureCount; i++) _m('m$i'),
      ],
      cells: const <CrosstabCellKey, JetValue>{},
    );

void main() {
  const CrosstabStyle style =
      CrosstabStyle(rowLabelWidth: 100, measureColumnWidth: 50);

  group('sliceColumns', () {
    test('everything in one slice when it fits', () {
      final List<Diagnostic> diags = <Diagnostic>[];
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[_leaf('Q1'), _leaf('Q2')], 1),
        style,
        availableWidth: 400,
        diagnostics: diags,
      );
      expect(slices, hasLength(1));
      expect(slices.single.columns, hasLength(2));
      expect(diags, isEmpty);
    });

    test('overflowing leaves move to a second slice', () {
      // budget = 300 - 100 = 200 -> four 50pt columns fit, the fifth does not.
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[
          for (int i = 0; i < 6; i++) _leaf('Q$i'),
        ], 1),
        style,
        availableWidth: 300,
        diagnostics: <Diagnostic>[],
      );
      expect(slices.map((CrosstabSlice s) => s.columns.length), <int>[4, 2]);
      expect(slices[1].index, 1);
    });

    test('a leaf group is never split across slices', () {
      // 3 measures -> a leaf is 150pt wide (chosen odd so an "even column
      // count" check couldn't accidentally pass); budget 300 fits two leaves,
      // and the third must move as a whole rather than leaving a measure
      // behind. Asserted directly by which leaf `pathKey`s land in which
      // slice, not by a column-count parity proxy.
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[_leaf('Q1'), _leaf('Q2'), _leaf('Q3')], 3),
        style,
        availableWidth: 400,
        diagnostics: <Diagnostic>[],
      );
      expect(slices.map((CrosstabSlice s) => s.columns.length), <int>[6, 3]);
      expect(
        slices[0].columns.map((CrosstabColumn c) => c.leaf.pathKey).toSet(),
        <String>{'Q1', 'Q2'},
      );
      expect(
        slices[1].columns.map((CrosstabColumn c) => c.leaf.pathKey).toSet(),
        <String>{'Q3'},
      );
      for (final CrosstabSlice s in slices) {
        final Set<String> leafKeys =
            s.columns.map((CrosstabColumn c) => c.leaf.pathKey).toSet();
        expect(s.columns.length, leafKeys.length * 3,
            reason: 'every leaf on this slice contributes all 3 of its measure '
                'columns, never a partial set');
      }
    });

    test(
        'the grand total is reserved a spot next to the last data leaf, '
        'never stranded alone', () {
      // 2 data leaves + a grand total, each 50pt, budget 120 (availableWidth
      // 220 - rowLabelWidth 100). Q1 + Q2 alone is 100, which fits in 120, so
      // an implementation with NO reservation packs both data leaves first
      // and only then discovers the total: [[Q1, Q2], [Total]] -- the total
      // stranded alone, exactly the pathology rule 2 exists to prevent. The
      // correct behaviour reserves the total's width while packing the slice
      // that will hold the last data leaf: Q1 alone (50) fits, but
      // Q1 + Q2 + the reserved total (150) does not fit in 120, so Q2 moves
      // out to join the total instead -> [[Q1], [Q2, Total]]. The two
      // outcomes disagree on which slice Q2 lands in, so this fixture forces
      // the divergence the old, always-matching fixture could not.
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[
          _leaf('Q1'),
          _leaf('Q2'),
          _leaf('Total', isTotal: true),
        ], 1),
        style,
        availableWidth: 220,
        diagnostics: <Diagnostic>[],
      );
      expect(slices, hasLength(2));
      expect(
        slices[0].columns.map((CrosstabColumn c) => c.leaf.pathKey).toList(),
        <String>['Q1'],
      );
      expect(
        slices[1].columns.map((CrosstabColumn c) => c.leaf.pathKey).toList(),
        <String>['Q2', 'Total'],
      );
      expect(slices[1].columns.last.leaf.isTotal, isTrue);
    });

    test('a single leaf wider than the page still prints, with a diagnostic',
        () {
      final List<Diagnostic> diags = <Diagnostic>[];
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[_leaf('Q1')], 4), // 200pt of measures
        const CrosstabStyle(rowLabelWidth: 100, measureColumnWidth: 50),
        availableWidth: 180, // budget 80 — not even one measure fits
        diagnostics: diags,
      );
      expect(slices.single.columns, hasLength(4));
      expect(diags.map((Diagnostic d) => d.message),
          anyElement(contains('wider than')));
    });

    test('an empty column axis produces no slices and no diagnostics', () {
      final List<Diagnostic> diags = <Diagnostic>[];
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[], 1),
        style,
        availableWidth: 400,
        diagnostics: diags,
      );
      expect(slices, isEmpty);
      expect(diags, isEmpty);
    });

    test('a grand-total-only column is placed in its own single slice', () {
      // budget = 300 - 100 = 200, and the total's own block is 50pt, so it
      // fits comfortably with no preceding data leaf at all.
      final List<Diagnostic> diags = <Diagnostic>[];
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[_leaf('Total', isTotal: true)], 1),
        style,
        availableWidth: 300,
        diagnostics: diags,
      );
      expect(slices, hasLength(1));
      expect(slices.single.columns, hasLength(1));
      expect(slices.single.columns.single.leaf.isTotal, isTrue);
      expect(diags, isEmpty);
    });

    test(
        'a grand-total-only column that cannot fit still prints, with a '
        'diagnostic that does not claim a data column group was involved', () {
      // budget = 120 - 100 = 20, and the total's own block is 50pt: it
      // cannot fit even alone, with no data leaf to blame it on.
      final List<Diagnostic> diags = <Diagnostic>[];
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[_leaf('Total', isTotal: true)], 1),
        style,
        availableWidth: 120,
        diagnostics: diags,
      );
      expect(slices, hasLength(1));
      expect(slices.single.columns, hasLength(1));
      expect(slices.single.columns.single.leaf.isTotal, isTrue);
      expect(
        diags.map((Diagnostic d) => d.message),
        anyElement(allOf(
          contains('does not fit'),
          isNot(contains('alongside')),
          isNot(contains('data column group')),
        )),
      );
    });

    test(
        'a packing budget narrower than the row-label column still prints '
        'every leaf, one per slice', () {
      // availableWidth (50) < style.rowLabelWidth (100) -> a negative budget.
      // Nothing may be dropped, so the packer degrades to one leaf per slice
      // rather than throwing.
      final List<Diagnostic> diags = <Diagnostic>[];
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[_leaf('Q1'), _leaf('Q2'), _leaf('Q3')], 1),
        style,
        availableWidth: 50,
        diagnostics: diags,
      );
      expect(slices, hasLength(3));
      for (int i = 0; i < 3; i++) {
        expect(
          slices[i].columns.map((CrosstabColumn c) => c.leaf.pathKey).toList(),
          <String>['Q${i + 1}'],
        );
        expect(slices[i].index, i);
      }
      expect(diags.map((Diagnostic d) => d.message),
          anyElement(contains('wider than')));
    });
  });
}
