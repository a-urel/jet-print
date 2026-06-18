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
- Q: Is there a dedicated band type for columns? → A: **No new `BandType`.** The
  existing `detail` band *is* the label template; columns only change where each
  instance is placed.
- Q: Where does the grid config live — report-level or band-level? → A:
  **Band-level.** `ColumnLayout` is an optional property of `Band`, carried by the
  detail band that serves as the label template. `columnWidth` is, in effect, that
  band's render width. (Considered report-level per the JasperReports precedent,
  but band-level was chosen to co-locate the grid with the band it lays out.)
- Q: Do we use the reserved `columnHeader` / `columnFooter` bands? → A: **No.**
  No use case for per-column chrome in label sheets. They stay reserved and
  ignored exactly as today.
- Q: Print order — horizontal, vertical, or both? → A: **Horizontal only**
  (left-to-right, wrap down) for v1. The field is omitted rather than added
  speculatively; a future newspaper-flow spec can introduce vertical order.
- Q: Label/cell height? → A: The **`detail` band's designed height** is the cell
  height. Cells are uniform. Content exceeding the cell is **clipped** with a
  diagnostic (labels are fixed-size by nature; per-cell growth is not meaningful).
- Q: How do `title` / `summary` / `noData` once-bands interact with the grid? →
  A: v1 supports only a **pure single-detail body** (root scope: no groups, no
  `footer`, exactly one `BandNode` label template, no once-bands). Any once-band,
  group, or nested scope present alongside a `ColumnLayout` triggers the
  documented **linear fallback** (warning). Real label sheets have none of these.
  `pageHeader` / `pageFooter` furniture is orthogonal and always composes with the
  grid (it is laid out independently of the filled band stream).

## Scope

**In scope**

