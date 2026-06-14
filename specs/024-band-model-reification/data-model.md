# Phase 1 Data Model — Band Model Reification

Domain-layer types (no Flutter/rendering imports). All are immutable value types
with `==`/`hashCode`, `copyWith`, and `toJson`/`fromJson` (via the codec).
Provisional names from the approved design; confirmed in /clarify.

## Entities

### ReportDefinition (root; replaces ReportTemplate)

| Field | Type | Notes |
|---|---|---|
| `name` | String | Human-readable report name |
| `page` | PageFormat | Unchanged domain type |
| `parameters` | List\<ReportParameter\> | Unchanged |
| `variables` | List\<ReportVariable\> | Unchanged shape, except `resetGroup` now holds a **GroupLevel id** (FR-003a) |
| `furniture` | PageFurniture | Record-blind, per-page chrome |
| `body` | ReportBody | Data-driven content |

### PageFurniture

| Field | Type | Notes |
|---|---|---|
| `pageHeader` | Band? | Laid out per page |
| `pageFooter` | Band? | Laid out per page |
| `columnHeader` | Band? | **Reserved** — not laid out (future multi-column) |
| `columnFooter` | Band? | **Reserved** |
| `background` | Band? | **Reserved** |

All furniture bands are **record-blind**: page-scoped substitution only
(`PAGE_NUMBER`/`PAGE_COUNT`/params); no `$F{}` field bindings (validated).

### ReportBody

| Field | Type | Notes |
|---|---|---|
| `title` | Band? | Printed once at start (no row context) |
| `summary` | Band? | Printed once at end (final variable snapshot) |
| `noData` | Band? | Printed when the data set is empty |
| `root` | DetailScope | The master/root scope (`collectionField == null`) |

### DetailScope

| Field | Type | Notes |
|---|---|---|
| `id` | String | Stable id |
| `collectionField` | String? | `null` ⇒ master/root scope; non-null ⇒ iterates that nested collection |
| `groups` | List\<GroupLevel\> | Outermost-first; `root.groups` are the master-level groups. *(Rendered only on `root` in this feature; per-scope grouping on non-root scopes is representable but deferred.)* |
| `children` | List\<ScopeNode\> | **Ordered, heterogeneous** — preserves band/sub-scope interleaving |

### ScopeNode (sealed)

```
sealed ScopeNode
  ├─ BandNode    { band: Band }            // a per-row band in this scope
  └─ NestedScope { scope: DetailScope }    // a nested collection scope
```

Ordered within `DetailScope.children` so "meta band → lines scope → total band"
order survives migration and editing.

### GroupLevel (replaces ReportGroup)

| Field | Type | Notes |
|---|---|---|
| `id` | String | Stable id — **the reference target for `ReportVariable.resetGroup`** (FR-003a) |
| `name` | String | Display label only (no longer the reference key) |
| `key` | String (expression) | Grouping-key expression; must parse |
| `header` | Band? | Group header |
| `footer` | Band? | Group footer |
| `keepTogether` | bool = false | Pagination flag |
| `reprintHeaderOnEachPage` | bool = false | Pagination flag |
| `startNewPage` | bool = false | Pagination flag (the 023 feature, now owned here) |

### Band

| Field | Type | Notes |
|---|---|---|
| `id` | String | Stable id (selection + lifecycle no longer index-based) |
| `type` | BandType | Retained (Q1) — labels/glyphs/identity/migration; validated consistent with slot |
| `height` | double | Designed height |
| `elements` | List\<ReportElement\> | Unchanged element model |

## Invariants

Structural (unrepresentable by construction): a furniture slot is one `Band?`;
a `GroupLevel` owns its header/footer; scope contents are typed `ScopeNode`s.

Semantic (returned by non-throwing `validate()`; surfaced as author-time
diagnostics — research §2):

- **I1** All `Band.id`, `GroupLevel.id`, `DetailScope.id` are unique within the
  definition.
