/// The crosstab aggregator (spec A, Task 7): turns a forward-only stream of
/// [DataRow]s into a [CrosstabMatrix] in one pass.
///
/// [CrosstabAggregation] is stateful, not a one-shot function, because the
/// fill engine folds rows as they stream over a forward-only cursor and never
/// holds them: it cannot hand this object a list of rows, and it cannot
/// rewind to recompute a subtotal after the fact.
///
/// The core technique is **prefix folding**: for each row, this evaluates the
/// row-axis expressions into a path and the column-axis expressions into a
/// path, then folds the row's measure values into *every* `(row-path prefix)
/// x (column-path prefix)` combination — including the empty prefix, which is
/// the grand total. A shortened prefix *is* that level's subtotal, so
/// subtotals cost nothing extra to compute later and, critically, `average`
/// stays correct at every level: each subtotal's accumulator sees the raw
/// per-row values directly, rather than rolling up already-averaged children
/// (which would compute an average of averages).
library;

import '../../data/data_row.dart';
import '../../domain/crosstab/crosstab.dart';
import '../../domain/crosstab/crosstab_group.dart';
import '../../domain/crosstab/crosstab_measure.dart';
import '../../domain/diagnostic.dart';
import '../../expression/aggregate/variable_accumulator.dart';
import '../../expression/eval_context.dart';
import '../../expression/expression.dart';
import '../../expression/expression_exception.dart';
import '../../expression/value.dart';
import 'crosstab_matrix.dart';

/// The cell-count threshold above which [CrosstabAggregation.build] appends a
/// single warning [Diagnostic] instead of silently producing an unbounded
/// matrix. The matrix is still built in full either way — this never
/// truncates.
const int _cellCountWarningThreshold = 50000;

/// Folds a stream of rows for one [Crosstab] into a [CrosstabMatrix].
///
/// Usage: construct once per crosstab render, call [fold] once per row in
/// stream order, then call [build] after the last row to obtain the result.
class CrosstabAggregation {
  /// Creates an aggregation for [ct]. [makeContext] builds the expression
  /// evaluation context for one row (e.g. binding `$F{}` to that row); it is
  /// invoked once per [fold] call.
  CrosstabAggregation(
    Crosstab ct, {
    required EvalContext Function(DataRow) makeContext,
  })  : _ct = ct,
        _makeContext = makeContext,
        _rowExprs = _compile(ct.rowGroups),
        _colExprs = _compile(ct.columnGroups),
        _measureExprs = <String, Expression?>{
          for (final CrosstabMeasure m in ct.measures)
            m.id: _tryParse(m.expression),
        };

  final Crosstab _ct;
  final EvalContext Function(DataRow) _makeContext;
  final List<Expression?> _rowExprs;
  final List<Expression?> _colExprs;
  final Map<String, Expression?> _measureExprs;

  /// Accumulators, keyed by cell address. A key exists here iff at least one
  /// row contributed to it — this is what keeps the built matrix sparse (an
  /// intersection with no rows has no entry at all, never an invented zero).
  final Map<CrosstabCellKey, VariableAccumulator> _acc =
      <CrosstabCellKey, VariableAccumulator>{};

  /// The row-axis value tree, built incrementally as rows are folded. Each
  /// level's map is keyed by that level's own `pathKey`, so two different
  /// parents can each have a child with the same pathKey (e.g. two regions
  /// that both contain a city named the same) without colliding — uniqueness
  /// only has to hold among siblings.
  final Map<String, _AxisNodeBuilder> _rowRoots = <String, _AxisNodeBuilder>{};

  /// The column-axis value tree; see [_rowRoots].
  final Map<String, _AxisNodeBuilder> _colRoots = <String, _AxisNodeBuilder>{};

  /// Folds one [row] into the running totals. Call once per row, in stream
  /// order; never rewinds or re-reads a row.
  void fold(DataRow row) {
    final EvalContext ctx = _makeContext(row);

    final List<JetValue> rowKeys = <JetValue>[
      for (final Expression? e in _rowExprs)
        e?.evaluate(ctx) ?? const JetNull(),
    ];
    final List<JetValue> colKeys = <JetValue>[
      for (final Expression? e in _colExprs)
        e?.evaluate(ctx) ?? const JetNull(),
    ];
    final List<String> rowPath = <String>[
      for (final JetValue v in rowKeys) jetStringify(v),
    ];
    final List<String> colPath = <String>[
      for (final JetValue v in colKeys) jetStringify(v),
    ];

    _insert(_rowRoots, rowKeys, rowPath);
    _insert(_colRoots, colKeys, colPath);

    final List<List<String>> rowPrefixes = _prefixes(rowPath, _ct.rowGroups);
    final List<List<String>> colPrefixes = _prefixes(colPath, _ct.columnGroups);

    for (final CrosstabMeasure m in _ct.measures) {
      final Expression? expr = _measureExprs[m.id];
      final JetValue v = expr?.evaluate(ctx) ?? const JetNull();
      for (final List<String> rp in rowPrefixes) {
        for (final List<String> cp in colPrefixes) {
          final CrosstabCellKey key = CrosstabCellKey(rp, cp, m.id);
          (_acc[key] ??= VariableAccumulator(m.aggregate)).fold(v);
        }
      }
    }
  }

