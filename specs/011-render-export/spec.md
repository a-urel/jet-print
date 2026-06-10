# Feature Specification: Render Report — Data-Filled Paginated Preview (JetReportEngine Facade)

**Feature Branch**: `011-render-export`
**Created**: 2026-06-09
**Status**: Draft
**Input**: User description: "render report"

## Overview

The designer slice (009) made the report designer **data-aware**: a host describes its data's *structure*, binds report elements to fields, and authors master/detail bands — but everything stayed at the level of **tokens, not values**. No template has ever been filled with real data and shown to a user.

This feature delivers the **render slice**: a host hands a designed `ReportTemplate` together with **actual data** (rows and parameter values) to a public engine facade, which **fills** the template — evaluating bound expressions, iterating collection-bound bands (master/detail), computing variables and aggregates, and **paginating** the result — and presents it as an **on-screen, paginated, WYSIWYG preview** that matches the design surface.

The complete fill → layout → paginate → paint engine **already exists internally** and its own doc comments name this public surface "the 011 JetReportEngine". This slice is the **public facade** over that engine plus the preview widget; it does not build a new engine.

**Scope boundary (this slice)**: on-screen preview only. Producing a saved/exportable artifact (PDF, image files, print spooling) is explicitly **deferred to a later slice**. The host supplies data through the library's **full data-source API** (`JetDataSource` and its in-memory / JSON / object-backed implementations), which becomes public in this slice.

## Clarifications

### Session 2026-06-10

- Q: How are field/URL-bound images resolved for the preview, given the headless-core constraint? → A: The host pre-resolves images to bytes and supplies them through the data source; the library performs no I/O. A URL-only image source renders a placeholder plus a diagnostic.
- Q: What locale drives number/date/currency formatting at fill time? → A: An explicit locale passed to the engine per render (engine render option); not the app's UI locale.
- Q: What interaction model should the preview offer? → A: A read-only paginated viewer with prev/next navigation, a "page X of N" indicator, and fit-to-width sizing.
- Q: Is lazy/on-demand page rendering required, or may the engine paginate eagerly? → A: Lazy first-page rendering is required — the first page must render without materializing all pages up front; SC-009 is a firm acceptance gate.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See a designed report filled with real data (Priority: P1)

A host application has a finished `ReportTemplate` (designed in the data-aware designer) and a set of records. It attaches the records and any parameter values to the engine and displays the result. The user sees a faithful, paginated rendering of the report with **real values in place of the design-time tokens** — page by page, exactly as it will print.

**Why this priority**: This is the reason the product exists. Without a data-filled rendering the designer produces an artifact no end user ever sees realized. Every other story builds on this one. It is the smallest slice that turns "a design" into "a report."

**Independent Test**: Provide a simple one-band template bound to a flat dataset of a few rows plus one parameter; render it; verify the on-screen output shows each row's actual values (not tokens), the parameter value where bound, and the correct number of pages. Delivers a viewable report end-to-end.

**Acceptance Scenarios**:

1. **Given** a template with a detail band bound to a dataset of N rows, **When** the host renders it with that dataset, **Then** the preview shows N rendered detail rows with each element displaying its evaluated value (not a `$F{...}` token).
2. **Given** a template element bound to a parameter, **When** the host supplies a value for that parameter, **Then** the rendered element shows the supplied value.
3. **Given** a report whose content exceeds one page, **When** it is rendered, **Then** the content is split across multiple pages at band boundaries and the user can move between pages.
4. **Given** the same template and data rendered twice, **When** compared, **Then** the output is identical (deterministic render).
5. **Given** a rendered report, **When** compared visually against the designer's WYSIWYG design surface for the same template, **Then** element positions, fonts, styles, and page geometry match (same underlying paint pipeline).

---

### User Story 2 - Author master/detail and aggregates that actually compute (Priority: P2)

A host renders an invoice-style report: a master record (the invoice) with a nested collection of detail records (line items), a group, and computed totals (sum of line amounts, running totals, page numbers). The rendered output iterates the nested collection, repeats group headers/footers correctly, and shows the **computed** aggregate and variable values.

**Why this priority**: Master/detail with aggregates is the defining capability of a report engine (vs. a static document) and the headline use case the whole product was scoped around (the invoice MVP). It is separable from P1 — P1 proves flat fill; P2 proves nested iteration and computation — but depends on P1's fill/preview being in place.

