# Feature Specification: Multi-Level Inline Aggregates (Descendant-Scoped)

**Feature Branch**: `033-multilevel-inline-aggregates`
**Created**: 2026-06-16
**Status**: Draft
**Input**: Inline aggregates (`{SUM([lineTotal])}`) work over a band's *own*
collection — one level. In a multi-level master/detail report
(Customer ▸ Order ▸ Line) an author can sum a leaf field in its immediate
footer, but cannot write the same aggregate one or two levels higher (the
customer footer, the summary) to total all of that scope's descendant leaves:
there is no field name for the lower-level total to reference, and the higher
band's scope does not "see" the deep leaf field. The only multi-level mechanism
today is hand-declared published totals (`DetailScope.totals` / `ScopeTotal`),
which have no inline-authoring or fx-editor path. Generalize inline aggregates so
the **same** `{AGG([leafField])}` expression placed in **any** aggregate-sink
band folds over **all descendant leaf rows** of that band's scope instance,
regardless of nesting depth.

## Problem

Three gaps, surfaced by manual GUI testing of the nested-lists sample
(Customer ▸ Order ▸ Line):

1. **Inline aggregates fold only one level.** `prepareNestedFooter`
   (`nested_footer.dart`, spec 029 B1) folds an inline aggregate over a nested
   scope's *immediate* child rows; `expandAggregates`
   (`aggregate_synthesizer.dart`, spec 028) folds over *master* rows. Neither
   reaches a leaf field that lives two or more collection levels below the band.
   So `{SUM([lineTotal])}` works in the `lines` footer (the order subtotal) but
   not in the `customerFooter` (all of a customer's lines) or the `summary` (all
   lines in the report).

2. **No name to roll up.** An inline footer aggregate is anonymous (`__nagg`)
   and display-only — it never becomes a field on the parent row, so a
   higher-level aggregate has nothing to sum. The only chaining mechanism,
   published totals (`ScopeTotal`, spec 030), must be hand-declared in the
   definition with no designer or fx-editor affordance.

3. **The designer flags valid multi-level intent as invalid.** Author-time
   resolution (`resolvableNamesForBand` / fx `statusFor`) only knows a band's
   own scope (plus, for a nested footer, its parent scope) and published totals
   one level down. A deep leaf field referenced inside an aggregate at a higher
   band is reported "Field not found", and `validate()`'s I8 rule forbids the
   aggregate outright. The original report — *"works fine, but only one level;
   multi-level aggregations are not validated"* — is this gap.

The engine's roll-up traversal (`augmentForScope` in `report_filler.dart`) is
already recursive and bottom-up; the gap is **authoring + resolution + a flat
descendant fold**, not a missing aggregation engine.

## Clarifications

### Session 2026-06-16

- Q: How should an author express a higher-level total? → A: Type the **same**
  leaf-field aggregate at every level (`{SUM([lineTotal])}` in the line footer,
  the customer footer, and the summary); each scopes to its own subtree. No
  intermediate names, no nested aggregate calls, no hand-declared published
  totals.
- Q: What does the aggregate range over at a higher band? → A: **All descendant
  leaf rows** of the band's scope instance that carry the operand field — the
  flattened subtree, not a roll-up of per-row subtotals.
- Q: AVG/MIN/MAX semantics under flattening? → A: **Flat** over leaves. SUM,
  COUNT, MIN, MAX equal the hierarchical roll-up (flat-associative); AVG is
  sum÷count over all descendant leaves (a flat average, **not** an
  average-of-averages). Accepted.
- Q: A leaf field name reachable through two *different* sibling collections? →
  A: **Validation error** (`ambiguous aggregate operand`). Never a silent
  first-match — the engine does not guess which collection was meant.
- Q: A bare deep reference (`[lineTotal]` *not* inside an aggregate) at a higher
  band? → A: Stays **unresolved** (unchanged). Deep leaf fields are legal **only
  as aggregate operands**; a bare deep ref has no row to bind to.

