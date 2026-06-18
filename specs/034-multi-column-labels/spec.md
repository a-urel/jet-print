# Feature Specification: Multi-Column Label Sheets

**Feature Branch**: `034-multi-column-labels`
**Created**: 2026-06-18
**Status**: Draft
**Input**: The engine lays out bands in a single column down the page. There is no
way to produce a label sheet (Avery-style: a fixed grid of identical cells, one
data row per cell) or any multi-column output. The domain already *reserves* the
shape for this — `BandType.columnHeader` / `columnFooter` exist and
`PageFurniture` carries unused `columnHeader` / `columnFooter` slots flagged
"not laid out" — but the layouter is purely linear. Add built-in multi-column
support, scoped to the **label-sheet** use case: a `detail` band repeated across
a uniform grid, filled in horizontal (left-to-right, then wrap down) print order.

## Problem

A `detail` band today stacks vertically: instance *n* lands at
`(bodyLeft, cursorY)`, the cursor advances by the band's height, and the page
breaks when the next band overflows the body region. This produces one column.

To print mailing labels or cards, an author needs the *same* `detail` band
repeated across a fixed grid of cells — e.g. 3 columns × 10 rows on an A4 sheet —
where each cell holds one data row and cells fill left-to-right then top-to-bottom
to match how label stock is consumed. The engine has no notion of columns: no
geometry to describe the grid, no placement path to fill it, and no validation
that a grid fits the page.

The architecture is well-suited to adding this: filling (data → flat band
stream) is already independent of layout (band stream → placed bands → pages).
A label grid changes **only** the (x, y) the layouter assigns to each `detail`
instance and **when** it breaks the page. Filling, band measurement, and element
rendering are untouched.

## Clarifications

### Session 2026-06-18

- Q: Which use case drives this — label sheets, newspaper flow, or a general
  page-column feature? → A: **Label sheets.** Fixed grid, one `detail` instance
  per cell, horizontal print order. No groups or aggregates inside the columnar
  flow for v1.
- Q: How does the author specify the grid? → A: **Column count + explicit column
  width + horizontal column spacing + vertical row spacing** (the JasperReports
  model). The engine validates the grid fits the page body.
- Q: Engine-only or also designer UI? → A: **Engine + serialization first**;
  designer authoring UI is deferred to a follow-up spec. This spec leaves a clean
  seam (a serializable config field) for it.
- Q: Is there a dedicated band type for columns? → A: **No.** `ColumnLayout` is
  page-flow geometry, not structure. The existing `detail` band *is* the label
  template; columns only change where each instance is placed. No new `BandType`.
- Q: Do we use the reserved `columnHeader` / `columnFooter` bands? → A: **No.**
  No use case for per-column chrome in label sheets. They stay reserved and
  ignored exactly as today.
- Q: Print order — horizontal, vertical, or both? → A: **Horizontal only**
  (left-to-right, wrap down) for v1. The field is omitted rather than added
  speculatively; a future newspaper-flow spec can introduce vertical order.
- Q: Label/cell height? → A: The **`detail` band's designed height** is the cell
  height. Cells are uniform. Content exceeding the cell is **clipped** with a
  diagnostic (labels are fixed-size by nature; per-cell growth is not meaningful).

## Scope

**In scope**

