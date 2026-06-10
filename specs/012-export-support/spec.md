# Feature Specification: Export Support — PDF, Image, and Print Output

**Feature Branch**: `012-export-support`
**Created**: 2026-06-10
**Status**: Draft
**Input**: User description: "create export support"

## Overview

The render slice (011) turned a designed `ReportTemplate` plus real data into an on-screen, paginated, WYSIWYG preview — but the result lives only on the screen. Nothing a user can save, send, archive, or print ever leaves the application. Export was explicitly deferred out of 011 ("PDF, image files, print spooling"), with the promise that the rendered result would be structured so an export slice could consume it **without rework**.

This feature delivers that **export slice**: a host takes the same rendered report the preview displays and turns it into a **shareable artifact** — a PDF document, per-page images, or a print job — that is faithful to the preview page-for-page. The deliverable is the document a customer actually receives: the invoice attached to an email, the report saved to disk, the page coming out of the printer.

**Scope boundary (this slice)**: producing the export artifact in memory, a library print helper that presents the system print dialog, export/print actions in the preview widget (invoking host callbacks), and a playground demonstrating save/print end-to-end. For file artifacts the library stays headless — it produces bytes; the host owns where they go (file, share sheet, email). Print is the one sanctioned exception. No template schema change, no other designer or preview capability.

## Clarifications

### Session 2026-06-10

- Q: Where should the export/print UI affordances live? → A: Built into the preview — `JetReportPreview` gains optional export/print toolbar actions that invoke host-supplied callbacks; the library still performs no file I/O itself.
- Q: Who implements the OS print integration behind the print action? → A: The library ships a print helper API that presents the system print dialog for a rendered report; headlessness is relaxed for print only (file saving/sharing remains host-owned).
- Q: How strict is export determinism? → A: Byte-identical — identical inputs produce identical artifact bytes; PDF metadata (timestamps, document IDs) is fixed/zeroed so byte-level golden tests are possible.
- Q: Does export need progress reporting/cancellation? → A: No — a single awaitable call returning the artifact suffices for this slice; hosts show indeterminate busy UI; progress/cancellation is deferred and must be addable later without breaking the API.
- Q: Which raster format for page-image export? → A: PNG only — lossless and deterministic, consistent with byte-identical golden tests; JPEG/quality options deferred.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Export a rendered report as a PDF document (Priority: P1)

A host application has rendered a report (the invoice: master record, line items, computed totals) exactly as in slice 011. It now asks the engine for a PDF of that report and receives a complete, multi-page document it can save, attach, or hand to any PDF viewer. Opened side by side, the PDF and the on-screen preview show the same pages: same geometry, fonts, styles, images, and page breaks.

**Why this priority**: PDF is the universal report artifact and the single reason most consumers adopt a report engine — the invoice MVP ends with "send the customer a PDF". Every other export target is secondary to it. This story alone turns the product from a viewer into a document generator.

**Independent Test**: Render the playground invoice, export it to PDF, open the bytes in a standard PDF viewer, and verify page count, content, and layout match the preview. Delivers a saveable, shareable report end-to-end with no other story implemented.

**Acceptance Scenarios**:

1. **Given** a rendered report of N pages, **When** the host exports it to PDF, **Then** the resulting document contains exactly N pages whose content and layout match the preview page-for-page.
2. **Given** an exported PDF, **When** it is opened in a standard PDF viewer, **Then** text appears as real text (selectable and searchable), not as a picture of text.
3. **Given** the same template, data, parameters, and locale exported twice, **When** the two documents are compared, **Then** they are byte-identical (deterministic export).
4. **Given** a report containing images supplied as resolved bytes, **When** exported, **Then** the images appear in the PDF at the same position and size as in the preview.
5. **Given** an exported PDF opened on a machine without the report's fonts installed, **When** viewed, **Then** the text still renders with the report's intended appearance (fonts travel with the document).

---

### User Story 2 - Export report pages as images (Priority: P2)

A host needs raster output rather than a document: a thumbnail of page one for a report list, page snapshots to embed in another UI, or images for a system that cannot consume PDF. It asks the engine for one page or all pages as images at a chosen scale and receives bitmaps that match the preview rendering of those pages.

