# Feature Specification: Inline Aggregates (master scope)

**Feature Branch**: `028-inline-aggregates`
**Created**: 2026-06-16
**Status**: Draft
**Input**: An author writes `{SUM([customerTotal])}` directly in a value field
instead of hand-declaring a `ReportVariable` and referencing `{$V{grandTotal}}`.
The aggregate's scope is inferred from the band it lives in (Summary → report,
Group Footer → that group). This is **Phase A** of a two-phase feature; Phase B
(aggregating *nested* collections) is a separate follow-up spec built on the same
syntax.

## Problem

To show a running total today, an author must do two disjoint things: declare a
`ReportVariable` on the report definition (`name`, `expression`, `calculation`,
`resetScope`) **and** reference it from a text element as `{$V{name}}`. The
totalling logic and the place it appears are split across the model, and the
ergonomic, obvious form an author reaches for — `{SUM([customerTotal])}`, the way
RDLC/Excel/Crystal express it — does nothing.

It *almost* works already. The designer's value-template compiler turns
`{upper[name]}` into `UPPER($F{name})` (function sugar), and `reverseCompile`
turns it back. So `{SUM([customerTotal])}` would compile to a normal-looking
expression string `SUM($F{customerTotal})`. Two things are missing:

1. **Runtime** — `SUM`/`AVG`/`COUNT`/`MIN`/`MAX` are aggregates; they live in the
   variable calculator, not the function registry. A top-level `SUM(...)` in an
   expression has no evaluator and would error.
2. **Scope** — `{SUM([customerTotal])}` doesn't say *which rows* to sum over. The
   `ReportVariable` mechanism makes that explicit via `resetScope`; the inline
   form must infer it.

This feature closes both gaps for **master-row aggregates** (the exact capability
the existing `ReportVariable` already has), by treating the inline aggregate as
sugar that the fill pass expands into a band-scoped hidden variable. It reuses the
entire tested variable/accumulator pipeline and changes the engine by a single
line. See [[report-engine-aggregation-scope]] for the master-row limitation this
phase inherits and Phase B will lift.

## Clarifications

### Session 2026-06-16

- Q: How is the aggregate's scope determined? → A: **Infer from the band.**
  Summary → report scope; Group Footer → that group. Most ergonomic
  (RDLC/Excel-style); scope is implicit.
- Q: Which aggregate functions? → A: **All five** — SUM/AVG/COUNT/MIN/MAX (the
  accumulator already supports sum/average/count/min/max).
- Q: How complex may the argument be? → A: **A full expression** —
  `{SUM([qty] * [unitPrice])}` — not just a single field.
- Q: How is the engine's master-row-only aggregation limit handled? → A: The
  user asked to *also* solve nested aggregation, so the work was **decomposed**.
  This spec (Phase A) handles master scope; nested aggregation is **Phase B**, a
  separate spec on the same syntax.
- Q: Single spec or phased? → A: **Two-phase, Phase A first.** Phase A is both
  independently valuable (ships the literal `{SUM([customerTotal])}` example) and
  the mandatory foundation for Phase B (syntax + compiler + scope inference are
  shared).

## Scope

**In scope (Phase A)**:

- Inline aggregate syntax `{FN([expr])}` where `FN ∈ {SUM, AVG, COUNT, MIN, MAX}`
  (case-insensitive), the argument is a full expression over `[field]` tokens.
- The aggregate token occupies the **whole value** of a text element (labels stay
  separate elements, as the existing layouts already do).
- Band-inferred scope: **Summary → report**, **Group Footer → that group**.
- A pure fill-time transform that expands inline aggregates into hidden,
  band-scoped `ReportVariable`s and rewrites the element to reference them.
- Forward + reverse compilation in the value-template compiler (expression args).
- Validation diagnostics for unsupported bands and nested-field arguments.

**Out of scope (intentional)**:

- **Nested-collection aggregation** (`{SUM([lineTotal])}` over an order's lines,
  `{SUM([orderTotal])}` over a customer's orders) — **Phase B**. Phase A emits a
  diagnostic when an argument references a nested field.
- **Aggregates mixed with literal text in one value** (`{Total: SUM([x])}`) — use
  a separate label element, as today.
- **Aggregates in Group Header / Detail / Page furniture bands** — diagnostic;
  the value is incomplete or record-blind there. (Running totals in Detail are a
  possible later phase.)
- **A dedicated Properties affordance** — authoring is via the value field /
  canvas token, which the compiler already round-trips. UI sugar can come later.
- Removing the precomputed `customerTotal` / `orderTotal` data fields — they stay
  until Phase B can compute them live.

## User Scenarios & Testing *(mandatory)*

The user is a **report author** designing in the visual designer.

### User Story 1 - Report-scoped grand total (Priority: P1)

An author selects the value element in the **Summary** band and types
`{SUM([customerTotal])}`. On render, it shows the sum of `customerTotal` across
all master (customer) rows — identical to today's hand-declared `grandTotal`
variable, with no variable to declare.

**Acceptance**: Replacing the sample's hand-written `grandTotal` `ReportVariable`
+ `{$V{grandTotal}}` with the inline `{SUM([customerTotal])}` token produces a
**byte-identical** rendered report (golden unchanged).

### User Story 2 - Group-scoped subtotal (Priority: P1)

An author puts `{SUM([customerTotal])}` in a **Group Footer**. It sums only the
rows of the current group and resets when the group breaks — matching a
hand-declared `resetScope: group` variable.

### User Story 3 - Expression argument (Priority: P2)

An author writes `{SUM([qty] * [unitPrice])}`. Each master row's expression is
evaluated first, then folded into the sum. No precomputed field is required.

### User Story 4 - Round-trip in the designer (Priority: P1)

After authoring `{SUM([customerTotal])}`, the value field and canvas token show
`{SUM([customerTotal])}` again (not the compiled `SUM($F{customerTotal})`), so the
author edits the same form they typed.

### User Story 5 - Guardrails (Priority: P2)

- An aggregate in a Detail / Group Header / Page-furniture band raises a
  validation diagnostic ("aggregate only allowed in summary or group footer").
- An aggregate over a nested field (e.g. `{SUM([lineTotal])}`) raises a diagnostic
  ("nested aggregation not yet supported"), never a silent wrong number.

## Requirements *(mandatory)*

### Functional

- **FR-001**: The value-template compiler MUST compile `{FN([expr])}` (FN one of
  SUM/AVG/COUNT/MIN/MAX, case-insensitive) into the expression `FN(<compiled>)`,
  where `<compiled>` is the argument with each `[name]` token replaced by
  `$F{name}` and all other expression syntax (operators, literals, parentheses,
  nested function calls) passed through. The aggregate token MUST be the entire
  value-field contents.
- **FR-002**: `reverseCompile` MUST render a stored top-level aggregate call back
  to its `{FN([expr])}` token, rendering field refs in the argument as `[name]`,
  so authoring round-trips.
- **FR-003**: A pure transform MUST expand a `ReportDefinition` by: scanning each
  scope-bearing band, inferring its scope (Summary → `report`; a group's Footer →
  `group` with that group's name), synthesizing one hidden `ReportVariable` per
  distinct `(calculation, expression, scope)` found in those bands, rewriting the
  element expression's aggregate call to `$V{<synthesized-name>}`, and appending
  the synthesized variables to the definition's variables.
- **FR-004**: The fill pass MUST apply this transform before building its
  calculator, so synthesized variables fold over master rows through the existing
  variable/accumulator pipeline with no separate evaluation path.
- **FR-005**: Disambiguation — within a Summary or Group-Footer band, a
  **single-argument** call to SUM/AVG/COUNT/MIN/MAX MUST be treated as an
  aggregate; multi-argument MIN/MAX (and any aggregate-named call outside those
  bands) MUST remain the existing scalar function.
- **FR-006**: Aggregate function-to-calculation mapping MUST live in one shared
  source: `SUM→sum`, `AVG→average`, `COUNT→count`, `MIN→min`, `MAX→max`. COUNT
  follows the accumulator's existing semantics (counts non-null/non-error
  contributions).
- **FR-007**: Validation MUST emit a diagnostic for an aggregate call in an
  unsupported band (Detail / Group Header / Page furniture) and MUST NOT render a
  value there.
- **FR-008**: Validation MUST emit a diagnostic when an aggregate argument
  references a field that belongs to a nested collection rather than the master
  schema (Phase A boundary), and MUST NOT render a silently-wrong value.
- **FR-009**: Synthesized variable names MUST be internal and deterministic, never
  surfaced to the author; the value field always shows the `{FN([expr])}` sugar.

### Key Entities

- **Aggregate token** — the authored `{FN([expr])}` form; presentation only.
- **Synthesized `ReportVariable`** — the hidden, band-scoped variable an aggregate
  token expands into; identical in kind to a hand-authored variable.
- **AggregateSynthesizer** — the pure `ReportDefinition → ReportDefinition`
  transform performing scope inference, synthesis, de-dup, and rewrite.

## Success Criteria *(mandatory)*

- **SC-001**: Replacing the playground sample's hand-declared `grandTotal`
  variable with `{SUM([customerTotal])}` in the Summary band renders
  **byte-identical** output (existing goldens unchanged).
- **SC-002**: A group-footer `{SUM([customerTotal])}` matches a hand-declared
  `resetScope: group` variable row-for-row.
- **SC-003**: `{SUM([qty] * [unitPrice])}` round-trips through compile /
  reverse-compile and folds the per-row product.
- **SC-004**: Aggregates in unsupported bands and over nested fields each surface
  a diagnostic; neither renders a wrong number.
- **SC-005**: The engine's aggregation code path is unchanged apart from invoking
  the transform (no parallel evaluation path; Constitution IV).
