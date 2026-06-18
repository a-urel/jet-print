# Feature Specification: Multi-Column Label Sheets — Designer UI

**Feature Branch**: `035-multi-column-designer`
**Created**: 2026-06-18
**Status**: Draft
**Input**: Engine spec 034 added a band-level `ColumnLayout {columnCount,
columnWidth, columnSpacing, rowSpacing}` on the detail `Band` and the
grid-placement render path, but left authoring to a follow-up. Today the only
way to set a `columnLayout` is to hand-edit JSON. This feature adds the
designer affordances to author/edit/remove the column layout, with live
validation feedback and a canvas cue — no engine changes.

## Problem

Spec 034 shipped the engine slice for multi-column label sheets: domain type
(`ColumnLayout`, `Band.columnLayout`), additive serialization, the
`isPureSingleDetailBody` activation gate, the grid-placement branch in
`ReportLayouter`, and a complete set of `validate()` column diagnostics. None of
it is reachable from the interactive designer:

1. **No authoring affordance.** A detail band's `columnLayout` can only be set
   by editing serialized JSON. The Properties panel edits band height (and, for
   group headers, group flags) but has no column-layout editor.
2. **Validation is computed but never shown.** `validate()` already emits every
   column diagnostic (grid wider than body, label taller than the page body,
   per-element cell-width overflow, `columnCount < 1`, non-positive dimensions,
   and the "ignored — applies only to the lone detail band" fallback warning),
   and the controller exposes `controller.diagnostics`, but **no designer UI
   surfaces it**. An author gets no feedback that a layout is invalid or
   inactive.
3. **The canvas gives no cue.** The canvas draws every band once at full body
   width. With a column layout active, the author has no visual indication of
   the cell width they are designing into or that the band repeats across a
   grid.

The engine, serialization, and validation logic are all in place. This feature
is **designer-only**: an editor, validation surfacing, and a canvas cue.

## Clarifications

### Session 2026-06-18

- Q: How far should the canvas go in visualizing the grid? → A: **Width hint +
  ghost columns.** Constrain the detail band's editable frame to `columnWidth`
  (design one true-size cell) and draw faint, read-only ghost outlines for the
  remaining columns. Not a full live grid (that stays the engine's job via
  preview/print), not panel-only.
- Q: How should the designer treat the engine's `isPureSingleDetailBody`
  activation gate? → A: **Disable the affordance when ineligible.** Only offer
  "Add column layout" when the body already satisfies the gate; otherwise
  disable the control with an explanatory tooltip. Exception: a layout that
  already exists on a now-ineligible body stays visible/editable/removable (we
  never trap orphaned config) and is marked inactive.
- Q: Reuse `validate()` or re-derive grid math in the UI? → A: **Reuse
  `validate()`.** The section reads `controller.diagnostics` filtered to the
  active band; the UI never re-implements the grid arithmetic.
- Q: Default values when enabling? → A: `columnCount: 2`, `columnSpacing: 0`,
  `rowSpacing: 0`, `columnWidth: bodyWidth / 2` (grid exactly fills the body →
  passes validation immediately).

## Scope

**In scope**

- A **"Column Layout" section** in the Properties panel band inspector, shown
  only for `BandType.detail`, after the Size (height) field, with three render
  states: eligible-no-layout (Add button), layout-present (four number fields +
  Remove), ineligible (Add disabled with tooltip).
- Two designer **commands** and controller methods: `setColumnLayout(bandId,
  ColumnLayout)` and `removeColumnLayout(bandId)`, on the existing
  `EditCommand` + `_commit` + undo/redo pipeline.
- **Validation feedback** in the section: surface `controller.diagnostics`
  filtered to the active band (band-level + per-element cell-overflow), plus an
  **inactive notice** when a layout exists on an ineligible body.
- **Localization** of every column-section string (section/field labels, Add
  tooltip, inactive notice, **and** the diagnostic rows) via new keys in the
  three `.arb` files (`en`/`de`/`tr`) and generated `JetPrintLocalizations`. The
  diagnostic rows are designer-generated friendly messages, not the engine's raw
  strings (see FR-008/FR-010).
- A **canvas cue**: when a layout is active (`columnLayout != null &&
  isPureSingleDetailBody`), draw the editable band frame at `columnWidth` and
  `columnCount − 1` faint read-only ghost cells at the real pitch.

**Out of scope**

- Any engine, serialization, or `validate()` change. The grid math, the gate
  predicate, and the diagnostic set are reused exactly as spec 034 shipped them.
- Editing *through* ghost cells, per-cell content variation, or rendering the
  full paginated grid on the canvas (preview/print already do this faithfully).
- A global diagnostics panel. Diagnostic surfacing here is scoped to the Column
  Layout section only.
