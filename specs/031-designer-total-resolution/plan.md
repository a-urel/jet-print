# Designer Resolution for Nested Footers + Published Totals — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Each task is Red→Green TDD (Constitution III).

**Goal:** Stop the designer raising false "Field not found in the data source" warnings for legitimate references introduced by spec 029 (nested-scope footers) and spec 030 (published scope totals). Two entangled layers: (1) teach the band-walking layer about `DetailScope.footer`; (2) teach field-resolution about published `DetailScope.totals`, with the nested-footer parent/child union. **Designer-only — no domain, serialization, or render-engine change; goldens unchanged.**

**Architecture:**
- **Band-walking** (`designer/controller/band_walker.dart`): `allBands` enumerates each scope's `DetailScope.footer` (fixing `findBand`/`findBandOfElement`/`allIds` transitively); `scopePathToBand` + `findScopeOfBand` match a footer to its owning scope.
- **Resolution primitive** (`data/binding_scope.dart`, pure): `publishedTotalsForScope(scope)` = names published by a scope's direct child scopes. The existing `fieldsInScopeForChain`/`expressionResolves`/`fieldResolves` stay.
- **Band resolvable set** (new `designer/controller/binding_resolution.dart`): `resolvableNamesForBand(def, schema, bandId)` composes the primitive with role detection — `resolvableAtScope(chain) = fieldNames(fieldsInScopeForChain) ∪ publishedTotalsForScope(chain.last or root)`; a nested footer of `S` (parent `P`) returns `resolvableAtScope(chainToS) ∪ resolvableAtScope(chainToP)`. A sibling `resolvableFieldChoices(...)` returns the picker's `FieldDef`s (schema fields + synthetic `FieldDef(name, double)` per published total).
- **Properties panel** (`designer/layout/panels/properties_panel.dart`): `_unresolved`, `_valueFieldChoices`, `_boundFieldType` consume the new helpers.

**Tech Stack:** Dart / Flutter, `flutter_test`. Designer + data(binding) layers only. Builds on [[spec-029-nested-aggregates-status]] (`DetailScope.footer`) and [[spec-030-recursive-aggregates-status]] (`DetailScope.totals`). The fill-engine analogue (knownFields widening) already shipped in 030.

**Conventions:** Run `flutter`/`dart` from `packages/jet_print`. Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` ([[git-cwd-drift-after-flutter]]). Branch is already `031-designer-total-resolution`.

## Constitution Check

| Principle | Status |
|---|---|
| I. Library-first / clean API | PASS — pure helpers under `src/`; nothing new exported (designer-internal). |
| II. Layered architecture | PASS — `binding_scope` (data) stays pure; `binding_resolution` (designer) composes band-walk + data; panel consumes. Dependencies point inward. |
| III. Test-First (NON-NEGOTIABLE) | PASS — every task Red→Green. |
| IV. Rendering fidelity / WYSIWYG | PASS — author-time only; no render path touched; goldens unchanged. |
| V. Serialization | PASS — no model/codec change. |
| VI. Docs/DX | PASS — dartdoc on new helpers; `dart format` + clean analyzer gate in Task 4. Improves DX (false warnings gone; published totals in the picker). |

No violations → Complexity Tracking omitted.

---

## File Map

- `packages/jet_print/lib/src/designer/controller/band_walker.dart` — **modify**: `allBands` (`addScope` adds `s.footer`), `scopePathToBand` + `findScopeOfBand` match `s.footer?.id`.
- `packages/jet_print/lib/src/data/binding_scope.dart` — **modify**: add `publishedTotalsForScope(DetailScope)`; (optional) a `fieldNamesInScopeForChain` convenience.
- `packages/jet_print/lib/src/designer/controller/binding_resolution.dart` — **new**: `resolvableNamesForBand(def, schema, bandId) -> Set<String>` + `resolvableFieldChoices(def, schema, bandId) -> List<FieldDef>`.
- `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` — **modify**: `_unresolved`, `_valueFieldChoices`, `_boundFieldType` use the new helpers.
- Tests: `test/designer/controller/band_walker_test.dart` (extend), `test/data/binding_scope_test.dart` (extend), new `test/designer/controller/binding_resolution_test.dart`, `test/designer/band_collection_binding_test.dart` (extend — UI regression on the 030 sample).

---

## Task 1: Band-walking sees `DetailScope.footer`

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/band_walker.dart`
- Test (modify): `packages/jet_print/test/designer/controller/band_walker_test.dart`

Context — `allBands` (`addScope`) currently enumerates `s.groups[].header/footer` + `s.children` BandNodes, recursing into NestedScopes, but NOT `s.footer` (the spec-029 nested-scope footer). `scopePathToBand` and `findScopeOfBand` match group headers/footers and BandNodes but not `s.footer`. `allBands` feeds `findBand`/`findBandOfElement`/`allIds`, so fixing `allBands` fixes those transitively.

