# Feature Specification: Band Model Reification

**Feature Branch**: `024-band-model-reification`
**Created**: 2026-06-13
**Status**: Draft
**Input**: Reify the flat band list into an explicit `ReportDefinition` section
tree. Full design: [docs/superpowers/specs/2026-06-13-band-model-reification-design.md](../../docs/superpowers/specs/2026-06-13-band-model-reification-design.md)

## Clarifications

### Session 2026-06-13

- Q: Does a `Band` keep a `type` field, or is its role purely positional? → A: Retain `type` (the existing `BandType`) on every band — for labels/glyphs, identity, and faithful migration — while the band's **structural position stays authoritative** for its rendering role, and `type` is validated to be consistent with its slot.
- Q: Do variables reference their reset group by `id` or by `name`? → A: By stable `id` (rename-safe); a group's `name` becomes a display label only; migration maps each existing `resetGroup` name to the corresponding group's id.

## User Scenarios & Testing *(mandatory)*

The "users" here are **report authors** (who design reports in the visual
designer) and **host developers** (who embed the library, save/load reports,
and render them). Today the engine can render rich reports — multi-level
grouping, arbitrary-depth master/detail — but the designer can only author
trivial ones, because a band's role is *inferred* from a fragile combination of
its type, a group-name string, a collection-field, and its position. This
feature makes the structure explicit so authoring can reach the engine's power,
without changing any existing output.

### User Story 1 - Existing reports render unchanged (Priority: P1)

A host developer with reports built on today's model loads and renders them
after the reification. Output — pagination, page frames, PDF, PNG — is
identical to before. Existing reports stored in the old format are migrated
forward automatically with no data loss.

**Why this priority**: This is the foundation and the safety guarantee. The
model + serialization + engine rewrite must land *first* and must not regress
anything; everything else builds on it.

**Independent Test**: Render the full existing fixture/golden suite through the
new engine and assert byte-identical frames; decode every old-format fixture,
migrate it, and assert it round-trips and renders identically to its
pre-migration form.

**Acceptance Scenarios**:

1. **Given** any existing report, **When** it is rendered through the new
   engine, **Then** every page frame is byte-identical to the current engine's
   output.
2. **Given** a report saved in the current schema version, **When** it is
   loaded, **Then** it is migrated to the new structure losslessly (every
   construct has a home; authored order is preserved) and renders identically.
3. **Given** a report with master-level multi-level grouping and arbitrary-depth
   master/detail, **When** rendered, **Then** group breaks, headers/footers, and
   nested iteration behave exactly as today.

---

### User Story 2 - Groups and scopes are first-class (Priority: P2)

A report author works with a group (or a detail scope) as a single addressable
thing: they select it, see its key and its pagination settings
(keep-together, reprint-header, start-new-page) in **one** place, and edit them
once. The current confusion — the same group setting appearing on both the
group's header band and its footer band — is gone.

**Why this priority**: This is the concrete pain that motivated the redesign and
the first visible authoring win once the model exists.

**Independent Test**: In the designer, select a group, change its
start-new-page setting once, and confirm there is exactly one control and the
change is reflected wherever that group is shown; confirm a group's key and
header/footer belong to the group, not to a loose band.

**Acceptance Scenarios**:

1. **Given** a report with a group, **When** the author selects the group,
   **Then** its key and all pagination flags are editable from a single
   inspector.
2. **Given** a group setting is changed, **When** the author looks at the
   group's header and footer, **Then** the setting is not duplicated as a
   second, independently-editable control.

---

### User Story 3 - Band, group, and scope lifecycle (Priority: P3)

A report author builds report structure directly in the designer: add a band,
remove one, reorder bands, change a band's role; create and delete groups and
detail scopes. Producing a realistic report (e.g. the invoice — page chrome, a
per-invoice header/footer, nested line items, one invoice per page) no longer
requires hand-editing the model.

**Why this priority**: This is the ultimate payoff — closing the gap between
what the engine renders and what the designer can author — but it depends on
US1 and US2.

**Independent Test**: In the designer, add/remove/reorder/retype bands and
create/delete groups and scopes; assert each change is reflected in the model
and is individually undoable/redoable.

**Acceptance Scenarios**:

1. **Given** a report, **When** the author adds, removes, reorders, or changes
   the type of a band, **Then** the structure updates accordingly and each edit
   is one undoable step.
2. **Given** a report, **When** the author creates a group or a detail scope and
   attaches bands to it, **Then** the new structure renders correctly.

### Edge Cases

- A report with several master-scope bands interleaved with a collection band →
  authored order (e.g. "header band, line items, total band") is preserved
  through migration and editing.
- Both a group header and a group footer reference the same group → they fold
  into the single first-class group, each becoming that group's header/footer.
- The data set is empty → the no-data section renders.
- A report with no groups and no nested detail → a trivial tree (root scope with
  one band) — the common simple report still works.
- A current-format report whose group band references an undeclared group →
  migrated best-effort with a diagnostic (preserving today's render-don't-crash
  behavior), not a hard failure.

## Requirements *(mandatory)*

### Functional Requirements

**Model**

- **FR-001**: The report model MUST be an explicit tree that separates
  record-blind page furniture from the data-driven body. A band's **rendering
  role** MUST be *stated* by where it sits in the tree (its furniture slot,
  body section, group header/footer, or scope position) — not inferred from a
  tangle of group-name, collection-field, and sibling order.
