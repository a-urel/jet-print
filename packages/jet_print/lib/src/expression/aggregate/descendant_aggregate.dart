/// Flat descendant leaf folding for multi-level inline aggregates (spec 033).
///
/// A sink-band aggregate (`{SUM([lineTotal])}` at a summary, root group footer,
/// or nested-scope footer) folds its operand over **every descendant leaf row**
/// reachable from the band's scope instance by descending a chain of collection
/// fields (the [DescendPath] from `resolveAggregatePath`). The fold is FLAT —
/// each leaf is folded directly into the accumulator, never via per-level
/// subtotals — so SUM/COUNT/MIN/MAX equal the hierarchical roll-up and AVG is a
/// true average over all leaves (FR-002, FR-004).
///
/// Pure: it knows nothing of `EvalContext` or diagnostics. The caller supplies
/// [eval] (operand value for one leaf row) and [childRowsOf] (a row's named
/// collection as child rows) so the filler can inject its own context/diagnostics.
library;

import '../../data/data_row.dart';
import '../value.dart';
import 'variable_accumulator.dart';

/// Folds [eval] over every descendant leaf reached from each row in [rows] by
/// descending the collection-field [path] (outermost-first), into [acc]. An
/// empty [path] folds [eval] over [rows] themselves.
void foldDescendantLeaves({
  required List<DataRow> rows,
  required List<String> path,
  required VariableAccumulator acc,
  required JetValue Function(DataRow leaf) eval,
  required List<DataRow> Function(DataRow row, String collectionField)
      childRowsOf,
}) {
  if (path.isEmpty) {
    for (final DataRow r in rows) {
      acc.fold(eval(r));
    }
    return;
  }
  final String head = path.first;
  final List<String> rest = path.sublist(1);
  for (final DataRow r in rows) {
    foldDescendantLeaves(
      rows: childRowsOf(r, head),
      path: rest,
      acc: acc,
      eval: eval,
      childRowsOf: childRowsOf,
    );
  }
}
