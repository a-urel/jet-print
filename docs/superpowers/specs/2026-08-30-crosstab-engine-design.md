# Crosstab / Pivot Grid — Engine Core (Spec A)

**Date:** 2026-08-30
**Status:** Design approved; implementation plan pending
**Layer:** domain + rendering (fill/layout seam). No painter, exporter, printer or preview change.

## Goal

Add a first-class, **paginated** crosstab (pivot grid) to the report engine: multi-level row and
column dimensions, multiple measures, subtotals at every level, column headers reprinted on each
page, and horizontal continuation pages when the data-driven columns exceed the page width.

The crosstab is an independent block bound to a collection — it performs its own group-by pass and
is placed in the scope tree as a sibling of bands.

## Scope split

"Full Jasper-equivalent crosstab" does not fit one spec. Three specs, each independently shippable:

| Spec | Content | Ships on its own |
|---|---|---|
| **A — Engine (this document)** | Domain model, codec + `UnknownScopeNode`, `CrosstabNode`, aggregator, planner, filler injection, layouter synthetic groups, `validate()`, playground demo | Yes — a crosstab authored in JSON renders, previews and exports to PDF; the designer shows it read-only |
| **B — Designer authoring** | Outline "Add crosstab", Properties editor (row/column groups, measures, style), canvas WYSIWYG via the same planner, selection/hit-test, l10n | Yes — authoring on top of A |
| **C — Polish** | "Across-first" slice order, fit/scale column mode, derived measures, cell templates | Optional, evidence-driven |

## Locked decisions

1. **Paginated, first-class** — not a fixed-size element in a box.
2. **N row groups x N column groups x M measures**, optional subtotal at each level.
3. **Cell = value + style** (expression, text style, box style, alignment). No per-cell mini-band.
   The model can gain an optional `template: Band?` later without breaking anything.
4. **Column overflow = horizontal continuation page**, row-label columns repeated on each slice.
5. **`CrosstabNode` in the scope tree**, carrying its own `collectionField` (null = the rows of the
   scope it lives in).
6. **Measure = per-row expression + aggregate + format.** The aggregate is the existing
   `JetCalculation`; `VariableAccumulator` does the folding.
7. **Position rule:** crosstabs placed *before* the first row-producing node (`BandNode` /
   `NestedScope`) in `children` print once *before* the row loop; those after it print once *after*.
   Relative order among themselves is preserved. No extra model field; matches the Outline order.

## 1. Domain model

New directory `lib/src/domain/crosstab/`. Pure domain — no Flutter, no rendering.

```dart
final class CrosstabNode extends ScopeNode with ValueEquality {
  const CrosstabNode(this.crosstab);
  final Crosstab crosstab;
}

class Crosstab with ValueEquality {
  const Crosstab({
    required this.id,
    this.name,                  // display name (Outline / Properties)
    this.collectionField,       // null = the rows of the enclosing scope
    required this.rowGroups,    // outermost-first, >= 1
    required this.columnGroups, // outermost-first, >= 1
    required this.measures,     // >= 1
    this.style = const CrosstabStyle(),
    this.visible = const BoolProperty(),
  });
}

class CrosstabGroup with ValueEquality {
  const CrosstabGroup({
    required this.id,
    required this.name,         // header text / total label stem
    required this.expression,   // per-row group key, e.g. '{[region]}'
    this.sort = CrosstabSort.ascending,
    this.showTotal = true,      // subtotal at this level
    this.totalLabel,            // null -> '<name> Total' (localized default)
  });
}

enum CrosstabSort { ascending, descending, dataOrder }

class CrosstabMeasure with ValueEquality {
  const CrosstabMeasure({
    required this.id,
    required this.name,         // column header
    required this.expression,   // per-row value, e.g. '{[qty] * [price]}'
    required this.aggregate,    // JetCalculation (none rejected by validate)
    this.format,                // '#,##0.00' — existing applyJetFormat
    this.cellStyle,             // optional per-measure override
  });
}

class CrosstabStyle with ValueEquality {
  const CrosstabStyle({
    this.headerText, this.headerBox,
    this.cellText,   this.cellBox,
    this.totalText,  this.totalBox,
    this.rowLabelWidth = 110,
    this.rowLabelIndent = 12,
    this.measureColumnWidth = 64,
    this.rowHeight = 14,
    this.headerRowHeight = 14,
  });
}
```