- **FR-001a**: Every `Band` MUST retain a `type` (the existing `BandType`
  vocabulary), used for the designer's labels/glyphs, band identity, and
  faithful migration. The band's structural position (FR-001) remains the source
  of truth for its rendering role; `type` MUST be validated as consistent with
  the band's slot at author time (e.g. a band in a page-header slot has the
  page-header type).
- **FR-002**: Every band MUST carry a stable identity that survives editing,
  reordering, and serialization (so selection and lifecycle do not depend on
  list position).
- **FR-003**: Groups MUST be first-class entities owning their key expression
  and pagination settings (keep-together, reprint-header, start-new-page). A
  group's settings MUST have exactly one editing home — never duplicated across
  its header and footer.
- **FR-003a**: Variables MUST reference their reset group by the group's stable
  `id`, not its name. A group's `name` is a display label; renaming a group MUST
  NOT break any variable's reset reference.
- **FR-004**: Detail scopes MUST form a tree supporting arbitrary-depth
  master/detail. A scope's contents (per-row bands and nested scopes) MUST
  preserve authored order, so bands and sub-scopes can interleave.
- **FR-005**: The model MUST be able to *represent* (even though this feature
  does not yet *render* them): grouping inside a nested scope, and multiple
  per-row bands within a scope — so no further schema change is needed when the
  engine grows into them.
- **FR-006**: Page furniture MUST provide reserved slots for column header,
  column footer, and background, which are not laid out in this feature.

**Serialization & migration**

- **FR-007**: The model MUST serialize to a new schema version, and every report
  in the current schema version MUST migrate forward **losslessly** — every
  existing construct maps to a home, authored order is preserved, and each
  existing variable `resetGroup` name is rewritten to the corresponding group's
  new stable id (FR-003a).
- **FR-008**: A migrated report MUST render identically to that same report
  before migration.

**Engine**

- **FR-009**: The render engine MUST consume the new model directly; the current
  flat model MUST be removed (no legacy intermediate representation retained).
- **FR-010**: For every existing report, rendered output (pagination, page
  frames, PDF, PNG) MUST be byte-identical to the current engine's output.
- **FR-011**: Existing master-level multi-level grouping and arbitrary-depth
  master/detail MUST behave exactly as today.

**Designer authoring**

- **FR-012**: A report author MUST be able to add, remove, reorder, and retype
  bands. "Retype" moves a band to a different role/slot and updates its `type`
  accordingly (FR-001a), keeping `type` and position consistent.
- **FR-013**: A report author MUST be able to create, delete, and configure
  groups and detail scopes as first-class, selectable entities.
- **FR-014**: The designer MUST validate model invariants at author time —
  unique ids/names within a scope, record-blind furniture rejecting
  record-dependent bindings, and parseable group keys — surfacing violations
  before render rather than as late render diagnostics.
- **FR-015**: Every structural edit MUST be individually undoable and redoable,
  consistent with the existing single-commit edit history.

### Out of Scope (each a separate future feature)

- Rendering **per-scope grouping** (grouping inside a nested collection).
- **Aggregation over nested child rows** (variables remain master-scoped).
- Rendering **multiple per-row bands** within one scope.
- **Record-aware page chrome** (page header/footer referencing the current
  record).

These are representable in the model (FR-005) but not rendered here.

### Key Entities

- **ReportDefinition**: the root — name, page, parameters, variables, plus
  `furniture` and `body`. Replaces the current flat template.
- **PageFurniture**: record-blind, per-page elements — page header, page footer,
  and reserved column header / column footer / background.
- **ReportBody**: the data-driven content — optional title, summary, and no-data
  sections, plus the root detail scope.
- **DetailScope**: a data scope — an optional collection field it iterates
  (absent for the master/root scope), its groups, and its ordered contents
  (per-row bands and nested scopes).
- **GroupLevel**: a first-class group — a stable `id` (the reference target for
  variable resets), a display `name`, a key expression, optional header/footer,
  and pagination settings.
- **Band**: a stable-id'd container of positioned elements with a height and a
  `type` (BandType) kept consistent with its structural slot.
- **ScopeNode**: an ordered scope content item — either a band or a nested
  scope (so interleaving order is preserved).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the existing render golden suite passes unchanged after
  the engine rewrite — zero visual regressions.
- **SC-002**: Every existing report loads and round-trips through the new format
  with no data loss, and renders identically to before.
- **SC-003**: A report author can set a group's page-break, keep-together, and
  reprint behavior from a single place, with no duplicate or conflicting
  control.
- **SC-004**: A report author can build a multi-band, grouped, master/detail
  report (page chrome + a per-record header/footer + nested detail + one record
  per page) entirely in the designer, with no hand-edited model.
- **SC-005**: Any band can be added, removed, reordered, or retyped in the
  designer, and each change is undoable and redoable.

## Assumptions

- The library is **pre-deployment** (pre-1.0): a clean rewrite is acceptable, no
  backward-compatibility bridge or dual-model period is required, and the
  current flat template type is removed rather than retained as an internal
  representation.
- "Identical output" is defined by the existing test fixtures and render
  goldens; these are the authority for the byte-identical guarantee.
- Migrated bands/groups/scopes receive deterministic stable ids (derived from
  position/role) so migrated reports are reproducible and golden-stable.
- The deferred capabilities listed in Out of Scope are intentionally
  representable-but-not-rendered; each is a separate future feature.
- The approved design document
  ([2026-06-13-band-model-reification-design.md](../../docs/superpowers/specs/2026-06-13-band-model-reification-design.md))
  is the reference for structure, naming, and the migration mapping.
