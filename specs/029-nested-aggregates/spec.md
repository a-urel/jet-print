# Feature Specification: Nested-Scope Footers + Single-Level Aggregates (Phase B1)

**Feature Branch**: `029-nested-aggregates`
**Created**: 2026-06-16
**Status**: Draft
**Input**: A nested collection scope gains a **footer** band, emitted once after
its rows. An inline aggregate authored in that footer — `{SUM([lineTotal])}` —
sums over **that scope's own collection** (the band's structural position infers
the scope, mirroring Phase A). This is **Phase B1**: single-level aggregation
over the immediate collection's *raw* fields. Recursive aggregation (a parent
total summing a child's computed total) is **Phase B2**, a separate follow-up.

## Problem

[[spec-028-inline-aggregates-status]] (Phase A) made inline aggregates work for
**master-scope** bands: `{SUM([customerTotal])}` in a summary or root group
footer expands to a hidden master-scope `ReportVariable`. But the engine's
variable calculator only accumulates over **master rows** — it never sees nested
collection rows (see [[report-engine-aggregation-scope]]). So a per-order line
total (`orderTotal = SUM(lineTotal)` over an order's `lines`) cannot be computed
live; the playground nested-list sample carries `orderTotal` and `customerTotal`
as **precomputed data fields** precisely because of this gap.

The engine is already ~80% ready: the fill pass iterates nested collection rows
(`childRowsOf`/`emitNode` recursion), resolves child-row fields, and the layout
stage is nesting-agnostic — it consumes a flat `List<FilledBand>` keyed only by
band `type` + `group`. A new band emitted into that flat stream lays out and
paginates transparently. What's missing is (1) a structural place for a
collection's footer, and (2) accumulation over the collection's child rows.

Phase B1 closes both for **single-level** aggregates: a nested scope gets a
`footer` band, and the filler folds the footer's aggregates over the just-
iterated child rows locally — reusing Phase A's aggregate detector and the
existing `VariableAccumulator`, without touching the master variable calculator
or adding a parallel render path.

## Clarifications

### Session 2026-06-16

- Q: How does a nested aggregate determine which collection to sum over? → A:
  **Structural** — a nested-scope footer sums over that scope's own collection;
  the band's position infers the scope (consistent with Phase A). Not
  field-implicit, not explicit-path syntax.
- Q: Recursive (a parent footer summing a child's computed total) or single-
  level? → A: **Recursive is the eventual goal, but decomposed.** Phase B1 (this
  spec) is single-level over raw fields; recursive scope-variables are **Phase
  B2**.
- Q: Do nested scopes get a header too, or footer only? → A: **Footer only.**
  Column headers stay in the parent band; a nested header is a later spec.
- Q: How is a collection footer represented? → A: a new **`Band? footer` field
  directly on `DetailScope`** — the "once after the collection" semantics, not a
  keyed `GroupLevel` (which would need key-break logic this scope doesn't have).

## Scope

**In scope (Phase B1)**:

- A new optional `footer` band on a nested `DetailScope`, emitted **once after**
  the scope's rows (once per parent invocation), with `group: null` so layout
  treats it as an ordinary linear band.
- Inline aggregates (`SUM/AVG/COUNT/MIN/MAX`, expression args — the Phase A
  grammar) in a nested footer, summing over that scope's **immediate**
  collection rows. The filler computes them locally during nested iteration and
  injects the result into the footer band's variables.
- Serialization of the new `footer` field (backward-compatible optional key).
- Validation: a nested-scope footer is an aggregate sink (extend Phase A's I8);
  the root scope must not carry a `footer`.
- Migrating the playground sample's precomputed `orderTotal` field to a live
  `{SUM([lineTotal])}` in the `lines`-scope footer (acceptance proof).

**Out of scope (intentional)**:

- **Recursive aggregation** — a footer summing a *child scope's* computed
  aggregate (`customerTotal = SUM(orderTotal)`, `grandTotal`). That requires
  per-scope variables flowing up the tree — **Phase B2**. In B1, a footer
  aggregate over anything but a raw field of its immediate collection resolves to
  an unresolved-field diagnostic (never a silently-wrong number).
- **Nested headers** (e.g. column titles before the rows) — a later spec.
- **Keep-footer-with-last-row pagination** (`keepTogether`-style) — the footer
  paginates like any band.
- **Rendering per-scope `GroupLevel` groups** (the I7 "not yet rendered"
  capability) — untouched; B1 adds a direct scope `footer`, not nested grouping.
- Removing the precomputed `customerTotal` field — it stays until Phase B2.

## User Scenarios & Testing *(mandatory)*

The user is a **report author** designing a nested-list report.

### User Story 1 - Live per-order total (Priority: P1)

An author adds a footer to the `lines` nested scope and puts
`{SUM([lineTotal])}` in it. On render, after each order's line rows, a row shows
that order's line-total sum — computed live, with no precomputed `orderTotal`
field.

**Acceptance**: Replacing the sample's precomputed `orderTotal` field +
`$F{orderTotal}` display with a `lines`-footer `{SUM([lineTotal])}` renders the
**same per-order totals** (value-equal; goldens updated deliberately if layout
adds the footer row).

### User Story 2 - Per-parent reset (Priority: P1)

With two orders A (lines summing 30) and B (lines summing 5), the `lines` footer
shows `30` after A's lines and `5` after B's lines — the accumulator resets per
parent invocation, not across the whole report.

### User Story 3 - Expression argument (Priority: P2)

A footer `{SUM([qty] * [unitPrice])}` folds the per-line product over the
collection — no precomputed line field required.

### User Story 4 - Guardrails (Priority: P2)

- A `footer` on the **root** scope is a validation error (root has no collection).
- An aggregate in a nested footer over a field **not** in that collection (e.g. a
  master field, or a child-scope computed total — the B2 case) surfaces a
  diagnostic, never a silently-wrong value.
- An empty collection emits **no** footer (consistent with empty → no bands).

## Requirements *(mandatory)*

### Functional

- **FR-001**: `DetailScope` MUST gain an optional `Band? footer`, with
  `copyWith`/equality updated. The root scope (`collectionField == null`) MUST
  NOT carry a `footer` (validation error if present).
- **FR-002**: The serialization codec MUST encode/decode `DetailScope.footer` as
  an optional key; definitions saved before this feature (no key) MUST load
  unchanged (backward compatible).
- **FR-003**: During nested iteration, the filler MUST emit a non-null
  `DetailScope.footer` **once, after** all of that scope's child rows for the
  current parent invocation, with `group: null`. An **empty** collection MUST
  emit no footer (and no child bands).
- **FR-004**: For each top-level inline aggregate (Phase A grammar) in a nested
  footer, the filler MUST fold its argument expression over the scope's child
  rows (each evaluated in a child-row context) using a `VariableAccumulator`, and
  inject the result so the footer element resolves to the computed value. The
  accumulator MUST reset per parent invocation (FR per US2).
- **FR-005**: This computation MUST reuse the Phase A aggregate detector
  (`topLevelAggregate`) and the existing `VariableAccumulator` — no new evaluator
  or parallel render path (Constitution IV). The master `VariableCalculator` MUST
  be untouched.
- **FR-006**: Validation MUST treat a nested-scope footer as a supported
  aggregate sink (extend Phase A's I8 so a footer aggregate there is NOT flagged
  as misplaced).
- **FR-007**: A nested footer aggregate over a field absent from its immediate
  collection schema (master field, or a child-scope computed total — B2) MUST
  surface a diagnostic at fill time (the existing unresolved-field warning) and
  MUST NOT render a silently-wrong value.
- **FR-008**: The footer band's `type` MUST be `BandType.groupFooter` (validated
  for slot consistency), emitted with `group: null` so the layout stage treats it
  as an ordinary linear band (no group-pagination semantics in B1).

### Key Entities

- **Nested scope footer** — `DetailScope.footer`, a band emitted once after the
  collection's rows; the structural home of a collection total.
- **Nested aggregate computation** — the filler-local fold of a footer's
  aggregates over child rows, reusing `topLevelAggregate` + `VariableAccumulator`,
  injected into the footer's variables.

## Success Criteria *(mandatory)*

- **SC-001**: Migrating the playground sample's precomputed `orderTotal` to a
  `lines`-footer `{SUM([lineTotal])}` renders the same per-order totals
  (value-equal); any golden change is limited to the added footer row and is
  reviewed deliberately.
- **SC-002**: A nested footer `SUM($F{x})` sums its collection's rows and resets
  per parent — verified by a two-parent engine test (`[30, 5]`, not `35`).
- **SC-003**: `{SUM([qty] * [unitPrice])}` in a footer round-trips through the
  compiler and folds the per-row product.
- **SC-004**: A root-scope `footer` is a validation error; a nested-footer
  aggregate over a non-collection field surfaces a diagnostic; an empty
  collection emits no footer.
- **SC-005**: The master `VariableCalculator` and the layout/render/paging stages
  are unchanged; Phase A master-scope aggregates still behave identically
  (no regression; no parallel render path).
