# Crosstab / Pivot Grid — Engine Core (Spec A)

**Date:** 2026-08-30
**Status:** Revision 2 — approved after three reviews; implementation plan pending
**Revision 2 changes:** filler integration redesigned (accumulate-and-splice, no row buffering);
one synthetic group per crosstab instead of per slice (per-slice groups never break a page); a
closing footer so the group stops reprinting; a prep task converting `ScopeNode` `is`-chains to
exhaustive switches; crosstab restricted to the root scope; several factual corrections.
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
   Edge cases: in a body with no row-producing node at all (a crosstab-only report) every crosstab
   prints in `children` order, once. A crosstab sitting *between* two bands counts as "after" — it
   prints after the whole row loop, not interleaved. Both are stated in the Outline's tooltip copy
   (Spec B) so the mental model does not mislead.
8. **Root scope only in Spec A.** A crosstab inside a `NestedScope` would instantiate once per
   parent row, which needs one synthetic group per instance and multiplies the slice/pagination
   surface. `validate()` rejects it; the model still permits it structurally. Revisit in Spec C.

## 0. Prep task — make the scope-node switches exhaustive

`CrosstabNode` joins the sealed `ScopeNode` hierarchy, and the exhaustiveness of Dart's switch is
supposed to turn every site that must handle it into a compile error. **That only holds where the
code actually switches.** Today most traversal is `is`-chains, which would silently drop a crosstab
with no analyzer noise:

- `designer/controller/band_walker.dart` — real switches at :123, :236, :290; `is`-chains at
  :165, :198, :214, :258, :318, :386, :517, :533
- `data/binding_scope.dart:74`, `domain/report_validation.dart:83`,
  `designer/layout/panels/scope_field_choices.dart`
- `domain/serialization/report_definition_codec.dart` — `_encodeNode` is a real switch, but
  `_decodeNode` ends in `default: throw`, so it too compiles silently

This is the repo's own recurring failure class (five commands once dropped `name`; five
scope-rebuilders once dropped `footer`/`totals`). **Before the variant is added**, convert those
`is`-chains to exhaustive `switch` statements as a standalone, behaviour-preserving commit with the
full suite green. Only then does "the compiler shows us every site" become a true statement.

`_decodeNode`'s `default` arm stays, but is repurposed: it returns `UnknownScopeNode` (section 5)
instead of throwing.

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
    required this.expression,   // per-row group key, e.g. r'$F{region}'
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
    required this.expression,   // per-row value, e.g. r'$F{qty} * $F{price}'
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

`CrosstabNode` joins the sealed `ScopeNode` hierarchy deliberately — but that guarantee is only as
good as section 0's prep task, which converts the surviving `is`-chains into real switches first.

**API impact:** `ScopeNode` is exported, so adding a variant is a compile-time break for any
downstream exhaustive switch over it. The feature is additive for *goldens and file format*, and
semver-breaking for the *public API*. Version accordingly.

## 2. Aggregation — data to matrix

`lib/src/rendering/crosstab/crosstab_aggregator.dart`. Pure: rows in, value tree out. No layout.

