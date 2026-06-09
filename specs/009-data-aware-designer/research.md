# Phase 0 Research: Data-Aware Designer (Invoice MVP)

**Feature**: 009-data-aware-designer | **Date**: 2026-06-09

This iteration has no unknown technologies — it builds on the existing model, designer (003), data layer, expression engine, and serialization. The "research" is therefore a set of **design decisions** resolving how to wire data-binding authoring into what already exists, grounded in a full read of the current code. Each decision lists what was chosen, why, and the alternatives rejected.

---

## D1 — Master/detail representation: recursive data bands

**Decision**: Add two **additive-optional** fields to `ReportBand`:
- `String? collectionField` — the name of the nested-collection field this band iterates (null ⇒ the band is in the master scope).
- `List<ReportBand> children` — bands nested *within* this band's (child) scope; default `const []`.

A band with `collectionField != null` establishes a child scope; its `children` (and its own `elements`) resolve against that scope. Nesting `children` recursively gives **arbitrary-depth** master/detail (invoice → lines → sub-lines) for free.

**Rationale**: This is the idiomatic "detail report band" model (JasperReports subreport / DevExpress DetailReportBand). It composes cleanly with the existing flat `bands` list (top-level bands stay the page structure; only data bands grow children), serializes as nested `children` arrays under the **pre-1.0 carve-out** (no schema bump, no migration — `schemaVersion` stays `1`), and keeps the recursion localized to four places: the codec (`_encodeBand`/decode recurse), the design-time layout (nested regions), the outline tree (already a tree), and the two new edit commands.

**Alternatives rejected**:
- *Flattened single dataset + grouping* (header repeats per row; `ReportGroup` break = master). The engine already supports this, but the spec's clarification explicitly chose a **nested-collection field type**, and flattening cannot represent arbitrary depth naturally.
- *Flat bands + `parentBandId` references.* Avoids making `ReportBand` recursive, but requires introducing stable band **ids** across the whole model (selection, outline, codec) and rebuilding the tree from references on every read — broader churn than this slice needs.
- *Separate top-level nested-dataset registry on `ReportTemplate`.* Heavier; duplicates structure that the recursive `FieldDef` already expresses; the clarification ruled it out.

---

## D2 — The nested-collection field type: `JetFieldType.collection` + recursive `FieldDef`