- `columnHeader`/`columnFooter` bands (reserved, no use case — unchanged from
  034).
- Designer affordances for converting a mixed report into a label sheet
  (stripping disqualifying bands). The gate only disables the Add control; it
  offers no auto-fix.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Author a label sheet (P1)

An author with a pure single-detail-body report selects the detail band. The
Properties panel shows a **Column Layout** section with an **Add column layout**
button. Clicking it creates a 2-column layout (`columnWidth = bodyWidth / 2`,
zero spacing) and reveals four numeric fields (Columns, Column width, Column
spacing, Row spacing). The canvas immediately constrains the band to the cell
width and shows one ghost column to the right. Editing any field and blurring
commits the change; preview/print renders the real grid.

### User Story 2 - Gate disables the affordance (P1)

In a report that is **not** a pure single-detail body (e.g. it has a title band
or a group), the author selects a detail band. The **Add column layout** button
is **disabled** with a tooltip: *"Requires a single detail band with no title,
summary, groups, or footer."* No column layout can be created in this shape.

### User Story 3 - Invalid grid shows an error (P1)

With a layout active, the author sets Column width so the grid
(`columnCount · columnWidth + (columnCount − 1) · columnSpacing`) exceeds the
page body width. The section shows an inline **error** row — a friendly,
localized message ("the columns don't fit the page width — reduce the column
count or width"), no raw float. The value remains as typed (author fixes it);
the engine still renders via its clamp/fallback, but the author sees the problem
at author time. (Changing the column **count** instead refits the width to fit,
so this error arises only from a direct width edit.)

### User Story 4 - Remove restores a plain band (P2)

The author clicks **Remove** in the Column Layout section. The `columnLayout` is
cleared; the band's `id`, `type`, `height`, and all `elements` are preserved.
The canvas returns to full-width single-column drawing.

### User Story 5 - Orphaned layout stays fixable (P2)

A report that once satisfied the gate gains a group band, making it ineligible
while the detail band still carries a `columnLayout`. The author selects the
band: the four fields and **Remove** are still shown (not hidden), and an
**inactive notice** explains *"Column layout is inactive: the report isn't a
single detail band."* The author can edit or remove it; the Add button (for a
band with no layout) would be disabled in this shape.

### User Story 6 - Cell overflow warning (P2)

Elements positioned so `bounds.x + bounds.width > columnWidth` produce a
**single** friendly, localized **warning** row carrying the count ("N elements
extend past the column and will be clipped"), and visually cross the editable
cell boundary on the canvas.

## Requirements *(mandatory)*

### Functional

- **FR-001**: The Properties band inspector MUST render a **Column Layout**
  section for `BandType.detail` bands only, positioned after the existing Size
  (height) field.
- **FR-002**: When the band has no `columnLayout` and the body **is** a pure
  single-detail body (`ReportDefinition.isPureSingleDetailBody`), the section
  MUST show an enabled **Add column layout** action that commits a default
  layout: `columnCount = 2`, `columnSpacing = 0`, `rowSpacing = 0`,
  `columnWidth = (page.width − margins.left − margins.right) / 2`.
- **FR-003**: When the band has no `columnLayout` and the body is **not** a pure
  single-detail body, the **Add column layout** action MUST be **disabled** with
  a tooltip explaining the requirement (single detail band; no title, summary,
  groups, or footer).
- **FR-004**: When the band has a `columnLayout`, the section MUST show four
  commit-on-blur numeric fields — Columns (`columnCount`, integer, rounded from
  the field value), Column width (`columnWidth`), Column spacing
  (`columnSpacing`), Row spacing (`rowSpacing`) — each committing via
  `setColumnLayout`, **regardless of body eligibility** (so an orphaned layout
  stays editable). Changing the **Columns** field MUST **refit** `columnWidth`
  to fill the page body evenly (`(bodyWidth − (count−1)·columnSpacing) / count`,
  guarded for `count ≥ 1`), so adding a column never overflows the page; the
  Column width field commits literally (a width set directly may overflow and
  surfaces as an FR-008 error). *(Refit added 2026-06-18 per user feedback.)*
- **FR-005**: When the band has a `columnLayout`, the section MUST show a
  **Remove** action that clears it via `removeColumnLayout(bandId)`.
- **FR-006**: `removeColumnLayout` MUST clear **only** `columnLayout`, preserving
  the band's `id`, `type`, `height`, and `elements`. (Because
  `Band.copyWith(columnLayout:)` uses `?? this.columnLayout` and cannot null the
  field, removal MUST rebuild the `Band` via its constructor, explicitly
  carrying all other fields — guarding against the spec-031 silent-drop class of
  bug.)