## Scope

**In scope**

- A flat, descendant-scoped fold for inline aggregates in the existing
  aggregate-sink bands: the **summary** band, a **root group footer**, and a
  **nested-scope footer** (`DetailScope.footer`).
- A pure **path resolver** (data layer) from a band's scope down to a uniquely
  named descendant leaf field, returning same-scope / descend-path / not-found /
  ambiguous.
- Filler computation of descendant aggregates via leaf-folding accumulators,
  reset by scope (report → summary, group → group footer, scope-row → nested
  footer).
- `validate()` I8 extended to accept a unique descendant leaf as an aggregate
  operand and to flag ambiguous / not-found operands.
- Designer resolution made **aggregate-operand-aware**: a deep leaf is *valid*
  as an operand, *unresolved* bare; the fx field palette offers descendant leaf
  fields (visually marked) for insertion inside a call.
- Composition with the spec-032 amendment (embedded/compound aggregates such as
  `{SUM([lineTotal]) * 1.1}`) and with multiple operands at different depths.

**Out of scope**

- Average-of-averages or any hierarchical (non-flat) aggregate semantics.
- Nested aggregate-call grammar (`SUM(SUM([x]))`).
- Auto-generating or deprecating hand-declared published totals (`ScopeTotal`);
  they remain valid and unchanged. The same numeric result is now also reachable
  inline.
- Per-scope grouping rendering (still I7 "not yet rendered").
- Any new serialization fields or grammar tokens.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Same aggregate at every level (P1)

An author building Customer ▸ Order ▸ Line types `{SUM([lineTotal])}` in the
line footer (this order's lines), the customer group footer (all of this
customer's lines), and the summary (every line). All three render correct
running subtotals and the grand total, matching the figures the hand-declared
published-total chain produces today — with no `ScopeTotal` declarations.

### User Story 2 - Designer accepts the deep aggregate (P1)

In the fx editor opened on the customer footer's value, typing
`{SUM([lineTotal])}` shows status **Valid** (not "Field not found"). The field
palette lists `lineTotal` marked as a deeper-collection field. `validate()`
returns no diagnostic for the expression.

### User Story 3 - Bare deep ref still flagged (P2)

At the customer footer, `[lineTotal]` (no aggregate) shows **Unresolved /
Field not found** — a deep leaf has no row to bind to outside an aggregate.

### User Story 4 - Flat AVG and empty collections (P2)

`{AVG([lineTotal])}` at the summary equals (sum of all lineTotals) ÷ (count of
all lines) — a flat average. A customer with no orders (or orders with no lines)
contributes nothing; `SUM`→0, `COUNT`→0, `AVG`/`MIN`/`MAX`→null, matching
existing accumulator behavior.

### User Story 5 - Ambiguous operand errors (P2)

If two sibling collections both contain a field named `amount`, an aggregate
over `[amount]` at an ancestor scope produces a validation **error**
(`ambiguous aggregate operand "amount"`), not a silently-chosen collection.

### User Story 6 - Composition with operators and multiple depths (P2)

`{SUM([lineTotal]) * 1.1}` and `{SUM([lineTotal]) + COUNT([orderNo])}` at the
customer footer resolve each operand independently (lines two levels down,
orders one level down) and compute correctly, reusing the spec-032 sub-term
lifting.

## Requirements *(mandatory)*

### Functional

- **FR-001**: A new pure data-layer resolver MUST, given a band's in-scope
  schema fields and an operand leaf name, return one of: **same-scope** (the
  field is a non-collection field at this scope), **descend(path)** (a unique
  chain of `collectionField` names to a non-collection leaf of that name in the
  subtree), **not-found**, or **ambiguous** (≥2 distinct descend paths).
- **FR-002**: An inline aggregate `{AGG([f])}` in an aggregate-sink band MUST
  fold `AGG` over every descendant leaf row reachable from the band's scope
  instance via the resolver's `descend(path)` (or the scope's own rows for
  same-scope). The fold is **flat**: leaves are folded directly, not via
  per-intermediate-row subtotals.
