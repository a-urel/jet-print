# Feature Specification: Recursive Scope Totals (Phase B2)

**Feature Branch**: `030-recursive-aggregates`
**Created**: 2026-06-16
**Status**: Draft
**Input**: A nested `DetailScope` can **publish named totals** — a roll-up
aggregate (`SUM($F{lineTotal})`) bound to a name (`orderTotal`). The engine
injects each published total as a **field on the parent row**, so an enclosing
scope, a group footer, or the report summary references it as an ordinary
`$F{name}`. Published totals compute **bottom-up and recursively**, so a parent
total can sum a child's *computed* total (`customerTotal = SUM($F{orderTotal})`)
and the report grand total (`SUM($F{customerTotal})`) sums those live. This is
**Phase B2**: the recursive completion of the nested-aggregation work.

## Problem

[[spec-029-nested-aggregates-status]] (Phase B1) made a nested collection's
per-row total live via a `DetailScope.footer` that folds an inline aggregate over
its **immediate** collection's *raw* fields (`orderTotal = SUM([lineTotal])`).
But B1 stops one level deep: a footer aggregate over anything but a raw field of
its own collection resolves to an unresolved-field diagnostic. So the two totals
*above* the per-order line total stay precomputed data in the playground sample:

- **`customerTotal`** — the customer's order total — would need to sum each
  order's *computed* `orderTotal` (a B1 footer value, not a raw field). B1 can't.
- **`grandTotal`** — the report total — is authored as the Phase A inline
  aggregate `SUM($F{customerTotal})`, but it sums the **precomputed** field, not a
  live value.

The blocker is **direction**: B1 computes a total *for display in its own
footer*; it never makes that total available to an *enclosing* scope. And the
customer total / grand total live in a **group footer** and the **summary** —
which flow through the master `VariableCalculator`, not B1's filler-local footer
path. Bridging requires the nested total to exist as something the master
calculator can see.

Phase B2 closes this by changing **direction and representation**: a scope
*publishes* named totals that roll **up** the tree as **synthetic fields on the
parent row**. Because each customer is one master row carrying its own `orders`,
injecting `customerTotal` onto the master row **before the calculator advances**
makes the customer group footer and the existing Phase A `grandTotal` work
through the **unchanged** calculator — no new aggregation engine, no parallel
render path. The recursion lives in *data preparation*, not in the render.

## Clarifications

### Session 2026-06-16

- Q: Target scope of B2 — full chain or one level? → A: **Full chain.**
  `customerTotal` *and* `grandTotal` go live; the precomputed `customerTotal`
  (and unused `orderTotal`) data fields are removed. The injection mechanism
  delivers `grandTotal` for free via Phase A, so a one-level split would be
  artificial.
- Q: How does a nested scope's computed total get a name and get referenced from
  an enclosing band? → A: **Scope-level published total.** A scope declares a
  named total (`{orderTotal: SUM($F{lineTotal})}`); the name enters the **parent
  row's field namespace** (`$F{orderTotal}`); any band displays it and an
  enclosing scope aggregates over it. Computation (rolls up) is separate from
  presentation (any band). Not inline-bound-to-display, not explicit-path syntax.
- Q: Field namespace or a distinct `$T{}`? → A: **Field namespace.** A published
  total *is* a field the row now has; this matches the author's intuition
  (`$F{customerTotal}`) and leaves `grandTotal`'s source literally unchanged.
- Q: Relationship to B1's `footer`? → A: **Independent and composable.** B1
  `footer` = anonymous, display-only, local. B2 `totals` = named, rolls up. The
  migrated `lines` footer displays the *published* `$F{orderTotal}` (one
  computation, reused) instead of a B1 inline aggregate.

## Scope

**In scope (Phase B2)**:

- A new optional `List<ScopeTotal> totals` on a nested `DetailScope`. Each
  `ScopeTotal` is `{name, expression}` where `expression` is a Phase A top-level
  aggregate folded over the scope's child rows.