- **FR-007**: `setColumnLayout` and `removeColumnLayout` MUST go through the
  existing `EditCommand` + `_commit` pipeline (undo/redo, listener
  notification), as new commands `SetColumnLayoutCommand` and
  `RemoveColumnLayoutCommand`. Both MUST no-op safely when the band id is not
  found.
- **FR-008** *(revised 2026-06-18 — see FR-010)*: When the layout is active, the
  section MUST surface **friendly, localized** column diagnostics derived from
  the same geometry the engine validates — its checks and the
  `bodyWidth`/`bodyCapacity` formulas MUST mirror `_validateColumns` exactly so
  the two cannot disagree — but presented in plain language and **de-duplicated**:
  the per-element cell-overflow case MUST collapse into a **single** row carrying
  the count (not one row per element). Errors MUST render in the destructive
  inline style; warnings in the warning inline style. The section MUST NOT
  surface the engine's raw `validate()` strings.
- **FR-009**: When a `columnLayout` exists but the body is **not** a pure
  single-detail body, the section MUST show an **inactive notice** distinct from
  the field-validation rows, explaining the layout will not render as a grid.
- **FR-010** *(revised 2026-06-18)*: **All** column-section strings — the section
  label, field labels, the Add tooltip, the inactive notice, AND the column
  diagnostic rows (FR-008) — MUST be localized via new keys in the `en`, `de`,
  and `tr` `.arb` files and generated `JetPrintLocalizations`; the clipped-count
  message MUST use an ICU plural. No raw developer strings and no unrounded
  floats appear in the UI. (Supersedes the initial "render `validate()` strings
  verbatim" decision: user feedback found the verbatim engine strings —
  English, with raw floats, one per element — not human-friendly. Rather than
  add a domain `Diagnostic` code, the designer generates these messages itself
  from the same geometry it already holds; the engine's `validate()` strings are
  unchanged and remain the source of truth for the render/export path.)
- **FR-011**: When a detail band has an active layout (`columnLayout != null &&
  isPureSingleDetailBody`), the canvas MUST draw the editable band frame at
  `columnWidth` and MUST draw `columnCount − 1` faint, **read-only,
  non-interactive** ghost cell outlines at pitch `columnWidth + columnSpacing`,
  clipped to the page body width.
- **FR-012**: When a band has no layout, or the body is ineligible, the canvas
  MUST draw the band exactly as today (full body width, no ghosts) — no
  regression for non-label reports.
- **FR-013**: Element drag/resize/selection inside the constrained cell MUST
  continue to work unchanged; ghost cells MUST NOT participate in hit-testing or
  selection.

### Key Entities

- **`SetColumnLayoutCommand`** *(new, designer)* — `{bandId, layout}`; applies
  `updateBand(def, bandId, (b) => b.copyWith(columnLayout: layout))`.
- **`RemoveColumnLayoutCommand`** *(new, designer)* — `{bandId}`; rebuilds the
  band with `columnLayout` omitted, all other fields preserved.
- **Column Layout section** *(new, designer UI)* — the Properties band-inspector
  block; three render states keyed on `band.columnLayout` and
  `def.isPureSingleDetailBody`.
- **Eligibility predicate** *(existing, reused)*
  — `ReportDefinition.isPureSingleDetailBody`; the single source of truth shared
  by the engine gate, the validator, and this UI.

## Success Criteria *(mandatory)*

- **SC-001**: From a pure single-detail-body report, an author adds a column
  layout, edits all four values, and sees them reflected in
  `controller.definition` and in preview/print output — without editing JSON.
- **SC-002**: The **Add column layout** action is enabled iff
  `def.isPureSingleDetailBody` and the band has no layout; the disabled state
  carries the explanatory tooltip.
- **SC-003**: A grid-too-wide fixture shows a friendly, localized error row in
  the section (no raw float, no developer phrasing); a fixture with N
  cell-overflowing elements shows a **single** localized warning row carrying
  the count N.
- **SC-004**: **Remove** clears `columnLayout` while a widget test asserts the
  band's `elements` and `height` survive (spec-031 regression guard).
- **SC-005**: An orphaned-layout fixture (layout present, body ineligible) shows
  the editable fields, Remove, and the inactive notice — nothing is hidden.
- **SC-006**: The canvas renders a band with an active layout at `columnWidth`
  with `columnCount − 1` ghost cells; a no-layout/ineligible band renders
  full-width with none.
- **SC-007**: New designer-chrome `.arb` keys resolve in `en`/`de`/`tr` with no
  missing-key fallback.
- **SC-008**: The full suite (`jet_print`) is green, `flutter analyze` is clean,
  and existing goldens are **byte-identical** (designer-only change; no engine
  output or `schemaVersion` change).
