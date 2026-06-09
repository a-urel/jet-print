# Contract: Data-Aware Designer Public API & Behavior

**Feature**: 009-data-aware-designer | **Date**: 2026-06-09

This is the authoritative contract for the public surface and observable behavior added by this slice. Signatures are the *intended* shape (Dart); exact names may be refined under TDD but the contract — what's public, what persists, what the user observes — is binding. Every section maps to spec FRs and to a test group (§ test-groups).

---

## 1. New / changed public symbols (exported from `lib/jet_print.dart`)

### 1.1 `JetFieldType.collection` (FR-002, FR-003)
```dart
enum JetFieldType { string, integer, double, boolean, dateTime, collection, unknown }
```
- `collection` denotes a field holding a child collection; its child schema is `FieldDef.fields`.
- Additive enum value; `JetFieldType` is already exported.

### 1.2 `FieldDef` — now public + recursive (FR-001, FR-002)
```dart
class FieldDef {
  const FieldDef(this.name, {this.type = JetFieldType.unknown, this.fields = const <FieldDef>[]});
  final String name;
  final JetFieldType type;
  final List<FieldDef> fields; // child schema; non-empty only when type == collection
  // value-equality includes fields (deep); dartdoc required.
}
```
- **Contract**: `fields` is empty unless `type == collection`. A `collection` with empty `fields` is valid (empty expandable node).

### 1.3 `JetDataSchema` — new (FR-001)
```dart
class JetDataSchema {
  const JetDataSchema({required this.name, required this.fields});
  final String name;            // dataset display name (tree root)
  final List<FieldDef> fields;  // root field tree
  // value-equality; dartdoc required.
}
```
- **Contract**: host-supplied; **never serialized** into a `ReportTemplate`. Describes structure only (no rows).

### 1.4 `JetReportDesigner.dataSchema` — new optional param (FR-005)
```dart
const JetReportDesigner({
  super.key,
  this.controller,
  this.initialReport,
  this.onSaveRequested,
  this.onOpenRequested,
  this.dataSchema,            // NEW: JetDataSchema?  — attach a data source's structure
});
```
- **Contract**: when `dataSchema` is non-null, the Data Source panel renders it; when null, the panel shows the **empty state** (FR-008). Changing `dataSchema` updates the panel and re-checks binding resolution.

### 1.5 `JetReportDesignerController` — new methods (FR-009..FR-017)
```dart
// Element binding (text → expression; image → FieldImageSource). Undoable.
void setBinding(String elementId, String expression);   // text element
void clearBinding(String elementId);                     // → static content
void setImageField(String elementId, String field);      // image element → FieldImageSource
// Band → collection (master/detail). bandPath addresses nested bands (D5). Undoable.
void setBandCollection(List<int> bandPath, String? collectionField);
// Convenience used by drag-to-bind (create a bound text element at a drop point).
void createBoundElement({required int bandIndex, required JetOffset at, required String expression});
```
- **Contract**: each method maps to exactly one `EditCommand` via `_commit(...)`, producing one undo/redo step and one `notifyListeners()`; a no-op edit pushes no history (consistent with existing `_commit`). `bandPath == [i]` addresses the top-level band `i` (back-compat with `setBandHeight(int)` etc.).

### 1.6 `ReportBand` — new fields (FR-015, FR-015a, FR-019)
```dart
const ReportBand({ required this.type, required this.height,
  this.elements = const [], this.group,
  this.collectionField,                 // NEW: String?
  this.children = const <ReportBand>[], // NEW: nested data bands
});
ReportBand copyWith({ ...existing..., String? collectionField, List<ReportBand>? children });
```
- **Contract**: `collectionField == null` ⇒ master scope. `children` recurse for arbitrary nesting.

### 1.7 Reused-as-is (already public, no change)
`TextElement.expression` (the text binding), `FieldImageSource` / `ImageElement` (the image binding), `JetReportFormat` (codec facade), `ReportTemplate`.

---

## 2. Serialization contract (FR-019, FR-019a; Constitution V)

- **`schemaVersion` stays `1`.** New `ReportBand` fields are additive-optional under the pre-1.0 carve-out — **no migration**.
- **Band encoding** adds: `if (collectionField != null) 'collectionField': collectionField`, and `if (children.isNotEmpty) 'children': [ <recurse _encodeBand> ]`. Decode mirrors this (absent ⇒ default).
- **Bindings are self-describing**: `TextElement.expression` and `FieldImageSource.field` already serialize and carry their own references. **No `JetDataSchema` is written.**
- **Round-trip**: `encode → jsonEncode → jsonDecode → decode` reproduces an equal template (incl. nested `children`, `collectionField`, bindings); `UnknownElement` passthrough preserved.
- **Reopen-without-source (FR-019a)**: decoding a template with no `dataSchema` attached yields a fully-bound template whose elements display tokens; the panel tree is empty until a schema is attached, after which unresolved bindings are flagged.