- [ ] **Step 1: Write failing tests.** Read the existing `band_walker_test.dart` style first. Build a definition with a nested scope carrying a `footer` (a `Band` of type `groupFooter` with one element), e.g.:
  ```dart
  const footer = Band(id: 'lf', type: BandType.groupFooter, height: 12,
      elements: <ReportElement>[TextElement(id: 'ot',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 12), text: 'ot',
        expression: r'$F{orderTotal}')]);
  final def = /* root → NestedScope(lines, collectionField: 'lines', footer: footer, children:[lineRow]) */;
  ```
  Assert:
  - `allBands(def)` contains the footer (`anyElement((b) => b.id == 'lf')`).
  - `findBand(def, 'lf')` is non-null; `findBandOfElement(def, 'ot')?.id == 'lf'`.
  - `allIds(def)` contains `'lf'` and `'ot'`.
  - `scopePathToBand(def, 'lf')` ends at the `lines` scope (e.g. `.last.id == 'lines'`).
  - `findScopeOfBand(def, 'lf')?.id == 'lines'`.
  Run → FAIL.

- [ ] **Step 2: Implement.**
  - `allBands` `addScope`: after the `s.children` loop, add `if (s.footer != null) out.add(s.footer!);`.
  - `scopePathToBand` `search`: alongside the group/BandNode matches, add `if (s.footer?.id == bandId) { result.addAll(here); return true; }` (place it so each band is matched once; `here = [...trail, s]`).
  - `findScopeOfBand` `search`: add `if (s.footer?.id == bandId) return s;` (mirror the group-footer match).
  - Verify `allIds` needs no separate change (it iterates `allBands` for band/element ids).

- [ ] **Step 3: Run → PASS.**
- [ ] **Step 4: FULL designer suite** (`flutter test test/designer`) — adding footers to `allBands` means any consumer now sees them; confirm nothing regresses (e.g. outline/id tests). If a test asserts an exact band count/list that legitimately should now include footers, update it deliberately and note why. **No golden should change** (these are structural walks). If one does, STOP and inspect.
- [ ] **Step 5: Analyzer + format.** Commit — `fix(designer): band-walking sees DetailScope.footer (allBands/scopePath/findScopeOfBand)`.

---

## Task 2: Resolution primitive + band resolvable set

**Files:**
- Modify: `packages/jet_print/lib/src/data/binding_scope.dart`
- New: `packages/jet_print/lib/src/designer/controller/binding_resolution.dart`
- Tests: `packages/jet_print/test/data/binding_scope_test.dart` (extend), new `packages/jet_print/test/designer/controller/binding_resolution_test.dart`

### 2a — `binding_scope.dart` (pure data seam)
- [ ] **Step 1: Failing test** (in `binding_scope_test.dart`): `publishedTotalsForScope(scope)` returns the names published by a scope's DIRECT child scopes. E.g. a scope whose child `NestedScope` has `totals: [ScopeTotal('orderTotal', ...)]` → `{'orderTotal'}`; a scope with no nested children → `{}`; it does NOT recurse into grandchildren.
- [ ] **Step 2: Implement** in `binding_scope.dart`:
  ```dart
  /// The published-total names injected onto [scope]'s rows: the names published
  /// by [scope]'s DIRECT child scopes (spec 030 — a child scope's `totals` land
  /// on its parent's rows). Not recursive (a grandchild's totals land on the
  /// child's rows, not here).
  Set<String> publishedTotalsForScope(DetailScope scope) => <String>{
        for (final ScopeNode n in scope.children)
          if (n is NestedScope)
            for (final ScopeTotal t in n.scope.totals) t.name,
      };
  ```
  Add imports for `ScopeNode`/`NestedScope`/`ScopeTotal` (they live in `detail_scope.dart` / `scope_total.dart`; `detail_scope.dart` is already imported — confirm `ScopeNode`/`NestedScope` are exported from it and add `scope_total.dart` if needed).
- [ ] **Step 3: PASS.**

### 2b — `binding_resolution.dart` (new designer helper)
- [ ] **Step 1: Failing tests** (`binding_resolution_test.dart`). Build the 3-level nested-list shape (root → orders[totals: customerTotal] → lines[totals: orderTotal, footer]) with an attached `JetDataSchema` (customers → orders → lines, only `lineTotal` etc. as real fields). Assert `resolvableNamesForBand(def, schema, bandId)`:
  - summary band → contains `customerTotal`; does NOT contain `orderTotal`.
  - customer group footer → contains `customerTotal`.
  - an order-level detail band → contains `orderTotal`; not `customerTotal`.
  - the `lines` footer → contains BOTH `lineTotal` (child schema) and `orderTotal` (parent published); does NOT contain `customerTotal` (SC-004).
  - a real typo name (`bogus`) is in NO band's set.
  And `resolvableFieldChoices(def, schema, summaryBandId)` includes a `FieldDef` named `customerTotal` (synthetic, type `double`).
  Run → FAIL.
