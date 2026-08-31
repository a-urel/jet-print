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
      // `b` is built with a runtime `rowPath` literal, not `const`: if both
      // were const, identical arguments would const-canonicalize `a` and `b`
      // to the very same instance, and `ValueEquality.==` would short-circuit
      // on `identical(this, other)` (value_equality.dart:21-27) — the
      // `equals(b)` check below would pass even if equality were entirely
      // unimplemented. The `isFalse` check guards against that silently
      // degrading back if a future edit makes `b` constable again.
      final CrosstabCellKey b =
          CrosstabCellKey(<String>['North'], <String>['Q1'], 'm/a');
      expect(identical(a, b), isFalse);
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

    test(
        'distinct cell keys whose paths collide under a naive '
        "space-joined string ('A B' + 'C' vs 'A' + 'B C') are not confused, "
        'regardless of insertion order', () {
      // rowPath: ['A B'], colPath: ['C']  and
      // rowPath: ['A'],   colPath: ['B C']
      // both flatten to the same "A B C" string if paths are simply
      // space-joined together — a real hazard, since path segments are group
      // labels drawn from data (e.g. "New York", "Q1 2026") and routinely
      // contain spaces. A correct implementation must keep these two keys
      // distinguishable, and matrix equality must still be insertion-order
      // independent even though the two keys collide under a naive joined
      // string.
      const CrosstabCellKey keyX =
          CrosstabCellKey(<String>['A B'], <String>['C'], 'm/a');
      const CrosstabCellKey keyY =
          CrosstabCellKey(<String>['A'], <String>['B C'], 'm/a');
      expect(keyX, isNot(equals(keyY)));

      final CrosstabMatrix forward = CrosstabMatrix(
        rowAxis: rowAxis,
        columnAxis: columnAxis,
        measures: measures,
        cells: <CrosstabCellKey, JetValue>{
          keyX: const JetNumber(1),
          keyY: const JetNumber(2),
        },
      );
      final CrosstabMatrix backward = CrosstabMatrix(
        rowAxis: rowAxis,
        columnAxis: columnAxis,
        measures: measures,
        cells: <CrosstabCellKey, JetValue>{
          keyY: const JetNumber(2),
          keyX: const JetNumber(1),
        },
      );

      expect(forward, equals(backward));
      expect(forward.hashCode, backward.hashCode);
    });

    test('two matrices with empty cells maps are equal', () {
      // `a` is const; if `b` were const too, every argument would be
      // const-canonicalized to the very same instance, so `ValueEquality.==`
      // would short-circuit on `identical(this, other)`
      // (value_equality.dart:21-27) and the test would pass even with `==`
      // entirely unimplemented. `b` is built with a runtime `cells` literal
      // specifically to defeat that canonicalization; the `isFalse` check
      // below guards against this test silently degrading back into the
      // vacuous case if a future edit makes `b` constable again.
      const CrosstabMatrix a = CrosstabMatrix(
        rowAxis: <CrosstabAxisNode>[],
        columnAxis: <CrosstabAxisNode>[],
        measures: <CrosstabMeasure>[],
        cells: <CrosstabCellKey, JetValue>{},
      );
      final CrosstabMatrix b = CrosstabMatrix(
        rowAxis: <CrosstabAxisNode>[],
        columnAxis: <CrosstabAxisNode>[],
        measures: <CrosstabMeasure>[],
        cells: <CrosstabCellKey, JetValue>{}, // runtime literal, not const
      );
      expect(identical(a, b), isFalse);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('cell path ordering', () {
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

    test('a path that is a prefix of another sorts first', () {
      // ['North'] is a prefix of ['North', 'Istanbul'] -- the shorter path
      // (the region subtotal) must sort before the longer one (the city
      // leaf), matching _compareStringLists's documented shorter-sorts-first
      // rule for prefix pairs.
      const CrosstabCellKey shortKey =
          CrosstabCellKey(<String>['North'], <String>['Q1'], 'm/a');
      const CrosstabCellKey longKey =
          CrosstabCellKey(<String>['North', 'Istanbul'], <String>['Q1'], 'm/a');

      final CrosstabMatrix inOrder = CrosstabMatrix(
        rowAxis: rowAxis,
        columnAxis: columnAxis,
        measures: measures,
        cells: <CrosstabCellKey, JetValue>{
          shortKey: const JetNumber(1),
          longKey: const JetNumber(2),
        },
      );
      final CrosstabMatrix reversed = CrosstabMatrix(
        rowAxis: rowAxis,
        columnAxis: columnAxis,
        measures: measures,
        cells: <CrosstabCellKey, JetValue>{
          longKey: const JetNumber(2),
          shortKey: const JetNumber(1),
        },
      );

      // Insertion order must not matter (props flattens in a fixed order)...
      expect(inOrder, equals(reversed));
      expect(inOrder.hashCode, reversed.hashCode);
      expect(inOrder.props, equals(reversed.props));

      // ...and that fixed order must actually put the prefix first: the
      // flattened cell list (props[3]) is [key, value, key, value, ...], so
      // the shorter path's key/value pair must precede the longer path's.
      final List<Object?> flatCells = inOrder.props[3]! as List<Object?>;
      expect(flatCells, <Object?>[
        shortKey,
        const JetNumber(1),
        longKey,
        const JetNumber(2),
      ]);
    });
  });
}
