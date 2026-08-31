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
  /// directly. That flattening is ordered by [_compareCellKeys] (`rowPath`,
  /// then `colPath`, then `measureId`), so **matrix equality — and
  /// `hashCode` — is independent of cell insertion order**: two matrices
  /// holding the same cells, inserted in different orders, compare equal.
  @override
  List<Object?> get props {
    final List<MapEntry<CrosstabCellKey, JetValue>> sortedEntries =
        cells.entries.toList()
          ..sort((MapEntry<CrosstabCellKey, JetValue> a,
                  MapEntry<CrosstabCellKey, JetValue> b) =>
              _compareCellKeys(a.key, b.key));
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

/// Orders two cell keys by `rowPath`, then `colPath`, then `measureId` — the
/// ordering that makes [CrosstabMatrix.props] independent of cell insertion
/// order.
///
/// Compares the paths' components directly (via [_compareStringLists])
/// rather than joining them into one string first: path segments are group
/// labels drawn from data (e.g. `New York`, `Q1 2026`) and routinely contain
/// spaces or any other separator, so no join-with-a-separator scheme can be
/// collision-free. Comparing structurally is collision-free by construction —
/// two distinct [CrosstabCellKey]s can never compare equal here — so there
/// are no ties for [List.sort]'s documented instability to disturb.
int _compareCellKeys(CrosstabCellKey a, CrosstabCellKey b) {
  final int rowCmp = _compareStringLists(a.rowPath, b.rowPath);
  if (rowCmp != 0) return rowCmp;
  final int colCmp = _compareStringLists(a.colPath, b.colPath);
  if (colCmp != 0) return colCmp;
  return a.measureId.compareTo(b.measureId);
}

/// Lexicographic comparison of two path segment lists: element by element,
/// with the shorter list sorting first when one is a prefix of the other.
int _compareStringLists(List<String> a, List<String> b) {
  final int shorterLength = a.length < b.length ? a.length : b.length;
  for (int i = 0; i < shorterLength; i++) {
    final int cmp = a[i].compareTo(b[i]);
    if (cmp != 0) return cmp;
  }
  return a.length.compareTo(b.length);
}

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