  /// Produces the resulting [CrosstabMatrix] from every row folded so far.
  /// Call once, after the last row.
  CrosstabMatrix build() {
    final List<CrosstabAxisNode> rowAxis = _toAxis(_rowRoots, _ct.rowGroups, 0);
    final List<CrosstabAxisNode> columnAxis =
        _toAxis(_colRoots, _ct.columnGroups, 0);
    final Map<CrosstabCellKey, JetValue> cells = <CrosstabCellKey, JetValue>{
      for (final MapEntry<CrosstabCellKey, VariableAccumulator> e
          in _acc.entries)
        e.key: e.value.value,
    };

    final List<Diagnostic> diagnostics = <Diagnostic>[];
    if (_acc.length > _cellCountWarningThreshold) {
      diagnostics.add(Diagnostic(
        DiagnosticSeverity.warning,
        'crosstab "${_ct.id}" produced ${_acc.length} cells; check the '
        'group bindings',
      ));
    }

    return CrosstabMatrix(
      rowAxis: rowAxis,
      columnAxis: columnAxis,
      measures: _ct.measures,
      cells: cells,
      diagnostics: diagnostics,
    );
  }

  /// Compiles each group's expression, in order. A malformed expression
  /// compiles to `null` (render-don't-crash) rather than throwing; `validate()`
  /// is what surfaces that authoring mistake to the designer.
  static List<Expression?> _compile(List<CrosstabGroup> groups) =>
      <Expression?>[
        for (final CrosstabGroup g in groups) _tryParse(g.expression)
      ];

  static Expression? _tryParse(String source) {
    try {
      return Expression.parse(source);
    } on ExpressionException {
      return null;
    }
  }
}

/// Inserts one row's full [path] (with typed [keys]) into the axis tree
/// rooted at [roots], creating nodes as needed. Unconditional: every level of
/// every row's real value combination is represented, independent of any
/// `showTotal` gating (that gating only decides which *cells* get folded, in
/// [_prefixes] — the tree itself always reflects the data actually seen; a
/// non-leaf node's own path already doubles as the address of that level's
/// subtotal cell, so no separate synthetic "total" node is needed).
void _insert(
  Map<String, _AxisNodeBuilder> roots,
  List<JetValue> keys,
  List<String> path,
) {
  Map<String, _AxisNodeBuilder> level = roots;
  for (int i = 0; i < keys.length; i++) {
    final String pathKey = path[i];
    final _AxisNodeBuilder node =
        level.putIfAbsent(pathKey, () => _AxisNodeBuilder(keys[i], pathKey));
    level = node.children;
  }
}

/// Converts one level of the value tree rooted at [level] into sorted
/// [CrosstabAxisNode]s, recursing into children. [groups] is the full axis
/// group list and [depth] indexes into it for this level's [CrosstabGroup]
/// (which supplies the [CrosstabSort] to apply among this level's siblings).
List<CrosstabAxisNode> _toAxis(
  Map<String, _AxisNodeBuilder> level,
  List<CrosstabGroup> groups,
  int depth,
) {
  final List<_AxisNodeBuilder> nodes = level.values.toList();
  switch (groups[depth].sort) {
    case CrosstabSort.ascending:
      nodes.sort((_AxisNodeBuilder a, _AxisNodeBuilder b) =>
          _compareTyped(a.key, b.key));
    case CrosstabSort.descending:
      nodes.sort((_AxisNodeBuilder a, _AxisNodeBuilder b) =>
          _compareTyped(b.key, a.key));
    case CrosstabSort.dataOrder:
      break; // Map preserves first-insertion order already.
  }
  return <CrosstabAxisNode>[
    for (final _AxisNodeBuilder n in nodes)
      CrosstabAxisNode(
        key: n.key,
        pathKey: n.pathKey,
        label: n.pathKey,
        depth: depth,
        children: n.children.isEmpty
            ? const <CrosstabAxisNode>[]
            : _toAxis(n.children, groups, depth + 1),
      ),
  ];
}

/// Compares two typed group keys for [CrosstabSort.ascending]/`descending`:
/// numbers numerically and dates chronologically via [jetCompare]; falls back
/// to comparing the stringified form for any pair `jetCompare` cannot order
/// (mismatched or non-orderable types), so sorting never throws even over
/// heterogeneous data.
int _compareTyped(JetValue a, JetValue b) =>
    jetCompare(a, b) ?? jetStringify(a).compareTo(jetStringify(b));

/// The full path plus every shortened prefix whose *last kept* level has
/// `showTotal: true` — that level's own subtotal, aggregating away everything
/// nested beneath it. The empty prefix (the grand total) is gated by the
/// outermost level's `showTotal` instead, since it has no "last kept level"
/// of its own.
///
/// Each length is gated independently: a `false` at one level does not
/// suppress shorter prefixes gated by a different level.
List<List<String>> _prefixes(List<String> path, List<CrosstabGroup> groups) {
  final int n = path.length;
  final List<List<String>> out = <List<String>>[path];
  for (int k = n - 1; k >= 0; k--) {
    final CrosstabGroup gate = groups[k == 0 ? 0 : k - 1];
    if (gate.showTotal) {
      out.add(path.sublist(0, k));
    }
  }
  return out;
}

/// One in-progress node of an axis value tree, before sorting/depth are
/// resolved into a [CrosstabAxisNode].
class _AxisNodeBuilder {
  _AxisNodeBuilder(this.key, this.pathKey);

  /// The typed group key this node represents.
  final JetValue key;

  /// The stringified form of [key].
  final String pathKey;

  /// Children, keyed by their own `pathKey` (unique among siblings only).
  final Map<String, _AxisNodeBuilder> children = <String, _AxisNodeBuilder>{};
}
