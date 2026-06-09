# Feature Specification: Invoice MVP — Data-Aware Designer (Bindable Datasets & Master/Detail Authoring)

**Feature Branch**: `009-data-aware-designer`
**Created**: 2026-06-09
**Status**: Draft
**Input**: User description: "create invoice sample: create invoice datasource in demo app, display data structure in designer, support data aware report elements. We need to cover master/detail data structure to represent invoice lines."

## Overview

Today the report designer is **structure-only**: it lets an author place and arrange elements, but those elements carry no data. The Data Source panel shows a **hardcoded placeholder** dataset that is disconnected from anything real, and there is no way for an author to make an element show a value from a data source.

This feature makes the designer **data-aware**. A host application can describe the **structure** of a data source — its datasets and typed fields, including **nested collections** — and hand it to the designer. The designer then **displays that real structure** (replacing the placeholder), and authors can **bind** report elements to fields so the elements become data-driven. Crucially, the data structure supports a **master/detail** shape: an invoice (master record) carries a **nested collection of line items** (the detail), and a band can be bound to that collection to represent the repeating lines.

The concrete proof is an **invoice sample** in the demo/playground app: the app defines an invoice data source through the library's public API and ships a sample invoice template demonstrating master/detail bindings.

This is the **authoring surface** for data binding. At design time, bound elements show a **field token / placeholder** (e.g. the field name or expression) — they are visibly "bound," but the designer does **not** fill the template with real values or render a data-filled result in this iteration. Rendering filled, paginated output (and exposing the fill/export engine publicly) is the separate engine export slice and is explicitly out of scope here.

## Out of Scope *(deferred to later specs)*

- **Filling / previewing the report with real data values.** No data-filled, paginated render of the report appears in the UI this iteration; bound elements display tokens only. The data-filled render/export is the engine export slice.
- **Exposing the expression evaluator and fill engine as public API.** Only the data-source *structure description* and the *binding* vocabulary become public here; evaluation/rendering stays internal.
- **Live / queryable data backends.** The data source is an in-memory, structural description supplied by the host; no database connections, network fetches, queries, or credentials.
- **A visual expression/formula builder.** Binding is by field selection plus a basic free-form expression text input — not a graphical formula designer or auto-complete/validation of expression syntax.
- **Barcode value binding.** Barcode elements stay static this iteration; binding a barcode's value to a field is deferred (only text and image elements are data-aware here).
- **Band & group structure editing and page setup** beyond what is needed to designate a band as collection-bound (the broader band/group editor remains its own concern).
- **Multiple simultaneous data sources** and source-to-source joins. One attached data-source structure at a time.

## Clarifications

### Session 2026-06-09

