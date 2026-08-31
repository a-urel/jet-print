/// The crosstab aggregation result (spec A): two axis trees plus a sparse cell
/// map. Pure data with value equality, so a matrix is a snapshot-testable data
/// golden independent of any geometry.
library;

import '../../domain/crosstab/crosstab_measure.dart';
import '../../domain/diagnostic.dart';
import '../../domain/value_equality.dart';
import '../../expression/value.dart';

/// One node of a resolved axis tree.
class CrosstabAxisNode with ValueEquality {
  /// Creates an axis node.
  const CrosstabAxisNode({
    required this.key,
    required this.pathKey,
    required this.label,
    required this.depth,
    this.children = const <CrosstabAxisNode>[],
    this.isTotal = false,
  });

  /// The typed group key — **the sort key**. Kept typed so `9` orders before
  /// `10` and dates order chronologically.
  final JetValue key;

  /// The stringified key, used in cell paths and element ids.
  final String pathKey;

  /// The text printed for this node.
  final String label;

  /// Nesting depth; 0 is the outermost level.
  final int depth;

  /// Child nodes; empty means this node is a leaf.
  final List<CrosstabAxisNode> children;

  /// Whether this node is a subtotal (or, at depth 0, the grand total).
  final bool isTotal;

  @override
  List<Object?> get props =>
      <Object?>[key, pathKey, label, depth, children, isTotal];

  @override
  String toString() =>
      'CrosstabAxisNode($pathKey${isTotal ? ' total' : ''}, d$depth)';
}

/// The address of one cell: a row path, a column path and a measure id.
///
/// A **shortened** path addresses that level's subtotal; the full leaf paths
/// address a data cell.
class CrosstabCellKey with ValueEquality {
  /// Creates a cell address.
  const CrosstabCellKey(this.rowPath, this.colPath, this.measureId);

  /// Row-axis `pathKey`s, outermost first.
  final List<String> rowPath;

  /// Column-axis `pathKey`s, outermost first.
  final List<String> colPath;

  /// The measure this cell holds.
  final String measureId;

  @override
  List<Object?> get props => <Object?>[rowPath, colPath, measureId];

  @override
  String toString() =>
      'CrosstabCellKey(${rowPath.join('/')} x ${colPath.join('/')} : $measureId)';
}

/// A resolved crosstab: both axis trees, the measures in column order, and the
/// **sparse** cell map — an intersection that saw no rows has no entry, which is
/// how an empty cell stays distinguishable from a zero.
class CrosstabMatrix with ValueEquality {
  /// Creates a matrix.
  const CrosstabMatrix({
    required this.rowAxis,
    required this.columnAxis,
    required this.measures,
    required this.cells,
    this.diagnostics = const <Diagnostic>[],
  });

  /// Row axis roots, in sorted order.
  final List<CrosstabAxisNode> rowAxis;

  /// Column axis roots, in sorted order.
  final List<CrosstabAxisNode> columnAxis;

  /// The measures, in column order.
  final List<CrosstabMeasure> measures;

  /// Populated cells only.
  final Map<CrosstabCellKey, JetValue> cells;

  /// Issues raised while folding (e.g. the cardinality warning).
  final List<Diagnostic> diagnostics;

  /// The fields participating in equality.
  ///
  /// [cells] is a [Map], and [ValueEquality] compares a `Map` field by
  /// identity — two maps with the same entries would otherwise compare
  /// unequal — so it is flattened into a `List` here instead of listed
  /// directly. That flattening is sorted by a stable composite key (`rowPath`
  /// and `colPath` joined with a space, which cannot occur inside a path
  /// segment, followed by `measureId`), so **matrix equality — and
  /// `hashCode` — is independent of cell insertion order**: two matrices
  /// holding the same cells, inserted in different orders, compare equal.
  @override
  List<Object?> get props {
    final List<MapEntry<CrosstabCellKey, JetValue>> sortedEntries =
        cells.entries.toList()
          ..sort((MapEntry<CrosstabCellKey, JetValue> a,
                  MapEntry<CrosstabCellKey, JetValue> b) =>
              _cellSortKey(a.key).compareTo(_cellSortKey(b.key)));
    return <Object?>[
      rowAxis,
      columnAxis,
      measures,
      <Object?>[
        for (final MapEntry<CrosstabCellKey, JetValue> e
            in sortedEntries) ...<Object?>[e.key, e.value],
      ],
      diagnostics,
    ];
  }

  @override
  String toString() => 'CrosstabMatrix(${rowAxis.length} row root(s) x '
      '${columnAxis.length} column root(s), ${cells.length} cell(s))';
}

/// The stable sort key used to make [CrosstabMatrix.props] order-independent:
/// `rowPath` and `colPath` joined with a space (which cannot occur inside a
/// path segment), then `measureId`.
String _cellSortKey(CrosstabCellKey key) =>
    '${key.rowPath.join(' ')} ${key.colPath.join(' ')} ${key.measureId}';

/// The depth-first leaves of [axis]; a childless node is its own leaf.
List<CrosstabAxisNode> leavesOf(List<CrosstabAxisNode> axis) {
  final List<CrosstabAxisNode> out = <CrosstabAxisNode>[];
  void walk(CrosstabAxisNode n) {
    if (n.children.isEmpty) {
      out.add(n);
      return;
    }
    for (final CrosstabAxisNode c in n.children) {
      walk(c);
    }
  }

  for (final CrosstabAxisNode n in axis) {
    walk(n);
  }
  return out;
}
