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
      // 2 measures -> a leaf is 100pt wide; budget 250 fits two leaves, and the
      // third must move rather than leaving one measure behind.
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[_leaf('Q1'), _leaf('Q2'), _leaf('Q3')], 2),
        style,
        availableWidth: 350,
        diagnostics: <Diagnostic>[],
      );
      expect(slices.map((CrosstabSlice s) => s.columns.length), <int>[4, 2]);
      for (final CrosstabSlice s in slices) {
        expect(s.columns.length.isEven, isTrue,
            reason: 'each leaf contributes both of its measures');
      }
    });

    test('the grand total keeps its width in the final slice', () {
      // 5 data leaves + a grand total, budget 200 = four 50pt columns per slice.
      // Without reservation the total would start a sixth-column slice alone.
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[
          for (int i = 0; i < 5; i++) _leaf('Q$i'),
          _leaf('Total', isTotal: true),
        ], 1),
        style,
        availableWidth: 300,
        diagnostics: <Diagnostic>[],
      );
      expect(slices.last.columns.last.leaf.isTotal, isTrue);
      expect(slices.last.columns, hasLength(greaterThan(1)),
          reason: 'the total must not be alone on a continuation page');
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
  });
}
