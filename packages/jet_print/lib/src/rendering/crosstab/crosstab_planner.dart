/// The crosstab planner (spec A, Task 8): packs a [CrosstabMatrix]'s printed
/// data columns into horizontal page-[CrosstabSlice]s.
///
/// A crosstab's column count is data-driven, so it routinely cannot fit in
/// one page's width. [sliceColumns] answers that with horizontal continuation
/// pages: it packs the leaf column groups of [CrosstabMatrix.columnAxis]
/// greedily into slices no wider than the available body width, never
/// splitting a leaf's measure block across a page boundary (that would cut
/// its header span), and reserving room for a trailing grand-total leaf so it
/// lands on the same page as the last data leaf whenever it can.
///
/// This is the packing half of the planner; a later task turns each slice
/// into actual bands, and the layouter gets the horizontal page breaks for
/// free from a synthetic group over the slices.
library;

import '../../domain/crosstab/crosstab_measure.dart';
import '../../domain/crosstab/crosstab_style.dart';
import '../../domain/diagnostic.dart';
import 'crosstab_matrix.dart';

/// One printed data column: a leaf column-axis group crossed with one
/// [measure].
class CrosstabColumn {
  /// Creates a printed column.
  const CrosstabColumn({
    required this.leaf,
    required this.measure,
    required this.width,
  });

  /// The column-axis leaf this column belongs to. All of a leaf's measure
  /// columns share the same [leaf] and always land in the same
  /// [CrosstabSlice] — see [sliceColumns].
  final CrosstabAxisNode leaf;

  /// The measure this column shows.
  final CrosstabMeasure measure;

  /// This column's width. Spec A always sets this to
  /// `style.measureColumnWidth`; a per-measure width override is out of
  /// scope.
  final double width;
}

/// One horizontal page-slice: a contiguous run of [columns] that fits within
/// one page's body width alongside the row-label column.
class CrosstabSlice {
  /// Creates a slice.
  const CrosstabSlice({required this.index, required this.columns});

  /// This slice's 0-based position among the slices [sliceColumns] returned.
  /// Every slice after the first (`index > 0`) starts a new page.
  final int index;

  /// The printed columns carried by this slice, in column order. Every slice
  /// implicitly also carries the row-label column (`style.rowLabelWidth`),
  /// which is not represented here.
  final List<CrosstabColumn> columns;
}

/// Packs [m]'s column-axis leaves into [CrosstabSlice]s that each fit within
/// [availableWidth], appending any pathology found while packing to
/// [diagnostics].
///
/// The packing budget for columns is `availableWidth - style.rowLabelWidth`,
/// since every slice implicitly repeats the row-label column. A leaf's whole
/// measure block (all of `m.measures`) is the packing unit — a slice never
/// splits it, so a leaf's header span is never cut across a page boundary.
///
/// When [m]'s column axis ends in a depth-0 leaf with `isTotal: true` (the
/// grand total), that leaf's width is reserved while packing the slice that
/// will hold the last data leaf, so the grand total lands on that same page
/// whenever it can. If it still cannot fit there — even alone — it gets its
/// own trailing slice and a [Diagnostic.warning] records the pathology; data
/// is never dropped to make it fit.
///
/// A leaf whose own measure block is wider than the budget is placed anyway
/// (rendered, not silently dropped, however it overflows); that pathology
/// also produces one [Diagnostic.warning], regardless of how many leaves
/// trigger it (every leaf has the same measure count, hence the same width,
/// so the condition is either true for all leaves or none).
List<CrosstabSlice> sliceColumns(
  CrosstabMatrix m,
  CrosstabStyle style, {
  required double availableWidth,
  required List<Diagnostic> diagnostics,
}) {
  final List<CrosstabAxisNode> allLeaves = leavesOf(m.columnAxis);

  // The grand total, when present, is a trailing depth-0 `isTotal` leaf —
  // see the library doc comment. A subtotal leaf produced by collapsing a
  // shallower group (isTotal at depth > 0) is not this; it is packed like
  // any other data leaf.
  CrosstabAxisNode? grandTotalLeaf;
  List<CrosstabAxisNode> dataLeaves = allLeaves;
  if (allLeaves.isNotEmpty &&
      allLeaves.last.isTotal &&
      allLeaves.last.depth == 0) {
    grandTotalLeaf = allLeaves.last;
    dataLeaves = allLeaves.sublist(0, allLeaves.length - 1);
  }

  final double leafWidth = m.measures.length * style.measureColumnWidth;
  final double budget = availableWidth - style.rowLabelWidth;

  if (leafWidth > budget && (dataLeaves.isNotEmpty || grandTotalLeaf != null)) {
    diagnostics.add(const Diagnostic(
      DiagnosticSeverity.warning,
      'crosstab column group is wider than the page body',
    ));
  }

  final List<CrosstabSlice> slices = <CrosstabSlice>[];
  List<CrosstabColumn> current = <CrosstabColumn>[];
  double currentWidth = 0;

  void appendLeaf(CrosstabAxisNode leaf) {
    for (final CrosstabMeasure measure in m.measures) {
      current.add(CrosstabColumn(
        leaf: leaf,
        measure: measure,
        width: style.measureColumnWidth,
      ));
    }
    currentWidth += leafWidth;
  }

  for (int i = 0; i < dataLeaves.length; i++) {
    final bool isLastDataLeaf = i == dataLeaves.length - 1;
    // Reserve the grand total's width while packing the slice that will hold
    // the last data leaf, so the total is never stranded alone on a page of
    // its own.
    final double reserve =
        isLastDataLeaf && grandTotalLeaf != null ? leafWidth : 0;
    final double needed = leafWidth + reserve;
    if (current.isNotEmpty && currentWidth + needed > budget) {
      slices.add(CrosstabSlice(index: slices.length, columns: current));
      current = <CrosstabColumn>[];
      currentWidth = 0;
    }
    appendLeaf(dataLeaves[i]);
  }

  if (grandTotalLeaf != null) {
    if (currentWidth + leafWidth <= budget) {
      appendLeaf(grandTotalLeaf);
    } else {
      // The total does not fit in whatever room is left in `current` — either
      // the reservation above could not secure enough of it (e.g. the last
      // data leaf's own block, plus the total, exceeds the whole budget), or
      // there were no data leaves at all and the total's own width alone
      // exceeds the budget. Either way this is accepted pathology, not
      // silent: it prints on its own continuation page and a diagnostic says
      // so.
      if (current.isNotEmpty) {
        slices.add(CrosstabSlice(index: slices.length, columns: current));
        current = <CrosstabColumn>[];
        currentWidth = 0;
      }
      appendLeaf(grandTotalLeaf);
      diagnostics.add(const Diagnostic(
        DiagnosticSeverity.warning,
        'crosstab grand total does not fit in the available width and was '
        'placed on its own continuation page',
      ));
    }
  }

  if (current.isNotEmpty) {
    slices.add(CrosstabSlice(index: slices.length, columns: current));
  }

  return slices;
}
