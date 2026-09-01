/// The crosstab planner (spec A, Tasks 8 and 9): turns a [CrosstabMatrix]
/// into ordinary [FilledBand]s plus one synthetic [GroupLevel], so that
/// vertical pagination, header reprint and horizontal continuation all come
/// free from the existing layouter.
///
/// Two halves:
///
/// * [sliceColumns] — packing. A crosstab's column count is data-driven, so
///   it routinely cannot fit in one page's width. It packs the leaf column
///   groups of [CrosstabMatrix.columnAxis] greedily into slices no wider than
///   the available body width, never splitting a leaf's measure block across
///   a page boundary (that would cut its header span), and reserving room for
///   a trailing grand-total leaf so it lands on the same page as the last
///   data leaf whenever it can.
/// * [planCrosstab] — emission. It synthesises the axes' total nodes, slices
///   the (augmented) column axis, and emits header/row/total bands per slice
///   under one synthetic group whose `startNewPage` gives the horizontal
///   continuation pages.
///
/// **Total addressing is the correctness property of this file.** A total
/// addresses a path *prefix*, and prefix length `k` is gated by
/// `groups[k].showTotal` — exactly `_prefixes` in `crosstab_aggregator.dart`.
/// Read concretely: the total *for* a node `N` at depth `d` aggregates N's
/// children, so its address is N's own path (length `d + 1`) and it is gated
/// by `groups[d + 1].showTotal`; it therefore exists only while
/// `d + 1 < groups.length`, i.e. an innermost-level node has no total. The
/// grand total's address is the empty path, gated by `groups[0].showTotal`.
/// Drifting from that rule here would print totals for cells the aggregator
/// never folded (blank), and omit ones it did.
library;

import '../../domain/crosstab/crosstab.dart';
import '../../domain/crosstab/crosstab_group.dart';
import '../../domain/crosstab/crosstab_measure.dart';
import '../../domain/crosstab/crosstab_style.dart';
import '../../domain/diagnostic.dart';
import '../../domain/elements/shape_element.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/geometry.dart';
import '../../domain/group_level.dart';
import '../../domain/report_band.dart';
import '../../domain/report_element.dart';
import '../../domain/styles/box_style.dart';
import '../../domain/styles/text_style.dart';
import '../../expression/format/apply_jet_format.dart';
import '../../expression/value.dart';
import '../fill/filled_report.dart';
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

/// The band plan for one crosstab: the [bands] to splice into the fill
/// stream, the [syntheticGroups] to register with the layouter, and the
/// [diagnostics] raised while planning.
class CrosstabPlan {
  /// Creates a plan.
  const CrosstabPlan({
    required this.bands,
    required this.syntheticGroups,
    required this.diagnostics,
  });

  /// The emitted bands, in print order: per slice, one `groupHeader` per
  /// column-group level (plus a measure-name `groupHeader` when there are two
  /// or more measures), then the row-axis `detail` bands; and once, after the
  /// last slice, a zero-height `groupFooter` that closes the synthetic group.
  final List<FilledBand> bands;

  /// The synthetic groups the [bands] hang from — always exactly one, see
  /// [planCrosstab].
  final List<GroupLevel> syntheticGroups;

  /// Pure-domain diagnostics (packing pathologies from [sliceColumns], and a
  /// group-name collision). The rendering layer routes these into its sink.
  final List<Diagnostic> diagnostics;

  @override
  String toString() => 'CrosstabPlan(${bands.length} band(s), '
      '${diagnostics.length} diagnostic(s))';
}