- **Field-namespace injection**: each published total is added as a synthetic
  field (name → folded value) on the **parent row**, resolvable as `$F{name}` by
  any band and by enclosing aggregates.
- **Bottom-up recursive computation** in the filler: a scope's total may
  reference a **direct child scope's** published total (injected on the child
  rows), enabling `customerTotal = SUM($F{orderTotal})`.
- **Master-row injection before `calc.advance`**, so a top-level scope's total
  (`customerTotal`) is visible to the customer group footer and to the existing
  Phase A summary aggregate (`grandTotal`) through the **unchanged** master
  calculator.
- **Single computation / one render path**: `emitNode` consumes the
  rollup-augmented row tree (the B1 footer display reads `$F{orderTotal}` off the
  already-augmented order row) — each aggregate folds exactly once; layout /
  paging / render untouched.
- Serialization of `totals` (backward-compatible optional key).
- Validation: root scope must not carry `totals`; each expression must be a
  top-level aggregate; each name must be unique in its scope and must not collide
  with a real field of the parent collection.
- Migrating the playground sample's precomputed `customerTotal`/`orderTotal` data
  fields to published totals (`orderTotal` on `lines`, `customerTotal` on
  `orders`), making the whole Customer ▸ Order ▸ Line total chain live.

**Out of scope (intentional)**:

- **A new evaluator or master-calculator change** — B2 adds only a data-prep
  pass; the `VariableCalculator` is untouched and stays the single engine for
  master/group/summary aggregation.
- **Forward / sibling references** — a total may reference its own collection's
  raw fields or a *direct child* scope's published total only. A reference to a
  master field, a non-adjacent scope, or a not-yet-injected name surfaces a
  diagnostic (never a silently-wrong value).
- **Nested headers** and **keep-footer-with-last-row pagination** — unchanged
  from B1; still later specs.
- **Removing B1's `footer`** — it stays for anonymous local display totals; B2 is
  additive.
- **Per-scope `GroupLevel` rendering** (the I7 "not yet rendered" capability) —
  untouched.

## User Scenarios & Testing *(mandatory)*

The user is a **report author** designing a multi-level nested-list report.

### User Story 1 - Live recursive customer total (Priority: P1)

An author publishes `orderTotal = SUM($F{lineTotal})` on the `lines` scope and
`customerTotal = SUM($F{orderTotal})` on the `orders` scope. On render, each
customer's footer shows the sum of that customer's order totals — computed live,
with no precomputed `customerTotal` field.

**Acceptance**: Removing the sample's precomputed `customerTotal` field and
publishing it as `SUM($F{orderTotal})` renders the **same per-customer totals**
(value-equal to the data-derived sums).

### User Story 2 - Live grand total, unchanged source (Priority: P1)

The summary keeps its existing `SUM($F{customerTotal})` expression. After B2 it
sums the **injected** `customerTotal` across master rows and produces the same
grand total — with the precomputed field gone. The author changed nothing in the
summary.

**Acceptance**: The summary's `grandTotal` source is byte-identical pre/post-B2;
its rendered value equals the data-derived grand total.

### User Story 3 - Per-parent reset, recursively (Priority: P1)

With customer A (orders totalling 35) and customer B (orders totalling 12), the
customer footer shows `35` then `12` — the roll-up resets per parent at *every*
level, not across the report.

### User Story 4 - Guardrails (Priority: P2)

- A `totals` entry on the **root** scope is a validation error.
- A `ScopeTotal.name` equal to a real field of the parent collection, or
  duplicated within a scope, is a validation error.
- A non-aggregate `ScopeTotal.expression` (`$F{x} + 1`) is a validation error.
- A total whose argument references an unresolvable name (master field,
  non-adjacent scope, typo) surfaces a fill-time diagnostic and resolves to null,
  never a silently-wrong number.

## Requirements *(mandatory)*