Fixed semantics:

- **Measures live on the innermost column axis.** Each leaf column group is followed by M measure
  columns. No `measureAxis` option.
- **No separate grand-total flag.** `showTotal: true` on the outermost group *is* the grand total.
  One concept, one rule at every level.
- **An empty intersection is an empty cell.** If no row falls in a cell, nothing is printed — not
  even `count: 0`. Zero and "no data" stay distinguishable.
- **`collectionField` flattens.** A nested collection name pools that collection across all parent
  rows; this is what a pivot means.
- **Cell style resolves in three layers:** measure override -> crosstab `style` -> default.

`CrosstabNode` joins the sealed `ScopeNode` hierarchy deliberately: Dart's exhaustive switch turns
every site that must handle a crosstab into a compile error, so no branch can silently drop it.

## 2. Aggregation — data to matrix

`lib/src/rendering/crosstab/crosstab_aggregator.dart`. Pure: rows in, value tree out. No layout.

```dart
class CrosstabAxisNode {
  final String key;                       // comparable group key
  final String label;                     // text to print
  final int depth;                        // 0 = outermost
  final List<CrosstabAxisNode> children;  // empty = leaf
  final bool isTotal;                     // subtotal / grand-total node
}

class CrosstabMatrix {
  final List<CrosstabAxisNode> rowAxis;    // sorted roots
  final List<CrosstabAxisNode> columnAxis;
  final List<CrosstabMeasure> measures;
  /// (rowPath, colPath, measureId) -> value.
  /// No key when the intersection saw no rows (empty cell).
  final Map<CrosstabCellKey, JetValue> cells;
}

/// The address of one cell: the row-axis path, the column-axis path and the
/// measure id. A value type (`ValueEquality`) so it is a usable map key; a
/// shortened path addresses that level's subtotal.
class CrosstabCellKey with ValueEquality {
  const CrosstabCellKey(this.rowPath, this.colPath, this.measureId);
  final List<String> rowPath;
  final List<String> colPath;
  final String measureId;
}

CrosstabMatrix aggregateCrosstab(Crosstab ct, List<DataRow> rows, {...});
```

**Single pass, subtotals included.** For each row:

1. Evaluate the row-group expressions in order -> row path (e.g. `[North, Istanbul]`); the same for
   column groups -> column path (e.g. `[2025, Q1]`).
2. Evaluate each measure's per-row expression -> that row's contribution.
3. Fold the contribution into **every ancestor prefix combination**:
   `(row-path prefixes) x (column-path prefixes) x M`. A shortened prefix is that level's total node.

So one row contributes to the leaf intersection, the `∑ North` row, the `2025` total column and the
grand total **in the same pass**. There is no second roll-up pass.

This matters for correctness, not just speed: rolling leaf values upward would compute an average of
averages, which is not the average. With prefix folding every level sees the raw contributions.

Accumulators are held in `Map<CrosstabCellKey, VariableAccumulator>` during the pass, then converted
to values; keys are sorted per `CrosstabSort` (numeric keys numerically, otherwise as strings;
`dataOrder` = first-seen), and the axis trees are built.

Consequences:

- A level with `showTotal: false` is never folded — no wasted work.
- Per-row cost is `(rowDepth + 1) x (colDepth + 1) x M` folds; typically 8. Linear in rows.
- **Cardinality risk:** a high-cardinality group binding (e.g. customer name over 20k distinct
  values) explodes the cell count. A threshold diagnostic is raised through the existing
  `DiagnosticBudget` rather than growing silently.