/// Plans [ct] over its aggregated matrix [m] into bands that fit
/// [availableWidth].
///
/// The plan carries **one** synthetic [GroupLevel] named `'<ct.id>#ct'` for
/// the whole crosstab — not one per slice. The layouter breaks on
/// `startNewPage` only for the *second and later* instances of a group name
/// (`report_layouter.dart`: `!seenStartNewPageGroup.add(name)`, so the first
/// `add` returns true and does not break), so a group per slice would have
/// one instance each and would never break, silently killing horizontal
/// continuation. With one group, slice 0 does not break and slices 1..N each
/// start a fresh page. [GroupLevel.key] is a literal-string stub: the
/// layouter keys its maps on `name` and never evaluates a synthetic group's
/// key.
///
/// When [takenGroupNames] already holds that name, an **error**
/// [Diagnostic] is raised (a user-authored group of the same name would
/// otherwise win the layouter's map) — but planning still completes, because
/// the engine renders rather than crashes.
///
/// The trailing zero-height `groupFooter` is required, not decorative:
/// nothing else would close the group. An open group pops only on a
/// lower-level header, a matching footer, or `summary`/`noData`, and crosstab
/// rows are `detail` bands — without the footer the column header would
/// reprint on every page of any long detail run that follows the crosstab.
///
/// Total rows and total columns are both synthesised here, addressing the
/// path prefixes the aggregator folded (see this library's doc comment).
CrosstabPlan planCrosstab(
  Crosstab ct,
  CrosstabMatrix m, {
  required double availableWidth,
  Set<String> takenGroupNames = const <String>{},
}) {
  final List<Diagnostic> diagnostics = <Diagnostic>[];
  final String groupName = '${ct.id}#ct';
  if (takenGroupNames.contains(groupName)) {
    diagnostics.add(Diagnostic(
      DiagnosticSeverity.error,
      'crosstab "${ct.id}" needs the synthetic group name "$groupName", '
      'which a report group already uses; rename that group',
    ));
  }
  final GroupLevel synthetic = GroupLevel(
    id: groupName,
    name: groupName,
    // A literal-string expression: the layouter never reads a group's key.
    key: "'${ct.id}'",
    reprintHeaderOnEachPage: true,
    startNewPage: true,
  );

  final _AugmentedColumns columns =
      _augmentColumns(m.columnAxis, ct.columnGroups);
  final List<CrosstabSlice> slices = sliceColumns(
    CrosstabMatrix(
      rowAxis: m.rowAxis,
      columnAxis: columns.roots,
      measures: m.measures,
      cells: m.cells,
    ),
    ct.style,
    availableWidth: availableWidth,
    diagnostics: diagnostics,
  );

  final _Emitter emitter = _Emitter(ct, m, columns, groupName);
  final List<FilledBand> bands = <FilledBand>[];
  for (final CrosstabSlice slice in slices) {
    bands
      ..addAll(emitter.headerBands(slice))
      ..addAll(emitter.rowBands(slice));
  }
  if (slices.isNotEmpty) {
    bands.add(FilledBand(
      type: BandType.groupFooter,
      height: 0,
      elements: const <ReportElement>[],
      variables: const <String, JetValue>{},
      group: groupName,
    ));
  }

  return CrosstabPlan(
    bands: bands,
    syntheticGroups: <GroupLevel>[synthetic],
    diagnostics: diagnostics,
  );
}

// ---------------------------------------------------------------------------
// Axis augmentation: materialising the total columns
// ---------------------------------------------------------------------------

/// One printed column-axis leaf, with the two things its tree position no
/// longer tells us.
class _ColumnLeaf {
  const _ColumnLeaf({
    required this.path,
    required this.ancestorIds,
    required this.ancestorLabels,
    required this.isTotal,
  });

  /// The **cell address** of this leaf's column — *not* simply the node keys
  /// from the root down. For a data leaf it is exactly that; for a
  /// synthesised subtotal leaf it is its parent's path; for the grand total
  /// it is the empty path.
  final List<String> path;

  /// A unique token per ancestor, indexed by header level — `ancestorIds[l]`
  /// identifies the node covering this leaf at level `l`. Header cells span
  /// the run of adjacent columns sharing a token. Integers rather than
  /// path strings because group labels come from data and could collide with
  /// a synthesised total's label.
  final List<int> ancestorIds;

  /// The printed label of each ancestor, indexed by header level.
  final List<String> ancestorLabels;

  /// Whether this column is a subtotal or the grand total.
  final bool isTotal;
}