**Why this priority**: Image export is the second-most-requested artifact (thumbnails and previews-of-previews) and is independently valuable, but a host can ship the invoice MVP with PDF alone. It exercises the same export pipeline at a different output target.

**Independent Test**: Export page 1 of the rendered invoice as an image at 1x and at 2x scale; verify the image content matches the preview of page 1 and the 2x image has exactly twice the pixel dimensions with correspondingly sharper detail.

**Acceptance Scenarios**:

1. **Given** a rendered report, **When** the host exports a single page as an image, **Then** the image shows that page's full content matching the preview.
2. **Given** a requested scale factor (e.g., 1x, 2x, 3x), **When** a page is exported, **Then** the image's pixel dimensions equal the page dimensions multiplied by that scale.
3. **Given** a rendered report of N pages, **When** the host exports all pages as images, **Then** N images are produced in page order.
4. **Given** the same page exported twice with identical inputs, **When** compared, **Then** the images are identical (deterministic export).

---

### User Story 3 - Print the report (Priority: P3)

A user viewing the rendered invoice in the playground chooses "Print". The library's print capability presents the operating system's print dialog with the report laid out correctly, and the printed pages match the preview — completing the original "design → fill → preview → paper" journey the product was named for. A host gets this with one call: its print callback hands the rendered report to the library's print helper.

**Why this priority**: Printing is the final deferred target and completes the product promise, but it builds entirely on the P1 artifact (print systems consume the exported document) and is needed by fewer consumers. PDF and image export deliver value without it.

**Independent Test**: From the playground's preview of the invoice, trigger Print, observe the OS print dialog presenting the report with correct page size and content, and verify (via print-to-file) that the output matches the preview.

**Acceptance Scenarios**:

1. **Given** a rendered report shown in the playground, **When** the user invokes the preview's built-in print action, **Then** the system print dialog opens (the playground's callback delegating to the library's print helper) with the report's pages at the template's page size.
2. **Given** the print flow completed to a file (print-to-PDF), **When** the result is compared to the preview, **Then** pages, layout, and content match.
3. **Given** the library's public API, **When** a host calls the print capability with a rendered report, **Then** the system print dialog is presented without the host writing any platform-specific code and without any internal (`src/`) access.
4. **Given** a platform where printing is unavailable, **When** the print capability is invoked, **Then** it fails with a specific, identifiable error (no crash, no silent no-op).

---

### User Story 4 - Discover and wire export through the public API (Priority: P3)

A host developer who already renders a report adds export with a few lines of code: the export capability is reachable from the single public entry point, operates on the same rendered result the preview consumes, and is documented with a runnable playground example. To offer the UX, the developer passes export/print callbacks to the preview widget, whose built-in toolbar actions appear and delegate to them (the playground demonstrates save-to-file and print this way).

**Why this priority**: Ergonomics and discoverability make the feature adoptable, but they only matter once the artifacts (P1/P2) exist.

**Independent Test**: Using only `package:jet_print/jet_print.dart`, take the rendered invoice from the 011 example and produce a PDF and a page image; verify no `src/` import is needed and the playground example runs.

**Acceptance Scenarios**:

1. **Given** the public entry point, **When** a consumer imports the library, **Then** the export capability and its option/result types are reachable without any `src/` import.
2. **Given** the 011 playground invoice example, **When** the consumer extends it with export, **Then** rendering once is sufficient — the same rendered report feeds both the preview and the export (no second fill/render required).
3. **Given** the playground, **When** the user activates the preview's built-in export and print actions, **Then** a PDF is saved and the print dialog opens (via the playground's callbacks), demonstrating both flows end-to-end.
4. **Given** a host that supplies no export/print callbacks, **When** the preview is shown, **Then** no export/print actions appear and the preview behaves exactly as in 011.

---

### Edge Cases

