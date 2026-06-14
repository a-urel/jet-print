# Band Model Reification — Design

**Date:** 2026-06-13
**Status:** Approved — open questions resolved 2026-06-13; implementation via speckit (`specs/NNN-feature/`)
**Topic:** Replace the flat, role-by-position band list with an explicit,
id'd section tree that the designer can author and the engine can render.

---

## 1. Motivation

The model the engine *renders* is far more capable than the model the designer
can *author*, and a band's behavior is **implicit** — inferred from four
uncoordinated axes rather than stated:

1. `type` — one of 11 `BandType`s
   ([report_band.dart](../../../packages/jet_print/lib/src/domain/report_band.dart)),
2. `group` — a **string name** pointing into `ReportTemplate.groups`,
3. `collectionField` — presence makes a band a master/detail iterator,
4. **position** — among siblings and within the `children` tree.

So "the invoice total" is *"a `detail` band, no `collectionField`, positioned
after the `lines` band."* Reorder it and the meaning changes. Concrete symptoms
observed while building the invoice demo and the `startNewPage` feature:

| Symptom | Root cause |
|---|---|
| Can't add/remove/reorder/retype bands in the designer | No band lifecycle; bands are an anonymous flat list selected **by index** ([selection.dart](../../../packages/jet_print/lib/src/designer/controller/selection.dart)). Bands have **no stable id** (elements do). |
| "Start-on-new-page" toggle appears on both the group header and footer band | **Groups are second-class.** `startNewPage` is a `ReportGroup` property; bands reference it by name, so it is edited *through a band*. No group entity exists to select. |
| Customer/subtotal can't live in page header/footer | Page chrome is **record-blind** by design ([report_layouter.dart](../../../packages/jet_print/lib/src/rendering/layout/report_layouter.dart) substitutes against a page-scoped context, no row). |
| Master metadata had to be a "master-scope detail band" | No explicit master header/footer — faked by position relative to the collection band. |
| A `groupHeader` with an unknown group only fails at render | No authoring-time integrity; invalid combinations surface late, as fill diagnostics. |

The reification makes each band's role **stated**, makes **groups and scopes
first-class**, and gives **every band a stable id** — so the designer can reach
the power the engine already has.

## 2. Decisions taken (this brainstorm)

- **D1. Full reification** (not an authoring layer over the flat model, not a
  groups-only slice). Chosen for the cleanest end-state.
- **D2. General model, incremental engine.** The model is general enough to
  *represent* every complex scenario; the **step-1 engine implements only
  today's semantics** and renders **byte-identically**. Capabilities the current
  engine lacks are *representable but deferred* to later specs (see §6).

## 3. Goals / Non-goals

**Goals**
- An explicit section tree with stable ids; role is stated, not inferred.
- Groups and detail scopes are first-class, addressable entities.
- Page furniture (record-blind, per-page) is separated from data-driven body.
- A versioned, lossless migration from existing (`schemaVersion: 1`) reports.
- Step-1 rendering is **byte-identical** to today (golden-locked).

**Non-goals (this design / step 1)**
- New *rendering* behavior. Intra-collection grouping, aggregation over nested
  child rows, and multiple per-row bands are **representable but not rendered**
  in step 1 (§6).
- Authoring UI for the new structure beyond what step 1 needs (that is the
  step-2 sub-project, §8).

## 4. The reified model

Names are provisional. The hidden seam the current engine already obeys — the
fill pass consumes `title/group*/detail/summary/noData`, while the layouter
treats `page*/column*/background` as page furniture — becomes explicit:

```
ReportDefinition                       (replaces ReportTemplate as the serialized model)
├─ name, page, parameters[], variables[]
├─ furniture: PageFurniture            ← record-blind; repeats per page
│   ├─ pageHeader:   Band?
│   ├─ pageFooter:   Band?
│   ├─ columnHeader: Band?  (reserved; not laid out today)
│   ├─ columnFooter: Band?  (reserved)
│   └─ background:   Band?  (reserved)
└─ body: ReportBody                    ← data-driven content
    ├─ title:   Band?                  (once, at start)
    ├─ summary: Band?                  (once, at end)
    ├─ noData:  Band?                  (when the data set is empty)
    └─ root:    DetailScope            (the master/root scope)

DetailScope {
  id,
  collectionField: String?,            // null = master/root scope
  groups:   GroupLevel[],              // groups scoped to THIS scope (root.groups = master-level)
  children: ScopeNode[],               // ORDERED, heterogeneous (preserves interleaving)
}

// A scope's content is an ordered list of either a per-row band or a nested scope,
// so "meta band -> lines scope -> total band" ordering is preserved.
sealed ScopeNode = BandNode(Band) | NestedScope(DetailScope)

GroupLevel {
  id, name, key: Expression,
  header: Band?, footer: Band?,
  keepTogether, reprintHeaderOnEachPage, startNewPage,
}

Band { id, height, elements: ReportElement[] }   // every band has a stable id
```

**Why this shape**
- *Roles stated.* A group's flags live on its `GroupLevel` (one home → the
  two-bands smell is structurally gone). Scope nesting is the `DetailScope`
  tree, not sibling position. Page furniture is visibly record-blind.
- *General enough for the hard scenarios.* Per-scope `groups[]` ⇒
  intra-collection grouping is representable; ordered `children` ⇒ multiple
  per-row bands interleaved with sub-scopes is representable.
- *Stable ids everywhere* ⇒ band lifecycle and selection stop depending on
  list index.

**Model invariants (validated at construction / by the editor)**
- A `GroupLevel.key` must parse; group ids/names unique within a scope.
- `furniture.*` and `body.title/summary/noData` bands carry **no field
  bindings** that require a row (they are record-blind); flagged at author time
  instead of as a late render diagnostic.
- `collectionField` on a nested scope must name a collection in the data schema
  at that scope (when a schema is attached).

## 5. Capability matrix (general model vs step-1 engine)