/// A column axis with its total leaves materialised, plus the per-leaf data
/// [of] resolves.
class _AugmentedColumns {
  const _AugmentedColumns(this.roots, this._leaves);

  /// The augmented axis roots, ready to hand to [sliceColumns].
  final List<CrosstabAxisNode> roots;

  /// Keyed by **identity**: every node in [roots] is a freshly constructed
  /// instance (see [_augmentColumns]), while two value-equal leaves under
  /// different parents are commonplace (`2025/Q1` and `2026/Q1`) and would
  /// collide in a value-keyed map.
  final Map<CrosstabAxisNode, _ColumnLeaf> _leaves;

  /// The data for [leaf], which must be one of [roots]' leaves — the only
  /// nodes [sliceColumns] can hand back.
  _ColumnLeaf of(CrosstabAxisNode leaf) => _leaves[leaf]!;
}

/// Rebuilds [axis] with a total leaf appended wherever [groups] asks for one.
///
/// The rule mirrors the aggregator's `_prefixes` exactly: an internal node
/// `N` at depth `d` gains a **trailing, childless** `isTotal` child at depth
/// `d + 1` **addressed at N's own path**, iff `groups[d + 1].showTotal`; and
/// the axis gains a **trailing, childless, depth-0** `isTotal` root
/// **addressed at the empty path** (the grand total) iff `groups[0].showTotal`.
///
/// That trailing/depth-0/childless shape is a contract, not a preference:
/// [sliceColumns] recognises the grand total precisely as a trailing depth-0
/// `isTotal` leaf, and only then reserves its width so it shares a page with
/// the last data leaf.
///
/// Nodes are rebuilt (never reused) so that every node in the result is a
/// distinct instance, which is what makes [_AugmentedColumns]' identity map
/// exact. Each is rebuilt at its **structural** depth, so a leaf's
/// `ancestorIds` index is always its header level.
_AugmentedColumns _augmentColumns(
  List<CrosstabAxisNode> axis,
  List<CrosstabGroup> groups,
) {
  final Map<CrosstabAxisNode, _ColumnLeaf> leaves =
      Map<CrosstabAxisNode, _ColumnLeaf>.identity();
  int nextId = 0;

  List<CrosstabAxisNode> visit(
    List<CrosstabAxisNode> nodes,
    int depth,
    List<String> parentPath,
    List<int> parentIds,
    List<String> parentLabels,
  ) {
    final List<CrosstabAxisNode> out = <CrosstabAxisNode>[];
    for (final CrosstabAxisNode n in nodes) {
      final List<String> path = <String>[...parentPath, n.pathKey];
      final List<int> ids = <int>[...parentIds, nextId++];
      final List<String> labels = <String>[...parentLabels, n.label];

      if (n.children.isEmpty) {
        final CrosstabAxisNode leaf =
            _rebuilt(n, depth, const <CrosstabAxisNode>[]);
        leaves[leaf] = _ColumnLeaf(
          path: path,
          ancestorIds: ids,
          ancestorLabels: labels,
          isTotal: n.isTotal,
        );
        out.add(leaf);
        continue;
      }

      final List<CrosstabAxisNode> children =
          visit(n.children, depth + 1, path, ids, labels);
      if (depth + 1 < groups.length && groups[depth + 1].showTotal) {
        final String label = _totalLabel(groups[depth + 1], n.label);
        final CrosstabAxisNode total = _totalNode(label, depth + 1);
        leaves[total] = _ColumnLeaf(
          // A subtotal column addresses its PARENT's path.
          path: path,
          ancestorIds: <int>[...ids, nextId++],
          ancestorLabels: <String>[...labels, label],
          isTotal: true,
        );
        children.add(total);
      }
      out.add(_rebuilt(n, depth, children));
    }
    return out;
  }

  final List<CrosstabAxisNode> roots =
      visit(axis, 0, const <String>[], const <int>[], const <String>[]);

  if (roots.isNotEmpty && groups.isNotEmpty && groups[0].showTotal) {
    final String label = _totalLabel(groups[0], null);
    final CrosstabAxisNode total = _totalNode(label, 0);
    leaves[total] = _ColumnLeaf(
      // The grand total addresses the EMPTY path.
      path: const <String>[],
      ancestorIds: <int>[nextId++],
      ancestorLabels: <String>[label],
      isTotal: true,
    );
    roots.add(total);
  }

  return _AugmentedColumns(roots, leaves);
}