- **FR-003**: Descendant-aggregate values MUST reset by sink scope — **report**
  for the summary band, the owning **group** for a root group footer, the
  current **scope row** for a nested-scope footer — yielding per-group subtotals
  and a report grand total.
- **FR-004**: SUM/COUNT/MIN/MAX over descendant leaves MUST equal the
  hierarchical roll-up of the same field; AVG MUST be the flat sum÷count over
  leaves. Empty leaf sets MUST follow existing accumulator behavior (SUM 0,
  COUNT 0, AVG/MIN/MAX null).
- **FR-005**: `validate()` (I8) MUST accept an aggregate whose operand resolves
  to **same-scope** or a unique **descend(path)** in summary / root group footer
  / nested-scope footer bands; MUST emit an **error** for an **ambiguous**
  operand and for a **not-found** operand; and MUST continue to forbid
  aggregates in non-sink bands.
- **FR-006**: A **bare** (non-aggregate) reference to a descendant leaf field at
  a band where it is not in the band's own scope MUST remain **unresolved** (the
  record-blind / "Field not found" path is unchanged).
- **FR-007**: Designer author-time resolution (`statusFor`, `_unresolved`, and
  the value-field choices) MUST be **aggregate-operand-aware**: a descendant
  leaf is **valid** when it is the operand of an aggregate and **unresolved**
  when referenced bare. The fx **field palette** MUST additionally offer
  descendant leaf fields, visually marked as deeper-collection, inserting the
  plain `[field]` token (the author wraps it in a function).
- **FR-008**: The feature MUST compose with the spec-032 sub-term lifting:
  embedded/compound aggregates (`{SUM([f]) * k}`) and multiple operands at
  different depths each resolve and fold independently.
- **FR-009**: Hand-declared published totals (`ScopeTotal`) MUST remain valid
  and unchanged; the new inline path MUST produce the **same** numeric result
  for the equivalent SUM/COUNT/MIN/MAX chain. No serialization or grammar-token
  changes.
- **FR-010**: An ambiguous or not-found operand MUST never render a
  silently-wrong number — it surfaces as a validation diagnostic at author time
  and a fill-time `#ERROR` / fallback at render time, never a guess.

### Key Entities

- **Aggregate field path** *(new, data)* — the resolver result: `sameScope` ·
  `descend(List<String> collectionPath)` · `notFound` · `ambiguous`.
- **Descendant aggregate** *(new, fill)* — a sink aggregate computed by folding
  descendant leaf values into a `VariableAccumulator`, reset by sink scope.
  Sibling to the spec-029 `NestedAgg` (one level) and spec-030 `ScopeAgg`
  (published roll-up); this one is depth-general and flat.
- **Aggregate-sink band** *(existing)* — summary, root group footer,
  nested-scope footer; the only bands where a descendant aggregate is computed
  and accepted.

## Success Criteria *(mandatory)*

- **SC-001**: The playground nested-lists sample authored with
  `{SUM([lineTotal])}` at the line footer, customer footer, and summary renders
  byte-identical totals to the current published-totals version of the sample.
- **SC-002**: The fx editor shows **Valid** for `{SUM([lineTotal])}` at the
  customer footer and **Unresolved** for bare `[lineTotal]` there.
- **SC-003**: `validate()` returns no diagnostic for the three-level
  `{SUM([lineTotal])}` authoring and an **error** for an ambiguous-operand
  fixture.
- **SC-004**: `{AVG([lineTotal])}` at the summary equals total-sum ÷ total-leaf
  count; empty-collection fixtures follow SUM 0 / COUNT 0 / AVG·MIN·MAX null.
- **SC-005**: The full suite (jet_print + playground) is green; existing goldens
  are unchanged except the playground sample's optional migration to inline
  authoring (which must remain numerically identical).