- [ ] **Step 2: Implement** `binding_resolution.dart`:
  ```dart
  /// Author-time field resolution that accounts for spec-030 published totals and
  /// the spec-029 nested-footer parent/child duality. Composes the band-walk
  /// (designer) with the pure schema/total seam (data).
  library;

  import '../../data/binding_scope.dart';
  import '../../data/data_schema.dart';
  import '../../data/field_def.dart';
  import '../../domain/detail_scope.dart';
  import '../../domain/report_definition.dart';
  import 'band_walker.dart';

  /// The names resolvable in the band [bandId]: schema fields in scope plus the
  /// published totals on the band's render row. A nested-scope footer (renders at
  /// its parent row, aggregates over its own collection) sees the union of what a
  /// band at its own scope sees and what a band at its parent scope sees.
  Set<String> resolvableNamesForBand(
      ReportDefinition def, JetDataSchema schema, String bandId) {
    final List<DetailScope> chain = scopePathToBand(def, bandId);
    final DetailScope? owner = findScopeOfBand(def, bandId);
    final bool isNestedFooter = owner != null && owner.footer?.id == bandId;
    if (isNestedFooter) {
      final List<DetailScope> parent =
          chain.isEmpty ? const <DetailScope>[] : chain.sublist(0, chain.length - 1);
      return <String>{
        ..._resolvableAtScope(def, schema, chain),
        ..._resolvableAtScope(def, schema, parent),
      };
    }
    return _resolvableAtScope(def, schema, chain);
  }

  Set<String> _resolvableAtScope(
      ReportDefinition def, JetDataSchema schema, List<DetailScope> chain) {
    final DetailScope scope = chain.isEmpty ? def.body.root : chain.last;
    return <String>{
      for (final FieldDef f in fieldsInScopeForChain(schema, chain)) f.name,
      ...publishedTotalsForScope(scope),
    };
  }

  /// The value-field picker choices for [bandId]: in-scope NON-collection schema
  /// fields plus a synthetic `FieldDef(name, double)` per published total on the
  /// render row (so an author can pick `orderTotal`/`customerTotal`).
  List<FieldDef> resolvableFieldChoices(
      ReportDefinition def, JetDataSchema schema, String bandId) {
    // Schema fields: reuse the same role logic for the FieldDef side.
    // ... (build from fieldsInScopeForChain over chain (+ parent chain for a
    //      footer), filter out collection fields, then append synthetic
    //      FieldDef(name, JetFieldType.double) for each published-total name not
    //      already present.)
  }
  ```
  VERIFY before trusting the sketch: `scopePathToBand`/`findScopeOfBand` return types and that (post-Task-1) a footer resolves; `fieldsInScopeForChain(schema, chain)` signature; `JetDataSchema` import path (`../../data/data_schema.dart`); `ReportBody.root` access via `def.body.root`. For `resolvableFieldChoices`, mirror the existing `_valueFieldChoices` collection-field filter (`f.type != JetFieldType.collection`) and dedupe synthetic totals against schema names. Decide a clean shared shape (e.g. a small private `_choicesAtScope` mirroring `_resolvableAtScope`) so the footer union works for FieldDefs too.
- [ ] **Step 3: PASS.**
- [ ] **Step 4: Analyzer + format. Commit** — `feat(designer): resolvable-names helper for published totals + nested-footer union`.

---

