# Phase 1 Data Model: Data-Aware Designer (Invoice MVP)

**Feature**: 009-data-aware-designer | **Date**: 2026-06-09

Entities below are grouped by seam. **New** = created this slice; **Changed** = additive edit to an existing type; **Reused** = already exists, used as-is. All domain/data types are pure Dart (no Flutter), preserving the layer-boundary invariant.

---

## Schema / structure (data + domain seams)

### `JetFieldType` — *Changed* (domain)
Add one member to the existing coarse taxonomy.

| Member | Meaning |
|--------|---------|
| `string`, `integer`, `double`, `boolean`, `dateTime`, `unknown` | (existing) scalar tags |
| **`collection`** | **NEW** — a field that holds a child collection of records; its child schema lives in `FieldDef.fields` |

- Inference (`FieldDef.inferType`) is unchanged: it returns scalar types only. `collection` is **declared**, never inferred.

### `FieldDef` — *Changed* (data) — now recursive
| Field | Type | Notes |
|-------|------|-------|
| `name` | `String` | field name, referenced by `$F{name}` and `FieldImageSource.field` |
| `type` | `JetFieldType` | scalar or `collection` |
| **`fields`** | **`List<FieldDef>`** | **NEW**, default `const []`. The child schema; non-empty only when `type == collection`. Recursive ⇒ arbitrary nesting. |

- **Validation**: `fields` is empty unless `type == collection`. A `collection` field MAY declare zero children (displayed as an empty expandable node — edge case).
- **Equality**: value-equality extended to include `fields` (deep).
- **Public**: newly exported from `jet_print.dart`.
- **Terminology**: the spec's "decimal" scalar maps to the existing `JetFieldType.double` (fractional) — no new scalar type is added.

### `JetDataSchema` — *New* (data)
The host-supplied structure attached to the designer. **Not serialized** into the template.

| Field | Type | Notes |
|-------|------|-------|
| `name` | `String` | dataset display name (e.g. `"Invoice"`) shown as the tree root |
| `fields` | `List<FieldDef>` | root field tree (master fields + nested-collection fields) |

- Pure value type with value-equality; dartdoc'd; exported from `jet_print.dart`.
- Relationship: the designer’s **Data Source panel** renders this tree; **bindings** reference field names within it; **scope** resolution walks it via the band nesting.

---

## Report model (domain seam)

### `ReportBand` — *Changed* — gains collection binding + nesting
| Field | Type | Notes |
|-------|------|-------|
| `type`, `height`, `elements`, `group` | (existing) | unchanged |
| **`collectionField`** | **`String?`** | **NEW**, default `null`. The nested-collection field this band iterates; `null` ⇒ master scope. |
| **`children`** | **`List<ReportBand>`** | **NEW**, default `const []`. Bands nested within this band's child scope (recursive ⇒ arbitrary depth). |

- `copyWith` extended to cover both new fields, preserving non-destructiveness (FR-025 carryover).
- **Scope rule** (derived): a band's scope = its own `collectionField` if set, else its nearest enclosing ancestor band's scope, else master. Elements/`children` resolve fields against that scope.
- **Serialization**: additive-optional — `collectionField` written only when non-null; `children` written only when non-empty (recursing through `_encodeBand`). `schemaVersion` stays `1` (pre-1.0 carve-out). Round-trips losslessly.

### `TextElement` — *Reused* (the text binding)
- `expression: String?` (existing) **is** the text binding (`$F{}`/`$P{}`/`$V{}` + functions). A field drag stores `$F{name}`; the Properties editor may store any expression. Already serialized. No change to the type.

### `ImageElement` / `FieldImageSource` — *Reused* (the image binding)
- `ImageElement.source = FieldImageSource(field)` (existing) **is** the image binding. Already serialized (`{'kind':'field','field':name}`). No change to the types; the designer gains the UI to set/clear it and a design-time placeholder.

### `ReportTemplate` — *Reused* (unchanged)
- Holds `bands` (now possibly carrying `children`), `groups`, `parameters`, `variables`. **No** `dataSchema` field — structure is host-supplied (D3). No change.

### Out-of-scope element types
- `BarcodeElement.data`, `ShapeElement` — **no binding** this slice (barcode binding deferred). Unchanged.

---

## Designer-only types (designer seam — not serialized)

### `FieldDragData` — *New*
Payload for dragging a field from the Data Source panel onto the canvas.

| Field | Type | Notes |
|-------|------|-------|
| `fieldName` | `String` | the leaf field's name |
| `path` | `List<String>` | path from the schema root (for scope/diagnostics; e.g. `['lines','description']`) |
| `type` | `JetFieldType` | the field's type (drives default element kind: scalar → text; image-ish → image) |

- A `collection` (branch) node is **not** draggable to create an element (edge case: no-op).

### Binding scope (derived, not a stored entity)
- Computed at authoring time by walking the band nesting to the nearest `collectionField`. Used to (a) populate the Properties field picker with in-scope fields and (b) flag **unresolved** bindings (FR-018) — a pure structural check against `JetDataSchema`, no evaluation.

---

## Relationships (diagram)

```text
JetDataSchema (host-supplied, NOT serialized)
  name: "Invoice"
  fields: [ customerName:string, invoiceNo:string, date:dateTime, total:double,
            lines: COLLECTION
              fields: [ description:string, qty:integer, unitPrice:double, lineTotal:double,
                        subLines: COLLECTION  fields:[ ... ]  ]   ← arbitrary depth
          ]
        │  displayed by
        ▼
Data Source panel (tree)  ──drag field──►  Canvas / Properties
                                              │ creates/sets
                                              ▼
ReportTemplate (serialized)
  bands: [
    title/header     (master scope)   elements bound to $F{customerName}, $F{invoiceNo} ...
    detail            collectionField:"lines"        ← repeats per line
      elements: $F{description}, $F{qty}, $F{lineTotal}
      children: [
        detail        collectionField:"subLines"     ← nested master/detail
          elements: $F{...}
      ]
    summary          (master scope)   $F{total}
  ]
  (element bindings are self-describing → reopen without schema still shows tokens)
```

---

## State transitions (binding lifecycle)

```text
static element ──setBinding(expr)──► bound (token shown)
bound ──setBinding(newExpr)──► bound (token updated)
bound ──clearBinding()──► static element (token removed)
bound + field missing/out-of-scope ──► bound + UNRESOLVED indicator (binding preserved, FR-018)
band (master) ──setBandCollection(field)──► collection-bound band (child scope established)
collection-bound band ──setBandCollection(null)──► master-scope band
```
All transitions are `EditCommand`s applied via `controller._commit(...)`, so each is a single undo/redo step and notifies listeners for cross-panel sync.