/// A fresh copy of [n] at structural [depth] carrying [children].
CrosstabAxisNode _rebuilt(
  CrosstabAxisNode n,
  int depth,
  List<CrosstabAxisNode> children,
) =>
    CrosstabAxisNode(
      key: n.key,
      pathKey: n.pathKey,
      label: n.label,
      depth: depth,
      children: children,
      isTotal: n.isTotal,
    );

/// A synthesised total node. Its own `key`/`pathKey` are never used to
/// address a cell — a total's address is carried on [_ColumnLeaf.path] — so
/// they simply echo the printed [label].
CrosstabAxisNode _totalNode(String label, int depth) => CrosstabAxisNode(
      key: JetString(label),
      pathKey: label,
      label: label,
      depth: depth,
      isTotal: true,
    );

/// The label of the total that collapses [group] away.
///
/// `'∑ <parent label>'` (`∑ North`) by default, overridden by
/// [CrosstabGroup.totalLabel]. The grand total has no parent, hence
/// `'∑ Total'`.
String _totalLabel(CrosstabGroup group, String? parentLabel) =>
    group.totalLabel ?? '∑ ${parentLabel ?? 'Total'}';

// ---------------------------------------------------------------------------
// Band emission
// ---------------------------------------------------------------------------

/// Emits one crosstab's bands. Holds the per-crosstab context the header,
/// row and cell builders all need.
class _Emitter {
  _Emitter(this.ct, this.m, this.columns, this.groupName);

  final Crosstab ct;
  final CrosstabMatrix m;
  final _AugmentedColumns columns;
  final String groupName;

  CrosstabStyle get style => ct.style;

  /// The `groupHeader` bands for [slice]: one per column-group level,
  /// outermost first, plus a measure-name band when there are two or more
  /// measures (with one measure the leaf header already names the column).
  ///
  /// A level whose columns in this slice have no ancestor there (e.g. a slice
  /// holding only the grand total under a multi-level axis) still emits its
  /// header band at the usual [CrosstabStyle.headerRowHeight] with zero
  /// elements, rather than being omitted or shrunk — that keeps every header
  /// level's height uniform across slices, so a horizontal-continuation
  /// page's header block still lines up level-for-level with every other
  /// slice's.
  List<FilledBand> headerBands(CrosstabSlice slice) {
    final List<double> xs = _xOffsets(slice);
    final List<FilledBand> bands = <FilledBand>[];

    for (int level = 0; level < ct.columnGroups.length; level++) {
      final List<ReportElement> elements = <ReportElement>[];
      int i = 0;
      while (i < slice.columns.length) {
        final int? id = _ancestorId(slice.columns[i].leaf, level);
        int j = i + 1;
        double width = slice.columns[i].width;
        while (j < slice.columns.length &&
            _ancestorId(slice.columns[j].leaf, level) == id) {
          width += slice.columns[j].width;
          j++;
        }
        // A null id means this column has no ancestor at this level — the
        // grand-total column below the outermost level, say — so the header
        // cell is simply absent rather than blank-but-boxed.
        if (id != null) {
          _addCell(
            elements,
            id: '${ct.id}/s${slice.index}/h$level/c$i',
            text: columns.of(slice.columns[i].leaf).ancestorLabels[level],
            x: xs[i],
            width: width,
            height: style.headerRowHeight,
            textStyle: _columnHeaderText,
            boxStyle: style.headerBox,
          );
        }
        i = j;
      }
      bands.add(_headerBand(elements));
    }

    // The MATRIX's measure list is authoritative for everything printed: it
    // is what was actually folded, and it is what `sliceColumns` built the
    // columns from. (The aggregator copies `ct.measures` into the matrix, so
    // the two agree for any matrix this engine produced.)
    if (m.measures.length > 1) {
      final List<ReportElement> elements = <ReportElement>[];
      for (int i = 0; i < slice.columns.length; i++) {
        _addCell(
          elements,
          id: '${ct.id}/s${slice.index}/hm/c$i',
          text: slice.columns[i].measure.name,
          x: xs[i],
          width: slice.columns[i].width,
          height: style.headerRowHeight,
          textStyle: _columnHeaderText,
          boxStyle: style.headerBox,
        );
      }
      bands.add(_headerBand(elements));
    }

    return bands;
  }

