# Feature Specification: Designer Author-Time Resolution for Nested Footers + Published Totals

**Feature Branch**: `031-designer-total-resolution`
**Created**: 2026-06-16
**Status**: Draft
**Input**: The designer's author-time binding check raises a false "Field not
found in the data source" warning for legitimate references introduced by spec
029 (nested-scope footers) and spec 030 (published scope totals). Two entangled
gaps: (1) the designer's band-walking layer never sees a `DetailScope.footer`, so
nested-footer elements are invisible to field resolution (and to id-collision
minting); (2) the field-resolution layer only descends the data **schema**, so it
doesn't know a scope's published `totals` names (`customerTotal`, `orderTotal`)
are legitimately resolvable. This is a **designer-only** fix — no domain,
serialization, or render-engine change.

## Problem

The fill engine renders the migrated nested-list sample correctly (spec 030
widened the filler's `knownFields` with published-total names). But the
**designer** flags valid references at author time:

- The summary's `{SUM([customerTotal])}` and the customer group footer's
  `[customerTotal]` show "Field not found in the data source" — `customerTotal`
  is no longer a schema field (it's a published total), and
  `fieldsInScopeForChain` only knows schema fields.
- The `lines` footer's `$F{orderTotal}` is worse: the footer band is a
  `DetailScope.footer`, which `allBands` never enumerates, so
  `findBandOfElement`/`scopePathToBand`/`findScopeOfBand` can't see it at all —
  the element resolves against the root schema (empty chain) or not at all, and
  `allIds` omits its ids (a latent id-collision-minting hazard).

Both are **author-time only** (a red hint on a correct report), but they
undermine trust in the designer and predate this work — the band-walking gap has
existed since spec 029; spec 030's non-schema published names are simply the
first references to surface it.

The fix has two layers, matching the two gaps:
1. **Band-walking** — teach `allBands` (and transitively `findBand`,
   `findBandOfElement`, `allIds`) plus `scopePathToBand` and `findScopeOfBand`
   about `DetailScope.footer`.
2. **Field-resolution** — compute a band's resolvable name set from the data
   schema **plus** the published totals injected onto that band's render row,
   accounting for a nested footer's parent-row/child-collection duality.

## Clarifications

### Session 2026-06-16

- Q: Scope — both the 029 band-walking gap and the 030 published-totals
  resolution, or only the 030 warning? → A: **Both.** They are entangled: a
  `lines` footer can't resolve `$F{orderTotal}` until it is visible to the
  band-walking layer. Fixing both also closes the latent id-collision hazard.
- Q: How does a nested-scope footer resolve fields, given it renders against the
  **parent** row but aggregates over the **child** collection? → A: **Union** —
  parent-level fields + parent-row published totals (direct refs like
  `$F{orderTotal}`, `$F{orderNo}`) ∪ the child collection's fields (aggregate
  arguments like `SUM($F{lineTotal})`). No aggregate-boundary parsing (consistent
  with the existing `expressionResolves`, which checks all refs uniformly; YAGNI).
- Q: Should published totals appear in the value-field picker, not just stop the
  warning? → A: **Yes** — synthesize a `FieldDef(name, double)` per published
  total so the author can pick `orderTotal`/`customerTotal` from the dropdown.

## Scope

**In scope**:

- **Band-walking**: `allBands` enumerates each scope's `DetailScope.footer`
  (after its children, matching structural order); `scopePathToBand` and
  `findScopeOfBand` match a footer to its owning scope. `findBand`,
  `findBandOfElement`, and `allIds` are fixed transitively (they iterate
  `allBands`).
- **Field-resolution**: a pure helper computes a band's resolvable name set as
  schema fields in scope **plus** the published totals on the band's render row,
  with the nested-footer union (parent resolvables ∪ child collection fields).
- **Properties panel** wiring: `_unresolved`, `_valueFieldChoices` (with
  synthetic `FieldDef`s for published totals), and `_boundFieldType` (published
  totals typed `double`) use the new resolvable set.

**Out of scope (intentional)**:

- Any domain / serialization / render-engine change — `DetailScope.totals` and
  the fill-time behavior already exist (spec 030).
- Aggregate-boundary parsing in the resolver (the union accepts a direct
  `$F{lineTotal}` in a footer; the engine's own FR-009 diagnostic still catches a
  genuine runtime mismatch).
- New localized strings — the existing `bindingUnresolved` message is unchanged;
  it simply fires less.
- The `Outline`/`Data Source` panels' own published-total affordances (e.g.
  authoring a `ScopeTotal` from the UI) — this fixes resolution/validation only.

## User Scenarios & Testing *(mandatory)*

The user is a **report author** editing the nested-list sample in the designer.

### User Story 1 - No false warning on a valid published-total reference (P1)