**Decision**:
- Add `collection` to `JetFieldType` ([value_type.dart](../../packages/jet_print/lib/src/domain/value_type.dart)).
- Make `FieldDef` **recursive**: add `final List<FieldDef> fields` (default `const []`), meaningful only when `type == JetFieldType.collection` (it carries the collection's child schema).

**Rationale**: Reuses the existing coarse type taxonomy that both the `data` and `domain` seams already share, so it stays pure Dart and inward-only (layer-boundary test unaffected). A `collection` field whose `fields` are themselves potentially `collection`-typed expresses arbitrary nesting with one recursive type — matching D1. `FieldDef.inferType` keeps returning scalar types for flat values; `collection` is **declared**, not inferred (a nested `List`/child source isn't a scalar column).

**Alternatives rejected**:
- *A distinct `CollectionFieldDef` subtype.* `FieldDef` is currently a plain final class with value-equality; subtyping complicates equality, codec dispatch, and the schema tree. A single recursive class is simpler and round-trips trivially.
- *Encoding nesting as a separate parallel structure.* Splits one concept (a field that is a collection) across two types; harder to keep consistent.

---

## D3 — Attaching structure: `JetDataSchema`, host-supplied, not embedded

**Decision**: Introduce a public **`JetDataSchema`** = `{ String name; List<FieldDef> fields }` (the dataset's display name + its root field tree). The host builds it and passes it to `JetReportDesigner(dataSchema: ...)`. It is **not** serialized into the `ReportTemplate` (spec Q2). A new `DesignerSchemaScope` (`InheritedWidget`) provides it to the panels and canvas, mirroring the existing `DesignerScope` pattern.

**Rationale**: Tokens-only needs **structure, not rows**, so a lightweight schema descriptor is the right abstraction — the designer never opens a cursor or touches data. Keeping the schema host-supplied (not embedded) keeps report files portable and the structure host-owned, and directly delivers FR-019a (reopen without source → tokens persist, tree empty). It also keeps the public surface minimal (Constitution I): we expose only `FieldDef` + `JetDataSchema`; the data-bearing `JetDataSource`/`DataSet`/`DataRow` stay internal until the render slice needs them.

**Alternatives rejected**:
- *Pass a live `JetDataSource` and read `.open().fields`.* Forces opening a cursor in the UI and exposing the whole data API prematurely; unnecessary when only structure is shown.
- *Embed the structure in the template.* Bloats report files, lets the embedded copy drift from the live source, and contradicts the chosen reopen behavior (Q2).

---

## D4 — Token display on the shared render pipeline (Constitution IV)

**Decision**: Do **not** modify `TextElementRenderer`. In the design-time frame builder ([design_time_frame.dart](../../packages/jet_print/lib/src/designer/canvas/design_time_frame.dart)), when an element is bound, emit a **display copy** whose visible text is a token derived from the binding (e.g. `«customerName»` / the raw expression), styled distinctly (muted/italic + delimiters). For a bound `ImageElement` (`FieldImageSource`), emit a design-time **placeholder** (icon + field token) instead of attempting to resolve bytes.

**Rationale**: Constitution IV forbids a parallel/divergent draw path. Feeding a token string through the **unchanged** `ElementRenderer`→`FrameBuilder`→`CanvasPainter` keeps the paint path single-sourced; the only new logic ("what string represents a bound element at design time") lives in the designer seam, which is allowed to know about design-time presentation. The same substitution feeds the committed `ui.Picture` and any golden, so canvas and goldens agree by construction.

**Alternatives rejected**:
- *Add binding awareness to `TextElementRenderer`.* Pushes design-time-only token formatting into the shared renderer, which must paint *resolved values* in the fill path — coupling design-time and fill concerns and risking divergence.
- *A separate overlay painter for tokens.* A second draw path — exactly what Constitution IV prohibits.

---

## D5 — Nested-band addressing: band paths

**Decision**: Address bands for editing/selection by a **path** (`List<int>` of child indices from the top-level band list) in the new commands and the extended `Selection`. Preserve the existing top-level `int` band-index API (`selectBand(int)`, `setBandHeight(int)`) for back-compat (a top-level band is the one-element path `[i]`).

**Rationale**: Arbitrary-depth nesting (D1) makes a single `int` index insufficient to identify a nested band. A path is the minimal, allocation-free addressing that the recursive `children` structure already implies, and it extends `Selection` without introducing model-wide band ids.

**Alternatives rejected**:
- *Stable band ids on every `ReportBand`.* Cleaner addressing in the abstract, but a model-wide change (selection, outline, codec, equality) far broader than this slice; deferred unless a later feature needs band identity beyond position.

---

## D6 — Binding interaction: drag-from-panel + Properties editor

**Decision**: Two complementary affordances (spec FR-011):
1. **Drag a field** from the Data Source panel onto the canvas. Field rows become `Draggable<FieldDragData>` (payload: field path + scope). The canvas gains a `DragTarget` that discriminates field drags from the existing `Draggable<DesignerToolType>` toolbox drags: dropping a field on empty band space creates a **bound text element**; dropping on an existing bindable element **binds** it.
2. **Properties-panel binding editor** for the selected element: a field picker (populated from the attached `JetDataSchema`, scope-aware), a free-form **expression** text input (`$F{}`/`$P{}`/`$V{}` + functions), and a **Clear** button. A band-selection shows a **collection-field** editor (designate which collection this band iterates).

Each edit calls a new controller method that wraps a command through the existing `_commit`/history mechanism, so binding/unbinding/collection-designation are fully **undoable**.

**Rationale**: Matches the existing 003 patterns exactly (toolbox `Draggable` + canvas `DragTarget` `_handleDrop`; Properties editors calling `controller.setGeometry`/`setText`). Reuses the immutable command/history machinery, giving undo/redo and cross-panel sync for free.

**Alternatives rejected**:
- *Drag-only* (no Properties editor): can't express free-form expressions or clear a binding cleanly.
- *Properties-only* (no drag): loses the fast, discoverable "drag a field onto the page" gesture the request emphasizes.

---

## D7 — Binding expressiveness & scope resolution

**Decision**: A text binding is stored in the existing `TextElement.expression` as either a single field reference (`$F{name}`, produced by a field drag) or a full expression typed by the author. An image binding is the existing `FieldImageSource(name)`. Scope is **derived, not stored**: an element resolves its fields against the **nearest enclosing collection-bound band** (child scope) or, absent one, the master scope. At authoring time the designer checks a binding's referenced fields against the in-scope schema and flags **unresolved** ones (missing field or wrong scope) per FR-018 — without evaluating anything (tokens only).

**Rationale**: The model already stores expressions as strings; no model change. Deriving scope from band nesting avoids a redundant per-element scope field and keeps the template minimal. The unresolved check is a pure structural comparison against `JetDataSchema` — no expression evaluation, consistent with tokens-only.

**Alternatives rejected**:
- *Store an explicit scope/dataset id per element.* Redundant with band nesting; another field to keep consistent and serialize.
- *Validate expressions by evaluating them.* Out of scope (no fill this iteration) and needs data.

---

## D8 — Localization of new chrome

**Decision**: Add new strings (panel empty state, "Binding"/"Expression"/"Field" labels, "Clear binding", "Bind to collection", unresolved-binding indicator/tooltip) to the three ARB files ([jet_print_en.arb](../../packages/jet_print/lib/src/designer/l10n/jet_print_en.arb), `_de.arb`, `_tr.arb`) and regenerate via `flutter gen-l10n` (the package has `flutter: generate: true` + `l10n.yaml`). The **invoice sample's field names** (e.g. `customerName`, `lineTotal`) are illustrative data and are **not** localized, consistent with the existing panel comment.

**Rationale**: Matches the established gen-l10n pipeline; English is the documented fallback. Generated `jet_print_localizations*.dart` files are excluded from the lint gate already.

**Alternatives rejected**: Hand-editing the generated Dart files (they are regenerated and overwritten).

---

## Summary of model/API deltas

| Change | Layer | Serialized? | Public? | Migration? |
|--------|-------|-------------|---------|------------|
| `JetFieldType.collection` | domain | n/a (schema not embedded) | yes (enum already exported) | no |
| `FieldDef.fields` (recursive) | data | only inside a `JetDataSchema` (host-side) | **newly exported** | no |
| `JetDataSchema` | data | **no** (host-supplied) | **new export** | no |
| `ReportBand.collectionField`, `.children` | domain | **yes** (additive-optional) | yes (`ReportBand` exported) | **no** (pre-1.0 carve-out) |
| `TextElement.expression` | domain | already serialized | already public | no |
| `FieldImageSource` | domain | already serialized | already public | no |
| `JetReportDesigner.dataSchema` | designer | n/a | **new param** | no |
| `setBinding`/`clearBinding`/`setBandCollection` + 2 commands | designer | n/a | **new methods** | no |