- A new immutable value type `ColumnLayout { columnCount, columnWidth,
  columnSpacing, rowSpacing }`, attached as an optional field on
  `ReportDefinition` (null ⇒ today's single-column behavior; this is the gate).
- A dedicated **grid-placement path** in `ReportLayouter`, taken only when
  `columnLayout != null`, that places each `detail` instance into a uniform grid
  cell in horizontal print order and breaks the page when the grid fills.
- Full-page-width placement of page chrome (`title`, `pageHeader`, `pageFooter`,
  `summary`, `background`) via the existing, unchanged layout path; only the body
  region between header and footer becomes the grid.
- Exact up-front page count (`ceil(detailCount / cellsPerPage)`), preserving the
  existing `LazyLayout` contract (page count known, frames built on demand).
- `validate()` rules for the grid (dimensions, fit, degenerate cases, unsupported
  body shapes, element overflow).
- JSON `toJson` / `fromJson` for `ColumnLayout`; `ReportDefinition` serializes
  `columnLayout` only when non-null (absent key ⇒ single column).
- Unit, golden, and round-trip test coverage.

**Out of scope**

- Designer authoring UI (properties panel for the grid) — follow-up spec.
- Vertical / newspaper print order.
- Per-column headers/footers (`columnHeader` / `columnFooter` remain reserved).
- Columnar layout of groups or nested `DetailScope`s — flagged and falls back to
  linear (see FR-009).
- Per-cell band growth / overflow reflow — cells are fixed height, overflow clips.
- Column balancing (equalizing column lengths on the last page).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Render a label sheet (P1)

An author sets `ColumnLayout(columnCount: 3, columnWidth: 180, columnSpacing: 12,
rowSpacing: 8)` on a report whose body is a single `detail` band 80 pt tall, with
30 data rows. The output is a multi-page sheet: each page holds a 3-column grid
of 80 pt cells filled left-to-right then top-to-bottom; the last page holds the
partial remainder. Each cell renders one data row's label.

### User Story 2 - Existing single-column reports are unaffected (P1)

A report with `columnLayout == null` (every report authored before this feature)
renders exactly as today, through the unchanged linear path, and its golden output
is byte-identical.

### User Story 3 - Grid that overflows the page is rejected (P2)

A `ColumnLayout` whose columns plus spacing exceed the page body width, or whose
label height exceeds the body height (zero rows fit), produces a validation
**error** with a clear message and does not render a broken/empty sheet.

### User Story 4 - Page chrome coexists with the grid (P2)

A label report that also defines a `pageHeader` (e.g. a sheet title) and
`pageFooter` (page number) renders the header and footer at **full page width**,
with the label grid occupying the body region between them, paginating correctly.

### User Story 5 - Oversized label content is flagged (P3)

A `detail` element positioned or sized past `columnWidth` renders clipped to the
cell and produces a validation **warning** (`element overflows cell width`).

### User Story 6 - Unsupported body shape falls back (P3)

A report that defines a `ColumnLayout` but whose body also contains groups or a
nested `DetailScope` produces a validation **warning** (`column layout ignored`)
and renders via the linear path rather than mislaying grouped content.

## Requirements *(mandatory)*

### Functional

- **FR-001**: A new immutable value type `ColumnLayout` MUST hold `columnCount`
  (int), `columnWidth`, `columnSpacing`, and `rowSpacing` (doubles, points), with
  value equality. `ReportDefinition` MUST carry an optional `columnLayout`;
  `null` MUST preserve current single-column layout exactly.
- **FR-002**: When `columnLayout != null` and the body is a flat `detail` flow,
  `ReportLayouter` MUST place each `detail` instance into a uniform grid cell.
  For the *k*-th instance on a page (0-based): `row = k ÷ columnCount`,
  `col = k % columnCount`, `x = bodyLeft + col·(columnWidth + columnSpacing)`,
  `y = bodyTop + row·(labelHeight + rowSpacing)`, where `labelHeight` is the
  `detail` band's designed height and `bodyTop` / `bodyLeft` are the body region
  origin (after page header / margins).
- **FR-003**: `rowsPerPage` MUST be `floor((bodyHeight + rowSpacing) /
  (labelHeight + rowSpacing))` and `cellsPerPage = rowsPerPage × columnCount`.
  When a page accumulates `cellsPerPage` instances, the layouter MUST start a new
  page (re-emitting `pageHeader` / `pageFooter` full-width via the existing path)
  and reset the cell index.
- **FR-004**: Print order MUST be **horizontal** (left-to-right within a row, then
  wrap to the next row down). No vertical-order option is introduced.
- **FR-005**: `title`, `pageHeader`, `pageFooter`, `summary`, and `background`
  MUST be placed at full page width by the existing layout path, unchanged by
  `ColumnLayout`; only the body region between header and footer is gridded.
- **FR-006**: The layouter MUST compute exact total page count up front as
  `ceil(detailCount / cellsPerPage)` and preserve the existing `LazyLayout`
  contract (page count known immediately; `PageFrame`s built on demand).
- **FR-007**: `validate()` MUST emit an **error** for: `columnCount < 1`;
  `columnWidth ≤ 0`, `columnSpacing < 0`, or `rowSpacing < 0`;
  `columnCount·columnWidth + (columnCount−1)·columnSpacing > bodyWidth` (grid
  wider than the body); and `labelHeight > bodyHeight` (i.e. `rowsPerPage == 0`).
  An errored `ColumnLayout` MUST block rendering with a clear diagnostic.
- **FR-008**: `validate()` MUST emit a **warning** when a `detail` element's
  bounds extend past `columnWidth`; such content renders clipped to the cell.
- **FR-009**: When `columnLayout != null` but the body contains groups or a nested
  `DetailScope`, `validate()` MUST emit a **warning** (`column layout ignored`)
  and the engine MUST render via the linear path (no broken columnar grouping).
- **FR-010**: `ColumnLayout` MUST round-trip through JSON (`toJson` / `fromJson`).
  `ReportDefinition` MUST serialize the `columnLayout` key only when non-null, so
  every existing report JSON round-trips byte-identically and existing goldens are
  unchanged.

### Key Entities

- **ColumnLayout** *(new, domain)* — page-flow geometry describing a uniform label
  grid: `columnCount`, `columnWidth`, `columnSpacing`, `rowSpacing`. Orthogonal to
  `Band` / `BandType`; consumed only by the layouter. Not a band, not a container.
- **Grid-placement path** *(new, layout)* — the layouter routine taken when
  `columnLayout != null`: arithmetic cell placement of `detail` instances in
  horizontal order with count-driven page breaks. Sibling to the existing linear
  pagination path; selected by config presence.
- **`detail` band** *(existing)* — under `ColumnLayout`, the band *is* the label
  template; its designed height is the cell height and `columnWidth` is its
  effective render width. Unchanged structurally.

## Success Criteria *(mandatory)*

- **SC-001**: A 3-column, 30-row label fixture renders to a stable golden whose
  cell origins match the FR-002 arithmetic and whose page count matches FR-006.
- **SC-002**: An existing single-column golden re-runs **byte-identical** with the
  feature present (proving the `columnLayout == null` gate is invisible).
- **SC-003**: Each `validate()` rule in FR-007 / FR-008 / FR-009 is exercised by a
  fixture asserting the exact severity and message; an errored grid does not render.
- **SC-004**: Grid arithmetic (`rowsPerPage`, `cellsPerPage`, row→(page, cell)
  mapping including the partial last page) is unit-tested across representative
  configs (3-col, 2-col, 1-col degenerate) without rendering.
- **SC-005**: `ColumnLayout` and a `ReportDefinition` carrying one survive a
  JSON round-trip as value-equal; a definition without one omits the key.
- **SC-006**: The full suite (jet_print + playground) is green; no existing golden
  changes.
