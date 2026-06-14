# Designer Authoring Affordances — Design

**Date**: 2026-06-14
**Status**: Approved (brainstorm) — ready for implementation plan
**Prerequisite**: Spec 024 *Band Model Reification* is merged to `main` (PR #19). This feature branches off `main`.
**Scope tier**: Focused fix (authoring-UX regression repair), delivered comprehensively.

## Problem

The 024 reification made `GroupLevel` and `DetailScope`/`NestedScope` first-class,
id'd nodes in the model — replacing the old flat band list where a band's role was
*inferred* from `type` + group-name + `collectionField` + sibling position. The model
moved forward. **The designer UI did not gain matching create/manage affordances**, so
the day-to-day authoring experience regressed:

1. **You cannot create a list (nested scope) or a group from the UI.** The controller
   already has `createScope()` and `createGroup()`, but they are wired to no button.
   The Outline `+` menu ([outline_panel.dart:182-226](../../../packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart#L182-L226))
   only offers "add detail band" and group-band options.
2. **The list binding became invisible where users look.** In the old flat model the
   collection binding (`collectionField`) lived on the *detail band* you selected. After
   reification it lives on the enclosing **scope** ([detail_scope.dart](../../../packages/jet_print/lib/src/domain/detail_scope.dart),
   `String? collectionField`). Selecting a detail band now shows only its height
   ([properties_panel.dart:524-567](../../../packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart#L524-L567)).
   Users look at the band — where the field used to be — and find nothing. Hence
   *"list field seçemiyorum"* and *"her şey arka planda oluyor."*
3. **A blank report cannot be built into an invoice through the UI alone.** The playground
   pre-seeds a complete `invoiceSampleDefinition()`, so users *edit* an existing tree; the
   from-scratch path is blocked at "add list" and "add group." Hence *"sıfırdan tasarlanabilir
   mi emin değilim."*

**Net assessment:** the reification was the right move (it killed the fragile inferred-role
model); the broken thing is *missing UI affordances for the new first-class entities*, not the
model. The debt sits entirely in one layer (`designer/`), so it can be repaid in one layer.

## Goals

- Restore and improve from-scratch authoring: a blank report can be built into a grouped,
  master/detail invoice using the UI alone.
- Make list/scope creation and binding **discoverable and explicit**, via two co-equal,
  first-class paths (the user chose "both equal priority"):
  - **Data-first** drag from the Data Source panel (primary surface).
  - **Structure-first** explicit create buttons in the Outline.
- Surface the list binding **where the user looks** (the selected band/scope), completing the
  "edit the structural entity from its band" pattern already established for groups (9401f8c).
- Surface existing author-time diagnostics so mistakes are caught at gesture time, not render
  time.

## Non-goals (explicitly deferred)

- "New from template" / blank-state wizard (the guided-start tier the user set aside). The
  existing sample tabs — Fatura/Etiket/Liste/Makbuz/İç İçe Listeler — are *not* turned into a
  scaffolding flow here.
- A full dedicated diagnostics panel/tab (only inline + compact summary here).
- Any render-side capability already deferred by 024 (multiple per-row bands, per-scope
  grouping, nested aggregation rendering).

## Constraints & invariants preserved

- **UI-only.** All work lands in `packages/jet_print/lib/src/designer/`. The domain model,
  serialization codec, and `kReportSchemaVersion` (=2) **do not change** → no schema bump, no
  migration, existing saved reports are unaffected.
  - *Single exception:* if the "nested scope has no `collectionField`" check is not already in
    `validate()`, we add it as an **additive, non-throwing diagnostic** in
    `report_validation.dart`. This is an additive domain change only — it does not alter any
    model shape, codec output, or schema version.
- **Rendering fidelity (Principle IV).** Render goldens stay **byte-identical**. Because
  authoring UX does not touch the render path, a golden change here would mean we accidentally
  modified the wrong layer — so the golden gate doubles as a "stayed in the right layer" proof.
- **Layered (Principle II).** New widgets live under `src/designer/`; `layer_boundaries_test`
  stays green. The designer continues to depend inward on the domain.
- **Minimal public surface (Principle I).** New widgets are designer-internal; `public_api_test`
  stays effectively unchanged. No new public types are expected.
- **Localized.** All new user-facing strings are added for TR/EN/DE (building on 0182344).

## Design

Three interaction surfaces plus validation. The three surfaces are not mutually exclusive — all
ship — but they are prioritized: **B is the primary front door, A is the discoverability anchor,
C is the explicit/structural path with read-friendly labels.**

### B — Data-source-led list creation (primary)

**Gesture.** In the Data Source panel ([data_source_panel.dart](../../../packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart)),
a **collection** field (e.g. `lines`) becomes a source for creating a list:

- **Drag** the collection field onto the canvas / Outline, **or** click a small **"+" affordance**
  next to it (the click alternative serves accessibility and discoverability, and bridges B and C).
- Tapping the collection node still toggles **expand/collapse** as today. Disambiguation:
  *tap = expand/collapse*, *drag or "+" = create list*.
- Scalar fields keep today's behavior: dragging a scalar creates a bound `TextElement`
  (`createBoundElement`). Unchanged.

**Drop target → parent scope.** The new nested scope's parent is the scope that **governs the drop
location**. `lines` is a field of the root `Invoice` record, so it nests under the root scope.
Schema-awareness validates this: valid drop targets are highlighted **green**; dropping a collection
field at a level whose record does not contain it is **rejected** (red + tooltip). This turns
"list placed at the wrong level" from a render-time failure into a gesture-time rejection.

**Resulting command sequence (one undo unit).**

```
createScope(parentScopeId, collectionField: 'lines')
  → addDetailBand(newScopeId)
  → select the new detail band
  → auto-expand `lines` children in the Data Source panel (so the next scalar drags are easy)
```

The new scope + detail band must collapse into a **single compound/undoable step** — otherwise a
user who made one gesture would need two Ctrl+Z presses (one removing the band, one the scope) and
be confused. *Implementation note:* verify the command stack supports compound/transactional
commands; if not, add a thin compound-command wrapper.

**Edge cases.**

- Nested-into-nested (`lines` inside `lines`): allowed only if the schema has a collection at that
  deeper level (master/detail/detail). Same parent-resolution rule.
- Second list over the same collection: the model permits it → allow, with a gentle diagnostic.
- Drop creates a non-empty unit: always an empty **detail band** is created with the scope (an empty
  list is useless).

### A — Inspector binding discoverability (second)

This completes a pattern the team already chose: in 9401f8c the abstract group node was dropped and
group flags are edited **from the group header band**. We apply the same language to the detail band.

**Behavior.**

- **Detail band of a nested list selected** → the Properties inspector shows a **"List" section**:
  `Bu band şunu yineler: [ lines ▾ ]`, a **schema-aware picker** populated from the collection fields
  valid at the band's level, with a **free-text fallback**. The control edits the **enclosing scope's**
  `collectionField` via `setScopeCollection(enclosingScopeId, field)`.
- **Detail band of the root scope selected** → a **read-only** "Source: Main dataset (root)" label
  instead of a picker. Only `NestedScope`s have a `collectionField`; the root scope iterates the
  dataset itself, so there is no field to choose. The inspector honestly mirrors the model's shape
  (`collectionField` is `null` at the root), pre-empting "why can't I pick a field here?".
- **Scope node selected (Outline)** → the same schema-aware picker (upgrading the existing free-form
  collection-field input at [properties_panel.dart:630-683](../../../packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart#L630-L683)).

**Consistency table (the established "edit the structural entity from its band" language):**

| Band selected      | Inspector edits                                   | Status            |
|--------------------|---------------------------------------------------|-------------------|
| Group header band  | group flags (key, keepTogether, startNewPage)     | ✓ exists (9401f8c) |
| Detail band        | enclosing scope's `collectionField`               | + this feature (symmetric missing piece) |
| Scope node (Outline)| `collectionField` (free input → schema picker)   | upgrade           |

### C — Outline affordances + readable labels (explicit path)

Respects 9401f8c: **no abstract group node returns** — groups remain represented by their bands.

**C-core (the agreed explicit "button" path).** The scope `+` menu gains, alongside "add detail band":

- **"Add list"** → `createScope` (a nested child collection under this scope).
- **"Add group"** → `createGroup` **+** `addGroupBand(header)` (the header band is created so the group
  is visible in the Outline; without a band a new group would itself be invisible / "in the background").
- Short help text disambiguating the two — the reified model's finest conceptual distinction:
  *List* = a new collection axis (master/detail), *Group* = splitting the same axis by a key. In the
  old flat model this distinction was buried in inference; now they are two named actions.

**C-polish.** Make structure readable at a glance (directly attacks "her şey arka planda"):

- Node labels show the binding: `📃 List: lines`, `Group header · invoiceNo` (the key).
- Icons (📃 list, 🔁 group).

### Validation surfacing

Logic mostly already exists in `validate()` / `controller.diagnostics` (author-time, non-throwing).
We only display it; authoring stays permissive (hard errors still surface at render time).

**Surfaced on three places:**
- Inline **⚠ badge** on the offending Outline node (with tooltip).
- Inline message in the **inspector** when the offending entity is selected (red helper text under
  the binding picker).
- A compact **"⚠ N" toolbar badge → popover** listing diagnostics, each click navigating/selecting
  the offending node.

**Priority checks:** nested scope not bound to a collection field (most critical — wrong render);
binding references an unknown field (schema-aware); duplicate ids/names per scope and unparseable
group key (already in `validate()`).

*See the constraints section for the single additive-diagnostic exception.*

## Key model/controller touchpoints (all existing)

| Need | Existing API |
|------|--------------|
| Create a nested list | `createScope(parentScopeId, {collectionField})` |
| Re-bind / unbind a list | `setScopeCollection(scopeId, collectionField)` |
| Delete a list | `deleteScope(scopeId)` |
| Create a group | `createGroup(scopeId, {name, key})` |
| Show a group as a band | `addGroupBand(groupId, {header})` |
| Add a per-row band | `addDetailBand(scopeId)` |
| Create a bound text from a scalar drag | `createBoundElement({bandId, at, expression})` |
| Author-time diagnostics | `controller.diagnostics` / `validate()` |
| Blank starting point | `defaultBlankDefinition()` |

The work is overwhelmingly **UI wiring + new widgets + widget tests**, not new engine/model logic.

## Testing & acceptance

- **TDD red→green (Principle III)** widget tests per affordance:
  - B: collection drag/drop and "+" click → resulting tree (scope + detail band, bound); invalid-level
    drop rejected; single-undo collapse.
  - A: detail-band inspector binding picker for nested vs root; scope-node picker; edits route through
    `setScopeCollection`.
  - C: scope `+` menu items create scope/group(+header band); node labels show binding/key.
  - Validation: badge/inspector/summary render for each diagnostic; click-to-navigate.
- **Golden regression guard:** assert render goldens stay byte-identical (Principle IV) — proof we did
  not touch the render path.
- `public_api_test` / `layer_boundaries_test` stay green.
- **Localization:** TR/EN/DE keys for every new string (menu items, "List"/"repeats", "Main dataset
  (root)", help texts, diagnostic messages).
- **Headline acceptance scenario (manual GUI walkthrough):** in the playground, build the invoice from
  a **blank report** using only the new affordances — the real test of "can it be designed from scratch?"

## Out of scope / deferred

- "New from template" / blank-state wizard.
- Full diagnostics panel/tab.
- Render-side capabilities deferred by 024 (multiple per-row bands, per-scope grouping, nested
  aggregation rendering).

## Resolved decisions (from brainstorm)

- Mental model: **both data-first and structure-first are first-class** (equal priority).
- Data schema is **almost always attached** → schema-aware pickers and drag are the confident primary
  path; free-text remains as a fallback.
- Scope: **focused fix**, delivered comprehensively (A full, B full, C core + polish, validation).
- Surface priority: **B primary → A → C**.
- Root-scope detail band shows a **read-only "Main dataset (root)"** label (not a hidden section).