### Functional

- **FR-001**: `DetailScope` MUST gain an optional `List<ScopeTotal> totals`
  (default empty), with `copyWith`/equality/`hashCode`/`toString` updated.
  `ScopeTotal` is an immutable `{String name, String expression}` value type with
  equality. The root scope (`collectionField == null`) MUST NOT carry `totals`
  (validation error).
- **FR-002**: The serialization codec MUST encode/decode `DetailScope.totals` as
  an optional key (list of `{name, expression}`); definitions saved before this
  feature (no key) MUST load unchanged (backward compatible, no schema bump).
- **FR-003**: For each `ScopeTotal` on a nested scope, the filler MUST fold its
  aggregate argument over the scope's child rows (each in a child-row context)
  using a `VariableAccumulator`, and inject the result as a **synthetic field**
  `name → value` on the **parent row**. The accumulator MUST reset per parent
  invocation.
- **FR-004**: Computation MUST be **bottom-up**: a scope's child rows are
  augmented with their *own* child scopes' published totals **before** the scope
  folds over them, so a total MAY reference a direct child scope's published
  total as `$F{childTotalName}`.
- **FR-005**: For each master row, the rollup pass MUST run **before**
  `calc.advance`, injecting top-level scope totals onto the master row, so that
  the master `VariableCalculator`, group-break logic, group footers, and Phase A
  summary aggregates resolve them through the **unchanged** existing paths.
- **FR-006**: This MUST reuse the Phase A aggregate detector (`topLevelAggregate`)
  and the existing `VariableAccumulator` — no new evaluator or parallel render
  path (Constitution IV). The master `VariableCalculator` MUST be untouched.
- **FR-007**: `emitNode` MUST consume the rollup-augmented row tree so each
  aggregate folds **exactly once** and the B1 footer display reads injected totals
  as fields (no recomputation, no second render path).
- **FR-008**: Validation MUST reject: a root-scope `totals`; a non-top-level-
  aggregate `ScopeTotal.expression`; a `ScopeTotal.name` duplicated within a scope
  or colliding with a declared field of the parent collection's schema.
- **FR-009**: A `ScopeTotal` argument referencing a name absent from its child-row
  field namespace (after injection) MUST surface the existing unresolved-field
  fill-time diagnostic and resolve to null — never a silently-wrong value.

### Key Entities

- **Scope total (`ScopeTotal`)** — a named roll-up aggregate published by a nested
  scope: `{name, expression}`. The structural home of a recursive total.
- **Field-namespace injection** — adding a published total as a synthetic field on
  the parent row, the bridge that lets enclosing scopes, group footers, and the
  Phase A summary consume it through unchanged paths.
- **Bottom-up rollup pass** — the filler-local depth-first computation that
  augments the row tree once per master row before the calculator advances.

## Success Criteria *(mandatory)*

- **SC-001**: Publishing `customerTotal = SUM($F{orderTotal})` (over child rows
  that carry the deeper-published `orderTotal`) renders per-customer totals
  value-equal to the data-derived sums; the precomputed `customerTotal` field is
  removed from the sample schema and data.
- **SC-002**: The summary's `grandTotal` expression is unchanged and renders the
  live data-derived grand total over the injected `customerTotal`.
- **SC-003**: A two-customer engine test proves per-parent reset at the customer
  level (`[35, 12]`, not `47`), with the deeper order/line totals also resetting.
- **SC-004**: Guardrails: a root-scope `totals`, a name/field collision, a
  duplicate name, and a non-aggregate expression are each validation errors; a
  total over an unresolvable name surfaces a diagnostic and resolves to null.
- **SC-005**: `DetailScope.totals` round-trips through the codec; a definition
  without the key loads unchanged.
- **SC-006**: The master `VariableCalculator` and the layout/render/paging stages
  are unchanged; Phase A and B1 behaviors are identical (no regression; no
  parallel render path); each aggregate folds exactly once.