- A new immutable value type `ColumnLayout { columnCount, columnWidth,
  columnSpacing, rowSpacing }`, attached as an optional `columnLayout` property on
  `Band` (null ⇒ today's single-column behavior). The grid activates when the lone
  detail band of a **pure single-detail body** carries a non-null `columnLayout`;
  that combination is the gate.
- A dedicated **grid-placement path** in `ReportLayouter`, taken only when the gate
  holds, that places each `detail` instance into a uniform grid cell in horizontal
  print order and breaks the page when the grid fills.
- Full-page-width placement of page **furniture** (`pageHeader`, `pageFooter`,
  `background`) via the existing, unchanged layout path; only the body region
  between page header and footer becomes the grid.
- Exact up-front page count (`ceil(detailCount / cellsPerPage)`), preserving the
  existing `LazyLayout` contract (page count known, frames built on demand).
- `validate()` rules for the grid (dimensions, fit, degenerate cases, unsupported
  body shapes, `columnLayout` on a non-detail band, element overflow).
- JSON `toJson` / `fromJson` for `ColumnLayout`; `Band` serializes `columnLayout`
  only when non-null (absent key ⇒ single column).
- Unit, golden, and round-trip test coverage.

**Out of scope**

- Designer authoring UI (properties panel for the grid) — follow-up spec.
- Vertical / newspaper print order.
- Per-column headers/footers (`columnHeader` / `columnFooter` remain reserved).
- Columnar layout of groups, nested `DetailScope`s, or `title` / `summary` /
  `noData` once-bands — any non-pure-single-detail body falls back to linear
  (see FR-009).
- Per-cell band growth / overflow reflow — cells are fixed height, overflow clips.
- Column balancing (equalizing column lengths on the last page).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Render a label sheet (P1)

An author sets `columnLayout: ColumnLayout(columnCount: 3, columnWidth: 180,
columnSpacing: 12, rowSpacing: 8)` on the single `detail` band (80 pt tall) of a
report with 30 data rows. The output is a multi-page sheet: each page holds a
3-column grid of 80 pt cells filled left-to-right then top-to-bottom; the last
page holds the partial remainder. Each cell renders one data row's label.

### User Story 2 - Existing single-column reports are unaffected (P1)

A report whose detail band has `columnLayout == null` (every report authored
before this feature) renders exactly as today, through the unchanged linear path,
and its golden output is byte-identical.

### User Story 3 - Grid that overflows the page is rejected (P2)

A `ColumnLayout` whose columns plus spacing exceed the page body width, or whose
label height exceeds the body height (zero rows fit), produces a validation
**error** with a clear message and does not render a broken/empty sheet.

### User Story 4 - Page chrome coexists with the grid (P2)

A label report that also defines a `pageHeader` (e.g. a sheet title) and
`pageFooter` (page number) renders the header and footer at **full page width**,
with the label grid occupying the body region between them, paginating correctly.

### User Story 5 - Oversized label content is flagged (P3)

A `detail` element positioned or sized past the band's `columnWidth` renders
clipped to the cell and produces a validation **warning**
(`element overflows cell width`).

### User Story 6 - Unsupported body shape falls back (P3)

A report whose detail band carries a `columnLayout` but whose body is not a pure
single-detail flow (it has groups, a nested `DetailScope`, additional per-row
bands, or `title` / `summary` / `noData` once-bands) produces a validation
**warning** (`column layout ignored`) and renders via the linear path rather than
mislaying content. A `columnLayout` set on a **non-detail** band produces a
warning and is ignored.

## Requirements *(mandatory)*

### Functional

- **FR-001**: A new immutable value type `ColumnLayout` MUST hold `columnCount`
  (int), `columnWidth`, `columnSpacing`, and `rowSpacing` (doubles, points), with
  value equality. `Band` MUST carry an optional `columnLayout` property; `null`
  (the default on every band) MUST preserve current single-column layout exactly.
  The grid activates only when the lone detail band of a **pure single-detail
  body** carries a non-null `columnLayout`.
- **FR-002**: When the gate holds, `ReportLayouter` MUST place each `detail`
  instance into a uniform grid cell. For the *k*-th instance on a page (0-based):
  `row = k ÷ columnCount`, `col = k % columnCount`,
  `x = bodyLeft + col·(columnWidth + columnSpacing)`,
  `y = bodyTop + row·(labelHeight + rowSpacing)`, where `labelHeight` is the
  detail band's **designed** height (the fixed row pitch) and `bodyTop` /
  `bodyLeft` are the body region origin (after page header / margins). The
  measured band's elements are emitted at the cell origin; content exceeding the
  cell clips (cells are uniform — FR-003 does not advance by measured height).
- **FR-003**: `rowsPerPage` MUST be `floor((bodyCapacity + rowSpacing) /
  (labelHeight + rowSpacing))` (clamped to ≥ 1) and
  `cellsPerPage = rowsPerPage × columnCount`. When a page accumulates
  `cellsPerPage` instances, the layouter MUST start a new page (re-emitting
  `pageHeader` / `pageFooter` full-width via the existing path) and reset the cell
  index.
- **FR-004**: Print order MUST be **horizontal** (left-to-right within a row, then
  wrap to the next row down). No vertical-order option is introduced.
- **FR-005**: Page **furniture** — `pageHeader`, `pageFooter`, `background` — MUST
  be placed full page width by the existing layout path, unchanged by the grid;
  the grid occupies only the body region between `pageHeader` and `pageFooter`.
  (Furniture is laid out independently of the filled band stream, so it composes
  with the grid for free.)
- **FR-006**: The layouter MUST resolve exact total page count
  (`ceil(detailCount / cellsPerPage)`) during the boundary pass and preserve the
  existing `LazyLayout` contract (`pageCount` known immediately; `PageFrame`s
  built on demand).
- **FR-007**: `validate()` MUST emit an **error** for a detail-band
  `columnLayout` with: `columnCount < 1`; `columnWidth ≤ 0`, `columnSpacing < 0`,
  or `rowSpacing < 0`;
  `columnCount·columnWidth + (columnCount−1)·columnSpacing > bodyWidth` (grid
  wider than the body); and `labelHeight > bodyCapacity` (i.e. `rowsPerPage == 0`),
  where `bodyWidth = page.width − margins.left − margins.right` and `bodyCapacity =
  page.height − margins.top − margins.bottom − pageHeader.height − pageFooter.height`.
  An errored `columnLayout` MUST block rendering with a clear diagnostic.
- **FR-008**: `validate()` MUST emit a **warning** when a detail-band element's
  bounds extend past `columnWidth`; such content renders clipped to the cell.
- **FR-009**: The grid path applies only to a **pure single-detail body** — a root
  scope with no groups, no `footer`, exactly one `BandNode` child (the label
  template), and no `title` / `summary` / `noData` once-bands. When a detail band's
  `columnLayout != null` but the body is any other shape, `validate()` MUST emit a
  **warning** (`column layout ignored`) and the engine MUST render via the
  unchanged linear path. A `columnLayout` on a **non-detail** band MUST produce a
  warning and be ignored. The layouter MUST gate on the same condition so the
  diagnostic and the rendered output agree.
- **FR-010**: `ColumnLayout` MUST round-trip through JSON (`toJson` / `fromJson`).
  `Band` MUST serialize the `columnLayout` key only when non-null, so every
  existing report JSON round-trips byte-identically and existing goldens are
  unchanged.

### Key Entities

- **ColumnLayout** *(new, domain)* — geometry describing a uniform label grid:
  `columnCount`, `columnWidth`, `columnSpacing`, `rowSpacing`. An optional property
  of `Band`; consumed by the layouter and validator. Not a band, not a container.
- **Pure single-detail body** *(predicate, domain)* — the gate: a root scope with
  no groups, no `footer`, no once-bands (`title` / `summary` / `noData`), and
  exactly one `BandNode` child. Shared by the validator (to emit the fallback
  warning) and the layouter (to branch onto the grid path) so they always agree.
- **Grid-placement path** *(new, layout)* — the layouter routine taken when the
  gate holds: arithmetic cell placement of `detail` instances in horizontal order
  with count-driven page breaks. Sibling to the existing linear pagination path.
- **`detail` band** *(existing)* — the label template; its measured height is the
  cell height and its `columnLayout.columnWidth` is its effective render width.
  Structurally unchanged apart from the new optional property.

## Success Criteria *(mandatory)*

- **SC-001**: A 3-column, 30-row label fixture renders to a stable golden whose
  cell origins match the FR-002 arithmetic and whose page count matches FR-006.
- **SC-002**: An existing single-column golden re-runs **byte-identical** with the
  feature present (proving a null `columnLayout` gate is invisible).
- **SC-003**: Each `validate()` rule in FR-007 / FR-008 / FR-009 is exercised by a
  fixture asserting the exact severity and message; an errored grid does not render.
- **SC-004**: Grid arithmetic (`rowsPerPage`, `cellsPerPage`, row→(page, cell)
  mapping including the partial last page) is unit-tested across representative
  configs (3-col, 2-col, 1-col degenerate) without rendering.
- **SC-005**: `ColumnLayout` and a `Band` carrying one survive a JSON round-trip
  as value-equal; a band without one omits the key.
- **SC-006**: The full suite (jet_print + playground) is green; no existing golden
  changes.