- Output is deterministic ordered data, so `CrosstabMatrix` is snapshot-testable independently of any
  geometry.
- With `collectionField` set, the row pool is flattened through `coerceCollectionRows` — the same
  seam the chart resolver uses, so schema inference and malformed-entry diagnostics come for free.

## 3. Planner — matrix to band plan

`lib/src/rendering/crosstab/crosstab_planner.dart`. Pure: matrix + style + available width in,
bands + synthetic groups out. No data access, no measurement, no Flutter.

```dart
class CrosstabPlan {
  final List<FilledBand> bands;
  final List<GroupLevel> syntheticGroups;
  /// Pure-domain `Diagnostic`s (the `domain/diagnostic.dart` type, as returned
  /// by `validate()`) — the planner stays free of the rendering-layer
  /// `ReportDiagnostics` sink, which the filler routes them into.
  final List<Diagnostic> diagnostics;
}

CrosstabPlan planCrosstab(CrosstabMatrix m, CrosstabStyle style, {
  required double availableWidth,
});
```

**Column layout.** The column axis is flattened to leaves; each leaf x M measures is a data column.
A fixed `rowLabelWidth` row-label column sits on the left.

**Horizontal slicing.** A slice is the row-label column plus as many data columns as fit. Rules:

- A slice boundary never splits a leaf column group — a leaf's M measures always stay in one slice,
  otherwise the header span would be cut in half.
- If even a single leaf group does not fit, print it anyway and raise a diagnostic (mirroring the
  existing "exceeds body capacity" behaviour).
- The grand-total column appears **only in the last slice**. Repeating it per slice would read as
  "this slice's total", which is wrong. Not configurable.

**Bands per slice:**

| Band | Type | Note |
|---|---|---|
| Column header x `columnGroups.length` | `groupHeader`, `group: '<ctId>#s<N>'` | One band per level; a header cell's width is (leaves beneath it x column width), so the horizontal span is a single wide `TextElement` |
| Measure-name band | `groupHeader`, same group | Only when M > 1 |
| Row bands | `detail` | Row axis walked depth-first |
| Subtotal bands | `detail` | `∑ North`, styled with `totalText` / `totalBox` |

Row-axis walk: an inner node (`North`) prints a label-only row without indent; a leaf (`Istanbul`)
prints an indented label (`depth x rowLabelIndent`) plus the slice's cells; on leaving a node with
`showTotal` a `∑ North` band is emitted.

The synthetic group is `GroupLevel(id: '<ctId>#s<N>', reprintHeaderOnEachPage: true,
startNewPage: N > 0)`. `startNewPage` produces the horizontal continuation page; `reprint` repeats
the column header on every page. **No vertical-pagination code is written at all** — the layouter's
existing group mechanism does it.

**Cell elements.** A value cell is `TextElement(text: applyJetFormat(value, measure.format), ...)`.
When the resolved box style is non-null a `ShapeElement` rectangle is emitted behind it (a
`TextElement` has no box of its own). An unstyled crosstab emits no shapes, halving the element
count.

**Deterministic element ids:** `'<ctId>/s<slice>/r<rowIx>/c<colIx>/m<measureId>'`. The
`onElementPrint` host hook can key conditional formatting off these, and goldens stay stable.

A 50-row x 10-column crosstab is roughly 500 elements (1000 when styled). The planner raises a
diagnostic above an upper bound.

## 4. Integration

**Filler.** A third arm in `emitNode` (`report_filler.dart`):

```dart
case CrosstabNode(crosstab: final Crosstab ct):
  final List<DataRow> pool = ct.collectionField == null
      ? scopeRows
      : flattenCollection(scopeRows, ct.collectionField!);
  final CrosstabMatrix m = aggregateCrosstab(ct, pool, ...);
  final CrosstabPlan plan = planCrosstab(m, ct.style,
      availableWidth: def.page.width - def.page.margins.left
                                     - def.page.margins.right);
  bands.addAll(plan.bands);
  synthetic.addAll(plan.syntheticGroups);
```