  /// The `detail` bands for [slice]: the row axis walked depth-first, with a
  /// total row emitted on leaving a node whose next level allows one and the
  /// grand-total row after the last root.
  ///
  /// An inner node prints a label-only row (its cells live on its children);
  /// a leaf prints its label plus one cell per column of this slice. Every
  /// label is indented by `depth * rowLabelIndent`, and a node's total row is
  /// indented like the node it totals.
  List<FilledBand> rowBands(CrosstabSlice slice) {
    final List<double> xs = _xOffsets(slice);
    final List<FilledBand> bands = <FilledBand>[];
    int rowIx = 0;

    void emit({
      required String label,
      required int depth,
      required List<String>? rowPath,
      required bool isTotal,
    }) {
      final List<ReportElement> elements = <ReportElement>[];
      final String prefix = '${ct.id}/s${slice.index}/r$rowIx';
      final double indent = depth * style.rowLabelIndent;
      final double labelWidth = style.rowLabelWidth - indent;
      _addCell(
        elements,
        id: '$prefix/label',
        text: label,
        x: indent,
        width: labelWidth < 0 ? 0 : labelWidth,
        height: style.rowHeight,
        textStyle: isTotal ? _totalLabelText : _rowLabelText,
        boxStyle:
            isTotal ? (style.totalBox ?? style.headerBox) : style.headerBox,
      );

      if (rowPath != null) {
        for (int i = 0; i < slice.columns.length; i++) {
          final CrosstabColumn column = slice.columns[i];
          final _ColumnLeaf leaf = columns.of(column.leaf);
          // A cell is a total cell when either address is a total: the row
          // total, the total column, or their intersection.
          final bool total = isTotal || leaf.isTotal;
          _addCell(
            elements,
            id: '$prefix/c$i/m${column.measure.id}',
            text: _cellText(
              m.cells[CrosstabCellKey(rowPath, leaf.path, column.measure.id)],
              column.measure,
            ),
            x: xs[i],
            width: column.width,
            height: style.rowHeight,
            textStyle: total
                ? _totalCellText(column.measure)
                : _cellTextStyle(column.measure),
            boxStyle: total
                ? (style.totalBox ?? _cellBoxStyle(column.measure))
                : _cellBoxStyle(column.measure),
          );
        }
      }

      bands.add(FilledBand(
        type: BandType.detail,
        height: style.rowHeight,
        elements: elements,
        variables: const <String, JetValue>{},
      ));
      rowIx++;
    }

    void walk(
        List<CrosstabAxisNode> nodes, int depth, List<String> parentPath) {
      for (final CrosstabAxisNode n in nodes) {
        final List<String> path = <String>[...parentPath, n.pathKey];
        if (n.children.isEmpty) {
          emit(label: n.label, depth: depth, rowPath: path, isTotal: n.isTotal);
          continue;
        }
        emit(label: n.label, depth: depth, rowPath: null, isTotal: n.isTotal);
        walk(n.children, depth + 1, path);
        // The total FOR this node aggregates its children, so it is addressed
        // at this node's own path (length depth + 1) and gated by the group
        // that a prefix of that length collapses away.
        if (depth + 1 < ct.rowGroups.length &&
            ct.rowGroups[depth + 1].showTotal) {
          emit(
            label: _totalLabel(ct.rowGroups[depth + 1], n.label),
            depth: depth,
            rowPath: path,
            isTotal: true,
          );
        }
      }
    }

    walk(m.rowAxis, 0, const <String>[]);

    if (m.rowAxis.isNotEmpty &&
        ct.rowGroups.isNotEmpty &&
        ct.rowGroups[0].showTotal) {
      emit(
        label: _totalLabel(ct.rowGroups[0], null),
        depth: 0,
        rowPath: const <String>[],
        isTotal: true,
      );
    }

    return bands;
  }