**Independent Test**: Render the playground invoice (one invoice + several line items) and verify each line item appears once, the line-total expression computes per row, the invoice total equals the sum of line amounts, and the page-number variable increments across pages.

**Acceptance Scenarios**:

1. **Given** a band bound to a nested collection with M child records, **When** rendered, **Then** the band repeats M times, once per child record, with child-field values resolved.
2. **Given** a variable defined as a sum aggregate over a bound field, **When** the report is rendered, **Then** the variable shows the correct total at its reset scope (e.g., per group and grand total).
3. **Given** arbitrarily nested collection-bound bands, **When** rendered, **Then** each nesting level iterates its own collection within its parent's current record.
4. **Given** group header/footer bands, **When** the group key changes between records, **Then** the footer for the prior group and the header for the next group render at the boundary.

---

### User Story 3 - Supply data through the public data-source API (Priority: P3)

A host developer wires real data into the engine using the library's public data-source API. They can hand the engine in-memory rows, a JSON payload, or their own domain objects (via the object-backed source), plus a map of parameter values, without reaching into engine internals. The API is discoverable from the single public entry point and documented with a runnable example.

**Why this priority**: The first two stories prove the *rendering*; this story makes the *integration* ergonomic and is what a consumer actually codes against. It can be validated independently against the public API surface, but only matters once there is an engine to feed (P1).

**Independent Test**: Using only `package:jet_print/jet_print.dart`, construct each public data-source variant (in-memory, JSON, object-backed) for the same logical dataset, render with each, and verify identical output — proving the public surface is sufficient and consistent.

**Acceptance Scenarios**:

1. **Given** the public entry point, **When** a consumer imports the library, **Then** the engine facade and the data-source types (`JetDataSource`, dataset, row, and the in-memory / JSON / object-backed sources) are reachable without any `src/` import.
2. **Given** a dataset with a nested collection, **When** the consumer supplies it through a public data source, **Then** master/detail bands iterate it correctly (ties P3 to P2).
3. **Given** a host that supplies parameter values as a simple map, **When** rendering, **Then** parameter-bound elements and parameter-referencing expressions resolve to those values.

---

### User Story 4 - Get clear diagnostics instead of crashes (Priority: P3)

When the supplied data or template has problems — an expression references an unknown field, a parameter has no supplied value, an image field cannot be resolved, or a dataset is empty — the render does not crash. It produces a best-effort rendering and surfaces structured diagnostics describing each problem so the host can show or log them.

**Why this priority**: Robustness turns a demo into something a host can ship, and it is independently testable by feeding malformed inputs. It is P3 because the happy path (P1/P2) delivers the core value first.

**Independent Test**: Render templates with (a) an expression over a missing field, (b) an unsupplied parameter, (c) an empty dataset, and verify the engine returns diagnostics identifying each issue and still produces a renderable result.

**Acceptance Scenarios**:

1. **Given** an element bound to an expression referencing a non-existent field, **When** rendered, **Then** the engine emits a diagnostic identifying the element and the unknown field, and renders the element empty (or a defined placeholder) rather than crashing.
2. **Given** a detail band bound to a collection that is empty for the current master, **When** rendered, **Then** the band simply produces zero repetitions and the surrounding bands render normally.
3. **Given** a required parameter with no supplied value, **When** rendered, **Then** a diagnostic identifies the missing parameter and rendering continues with a defined default/empty result.

---

### Edge Cases