(Illustrative — the real arm uses the filler's own row/diagnostic variables.) `flattenCollection` is
a thin helper over the existing `coerceCollectionRows`: it pools one named child collection across
all rows of the enclosing scope, so schema inference and malformed-entry diagnostics stay on the
shared seam.

The position rule (decision 7) determines whether the crosstab's bands are emitted before or after
the scope's row loop. A crosstab whose `visible` `BoolProperty` resolves false emits no bands and no
synthetic groups at all — it is skipped before aggregation, so its data pass is not paid for either.

**`FilledReport.syntheticGroups`** — a new field on the internal IR, carrying the planner's groups.

**Layouter.** The single place that builds the group table (`report_layouter.dart`, the
`levelOf` / `groupByName` maps) uses `def.body.root.groups` **plus** `filled.syntheticGroups`, with
the synthetic ones appended so they become the innermost levels and nest correctly inside open
master groups. The three read sites in the pagination loop (`keepTogether`, `startNewPage`,
`reprint`) are untouched.

One side effect to handle: the "reprint set but no header" info diagnostic would fire wrongly for
synthetic groups (their header band lives in the stream, not in `def`). Synthetic groups are exempt.

**Sealed-switch fallout.** Adding `CrosstabNode` makes `dart analyze` flag every site; Spec A
behaviour:

| File | Spec A behaviour |
|---|---|
| `rendering/fill/report_filler.dart` | The real work (above) |
| `domain/serialization/report_definition_codec.dart` | `kind: 'crosstab'`, additive |
| `domain/report_validation.dart` | Crosstab rules (section 5) |
| `designer/controller/band_walker.dart` | A crosstab holds no bands, so `allBands` skips it; `allIds` **includes** the crosstab id (uniqueness) |
| `designer/canvas/design_time_layout.dart` | Placeholder block (real WYSIWYG is Spec B) |
| `designer/layout/panels/outline_panel/rows.dart` | Read-only row with a glyph |
| `domain/report_definition.dart` | `isPureSingleDetailBody` is false when a crosstab is present |
| `scope_commands.dart`, `api/groups_scopes.dart`, `api/bands.dart`, `scope_field_choices.dart`, `binding_scope.dart`, `default_definition.dart` | Arms that ignore or appropriately handle a crosstab |
| `migrations/v1_to_v2.dart` | Unreachable arm — v1 has no crosstab |

Painter, PDF exporter, printer, preview, `onElementPrint` and watermark are unchanged: the output is
ordinary text and shape primitives.

## 5. Serialization and validation

**Codec.** A third `kind` value on the scope-node discriminated union: `'crosstab'`. The crosstab
sub-objects get `toJson` / `fromJson` following the `ColumnLayout` pattern, omitting defaults so
crosstab-free reports stay byte-identical.

**Schema version stays 2** (as with chart, barcode and watermark). But there is a gap: an unknown
*element* type is preserved losslessly via `UnknownElement`, while an unknown scope-node `kind`
throws `ReportFormatException` — so an older build could not open a crosstab report at all.

Spec A therefore adds **`UnknownScopeNode`**: it keeps the raw JSON, is skipped during render, and is
written back verbatim on save. It is `UnknownElement`'s sibling, consistent with Constitution V
(lossless round-trip), and pays off for every future scope-node type.

**`validate()` rules** (added to the existing `Diagnostic` list):

| Rule | Severity |
|---|---|
| `rowGroups`, `columnGroups`, `measures` each have at least one entry | error |
| Group and measure expressions parse | error |
| Fields referenced by those expressions resolve in the crosstab's data scope (existing `binding_scope`) | warning |
| `measure.aggregate != JetCalculation.none` | error |
| `collectionField`, when set, names an actual collection in that scope | error |
| The crosstab id is unique across the band/element id pool | error |
| `rowLabelWidth`, `measureColumnWidth`, `rowHeight` are all > 0 | error |
| `rowLabelWidth + (M x measureColumnWidth)` exceeds the available body width — not even one leaf column group fits | warning |
| A crosstab and a `columnLayout` label grid coexist in the same body | warning |

The width rule is a quiet win of this architecture: because the crosstab's geometry derives entirely
from author-time numbers, "this crosstab will not fit the page" is answerable **without looking at
the data**. The only data-driven unknown is the column *count*, which horizontal slicing already
handles.

## 6. Testing and file map

| Layer | Test kind | What it proves |
|---|---|---|
| `crosstab_aggregator` | Pure unit + `CrosstabMatrix` data golden | Prefix-fold subtotals; `average` correct at every level; empty intersection has no key; `showTotal: false` is not folded; sorting (numeric / string / `dataOrder`); cardinality diagnostic |
| `crosstab_planner` | Pure unit + band-plan snapshot | A slice never splits a leaf group; grand total only in the last slice; header span widths; indentation; deterministic element ids; no shapes when unstyled |
| Codec | Round-trip + losslessness | Crosstab round-trips; `UnknownScopeNode` is written back verbatim; **crosstab-free reports are byte-identical** |
| `validate()` | One test per rule | All nine rules |
| Filler | Fill snapshot golden | Position rule (before / after the row loop); `collectionField` flattening; synthetic groups reach `FilledReport` |
| Layouter | Pagination tests | Column header repeats on every page of a multi-page crosstab; a horizontal slice starts a new page; synthetic groups raise no spurious info diagnostic |
| Render | PNG golden via the playground demo | WYSIWYG: canvas, preview and PDF agree |
| **Regression** | Full sweep | 2307 tests green; **zero golden changes for crosstab-free reports** |

That last row is Spec A's hard acceptance criterion: the feature is purely additive, so no existing
golden may move. If one does, a seam has leaked.

**New files:**

- `lib/src/domain/crosstab/crosstab.dart`, `crosstab_group.dart`, `crosstab_measure.dart`,
  `crosstab_style.dart`
- `lib/src/domain/crosstab/crosstab_codec.dart`
- `lib/src/domain/unknown_scope_node.dart`
- `lib/src/rendering/crosstab/crosstab_aggregator.dart` (+ `crosstab_matrix.dart`)
- `lib/src/rendering/crosstab/crosstab_planner.dart`
- Tests under `test/domain/crosstab/` and `test/rendering/crosstab/`
- Playground: a crosstab demo

**Modified:** `detail_scope.dart` (`CrosstabNode`), `report_definition_codec.dart` (`kind`),
`report_validation.dart`, `report_filler.dart` (`emitNode` + position rule), `filled_report.dart`
(`syntheticGroups`), `report_layouter.dart` (group-table union + diagnostic exemption),
`report_definition.dart` (`isPureSingleDetailBody`), plus the eight designer files in the
sealed-switch fallout (minimum behaviour in Spec A).

The barrel exports `Crosstab` and its sub-types, so `public_api_test` is updated.

## Acceptance criteria

- **SC-001** A crosstab authored in JSON renders identically on canvas, in preview and in PDF export.
- **SC-002** Subtotals are correct at every level for all five aggregates, `average` included.
- **SC-003** A crosstab longer than one page repeats its column header on every page.
- **SC-004** A crosstab wider than the page continues on further pages, with the row-label columns
  repeated and the grand-total column appearing only in the last slice.
- **SC-005** An empty intersection prints an empty cell, not a zero.
- **SC-006** No existing golden changes; the full suite stays green.
- **SC-007** Opening a crosstab report in a build without crosstab support preserves it losslessly
  via `UnknownScopeNode`.

## Out of scope (Spec A)

Designer authoring (Spec B). "Across-first" slice order, fit/scale column mode, derived measures,
per-cell band templates (Spec C). Vertical cell merging — the chosen layout puts hierarchical row
labels on their own rows, so it is not needed. Async / streaming fill; the engine fills eagerly, as
today.