- Q: How should the invoice master/detail structure be represented? → A: Via a **nested-collection field type** — the master record carries a field whose type is a collection (the invoice's line items), and that field exposes its own child field schema. (Not a separate top-level nested-dataset registry; not a flattened single table.)
- Q: What should data-aware elements show inside the designer at design time? → A: **Tokens only** this iteration — bound elements show a field token / placeholder; filling and rendering real data is deferred.
- Q: Identity/number for this spec given 009 was earmarked for the engine export slice → A: This **is** the 009 invoice-MVP slice, delivered designer-first; the engine export/render path follows later.
- Q: How expressive is an element binding this iteration? → A: **Field or expression** — an author may bind to a single field or to a full expression (`$F{field}`/`$P{param}`/`$V{var}` + functions) entered as text; the token shows the expression, and a dragged field becomes a simple field reference.
- Q: What does the designer show when a saved report is reopened without its data source re-attached? → A: **Tokens persist, structure tree empty** — bindings are self-describing and stored in the template (the data-source structure is NOT embedded); the tree stays empty until a source is attached, then bindings resolve.
- Q: What master/detail nesting depth does this iteration author and test? → A: **Arbitrary depth** — collections nested within collections (e.g. invoice → lines → sub-lines) are a first-class authoring scenario; a collection-bound band may contain a deeper collection-bound band.
- Q: Which element types accept data bindings this iteration? → A: **Text + Image** (text → field/expression; image → field image source). Barcode value binding is deferred.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the real data structure in the designer (Priority: P1)

A report author opens the designer with a data source attached (the invoice source). The Data Source panel shows the **actual structure** of that source as an expandable tree: the invoice dataset and its typed fields, and — nested beneath it — the **line-items collection** with its own child fields. The author can read, at a glance, exactly what data they can bind to. The previous hardcoded placeholder is gone.

**Why this priority**: Authors cannot bind to data they cannot see. Surfacing the true structure (including the master/detail hierarchy) is the foundation every binding action depends on, and it is independently valuable: it tells the author what the report can contain.

**Independent Test**: Attach the invoice data source to the designer; confirm the Data Source panel lists the invoice's fields with their types, shows a "lines" node that expands to reveal the line-item fields, and that no placeholder dataset (e.g. the old `SalesDB`/`Orders`) remains.

**Acceptance Scenarios**:

1. **Given** an invoice data source is attached, **When** the author opens the Data Source panel, **Then** the panel lists the invoice dataset and each of its fields with a name and a type indicator.
2. **Given** the invoice structure includes a nested line-items collection, **When** the author expands the collection field node, **Then** the child line-item fields (e.g. description, quantity, unit price) are shown nested beneath it.
3. **Given** no data source is attached, **When** the author opens the Data Source panel, **Then** an unambiguous empty state is shown and no stale/placeholder field names appear.

---

### User Story 2 - Bind an element to a data field (Priority: P1)

A report author makes an element data-driven. They drag a field from the Data Source panel onto the canvas to create (or target) a bound element, or they select an existing element and set its binding from the Properties panel. The bound element now shows a recognizable **field token** (e.g. the field name / expression) instead of static text, visibly distinct from literal content. The author can also clear a binding to return the element to static content. Bindings are saved with the template and survive reopening.

**Why this priority**: Binding is the core "data-aware element" capability and the headline of the request. With Story 1 (see the data) and Story 2 (bind to it), an author can express a data-driven report layout — the MVP of a data-aware designer.

**Independent Test**: With the invoice source attached, drag the invoice's customer-name field onto the canvas; confirm a bound text element appears showing a customer-name token. Select it, clear the binding, confirm it reverts to static. Re-bind, save, reopen — confirm the binding is intact.

**Acceptance Scenarios**:

1. **Given** the Data Source panel shows a field, **When** the author drags that field onto a band on the canvas, **Then** a bound element is created showing that field's token.
2. **Given** an element is selected, **When** the author sets a field/expression binding in the Properties panel, **Then** the element displays the corresponding token and is marked as bound.
3. **Given** a bound element, **When** the author clears its binding, **Then** the element returns to static content with no residual token.
4. **Given** elements with bindings, **When** the author saves and reopens the template, **Then** every binding is preserved exactly.

---

### User Story 3 - Represent invoice lines with master/detail (Priority: P2)

A report author lays out an invoice: header fields (invoice number, customer, date, totals) in the master area, and a **line-items section** that represents the repeating invoice lines. The author designates a band as **bound to the line-items collection**, then places elements inside it bound to the line fields (description, quantity, unit price, line total). The relationship between the master record and its detail collection is captured in the template so it is unambiguous which scope each binding resolves against. Everything round-trips losslessly through save/open.

**Why this priority**: Master/detail is explicitly called out in the request and is what distinguishes an invoice from a flat record. It builds directly on Stories 1–2 but is separable: the binding mechanics work without it, and master/detail adds the repeating-collection authoring on top.

**Independent Test**: Designate a band as bound to the invoice's line-items collection; place line-field-bound elements inside it and header-field-bound elements outside it; confirm the template records which band represents the detail collection and that each element's binding resolves against the correct scope (master vs. line); save and reopen with the structure intact.

**Acceptance Scenarios**:

1. **Given** the invoice structure has a nested line-items collection, **When** the author designates a band as bound to that collection, **Then** the band is marked as the detail/collection-bound band for the invoice lines.
2. **Given** a collection-bound band, **When** the author binds elements inside it to line-item fields, **Then** those bindings resolve against the line-item (child) scope.
3. **Given** header elements outside the collection-bound band, **When** they are bound to invoice (master) fields, **Then** those bindings resolve against the invoice (master) scope.
4. **Given** a complete master/detail layout, **When** the author saves and reopens, **Then** the master/detail relationship and all bindings are unchanged.
5. **Given** a collection field whose child schema itself contains a nested collection, **When** the author places a collection-bound band inside another collection-bound band, **Then** the inner band resolves against the deeper child scope (e.g. line → sub-line), and the nesting survives save/open.

---

### User Story 4 - Run the invoice sample in the demo app (Priority: P3)

A developer evaluating the library launches the demo/playground app. The app has defined an **invoice data source** — invoice master record plus a nested line-items collection — entirely through the library's **public API**, attached it to the designer, and ships a **sample invoice template** with master/detail bindings already in place. The developer immediately sees a realistic, data-aware invoice being authored, proving the public data API is sufficient for a real consumer.

**Why this priority**: The demo is the showcase and the public-API proof, but the reusable library capability (Stories 1–3) is the actual product. The sample makes the feature tangible and verifies Constitution I (consumers use only the public API).

**Independent Test**: Launch the playground; confirm the Data Source panel shows the invoice structure (master fields + nested lines), and the bundled sample invoice template loads with its bound elements visible as tokens — all without the app reaching into library internals.

**Acceptance Scenarios**:

1. **Given** the playground app, **When** it starts, **Then** the designer shows the invoice data source structure (master + nested lines).
2. **Given** the playground app, **When** the developer opens the bundled sample invoice template, **Then** it loads with master and line bindings shown as tokens.
3. **Given** the app defines the invoice source and sample, **When** the code is inspected, **Then** it uses only the library's public entry point (no private/internal access).

---

### Edge Cases

- **Stale binding**: a bound element references a field that does not exist in the attached source (e.g. the source was swapped for a different schema). The element keeps its binding (non-destructive) and is indicated as **unresolved** rather than silently dropped or blanked.
- **Scope mismatch**: a binding to a line-item (child) field placed outside a collection-bound band, or a master field bound inside one, is surfaced as unresolved/invalid rather than guessed.
- **Empty nested collection schema**: a collection field with no declared child fields displays as an expandable node with no children (not an error).
- **Dragging a non-bindable node** (e.g. a dataset/branch node rather than a leaf field) onto the canvas is a no-op.
- **Binding an inherently non-text element** (e.g. a shape) — only element types declared data-aware accept bindings; others ignore/refuse the drop.
- **Switching the attached data source** at runtime updates the displayed structure; existing bindings are matched by name where possible and flagged where not.
- **Deeply or multiply nested collections**: the structure may declare more than one collection, or a collection within a collection. The panel displays them all, and a collection-bound band may itself contain a deeper collection-bound band — so collections nested to arbitrary depth (e.g. invoice → lines → sub-lines) are authorable, each level resolving against its own child scope. A given band still binds to at most one collection (its immediate child).

## Requirements *(mandatory)*

### Functional Requirements

**Describing & attaching data structure (public API)**

- **FR-001**: The system MUST provide a public way for a host application to describe a data source's **structure** — a dataset and its fields, each field having a name and a type — and to attach that structure to the designer.
- **FR-002**: The field-type vocabulary MUST include a **nested-collection** type: a field whose value is a collection of child records and which carries its own child field schema (used to model invoice → line items).
- **FR-003**: The field-type vocabulary MUST cover at least text, integer, decimal, boolean, and date/time scalar types in addition to the nested-collection type, consistent with the existing field-type set.
- **FR-004**: All capability a consumer needs to define and attach a data source and bind elements MUST be reachable through the library's single public entry point; the demo app MUST consume it as an external consumer with no access to private internals.

**Displaying the structure in the designer**

- **FR-005**: The Data Source panel MUST display the structure of the attached data source as an expandable tree, **replacing** the previous hardcoded placeholder dataset.
- **FR-006**: A nested-collection field MUST be displayed as an expandable node whose children are the collection's fields, so the invoice's line items appear nested beneath the invoice.
- **FR-007**: Each field MUST display its name and a type indicator (icon and/or label) consistent across the panel.
- **FR-008**: When no data source is attached, the panel MUST present a clear empty state and MUST NOT show stale or placeholder field names.

**Binding elements (data-aware, tokens)**

- **FR-009**: An author MUST be able to bind a text element to a data field or expression so its content is data-driven.
- **FR-010**: A bound element MUST display a recognizable field token / placeholder at design time (e.g. the field name or expression), visually distinct from static literal content.
- **FR-011**: An author MUST be able to create/establish a binding by **dragging a field** from the Data Source panel onto an element/band on the canvas, **and** by editing the binding from the **Properties panel** for a selected element. The Properties-panel binding editor MUST accept either a single chosen field or a free-form expression (`$F{}`/`$P{}`/`$V{}` + functions); a dragged field is stored as a simple field reference.
- **FR-012**: An author MUST be able to **clear** a binding, returning the element to static content with no residual token.
- **FR-013**: Image elements MUST support binding to a field as their image source (leveraging the existing field-image capability), shown as a token/placeholder at design time.
- **FR-014**: The system MUST NOT evaluate bindings or render real data values in the designer this iteration; bound elements display tokens only.

**Master/detail authoring**

- **FR-015**: An author MUST be able to designate a band as **bound to a nested-collection field** so the band represents the repeating child rows (the invoice lines).
- **FR-015a**: Collection-bound bands MUST be **nestable** to arbitrary depth — a collection-bound band may contain a further collection-bound band bound to a collection field of its own child scope (e.g. invoice → lines → sub-lines) — so arbitrarily deep master/detail can be authored. Each band binds to at most one collection (its immediate child scope).
- **FR-016**: Elements inside a collection-bound band MUST be bindable to the child collection's fields (e.g. line description, quantity, unit price), and those bindings MUST resolve against the child (line) scope.
- **FR-017**: Elements outside any collection-bound band MUST resolve their bindings against the master (invoice) scope, with no ambiguity about which scope a given binding targets.
- **FR-018**: A binding that cannot be resolved against its scope (missing field, scope mismatch) MUST be surfaced as **unresolved** and MUST be preserved non-destructively (never silently dropped).

**Persistence**

- **FR-019**: All bindings and the master/detail relationship MUST round-trip **losslessly** through the existing save/open report file format. Bindings MUST be **self-describing** — each carries its own field reference/expression — so they persist independently of any attached source; the data-source **structure itself is NOT embedded** in the template.
- **FR-019a**: A report reopened with **no data source attached** MUST still display every bound element's token (bindings are self-describing); the Data Source panel structure tree MUST be empty until a source is attached, at which point bindings resolve (or are flagged unresolved per FR-018).

**Demo / sample**

- **FR-020**: The demo/playground app MUST define an **invoice data source** via the public API, describing an invoice master record with a nested line-items collection, and attach it to the designer so its structure is displayed.
- **FR-021**: The demo/playground app MUST ship a **sample invoice template** that demonstrates master fields and a collection-bound line-items section, loadable in the designer with its bindings shown as tokens.

**Localization & consistency**

- **FR-022**: All new author-visible designer chrome (labels, controls, empty states, unresolved-binding indicators) MUST be localized (en/de/tr with English fallback), consistent with existing panels; illustrative sample data names need not be translated.

### Key Entities *(include if feature involves data)*

- **Data Source (structure)**: A host-supplied description of what data is available to a report — one dataset with typed fields — attached to the designer for display and binding. Carries structure, not (for this iteration) rendered values.
- **Field**: A named, typed member of a dataset. A field's type is a scalar (text/integer/decimal/boolean/date-time) or a **nested collection**.
- **Nested-Collection Field**: A field whose type denotes a child collection of records; it owns its own child field schema. The mechanism by which an invoice carries its line items (master → detail).
- **Data Binding**: The link from a report element (or band) to a field/expression that makes it data-driven. Resolves against a scope (master or a collection's child scope).
- **Collection-Bound Band**: A band designated as bound to a nested-collection field; it represents the repeating child rows (the invoice lines) and provides the child scope for elements inside it.
- **Field Token**: The design-time placeholder shown for a bound element (the field name/expression), standing in for the eventual value.
- **Invoice (master) / Invoice Line (detail)**: The sample domain entities — an invoice header record and its nested collection of line items — used to demonstrate and test master/detail.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the invoice source attached, an author can see the complete structure — the invoice's fields plus the nested line-items collection and its child fields — within the Data Source panel by expanding at most two levels.
- **SC-002**: An author can bind a text element to a field and confirm the binding via a visible token using only the designer UI (drag-from-panel or Properties), with no file editing, in a small number of direct actions.
- **SC-003**: 100% of element bindings and the master/detail relationship survive a save→open round-trip unchanged.
- **SC-004**: An author can lay out an invoice with master header fields and a line-items section bound to the nested collection using only the designer UI.
- **SC-005**: The demo app launches and shows the invoice data-source structure in the designer, with at least one bundled sample template whose bindings are visible as tokens — using only the library's public API.
- **SC-006**: The empty state (no source attached) shows zero placeholder/stale field names — the old hardcoded sample dataset never appears.
- **SC-007**: An unresolved binding (missing field or scope mismatch) is always indicated to the author and never causes the bound element to be silently dropped or blanked.
- **SC-008**: Master/detail can be authored at least two collection levels deep (e.g. invoice → lines → sub-lines), each level's bindings resolving against its own scope and surviving a save→open round-trip.
- **SC-009**: A report reopened with no data source attached still shows all bound tokens and an empty structure tree — no binding is lost and no stale field names appear.

## Assumptions

- The data-source **structure** is supplied to the designer by the host application and is **not embedded** in the saved template; the library performs no file, database, or network I/O (it stays headless). Bindings are self-describing (they carry their field reference/expression as names) so they persist and display as tokens independently of any attached source.
- "Tokens only" means no expression evaluation or data-filled rendering appears in the UI this iteration; the existing internal fill/expression engine is not surfaced or exposed by this feature.
- The binding interaction is **drag-a-field-from-the-panel** plus a **Properties-panel binding editor** that accepts a chosen field or a free-form expression, consistent with the existing toolbox-drag and Properties patterns from the designer edit surface (003).
- Element types made data-aware this iteration are **text** (field/expression binding) and **image** (field image source); **barcode binding is deferred** (barcode elements stay static this iteration).
- A single data-source structure is attached at a time; multi-source and joins are out of scope.
- The invoice sample's field/label names are illustrative and intentionally not localized; only designer chrome is localized.
- Target platform for the demo is macOS desktop with mouse + keyboard input, consistent with prior specs; the library itself remains platform-agnostic.
- This feature builds on the existing report model, designer edit surface (003), and the internal data/expression/fill engine already present in the codebase; it **exposes and wires** the data-binding authoring surface rather than building the engine from scratch. A new nested-collection field type is the main model addition.