- **Empty report (zero data rows)**: export still produces a valid document containing the static pages the preview shows (title/summary/headers); never a corrupt or zero-page artifact when the preview shows at least one page.
- **Very large report (e.g., 1,000+ records, hundreds of pages)**: export completes within the success-criteria budget and does not exhaust memory; lazy preview pagination (011) does not prevent exporting the full page set — export materializes all pages.
- **Unresolved image (URL-only or missing bytes)**: the export shows the same placeholder the preview shows, with the same diagnostic — preview and artifact never disagree.
- **Element that failed expression evaluation**: the fallback rendering (empty/placeholder, per 011) appears identically in the export; diagnostics carry through.
- **Locale-sensitive formatting**: numbers, dates, and currency in the artifact match the preview exactly for the same explicit render locale — the 011 promise of preview/export consistency is honored.
- **Page-size variety**: A4, Letter, and custom page formats export at their true physical dimensions (a print of an A4 template measures A4).
- **Out-of-range page request (image export)**: requesting a page beyond the page count fails with a clear, structured error — not a crash or a silent empty image.
- **Concurrent/repeat export**: exporting the same rendered report multiple times (or while the preview is open) is safe and yields identical results.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose a public export capability reachable solely through the single public entry point `package:jet_print/jet_print.dart`, operating on the **same rendered report** the preview consumes (one render serves both preview and export — no separate fill/render pass and no parallel paint code).
- **FR-002**: The library MUST export a rendered report as a **PDF document** delivered as in-memory bytes, containing every page of the rendered report in order.
- **FR-003**: Exported PDF output MUST be **WYSIWYG-faithful** to the preview and design surface: element geometry, fonts, styles, images, page format, and page breaks match page-for-page.
- **FR-004**: Text in the exported PDF MUST remain **real text** (selectable, searchable, extractable), not rasterized images of text, for all standard text elements.
- **FR-005**: Fonts used by the report MUST travel with the exported PDF so the document renders with its intended appearance on systems where those fonts are not installed.
- **FR-006**: The library MUST export individual pages (and, by iteration, all pages) of a rendered report as **PNG images** delivered as in-memory bytes, at a host-chosen scale factor; output pixel dimensions equal page dimensions × scale.
- **FR-007**: Export MUST be **byte-deterministic**: identical rendered input and export options produce **byte-identical artifacts** across runs — document metadata that normally varies (creation timestamps, generated document IDs) is fixed/zeroed.
- **FR-008**: Export MUST preserve the **physical page dimensions** of the template's page format so paper output measures true size.
- **FR-009**: Export MUST remain **headless for file artifacts**: PDF and image export produce in-memory bytes and perform no filesystem or network I/O; saving and sharing are host responsibilities.
- **FR-009a**: The library MUST provide a **print capability** that presents the operating system's print dialog for a rendered report (the one deliberate exception to headlessness); spooling beyond presenting the system dialog remains the operating system's concern. On a platform without print support, the capability MUST fail with a specific, identifiable error rather than crashing.
- **FR-010**: Export failures and per-element problems MUST surface as **structured diagnostics or clear errors** consistent with the 011 diagnostics model: recoverable content problems (unresolved image, failed expression) export the same fallback the preview shows without aborting; invalid requests (e.g., out-of-range page) fail with a specific, identifiable error rather than a crash or corrupt artifact.
- **FR-011**: Exporting a large report MUST NOT require the preview's lazily materialized page set to have been fully viewed: export itself materializes all pages of the rendered report.
- **FR-012**: Existing template **serialization MUST be unaffected** — no schema change, no migration, no new serialization version.
- **FR-013**: Every new public symbol (export capability, option and result types, preview action callbacks) MUST carry documentation, and the playground MUST gain runnable **save-as-PDF and print** examples wired to the rendered-invoice preview.
- **FR-014**: All new user-visible chrome introduced by this slice (the preview's export/print actions and any labels/tooltips) MUST be localized in the library's supported languages (English, German, Turkish) with English fallback, and MUST be keyboard-operable with accessible names, consistent with prior slices.
- **FR-015**: The preview widget MUST offer **optional built-in export and print actions** in its chrome that invoke host-supplied callbacks (the library performs no I/O); when the host supplies no callbacks, the corresponding actions are absent and the preview behaves exactly as in 011.

### Key Entities

- **Export capability**: the public seam that turns a Rendered Report into artifacts; the export-side counterpart of the 011 preview.
- **Rendered Report (existing, from 011)**: the engine's filled, paginated output — the single shared input to preview, PDF export, image export, and print.
- **PDF document artifact**: the complete multi-page document as in-memory bytes; the unit a host saves, attaches, or prints.
- **Page image artifact**: a raster snapshot of one page at a requested scale, as in-memory PNG bytes.
- **Export options**: host choices per export — target page (for images), scale factor; defaults cover the common case (full document, 1x).
- **Print capability**: the library's helper that presents the system print dialog for a rendered report — the print-side consumer of the PDF artifact and the one sanctioned exception to headlessness.
- **Export diagnostics/errors**: structured problems surfaced during export, aligned with the 011 render-diagnostics vocabulary.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A host can produce a saveable PDF of the rendered invoice using **only** the public entry point, in **under 10 lines** of integration code beyond the existing 011 preview example.
- **SC-002**: For the invoice scenario, the exported PDF contains **100% of the preview's pages** with matching content — verified by comparing the artifact's pages against the preview's golden rendering, in light and dark themes where applicable.
- **SC-003**: Text in the exported invoice PDF is selectable and searchable in a standard PDF viewer; searching for a known line-item value finds it.
- **SC-004**: Export is **byte-deterministic** — exporting identical rendered input twice yields **byte-identical artifacts** (verifiable by hash comparison), across all supported export targets.
- **SC-005**: A **1,000-record** report (the 011 performance dataset) exports to a complete PDF in **under 10 seconds** on the reference desktop environment without memory exhaustion.
- **SC-006**: A page image exported at 2x has **exactly** 2× the pixel dimensions of the page and is visually identical to the preview of that page at that scale.
- **SC-007**: All defined malformed/edge inputs (empty dataset, unresolved image, failed expression, out-of-range page) produce either a faithful-fallback artifact or a specific structured error — **0 crashes and 0 corrupt artifacts** across the defined cases.
- **SC-008**: From the playground preview, a user can save the invoice as a PDF and open the system print dialog, and printed (print-to-file) output matches the preview page-for-page.

## Assumptions

- The deferred-export scope named in 011 — **PDF, image files, print spooling** — is exactly this slice's scope, prioritized PDF (P1) → images (P2) → print (P3) so each priority is an independently shippable cut.
- Export consumes the existing **Rendered Report** produced by `JetReportEngine` (011), honoring 011's FR-020 promise (no rework, no parallel pipeline); this slice does not change the fill/layout/paginate engine.
- The library remains **headless for file artifacts** (carried forward from 011): PDF/image artifacts are in-memory bytes; the host (and the playground, as the reference host) owns file dialogs, file writing, and sharing. **Print is the sanctioned exception** (confirmed during clarification): the library presents the system print dialog itself.
- A new export-oriented runtime dependency is acceptable — 011 explicitly anticipated that "export-format dependencies, if any, arrive with the deferred export slice".
- Image export produces **PNG only** (confirmed during clarification); additional formats and quality tuning (e.g., JPEG) are not in scope.
- Page-range selection for PDF export (exporting a subset of pages into one document) is not in scope; PDF export covers the full document, and per-page needs are served by image export.
- Password protection, digital signatures, PDF/A archival profiles, and other document-security/compliance features are out of scope for this slice.
- Export is a **single awaitable operation** (confirmed during clarification): no progress reporting or cancellation in this slice; hosts present indeterminate busy UI during export. The API shape must allow adding progress/cancellation later without breaking changes.
- The reference environment remains the macOS desktop playground; the library itself stays platform-agnostic.
- Locale-sensitive formatting in the artifact follows the explicit per-render locale exactly as in 011; export introduces no new formatting behavior.

## Dependencies

- Slice 011 (`011-render-export`): the public `JetReportEngine` facade, the Rendered Report result, the preview widget, the diagnostics model, and the playground rendered-invoice example this slice extends. **011 is implemented on its feature branch but not yet merged to `main`** — this slice builds on top of it.
- The shared rendering/paint pipeline (designer ↔ preview) from prior slices, which export reuses to guarantee fidelity.
- The existing public template model and serialization (`ReportTemplate`, `JetReportFormat`) — consumed unchanged.
