import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_matrix.dart';

CrosstabAxisNode _node(String k,
        {List<CrosstabAxisNode> children = const <CrosstabAxisNode>[],
        bool isTotal = false,
        int depth = 0}) =>
    CrosstabAxisNode(
      key: JetString(k),
      pathKey: k,
      label: k,
      depth: depth,
      children: children,
      isTotal: isTotal,
    );

void main() {
  group('CrosstabCellKey', () {
    test('equal paths make equal keys, so it works as a map key', () {
      const CrosstabCellKey a =
          CrosstabCellKey(<String>['North'], <String>['Q1'], 'm/a');
      const CrosstabCellKey b =
          CrosstabCellKey(<String>['North'], <String>['Q1'], 'm/a');
      expect(a, equals(b));
      final Map<CrosstabCellKey, JetValue> cells = <CrosstabCellKey, JetValue>{
        a: const JetNumber(1),
      };
      expect(cells[b], const JetNumber(1));
    });

    test('a shortened path is a different key — that is the subtotal', () {
      const CrosstabCellKey leaf =
          CrosstabCellKey(<String>['North', 'Istanbul'], <String>['Q1'], 'm/a');
      const CrosstabCellKey total =
          CrosstabCellKey(<String>['North'], <String>['Q1'], 'm/a');
      expect(leaf, isNot(equals(total)));
    });
  });

  group('leavesOf', () {
    test('returns depth-first leaves', () {
      final List<CrosstabAxisNode> axis = <CrosstabAxisNode>[
        _node('2025', children: <CrosstabAxisNode>[
          _node('Q1', depth: 1),
          _node('Q2', depth: 1),
        ]),
        _node('2026', children: <CrosstabAxisNode>[_node('Q1', depth: 1)]),
      ];
      expect(leavesOf(axis).map((CrosstabAxisNode n) => n.pathKey),
          <String>['Q1', 'Q2', 'Q1']);
    });

    test('a childless root is itself a leaf', () {
      expect(leavesOf(<CrosstabAxisNode>[_node('All')]).single.pathKey, 'All');
    });
  });

  group('CrosstabMatrix', () {
    final List<CrosstabAxisNode> rowAxis = <CrosstabAxisNode>[_node('North')];
    final List<CrosstabAxisNode> columnAxis = <CrosstabAxisNode>[_node('Q1')];
    final List<CrosstabMeasure> measures = <CrosstabMeasure>[
      const CrosstabMeasure(
        id: 'm/a',
        name: 'Total',
        expression: r'$F{qty}',
        aggregate: JetCalculation.sum,
      ),
    ];

    test(
        'two matrices with the same cells inserted in different orders are '
        'equal and share a hashCode', () {
      const CrosstabCellKey keyA =
          CrosstabCellKey(<String>['North'], <String>['Q1'], 'm/a');
      const CrosstabCellKey keyB =
          CrosstabCellKey(<String>['South'], <String>['Q1'], 'm/a');

      final CrosstabMatrix forward = CrosstabMatrix(
        rowAxis: rowAxis,
        columnAxis: columnAxis,
        measures: measures,
        cells: <CrosstabCellKey, JetValue>{
          keyA: const JetNumber(1),
          keyB: const JetNumber(2),
        },
      );
      final CrosstabMatrix backward = CrosstabMatrix(
        rowAxis: rowAxis,
        columnAxis: columnAxis,
        measures: measures,
        cells: <CrosstabCellKey, JetValue>{
          keyB: const JetNumber(2),
          keyA: const JetNumber(1),
        },
      );

      expect(forward, equals(backward));
      expect(forward.hashCode, backward.hashCode);
    });
  });
}