- **Empty dataset (zero rows)**: the detail/section renders zero repetitions; static bands (title, summary, page header/footer) still render; aggregates over zero rows yield their defined zero/empty value.
- **Content overflow within a single band**: a band whose content is taller than the remaining page space moves to the next page (or splits, per the engine's existing rule); page header/footer repeat on each page.
- **Single record producing many pages** and **many records producing one page**: pagination is driven by content height, not record count.
- **Image field that cannot be resolved** (missing/failed bytes, or a URL-only source the host did not pre-resolve): a diagnostic is emitted and a placeholder/empty box renders in its place; the rest of the page is unaffected.
- **Deeply nested collections** and **a master with no detail rows**: nesting recurses correctly; a childless master renders its master bands with an empty detail section.
- **Expression evaluation error** (type mismatch, divide-by-zero): isolated to the offending element with a diagnostic; the report still renders.
- **Very large dataset**: rendering remains responsive enough to preview (see Success Criteria); the preview **does not** materialize all pages at once (lazy first page — FR-021).
- **Locale-sensitive formatting** (numbers, dates, currency in the invoice): formatted values respect the render's **explicit locale** and the template's format specifiers, consistently between preview and the eventual export slice.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose a public report-engine facade (named `JetReportEngine`, per the engine's existing internal forward-references) reachable solely through the single public entry point `package:jet_print/jet_print.dart`.
- **FR-002**: The engine MUST accept a `ReportTemplate`, a data source supplying records, and a set of parameter values, and produce a filled, paginated report from them.
- **FR-003**: The engine MUST evaluate each bound element's expression against the current record/parameter/variable context and render the **resolved value** in place of the design-time token.
- **FR-004**: The engine MUST iterate collection-bound (master/detail) bands once per record in the bound collection, at arbitrary nesting depth, resolving child-field references within each iteration.
- **FR-005**: The engine MUST compute report variables and aggregates (e.g., sums, counts, running totals, page numbers) at their defined reset scopes and render their computed values.
- **FR-006**: The engine MUST render group header/footer bands at group-key boundaries.
- **FR-007**: The engine MUST paginate filled content into discrete pages based on content height and the template's page geometry, repeating page header/footer bands per page.
- **FR-008**: The library MUST provide an on-screen, **paginated preview** of the rendered report as a **read-only viewer** offering prev/next page navigation, a "page X of N" indicator, and fit-to-width sizing.
- **FR-009**: The preview MUST be **WYSIWYG-faithful to the design surface** — element geometry, fonts, styles, and page format MUST match the designer for the same template, by reusing the same shared rendering/paint pipeline (no parallel draw code).
- **FR-010**: Rendering MUST be **deterministic**: identical template + data + parameters + locale produce identical output.
- **FR-011**: The library MUST expose the **full public data-source API** — `JetDataSource` and its in-memory, JSON-backed, and object-backed implementations, plus the dataset/row/cursor vocabulary needed to supply records (including nested collections) — through the single entry point, with `src/` remaining private.
- **FR-012**: The engine MUST accept **parameter values** as a host-supplied collection keyed by parameter name and resolve parameter references in expressions and bindings to those values.
- **FR-012a**: The engine MUST accept an **explicit locale** as a per-render option and apply it to all locale-sensitive formatting (numbers, dates, currency, format specifiers); formatting MUST NOT depend on the application's UI locale.
- **FR-012b**: The host MUST supply image content for image-bound elements as **resolved bytes** through the data source; the library performs no image I/O. An image source that carries only a URL (no bytes) MUST render a placeholder and emit a diagnostic (it is the host's responsibility to pre-resolve such images to bytes).
- **FR-013**: The engine MUST produce **structured diagnostics** for fill/render problems (unknown field, missing parameter, unresolved image, expression error, empty dataset) that identify the affected element/band and the problem, **without aborting** the overall render.
- **FR-014**: On a recoverable per-element problem, the engine MUST render a defined fallback (empty or placeholder) for that element and continue rendering the rest of the report.
- **FR-015**: The library MUST remain **headless** for this slice — it produces an in-memory rendered/preview result and performs no filesystem, print, or network I/O; the host owns any such concerns.
- **FR-016**: Existing template **serialization MUST be unaffected** — rendering reads templates through the existing format with no schema change and no migration; round-trip fidelity is preserved.
- **FR-017**: Any new user-visible chrome in the preview (e.g., page indicator, navigation controls) MUST be localized in the library's supported languages (English, German, Turkish) with English fallback, consistent with prior slices.
- **FR-018**: New preview affordances MUST be keyboard-operable with accessible names, consistent with the designer's accessibility precedent.
- **FR-019**: Every new public symbol (the engine facade, the newly public data-source types, the preview widget, the diagnostics type) MUST carry documentation, and the playground MUST gain a **runnable rendered-invoice example** demonstrating template + data → preview.
- **FR-020**: File/document **export (PDF, image files, print spooling) is explicitly out of scope** for this slice and MUST NOT be required to satisfy any requirement here; the preview result SHOULD be structured so a later export slice can consume it without rework.
- **FR-021**: The preview MUST render its **first page without materializing all pages up front** (lazy/on-demand pagination), so first-page time does not scale with total record/page count.

### Key Entities *(include if feature involves data)*

- **Report Engine (`JetReportEngine`)**: the public facade. Takes a template + data source + parameter values; orchestrates fill, layout, pagination; yields a rendered report and diagnostics. The single public seam over the existing internal engine.
- **Data Source (`JetDataSource` + implementations)**: the host's supply of records — in-memory rows, a JSON payload, or domain objects — including nested collections for master/detail. Becomes public in this slice.
- **Parameter values**: host-supplied named inputs (e.g., report title, date range, "printed by") resolved in expressions and bindings.
- **Rendered/Filled Report**: the engine's output — an ordered set of laid-out, paginated pages of resolved, paintable content; the input to both the preview and the future export slice.
- **Page**: one paginated unit carrying the resolved content for that page, including repeated page header/footer.
- **Render Diagnostics**: a structured collection of problems found during fill/render, each identifying the affected element/band and the issue, surfaced to the host without aborting the render.
- **Preview**: the on-screen, paginated, WYSIWYG view of the Rendered Report.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A host can take a designed template plus data and display a data-filled, paginated preview using **only** the public entry point — no access to internal (`src/`) types is required.
- **SC-002**: For the invoice scenario (one invoice with multiple line items, a parameter, and a total), **100% of bound elements** display evaluated values (zero residual `$F{}`/`$P{}`/`$V{}` tokens), the invoice total equals the exact sum of line amounts, and line items each appear exactly once.
- **SC-003**: The preview is **visually identical** to the designer's design surface for the same template (same element geometry, fonts, styles, and page format), verified by shared-pipeline golden comparison in light and dark themes.
- **SC-004**: Rendering is **deterministic** — re-rendering identical inputs yields byte-identical paint output across runs.
- **SC-005**: A report whose content exceeds one page **paginates correctly**: content splits only at allowed boundaries, page header/footer repeat on every page, and the page count matches the content.
- **SC-006**: The same logical dataset supplied via **each** public data-source variant (in-memory, JSON, object-backed) produces **identical** rendered output.
- **SC-007**: Malformed inputs (unknown field, missing parameter, empty dataset, unresolved image) each produce a **specific diagnostic** and a non-crashing render; **0 unhandled crashes** across the defined malformed-input cases.
- **SC-008**: A first-time consumer can wire template + data → preview by following the runnable playground example in **under 30 lines** of integration code.
- **SC-009**: Previewing a report over a **1,000-record** dataset reaches a viewable first page in **under 2 seconds** on the reference desktop environment, without materializing all pages up front.

## Assumptions

- The internal fill → layout → paginate → paint engine (expression language, data sources, filler, layouter, frame builder, painter) is complete and correct; this slice is the **public facade + preview**, not a re-implementation. (Engine doc comments already name the facade "the 011 JetReportEngine".)
- Templates consumed here are produced by the existing designer/serialization (slice 009 and prior); no template schema change is introduced.
- "Render report" means **rendering for viewing** in this slice. **Export to a saved/printable artifact (PDF, image, print) is deferred** to a later slice (confirmed during specification).
- The host supplies data via the library's **full data-source API**, which is promoted to public here (confirmed during specification); the simpler "plain rows" facade is subsumed by the in-memory source.
- The preview is a **read-only paginated viewer** — prev/next page navigation, a "page X of N" indicator, and fit-to-width sizing (FR-008). Zoom controls, interactive editing, annotation, and print dialogs are not in scope.
- Target environment for preview is the macOS desktop playground; the library itself stays platform-agnostic and headless.
- Locale-sensitive formatting follows the **explicit locale passed to the engine per render** (FR-012a) plus the template's format specifiers; the supported UI-chrome languages remain English, German, and Turkish with English fallback (these two locales are independent — document formatting need not match the UI chrome language).
- This slice introduces **no new template serialization version** and **no new heavy runtime dependency** (export-format dependencies, if any, arrive with the deferred export slice).

## Dependencies

- The completed internal report engine and expression/data-source layers under `packages/jet_print/lib/src/` (rendering, expression, data).
- The existing public template model and serialization (`ReportTemplate`, `JetReportFormat`) from prior slices — consumed unchanged.
- The data-aware designer (009) as the producer of bound templates and master/detail bands that this slice renders.