- **I2** `GroupLevel.name` unique within its owning scope.
- **I3** `GroupLevel.key` parses as an expression.
- **I4** `furniture.*`, `body.title`, `body.summary`, `body.noData` bands carry
  no record-dependent (`$F{}`) bindings (record-blind).
- **I5** Each `Band.type` is consistent with its slot (e.g. `furniture.pageHeader`
  → `pageHeader`; a `GroupLevel.header` → `groupHeader`; a `BandNode` in a scope
  → `detail`; `body.title` → `title`; …).
- **I6** A non-root `DetailScope` has a non-null `collectionField`; `root` has
  `collectionField == null`.
- **I7** `validate()` emits an **info** diagnostic (not an error) for
  representable-but-not-yet-rendered shapes (FR-005): a non-root `DetailScope`
  with non-empty `groups`, or a scope whose `children` hold more than one
  `BandNode`.

## Migration mapping (v1 → v2)

| v1 (flat band / template) | v2 (tree) |
|---|---|
| `type: pageHeader` / `pageFooter` | `furniture.pageHeader` / `pageFooter` |
| `type: columnHeader` / `columnFooter` / `background` | `furniture.columnHeader` / `columnFooter` / `background` (reserved) |
| `type: title` / `summary` / `noData` | `body.title` / `summary` / `noData` |
| template `groups[]` (ordered) | `body.root.groups[]` (same order), each gets a fresh id |
| `type: groupHeader` with `group: G` | `body.root.groups[G].header` |
| `type: groupFooter` with `group: G` | `body.root.groups[G].footer` |
| `type: detail`, `collectionField: null` | `BandNode(band)` appended to `root.children` in v1 order |
| `type: detail`, `collectionField: C` | `NestedScope(DetailScope{collectionField: C, children:[…]})` appended to `root.children` in v1 order |
| `band.children[]` (nested) | recursively the nested scope's `children` |
| `ReportGroup.keepTogether/reprintHeaderOnEachPage/startNewPage` | same flags on `GroupLevel` |
| `ReportVariable.resetGroup: "G"` (name) | rewritten to the new `GroupLevel("G").id` |
| (assign) | deterministic stable `id` per band/group/scope (research §5); `Band.type` set from the v1 type |

Lossless: every v1 construct has a v2 home; `root.children` order = v1 band
order ⇒ a migrated report renders byte-identically (FR-008).

## Stable id scheme

Ids are deterministic and path-based, so a given tree shape always yields the
same ids (migration is reproducible; goldens stable):

- root scope = `root`; a child scope at `children[i]` = `<parentScopeId>/c<i>`
- a per-row band (`BandNode` at `children[i]`) = `<scopeId>/c<i>`
- furniture bands = `furniture/<slot>` (e.g. `furniture/pageHeader`)
- body singletons = `body/title` | `body/summary` | `body/noData`
- a group at `groups[i]` = `<scopeId>/g<i>`; its bands = `<groupId>/header` | `<groupId>/footer`

The v1→v2 migration assigns ids by this scheme (reproducible output). The
designer mints fresh, suffix-incremented ids for newly created nodes (the
existing `ElementIdFactory` pattern).

## State transitions (designer editing — Phase 3)

- **Add band**: insert a `BandNode` into a scope's `children`, a furniture slot,
  or a `GroupLevel.header/footer`; mint a fresh id; `type` set from the target
  slot.
- **Remove / reorder band**: remove or reorder within `children` (ids stable).
- **Retype band**: move the band to a different slot; `type` updated to match
  (FR-001a / FR-012).
- **Create / delete group**: add/remove a `GroupLevel` on a scope (outermost-first
  order); variables referencing a deleted group's id are flagged by `validate()`.
- **Create / delete scope**: add/remove a `NestedScope` (with a `collectionField`).
- All edits are single undoable commits (existing history model, FR-015).