---

## 3. Behavior contracts

### 3.1 Data Source panel (FR-005..FR-008)
- Renders `JetDataSchema` as an expandable tree: root (dataset name) → fields; a `collection` field is an **expandable node** whose children are its `fields` (recursive). Each field row shows name + a type indicator. **No** hardcoded placeholder remains.
- Empty state (no `dataSchema`): a clear, localized message; **zero** field names shown.

### 3.2 Binding an element (FR-009..FR-014)
- **Drag**: dragging a leaf field onto empty band space creates a bound text element (`createBoundElement` with `$F{name}`); onto an existing bindable element, binds it. Dragging a `collection` (branch) node is a no-op.
- **Properties editor**: field picker (in-scope fields from the schema) + free-form expression input + **Clear**. Setting commits via `setBinding`/`setImageField`; Clear commits `clearBinding`.
- **Token display**: a bound element shows a token (delimited, visually distinct from literal text) rendered **through the shared `ElementRenderer`** (design-time frame substitutes a display copy). **No value evaluation.** A bound image shows a field-image placeholder.
- **Clear**: returns the element to its static content with no residual token.

### 3.3 Master/detail (FR-015..FR-018)
- `setBandCollection(path, field)` marks a band as iterating `field`; `null` clears it. Nesting a collection-bound band inside another establishes a deeper child scope.
- Elements inside a collection-bound band resolve fields against the **child** scope; elements outside resolve against **master**. Scope is derived from band nesting (not stored per element).
- **Unresolved**: a binding referencing a field absent from its scope (or wrong scope) is flagged **unresolved** and **preserved** (never dropped/blanked).

### 3.4 Persistence (FR-019, FR-019a) — see §2.

---

## 4. Architecture invariants (must stay green)

- **Encapsulation test**: consumers (playground, non-seam tests) import only `package:jet_print/jet_print.dart`. New public symbols (`FieldDef`, `JetDataSchema`) are re-exported there; everything else stays under `src/`.
- **Layer-boundary test**: `JetFieldType.collection`, `FieldDef`, `JetDataSchema`, `ReportBand` changes import no rendering/designer/Flutter; the token substitution lives in the `designer` seam; no new `dart:ui` import outside `paint/canvas_painter.dart`.
- **Lints**: zero analyzer warnings; `dart format` clean; dartdoc on all new public symbols; `directives_ordering`/`prefer_relative_imports` for `src/`.

---

## 5. Test groups (TDD — write first; map to FRs)

| # | Test group | Location | Covers |
|---|-----------|----------|--------|
| T1 | Recursive `FieldDef` + `JetDataSchema` (construction, equality, nested) | `test/data/` | FR-001..003 |
| T2 | `JetFieldType.collection` declared/not-inferred | `test/data/field_def_test.dart` | FR-002/003 |
| T3 | Codec round-trip: `collectionField` + nested `children` (+ existing `expression`) | `test/domain/serialization/` | FR-019, V |
| T4 | `ReportBand.copyWith` for new fields (non-destructive) | `test/domain/` | FR-015 |
| T5 | `SetBindingCommand` / `SetBandCollectionCommand` + undo/redo + no-op-no-history | `test/designer/controller/` | FR-009..017 |
| T6 | Data Source panel renders injected schema incl. nested collection; empty state | `test/designer/data_source_schema_tree_test.dart` | FR-005..008 |
| T7 | Drag field → bound element shows token; branch-node drag is no-op | `test/designer/canvas/drag_field_bind_test.dart` | FR-010, FR-011 |
| T8 | Properties binding editor: set field, set expression, clear | `test/designer/properties_binding_editor_test.dart` | FR-009, FR-011, FR-012 |
| T9 | Collection-bound band designation + arbitrary nesting + scope resolution | `test/designer/band_collection_binding_test.dart` | FR-015..017 |
| T10 | Unresolved binding flagged + preserved (missing field / wrong scope) | `test/designer/band_collection_binding_test.dart` | FR-018 |
| T11 | Reopen without source: tokens persist, tree empty | `test/designer/reopen_without_source_test.dart` | FR-019a |
| T12 | Localization (en/de/tr + fallback) for new chrome | `test/designer/localization*_test.dart` | FR-022 |
| T13 | Goldens: data-aware invoice design surface + populated panel (light/dark) | `test/designer/goldens/data_aware_invoice_test.dart` | IV |
| T14 | Encapsulation + layer-boundary stay green with new public/exported types | `test/` (existing) | I, II |
| T15 | Playground invoice sample compiles & attaches via public API only | `apps/jet_print_playground/test/` | FR-020, FR-021 |