| Scenario | Model represents | Step-1 engine renders |
|---|---|---|
| Multi-level grouping at master level | ✅ | ✅ (today's `groups[]` cascade) |
| Arbitrary-depth nested detail (master/detail) | ✅ | ✅ (today's `children`/`collectionField`) |
| Master-level groups + nested detail combined | ✅ | ✅ |
| **Grouping inside a nested collection** (per-scope groups) | ✅ | ❌ deferred (§6) |
| **Multiple per-row bands in one scope** | ✅ | ❌ deferred (§6) |
| **Aggregation over nested child rows** | ✅ (variables addressable per scope later) | ❌ deferred (§6) |
| Record-aware page header/footer | n/a (furniture stays record-blind) | ❌ separate concern (§6) |

## 6. Deferred to later specs (representable now, rendered later)

1. **Per-scope grouping** — the fill pass currently advances the variable
   calculator once per *master* row and detects breaks only there
   ([report_filler.dart](../../../packages/jet_print/lib/src/rendering/fill/report_filler.dart)).
   Rendering `DetailScope.groups` on a nested scope needs per-scope break
   detection.
2. **Aggregation over nested rows** — variables are master-scoped today
   (filler comment: aggregates fold over data-source rows, not child rows).
3. **Multiple per-row bands per scope** — the engine emits one detail band per
   matching type today; rendering several requires ordered multi-band emission.
4. **Record-aware page chrome** — optional; would let `pageHeader/pageFooter`
   reference the current record (JasperReports-style). Kept out of furniture's
   contract for now.

Because the model already carries these shapes, none requires another schema
bump when the engine grows into them.

## 7. Serialization & migration

- Bump `kReportSchemaVersion` 1 → 2
  ([report_codec.dart](../../../packages/jet_print/lib/src/domain/serialization/report_codec.dart)).
- Ship one `SchemaMigration` (`fromVersion: 1`) implementing the v1→v2 map
  ([migration.dart](../../../packages/jet_print/lib/src/domain/serialization/migration.dart)
  already chains these). The migration is a **pure map→map transform**:

  | v1 (flat bands) | v2 (tree) |
  |---|---|
  | `type: pageHeader/pageFooter/columnHeader/columnFooter/background` | `furniture.*` |
  | `type: title/summary/noData` | `body.title/summary/noData` |
  | `groups[]` (template-level) | `body.root.groups[]` |
  | `type: groupHeader/groupFooter` with `group: G` | folded into `body.root.groups[G].header/footer` |
  | `type: detail`, `collectionField: null` (master) | a `BandNode` in `body.root.children`, in original order |
  | `type: detail`, `collectionField: C` | a `NestedScope(DetailScope{collectionField: C, …})` in `children`, in original order |
  | `band.children[]` (nested) | recursively, the nested scope's `children` |
  | (assign) | a fresh stable `id` per band/group/scope |

  Master-level band/sub-scope **order is preserved** by emitting `children` in
  the v1 band order — this is exactly why `ScopeNode` is an ordered heterogeneous
  list (§4).
- The migration is **lossless for all v1 documents** (every v1 construct has a
  v2 home). A round-trip test (`decode(v1) → encode(v2) → decode(v2)`) plus a
  golden render-equality test (v1-rendered == migrated-v2-rendered) lock it.

## 8. Engine strategy & decomposition

**The engine consumes the new model natively (D3).** No lowering and no
permanent legacy IR: `ReportFiller` and `ReportLayouter` are **rewritten** to
traverse the `ReportDefinition` tree directly. Because the library is
pre-deployment, the rewrite is acceptable and there is no need for a
backward-compat bridge. The byte-identical guarantee therefore rests on a
**faithful rewrite locked by the existing render goldens** (§9), not on reusing
the old back-end.

`ReportTemplate` is **removed**, not kept as an IR. The designer is deeply
coupled to it (the controller, ~15 edit commands, canvas, Properties/Outline
panels, selection), so migrating the designer to `ReportDefinition` is part of
the *same* reification — there is no bridge to keep the old designer alive
between phases. One speckit feature, phased plan:

1. **Domain + serialization** — `ReportDefinition` tree types (§4) with
   construction invariants; v2 codec + 1→2 migration (§7). No engine/designer
   yet; unit + round-trip tests.
2. **Native engine** — rewrite fill + layout to consume the tree; today's
   semantics only (§5). Locked byte-identical by the render goldens (§9).
3. **Designer migration** — controller/commands/selection/panels/canvas author
   `ReportDefinition`; band lifecycle (add/remove/reorder/retype via stable
   ids); first-class groups & scopes with their own inspector (kills the
   two-bands smell); author-time validation (§4 invariants).

**Separate future features (not this spec):** the §6 deferred engine
capabilities — per-scope grouping, nested aggregation, multiple per-row bands,
optional record-aware chrome — each its own speckit feature once the tree is in
place.

## 9. Testing strategy

- **Goldens (byte-identical):** the existing render goldens must stay
  byte-identical after the native-engine phase (the headline guarantee).
- **Engine equivalence:** for representative reports (incl. the invoice sample —
  page chrome + per-invoice group header/footer + nested lines) the rewritten
  fill+layout produce the same `PageFrame`s as today; captured as goldens
  carried over from the current fixtures.
- **Migration:** v1→v2 lossless round-trip; golden equality of a v1 report vs
  its migrated v2 form across canvas/preview/PDF/PNG.
- **Model:** construction invariants (§4) — unique ids/names, record-blind
  furniture rejects field bindings, parseable group keys.
- **TDD throughout** (project constitution: Test-First, non-negotiable).

## 10. Resolved decisions

1. **Engine — native (no lowering).** The engine is rewritten to consume
   `ReportDefinition` directly; `ReportTemplate` is removed. Acceptable because
   the library is pre-deployment (dev-phase rewrite); goldens lock byte-identity.
2. **Naming — keep** `ReportDefinition` / `DetailScope` / `ScopeNode` /
   `BandNode` / `NestedScope` / `GroupLevel` / `PageFurniture`.
3. **Furniture — reserve.** `columnHeader` / `columnFooter` / `background` stay
   as reserved slots; multi-column support is a future addition.
4. **Spec location — speckit.** The implementation spec/plan/tasks live under
   `specs/NNN-feature/` via the project's speckit flow.
```