## Task 3: Properties panel consumes the resolvable set

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`
- Test (modify/new): UI-level coverage lands in Task 4; here keep the existing panel tests green.

Context — `_valueFieldChoices` (≈L455), `_unresolved` (≈L537), `_boundFieldType` (≈L513) currently compute `fieldsInScopeForChain(schema, scopePathToBand(def, band.id))` directly. Rewire them to the Task-2 helpers.

- [ ] **Step 1.** Update `_unresolved`: when `expression != null`, return `!expressionResolves(<names>, expression)` where `<names>` = `resolvableNamesForBand(controller.definition, schema, band.id)` (build a `List<FieldDef>`-free overload: `expressionResolves` takes `List<FieldDef>` today — either add a `Set<String>` overload in `binding_scope.dart`, e.g. `expressionResolvesNames(Set<String> names, expr)`, or pass synthetic FieldDefs. Prefer a small `expressionResolvesNames` to avoid faking FieldDefs). For `imageField`, use `<names>.contains(imageField)` (or a `fieldResolvesName`). Keep the `schema == null` / `band == null` → not-unresolved guards.
- [ ] **Step 2.** Update `_valueFieldChoices` to return `resolvableFieldChoices(controller.definition, schema, elementId-or-band.id)` (note: it currently takes `elementId` then finds the band — keep that; pass the band id through). It already filters collection fields; ensure the helper does too.
- [ ] **Step 3.** Update `_boundFieldType`: after `_simpleFieldRef` extracts the name, look it up in `resolvableFieldChoices(...)` (or the names set + a type map) — a published total resolves to `JetFieldType.double`; a schema field to its declared type; otherwise null. Simplest: search `resolvableFieldChoices(...)` for `f.name == name` and return `f.type` (synthetic totals already carry `double`).
- [ ] **Step 4.** Add a `expressionResolvesNames(Set<String>, String)` (and if needed `fieldResolvesName`) to `binding_scope.dart` with a focused unit test, OR reuse existing by constructing FieldDefs — pick the cleaner one and note it.
- [ ] **Step 5: Run the existing designer/panel tests → green.** Analyzer + format. **Commit** — `feat(designer): properties panel resolves published totals + nested-footer fields`.

---

## Task 4: UI regression on the 030 sample + verification sweep

**Files:**
- Test (modify): `packages/jet_print/test/designer/band_collection_binding_test.dart` (or a new sibling) using the designer harness.
- Verification only otherwise.

- [ ] **Step 1: UI regression tests** (follow `band_collection_binding_test.dart`'s harness + `_unresolvedMsg = 'Field not found in the data source'` pattern). Load a definition equal to the playground nested-list sample (or a faithful minimal analogue: customer group with `[customerTotal]` footer + summary `{SUM([customerTotal])}` + orders/lines scopes publishing `customerTotal`/`orderTotal`, lines footer `$F{orderTotal}`) with the matching schema attached. Assert:
  - Selecting the summary grand-total element shows **no** `_unresolvedMsg`.
  - Selecting the customer-footer `customerTotal` element shows **no** `_unresolvedMsg`.
  - Selecting the `lines`-footer `orderTotal` element shows **no** `_unresolvedMsg` (this also proves the element is now reachable — Task 1).
  - Editing one of them to `$F{bogus}` SHOWS `_unresolvedMsg` (SC-002, no false negative).
  - (P2) The value picker for the summary element lists `customerTotal`.
- [ ] **Step 2: Run → GREEN** (after Tasks 1-3; if RED, the wiring is incomplete — fix in the owning task).
- [ ] **Step 3: Full verification sweep.**
  - `cd packages/jet_print && flutter analyze` → clean.
  - `dart format --output=none --set-exit-if-changed lib test` → clean.
  - `flutter test` (whole package) → all green. **GOLDENS unchanged** — author-time-only change; if any golden fails, STOP and inspect.
  - `cd apps/jet_print_playground && flutter analyze && flutter test` → green (the playground consumes the library; confirm no break).
- [ ] **Step 4: Confirm SCs.** SC-001 → Step 1 no-warning asserts. SC-002 → `$F{bogus}` still flagged. SC-003 → Task 1 band_walker tests. SC-004 → Task 2 `lines`-footer set (lineTotal + orderTotal, not customerTotal). SC-005 → picker test. SC-006 → suite green + goldens unchanged.
- [ ] **Step 5: Manual GUI smoke (optional).** `cd apps/jet_print_playground && flutter run -d macos`; open Nested Lists; confirm the three elements no longer show the red "Field not found" hint and Preview still renders the live totals (281.50 grand total).
- [ ] **Step 6: Commit** any test-only additions — `test(031): designer no longer false-flags published-total references`.

---

## Self-Review

- **Spec coverage:** FR-001/002/003 → Task 1. FR-004 → Task 2a. FR-005 → Task 2b (`resolvableAtScope` + footer union). FR-006 → Task 3 (`_unresolved`). FR-007 → Task 2b/3 (`resolvableFieldChoices` synthetic FieldDefs). FR-008 → Task 3 (`_boundFieldType`). FR-009 → no model/render change (all tasks designer-only; Task 4 confirms goldens). SC-001..006 → Task 4 (+ Task 1/2 unit tests).
- **Key risks:** (1) `allBands` now yields footers — a consumer asserting exact band sets may need a deliberate update (Task 1 Step 4). (2) `expressionResolves` takes `List<FieldDef>`; adding `expressionResolvesNames(Set<String>)` avoids faking FieldDefs (Task 3 Step 4). (3) The footer must be visible to band-walking (Task 1) BEFORE its resolution works (Task 2/3) — task order matters. (4) `resolvableFieldChoices` must mirror the footer union for the picker, not just the names set. (5) Synthetic published-total FieldDefs must dedupe against real schema names (a shadowing total — already a fill-time warning — shouldn't double-list).
- **No model/serialization/engine change**; author-time only; goldens unchanged (Constitution IV/V).