```dart
class CrosstabAxisNode {
  final JetValue key;                     // typed group key — the sort key
  final String pathKey;                   // stringified key, used in cell paths / ids
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
to values, and the axis trees are built.

**Sorting keys stay typed.** The group key is kept as the evaluated `JetValue` and sorted on that;
only `pathKey` (for cell addressing and element ids) and `label` (for printing) are stringified. If
the key were stringified before sorting, `"10"` would sort before `"9"` and non-ISO dates would order
by their rendered text. `dataOrder` = first-seen, which is stable because the pass is linear over a
deterministic row order.

Consequences:

- A level with `showTotal: false` is never folded — no wasted work.
- Per-row cost is `(rowDepth + 1) x (colDepth + 1) x M` folds — with two row groups, two column
  groups and one measure that is 9, not 8. Linear in rows.
- **Cardinality risk:** a high-cardinality group binding (e.g. customer name over 20k distinct
  values) explodes the cell count. Above **50,000 populated cells** the aggregator emits one
  warning naming the offending axis and its distinct-key count. It then **proceeds** — it never
  truncates, because silently dropping data is worse than a slow report. The matrix is sparse
  (only populated intersections are stored), so a 1000 x 500 axis pair at 10% fill holds ~50k
  accumulators, not 500k.
- **The aggregator returns plain domain `Diagnostic`s**, like the planner, and the filler routes
  them into the rendering-layer sink. `DiagnosticBudget` is per-row oriented
  (`recordRowIssue(key, message)`, row-prefixed and deduped); a distinct-key cardinality total is a
  one-shot fact about the whole pass, not a row issue.
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
- **Grand-total width is reserved while packing the slice that will hold the final leaf group.** Without
  the reservation the grand total spills into a slice of its own — a continuation page containing one
  column. If it still cannot fit there (the final leaf group exactly fills the width), it does start
  its own slice, and a diagnostic says so. Accepted pathology, not silent.

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

**One synthetic group per crosstab — not per slice.** The layouter breaks on `startNewPage` only for
the *second and later* instances of a group name (`report_layouter.dart:589-591`:
`if (startNewPage && !seenStartNewPageGroup.add(name))` — `add` returns true the first time, so the
first instance does not break). A group per slice would have exactly one instance each and would
therefore **never** break, silently killing SC-004. With a single group
`GroupLevel(id: ..., name: '<ctId>#ct', key: <stub>, reprintHeaderOnEachPage: true,
startNewPage: true)`, slice 1 is the first instance (no break) and slices 2..N each break onto a new
page. The semantics fall out for free.

`GroupLevel` requires `name` and `key`. The layouter's `levelOf` / `groupByName` maps key on
**`name`**, so the unique token goes there; `key` is a group-break expression the layouter never
reads (verified: no `.key` reference in `report_layouter.dart`) and synthetic groups skip
`validate()`, so a stub is safe. The planner raises an error diagnostic if a user-authored group
already carries the synthetic name — otherwise the user's group would silently win the map.

**A closing footer is required.** An open group is popped only by a lower-level `groupHeader`, a
matching `groupFooter`, or `summary`/`noData`. Crosstab row and subtotal bands are `detail`, so
nothing would close the synthetic group — and `reEmitHeaders` would keep reprinting the crosstab's
column header on every page of any long detail run that follows. The planner therefore emits a
trailing zero-height `groupFooter` for the synthetic group as the crosstab's last band.

`startNewPage` produces the horizontal continuation page; `reprint` repeats the column header on
every page (unconditional — not author-configurable in Spec A, so it is behaviour, not a
`validate()` rule). **No vertical-pagination code is written at all** — the layouter's existing
group mechanism does it.

**Cell elements.** A value cell is
`TextElement(text: jetStringify(measure.format == null ? value : applyJetFormat(value, measure.format!)), ...)`
— `applyJetFormat` returns a `JetValue`, not a `String` (`apply_jet_format.dart:43`), and `format` is
nullable, so both steps are explicit. When the resolved box style is non-null a `ShapeElement`
rectangle is emitted behind it (a `TextElement` has no box of its own). An unstyled crosstab emits no
shapes, halving the element count.

**Alignment rules** (defaults; a style layer may override): a column-header cell is centered over its
span — the header element's width is the full span, so a multi-word header like "Q1 Sales" centers
across its three columns exactly as any wide text element does. Row labels are left-aligned and
indented; measure cells are right-aligned; total labels are left-aligned and total values
right-aligned.

**Deterministic element ids:** `'<ctId>/s<slice>/r<rowIx>/c<colIx>/m<measureId>'`. Slices are
numbered by the planner *before* pagination and are never renumbered by it, so an id is stable for a
given (data, available width) pair; it does move when the data changes the row order, exactly as a
band's content does.

**What the host hook sees:** planner-built bands carry `fields: {}` (`filled_report.dart:39-50` — the
map is populated from an originating data row, and these bands have none). So `onElementPrint` can key
conditional formatting off the element id and the resolved value, but not off row fields.

A 50-row x 10-column crosstab is roughly 500 elements (1000 when styled). The planner raises a
diagnostic above an upper bound.

## 4. Integration

### How the crosstab gets its rows

The obvious sketch — a third `emitNode` arm that reads the scope's rows, aggregates and emits — does
not work, and the reason is structural:

- `emitNode` runs **per row**. `emitDetail(row)` is called for every master row
  (`report_filler.dart:579`) and calls `emitNode(node, row)` for each child (`:520`); nested scopes
  recurse per child row (`:458-461`). An arm there would emit the whole crosstab once per row.
- There is **no row list to read**. Master rows arrive from a forward-only cursor
  (`DataSet.moveNext()` / `current`, `data_set.dart:30-33`) with no rewind. Nothing in the filler
  holds the master pool, and nothing should start to.

**The crosstab does not need rows — it needs a fold.** So it folds as the filler streams, and splices
its bands in afterwards:

1. **Register.** When the scope iteration starts, each `CrosstabNode` in `children` is registered
   with a live aggregation state and, per decision 7, classified as before-loop or after-loop. A
   before-loop crosstab **reserves its index** in the `bands` list being built.
2. **Fold.** Inside the existing master-row walk, every registered crosstab folds the current row
   (or, when `collectionField` is set, that row's child rows via `coerceCollectionRows`) into its
   accumulators. No row is retained past the iteration.
3. **Plan and splice.** When the loop ends, each crosstab runs `planCrosstab` and its bands are
   spliced into the reserved index (before-loop) or appended (after-loop). `FilledReport` is
   constructed after the loop anyway, so the splice costs nothing.

Memory grows with the number of **populated cells**, not with rows: a 1M-row report over a 3x4 axis
pair holds twelve accumulators per measure. The engine's existing eager fill remains the memory
ceiling.

The `emitNode` arm itself is a **no-op** (with a comment saying why): a crosstab is not a per-row
node. Registration and splicing live at the two scope-iteration sites.

`availableWidth` is `def.page.width - def.page.margins.left - def.page.margins.right`.

A crosstab whose `visible` `BoolProperty` resolves false is skipped at registration — no fold, no
plan, no bands, no synthetic group. It is evaluated **without a row** (`row: null`): params and
report variables only, since a crosstab prints outside the row loop. A `$F{}` reference in a
crosstab's `visible` expression is therefore a `validate()` warning.

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
| `scope_commands.dart`, `api/groups_scopes.dart`, `api/bands.dart`, `scope_field_choices.dart`, `binding_scope.dart`, `default_definition.dart` | Arms that ignore or appropriately handle a crosstab |
| `migrations/v1_to_v2.dart` | Unreachable arm — v1 has no crosstab |

`report_definition.dart` needs **no change**: `isPureSingleDetailBody` already returns false when a
crosstab is present (`:191-199` — either `children.length != 1`, or the single child is not a
`BandNode`). It is not a compile-error site either, so it becomes a regression test rather than an
edit.

Painter, PDF exporter, printer, preview, `onElementPrint` and watermark are unchanged: the output is
ordinary text and shape primitives.

## 5. Serialization and validation

**Codec.** A third `kind` value on the scope-node discriminated union: `'crosstab'`. The crosstab
sub-objects get `toJson` / `fromJson` that **omit defaults**, so crosstab-free reports stay
byte-identical. The pattern to copy is `ReportVariable.toJson` and the codec's own
`_encodeGroup` / `_encodeBand` — *not* `ColumnLayout.toJson`, which writes all four fields
unconditionally (`column_layout.dart:57-62`).

**Schema version stays 2** (as with chart, barcode and watermark). But there is a gap: an unknown
*element* type is preserved losslessly via `UnknownElement`, while an unknown scope-node `kind`
throws `ReportFormatException` — so an older build could not open a crosstab report at all.

Spec A therefore adds **`UnknownScopeNode`**: it keeps the raw JSON, is skipped during render, and is
written back verbatim on save. It is `UnknownElement`'s sibling, consistent with Constitution V
(lossless round-trip).

**What this does and does not buy.** It ships *in* Spec A, so no already-released build gains it —
every existing build still throws `ReportFormatException` on `kind: 'crosstab'`
(`report_definition_codec.dart:287`). The payoff is forward compatibility **starting here**: from
this version on, an unknown scope-node type round-trips instead of failing the whole file.

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
| The crosstab sits in a `NestedScope` (decision 8 — root scope only in Spec A) | error |
| A `visible` expression references `$F{}` (a crosstab is evaluated without a row) | warning |

Dropped from an earlier draft: "a crosstab and a `columnLayout` label grid coexist" — unreachable.
The label grid requires `isPureSingleDetailBody`, which a crosstab already falsifies, so
`soleDetailBand` is null and the branch cannot engage. It becomes a regression test instead.

The width rule is a quiet win of this architecture: because the crosstab's geometry derives entirely
from author-time numbers, "this crosstab will not fit the page" is answerable **without looking at
the data**. The only data-driven unknown is the column *count*, which horizontal slicing already
handles.

## 6. Testing and file map

| Layer | Test kind | What it proves |
|---|---|---|
| `crosstab_aggregator` | Pure unit + `CrosstabMatrix` data golden | Prefix-fold subtotals; `average` correct at every level; empty intersection has no key; `showTotal: false` is not folded; typed-key sorting (`"9"` before `"10"`, dates chronological, `dataOrder` first-seen); cardinality warning fires and the pass still completes |
| `crosstab_planner` | Pure unit + band-plan snapshot | A slice never splits a leaf group; grand-total width reserved in the final slice; header span widths and centering; indentation; deterministic element ids; a trailing zero-height footer closes the synthetic group; no shapes when unstyled |
| Codec | Round-trip + losslessness | Crosstab round-trips; `UnknownScopeNode` is written back verbatim; **crosstab-free reports are byte-identical** |
| `validate()` | One test per rule | All nine rules |
| Filler | Fill snapshot golden | Position rule (before / after the row loop; crosstab-only body; mid-list crosstab); the before-loop splice lands at the reserved index; folding never retains rows; `collectionField` flattening; `visible: false` skips the fold entirely; synthetic groups reach `FilledReport` |
| Layouter | Pagination tests | Column header repeats on every page of a multi-page crosstab; slice 2 starts a new page (the single-group fix — a per-slice group would silently never break); the closing footer stops the reprint, proven by a long detail run *after* the crosstab; synthetic groups raise no spurious info diagnostic; a user group colliding with the synthetic name is rejected |
| Render | PNG golden via the playground demo | WYSIWYG: canvas, preview and PDF agree |
| Prep task (section 0) | Full sweep, no behaviour change | The `is`-chain to `switch` conversion is a pure refactor — the suite is green before the variant is added |
| **Regression** | Full sweep | Whole suite green; `isPureSingleDetailBody` still false with a crosstab, and the label grid still cannot engage; **zero golden changes for crosstab-free reports** |

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
(`syntheticGroups`), `report_layouter.dart` (group-table union + diagnostic exemption), plus the
designer files in the sealed-switch fallout (minimum behaviour in Spec A). The section 0 prep task
touches the same traversal files ahead of all of this.

The barrel exports `Crosstab` and its sub-types, so `public_api_test` is updated.

## Acceptance criteria

- **SC-001** A crosstab authored in JSON renders identically on canvas, in preview and in PDF export.
- **SC-002** Subtotals are correct at every level for all seven folding calculations
  (`sum, count, average, min, max, first, last` — `JetCalculation` also has `none`, which
  `validate()` rejects for a measure), `average` included.
- **SC-003** A crosstab longer than one page repeats its column header on every page.
- **SC-004** A crosstab wider than the page continues on further pages, with the row-label columns
  repeated and the grand-total column appearing only in the last slice.
- **SC-005** An empty intersection prints an empty cell, not a zero.
- **SC-006** No existing golden changes; the full suite stays green.
- **SC-007** An unknown scope-node `kind` round-trips byte-for-byte through `UnknownScopeNode`
  instead of throwing. (This protects builds from this version on; already-released builds still
  reject a crosstab file.)
- **SC-008** Filling a 1M-row report containing a crosstab retains no rows: memory grows with
  populated cells, not with rows.

## Out of scope (Spec A)

Designer authoring (Spec B). "Across-first" slice order, fit/scale column mode, derived measures,
per-cell band templates, crosstabs inside a `NestedScope` (Spec C). Vertical cell merging — the
chosen layout puts hierarchical row labels on their own rows, so it is not needed. Async /
streaming fill; the engine fills eagerly, as today.

**Text does not grow or shrink in a crosstab.** Rows are the fixed `rowHeight` and cells the fixed
column width, so a long row label or a wide value clips rather than wrapping or stretching. The
band-measurer's grow-only sizing is not applied to planner-built bands in Spec A. This is a known
v1 limitation, not a bug.