  /// The left edge of each of [slice]'s columns, after the row-label column
  /// that every slice repeats.
  List<double> _xOffsets(CrosstabSlice slice) {
    final List<double> xs = <double>[];
    double x = style.rowLabelWidth;
    for (final CrosstabColumn column in slice.columns) {
      xs.add(x);
      x += column.width;
    }
    return xs;
  }

  /// The token identifying [leaf]'s ancestor at header [level], or null when
  /// [leaf] sits above that level (a total column shallower than the axis).
  int? _ancestorId(CrosstabAxisNode leaf, int level) {
    final List<int> ids = columns.of(leaf).ancestorIds;
    return level < ids.length ? ids[level] : null;
  }

  FilledBand _headerBand(List<ReportElement> elements) => FilledBand(
        type: BandType.groupHeader,
        height: style.headerRowHeight,
        elements: elements,
        variables: const <String, JetValue>{},
        group: groupName,
      );

  /// Adds one cell: its box (only when a box style resolved, so an unstyled
  /// crosstab emits no shapes at all) and then its text, in that order, so
  /// the box paints behind.
  void _addCell(
    List<ReportElement> into, {
    required String id,
    required String text,
    required double x,
    required double width,
    required double height,
    required JetTextStyle textStyle,
    required JetBoxStyle? boxStyle,
  }) {
    final JetRect bounds = JetRect(x: x, y: 0, width: width, height: height);
    if (boxStyle != null) {
      into.add(ShapeElement(
        id: '$id/box',
        bounds: bounds,
        kind: ShapeKind.rectangle,
        style: boxStyle,
      ));
    }
    into.add(TextElement(id: id, bounds: bounds, text: text, style: textStyle));
  }

  /// The printed text of one cell: a missing key prints an empty string (an
  /// empty intersection is never an invented zero), and a measure's [format],
  /// when set, is applied before stringifying.
  String _cellText(JetValue? value, CrosstabMeasure measure) {
    if (value == null) return '';
    final String? format = measure.format;
    return jetStringify(format == null ? value : applyJetFormat(value, format));
  }

  /// Column headers centre over their span by default; an authored
  /// `headerText` is honoured as written, alignment included.
  JetTextStyle get _columnHeaderText =>
      style.headerText ?? const JetTextStyle(align: JetTextAlign.center);

  /// Row labels share the header slot but, when [CrosstabStyle.headerText] is
  /// unset, fall back to [JetTextStyle.fallback] (left-aligned) rather than the
  /// centred column-header default. An authored `headerText` is honoured as
  /// written, alignment included — so a report that centres its column
  /// headers also centres this stub column; only the unstyled case is
  /// left-aligned.
  JetTextStyle get _rowLabelText => style.headerText ?? JetTextStyle.fallback;

  JetTextStyle get _totalLabelText => style.totalText ?? _rowLabelText;

  /// Cell appearance resolves in three layers: the measure's own override,
  /// then the crosstab style, then the renderer's default.
  JetTextStyle _cellTextStyle(CrosstabMeasure measure) =>
      measure.cellTextStyle ?? style.cellText ?? JetTextStyle.fallback;

  /// A total cell takes the total style when there is one; the measure's own
  /// override is the next-best description of that column.
  JetTextStyle _totalCellText(CrosstabMeasure measure) =>
      style.totalText ?? _cellTextStyle(measure);

  /// Null when nothing resolved — the caller then emits no [ShapeElement].
  JetBoxStyle? _cellBoxStyle(CrosstabMeasure measure) =>
      measure.cellBoxStyle ?? style.cellBox;
}