Selecting the summary's grand-total element (`{SUM([customerTotal])}`), the
customer footer's `[customerTotal]`, or the `lines` footer's `$F{orderTotal}`
shows **no** "Field not found in the data source" warning — each reference is
recognized as a published total in scope.

**Acceptance**: For the spec-030 nested-list definition, `_unresolved` is false
for all three elements; the designer surfaces zero false binding warnings.

### User Story 2 - A genuine typo is still flagged (P1)

Changing a reference to a name that is neither a schema field nor a published
total (e.g. `$F{bogus}`) still shows the warning — the fix does not blanket-
suppress the check.

### User Story 3 - Nested-footer element is reachable and editable (P1)

The `lines` footer's `orderTotal` element is found by `findBandOfElement`
(via `allBands`), its scope chain resolves, and editing it in the Properties
panel works — it is no longer invisible to the designer.

### User Story 4 - Published totals appear in the value picker (P2)

The value-field picker for an element in scope offers the published totals on its
render row (e.g. `orderTotal` for an order-level band, `customerTotal` for the
summary/customer footer) as selectable fields.

### User Story 5 - Id minting accounts for footer ids (P2)

`allIds` includes nested-footer band and element ids, so a newly minted id cannot
collide with one inside a `DetailScope.footer`.

## Requirements *(mandatory)*

### Functional

- **FR-001**: `allBands` MUST enumerate every scope's `DetailScope.footer` (when
  non-null), so `findBand`, `findBandOfElement`, and `allIds` include nested
  footers and their elements.
- **FR-002**: `scopePathToBand` MUST return the scope chain (root-down to and
  including the owning scope `S`) for a band that is `S`'s `DetailScope.footer`.
- **FR-003**: `findScopeOfBand` MUST return the owning scope `S` for `S`'s
  `DetailScope.footer`.
- **FR-004**: A pure helper MUST compute the **published totals on a scope's
  rows** as the names published by that scope's direct child `NestedScope`s
  (`{t.name : child ∈ scope.children, t ∈ child.scope.totals}`).
- **FR-005**: Define the primitive `resolvableAtScope(chain)` =
  `fieldsInScopeForChain(schema, chain)` ∪ published totals on that scope's rows
  (FR-004 over `chain.last`, or over the **root** when `chain` is empty). A pure
  helper MUST compute a band's **resolvable name set** as:
  - Normal band / group header-footer (chain ends at `P`), and once-band /
    furniture (empty chain → root): `resolvableAtScope(chain)`.
  - Nested-scope footer of `S` with parent `P`: `resolvableAtScope(chainToS)` ∪
    `resolvableAtScope(chainToP)` — the footer sees everything a band at `S` sees
    (its aggregates fold over `S`'s rows, including totals published onto them)
    plus everything a band at `P` sees (it renders against `P`'s row).
- **FR-006**: `_unresolved` MUST flag an expression iff a `$F{}` reference is
  absent from the band's resolvable name set (FR-005). A reference to a published
  total in scope MUST NOT be flagged; a reference to an unknown name MUST be.
- **FR-007**: `_valueFieldChoices` MUST include, alongside the in-scope schema
  fields, a synthetic `FieldDef(name, JetFieldType.double)` for each published
  total on the band's render row.
- **FR-008**: `_boundFieldType` MUST report `JetFieldType.double` for a binding
  to a published total (so Format presets gate correctly).
- **FR-009**: No domain, serialization, or render-engine behavior changes; no new
  localized strings; goldens unchanged.

### Key Entities

- **Published totals on a scope's rows** — the names a scope's direct child
  scopes publish onto it; the bridge that makes `$F{customerTotal}` resolvable in
  the customer footer / summary.
- **Band resolvable name set** — the schema-in-scope fields plus the render-row
  published totals (with the nested-footer parent/child union), against which an
  author-time `$F{}` reference is checked.

## Success Criteria *(mandatory)*

- **SC-001**: For the spec-030 nested-list definition, the designer raises **zero**
  false "Field not found" warnings on `{SUM([customerTotal])}` (summary),
  `[customerTotal]` (customer footer), and `$F{orderTotal}` (`lines` footer).
- **SC-002**: A reference to a non-existent name (`$F{bogus}`) is still flagged
  unresolved in each of those bands (no false negative).
- **SC-003**: `allBands`/`findBandOfElement` include the `lines` footer; `allIds`
  includes its band + element ids; `scopePathToBand`/`findScopeOfBand` resolve it
  to the `lines` scope.
- **SC-004**: The resolvable-name helper returns, for the `lines` footer, a set
  containing both `lineTotal` (child) and `orderTotal` (parent published total),
  and **not** `customerTotal` (a root-level total, not on the order row).
- **SC-005**: The value picker offers `customerTotal` for the summary/customer
  footer and `orderTotal` for an order-level band.
- **SC-006**: The full designer test suite is green and all goldens are
  unchanged (author-time-only change; no render path touched).
