# Tasks: Export Support — PDF, Image, and Print Output

**Input**: Design documents from `/specs/012-export-support/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/export-api.md, quickstart.md

**Tests**: MANDATORY per Constitution Principle III (Test-First, NON-NEGOTIABLE). Every test task precedes the implementation it pins; write it, watch it fail, then implement. Golden tests pin rendered artifacts per Principle IV.

**Organization**: Tasks are grouped by user story so each story is an independently shippable cut: US1 = PDF (MVP), US2 = PNG, US3 = print, US4 = preview actions + playground.

**Conventions**: Run all commands from the repository root (`flutter` invocations can drift the cwd — always return to root before `git`/`flutter test`). Full suite: `flutter test packages/jet_print apps/jet_print_playground`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Dependencies and a verified-green baseline before any story begins.

- [X] T001 Add `pdf: ^3.12.0`, `printing: ^5.14.3`, and `image` (direct — already transitive via `pdf`) to `packages/jet_print/pubspec.yaml` dependencies; run `dart pub get` and confirm the workspace resolves with no version conflicts
- [X] T002 Verify the recovered 011 baseline is green before building on it: run `flutter test packages/jet_print apps/jet_print_playground` from the repo root and confirm the full suite (795 tests) passes

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story.

**No foundational tasks.** Slice 011 already provides everything the stories build on: `RenderedReport`/`RenderedPage`/`PageFrame` (the shared input), the `ReportPainter` abstraction with the exhaustive `paintFrame()` walk, `FontRegistry`, `computeImageFit`, and the diagnostics model. Phase 1's dependency addition is the only blocking prerequisite.

**Checkpoint**: Dependencies resolved, baseline green — user stories can begin.

---

## Phase 3: User Story 1 - Export a rendered report as a PDF document (Priority: P1) 🎯 MVP

**Goal**: `const JetReportExporter().toPdf(report)` returns deterministic in-memory PDF bytes — every page in order, real selectable text, embedded fonts, true physical page size — WYSIWYG-faithful to the preview via the shared `paintFrame` walk (no parallel paint code).

**Independent Test**: Render the playground invoice, export to PDF, open the bytes in a standard PDF viewer; verify page count, content, and layout match the preview, text is selectable/searchable, and exporting twice yields byte-identical files.

### Tests for User Story 1 (write FIRST — must fail before implementation)

- [X] T003 [P] [US1] Write PDF structure test in `packages/jet_print/test/rendering/export/pdf_export_test.dart`: exported document has exactly `report.pageCount` pages in order; each MediaBox equals the template's `PageFormat` width×height in points (A4 595.28×841.89, Letter, and a custom format); text appears as text objects with embedded TTF font programs (not images of text); a known line-item string is extractable; images land at the `computeImageFit` geometry the preview uses (contract B1/B2; FR-002/003/004/005/008)
- [X] T004 [P] [US1] Write determinism test in `packages/jet_print/test/rendering/export/pdf_determinism_test.dart`: exporting the identical rendered input twice yields byte-identical output (hash equality); repeat export over a *partially viewed* lazy report is also identical; leave a placeholder for the golden `invoice.pdf` pin added in T014 (contract B3; FR-007, SC-004, FR-011)
- [X] T005 [P] [US1] Write painter parity test in `packages/jet_print/test/rendering/export/pdf_painter_parity_test.dart`: per-primitive semantics mirror `CanvasPainter` — `TextLine` placed at exact baseline `pageHeight − (bounds.y + line.top + line.baseline)` with identical left/center/right alignment math; image src/dst rects from shared `computeImageFit`; rect/path emit fill first then stroke; top-left→bottom-left y-mapping is per-draw-call (no global y-flip CTM) (contract B2; research §6)
- [X] T006 [P] [US1] Write fallback test (PDF cases) in `packages/jet_print/test/rendering/export/export_fallback_test.dart`: empty dataset → valid PDF with the static pages the preview shows (never zero-page); unresolved image → same placeholder primitive as preview; failed expression → same fallback as preview; `report.diagnostics` unchanged; zero throws for content problems (contract B5; FR-010, SC-007)
- [X] T007 [P] [US1] Write performance test in `packages/jet_print/test/rendering/export/export_performance_test.dart`: the 011 1,000-record performance dataset exports to a complete PDF in under 10 seconds without memory exhaustion (contract B1; SC-005)

### Implementation for User Story 1

- [X] T008 [US1] Implement `PdfPainter` core in `packages/jet_print/lib/src/rendering/export/pdf_painter.dart`: pure-Dart `ReportPainter` over `package:pdf`'s low-level `PdfDocument`/`PdfPage`/`PdfGraphics`; deterministic by construction — internal `_FixedIdPdfDocument extends PdfDocument` overriding `documentID` to a constant, **no** `PdfInfo` object constructed, `verbose: false`; `beginPage` creates a page with MediaBox = `format.width × format.height` pt; per-draw-call y-mapping helper (`y' = pageHeight − y`); `drawLine`/`drawRect`/`drawPath` map to PDF stroke/fill operators with `CanvasPainter`'s color/strokeWidth/fill-then-stroke semantics (research §1/§2/§6)
- [X] T009 [US1] Implement `drawTextRun` in `packages/jet_print/lib/src/rendering/export/pdf_painter.dart`: for each pre-measured `TextLine`, resolve the font variant via `FontRegistry.bytesFor`, embed as `PdfTtfFont` once per variant per document, draw real text via `drawString` at the parity-test baseline and alignment — never re-wrap, never rasterize text (FR-004/005)
- [X] T010 [US1] Implement `drawImage` in `packages/jet_print/lib/src/rendering/export/pdf_painter.dart`: decode `ImagePrimitive.bytes` in `prepare` — JPEG passthrough via `PdfImage.jpeg`, everything else decoded with `package:image` to RGBA and embedded as raw `PdfImage` (alpha via `/SMask`); place via shared `computeImageFit` rects with clipping (research §5)
- [X] T011 [US1] Implement `JetReportExporter` facade with `toPdf` in `packages/jet_print/lib/src/rendering/export/jet_report_exporter.dart`: stateless `const` class; `Future<Uint8List> toPdf(RenderedReport report)` constructs a per-export `FontRegistry()..registerDefault()` (exactly as the preview does), iterates `report.pageAt(i)` for `i ∈ [0, pageCount)` materializing all pages, drives `paintFrame(frame, pdfPainter)` per page, returns the saved bytes (contract §1, B1; FR-001/002/011)
- [X] T012 [US1] Export `JetReportExporter` from `packages/jet_print/lib/jet_print.dart` with complete dartdoc on the class and both members (FR-013; pageToPng arrives in US2 — document `toPdf` now)
- [X] T013 [US1] Extend `packages/jet_print/test/architecture/layer_boundaries_test.dart`: `lib/src/rendering/export/` files must be Flutter-free (pure Dart — no `dart:ui`, no Flutter imports); the public-surface pin gains `JetReportExporter` (contract B7 + plan Complexity Tracking)
- [X] T014 [US1] Create the golden PDF pin `packages/jet_print/test/goldens/invoice.pdf` from the rendered invoice and wire the byte-level comparison into `pdf_determinism_test.dart` (deliberate-update artifact per research §2 compression caveat); run `flutter test packages/jet_print` and confirm all US1 tests pass

**Checkpoint**: PDF export works end-to-end — a saveable, shareable, deterministic document. MVP shippable.

---

## Phase 4: User Story 2 - Export report pages as images (Priority: P2)

**Goal**: `pageToPng(report, i, scale: s)` returns one page as in-memory PNG bytes with pixel dimensions exactly `round(page × s)`, pixel-identical to the preview (same `CanvasPainter`, rasterized).

**Independent Test**: Export page 1 of the rendered invoice at 1x and 2x; verify content matches the preview of page 1 and the 2x image has exactly twice the pixel dimensions.

### Tests for User Story 2 (write FIRST — must fail before implementation)

- [X] T015 [P] [US2] Write PNG export test in `packages/jet_print/test/rendering/export/png_export_test.dart`: pixel dimensions exactly `round(w×s) × round(h×s)` at 1x/2x/3x; all pages exportable in page order by host iteration; run-to-run byte determinism (in-process hash equality); `pageIndex` out of `[0, pageCount)` → `RangeError.range`; `scale <= 0` → `ArgumentError.value` (contract B4/B3; FR-006/007, SC-006)
- [X] T016 [P] [US2] Extend `packages/jet_print/test/rendering/export/export_fallback_test.dart` with PNG cases: empty dataset / unresolved image / failed expression each produce a valid PNG showing the same fallback content as the preview — zero crashes, zero corrupt artifacts (contract B5; SC-007)

### Implementation for User Story 2

- [X] T017 [US2] Implement `PageRasterizer` in `packages/jet_print/lib/src/rendering/paint/page_rasterizer.dart`: record `paintFrame(frame, CanvasPainter(canvas, fonts))` — the unchanged preview paint path — into a `ui.PictureRecorder` with a `scale` canvas transform, `Picture.toImage(round(w×scale), round(h×scale))`, encode `ImageByteFormat.png` (research §4; Constitution IV — no parallel paint code)
- [X] T018 [US2] Add `pageToPng(RenderedReport report, int pageIndex, {double scale = 1.0})` to `packages/jet_print/lib/src/rendering/export/jet_report_exporter.dart`: validate `pageIndex` (RangeError — same vocabulary as `RenderedReport.pageAt`) and `scale` (ArgumentError), delegate to `PageRasterizer`; complete the facade's dartdoc in `packages/jet_print/lib/jet_print.dart` exports (contract §1, B4)
- [X] T019 [US2] Extend `packages/jet_print/test/architecture/layer_boundaries_test.dart`: `page_rasterizer.dart` joins `canvas_painter.dart` as the **second and only other** declared `dart:ui` file in the rendering seam — the test still fails if any other rendering file grows a `dart:ui`/Flutter import (plan Complexity Tracking)
- [X] T020 [US2] Create the golden PNG pin `packages/jet_print/test/goldens/invoice_page1_2x.png` cross-checked against the existing preview goldens via the standard golden comparator (decoded-pixel comparison — engine PNG bytes are not cross-machine stable, research §4); run `flutter test packages/jet_print` and confirm all US2 tests pass

**Checkpoint**: PDF + PNG export both work independently; same `RenderedReport` feeds both.

---

## Phase 5: User Story 3 - Print the report (Priority: P3)

**Goal**: `const JetReportPrinter().printReport(report)` exports the US1 PDF and presents the system print dialog at the template's true page size — the one sanctioned exception to headlessness — failing with `PrintUnavailableException` where printing is unsupported.

**Independent Test**: With an injected fake presenter, verify the presenter receives the deterministic PDF bytes, page dimensions, and job name; trigger the real dialog from the playground (after US4 wiring) and verify print-to-file output matches the preview.

**Note**: Depends on US1 (`toPdf` is the artifact handed to the presenter).

### Tests for User Story 3 (write FIRST — must fail before implementation)

- [ ] T021 [P] [US3] Write printer test in `packages/jet_print/test/print/jet_report_printer_test.dart` using an injected fake `PrintDialogPresenter` (no platform channels in tests): presenter receives the same bytes `toPdf` produces plus `pageWidthPt`/`pageHeightPt` from the template's `PageFormat`; `jobName` defaults to `jobName ?? non-empty report.title ?? 'Report'`; presenter returning `false` (user cancelled) → `printReport` returns `false` without error; unavailable platform → `PrintUnavailableException` with an identifying message — never a crash, never a silent no-op (contract B6; FR-009a)

### Implementation for User Story 3

- [ ] T022 [US3] Implement the print seam in `packages/jet_print/lib/src/print/jet_report_printer.dart`: `PrintDialogPresenter` typedef (per contract §1 signature), `PrintUnavailableException implements Exception` with a message, and `const JetReportPrinter({PrintDialogPresenter? presenter})` whose `printReport` exports via `JetReportExporter.toPdf` then invokes the presenter; the default presenter checks `(await Printing.info()).canPrint` first (throws `PrintUnavailableException` if false — `info()` never throws) then calls `Printing.layoutPdf(onLayout: (_) async => pdfBytes, name: jobName, format: ...)` returning its bool; `onLayout` returns the same deterministic bytes regardless of dialog paper changes (research §3)
- [ ] T023 [US3] Export `JetReportPrinter`, `PrintDialogPresenter`, and `PrintUnavailableException` from `packages/jet_print/lib/jet_print.dart` with complete dartdoc (FR-013)
- [ ] T024 [US3] Extend `packages/jet_print/test/architecture/layer_boundaries_test.dart`: `package:printing` may be imported **only** inside `lib/src/print/`; no library file may import the print seam (it is outermost); public-surface pin gains the three print symbols (contract B7 + plan Complexity Tracking)
- [ ] T025 [P] [US3] Add the `com.apple.security.print` entitlement to both `apps/jet_print_playground/macos/Runner/DebugProfile.entitlements` and `apps/jet_print_playground/macos/Runner/Release.entitlements` (sandboxed macOS apps cannot print without it — research §3); run `flutter test packages/jet_print` and confirm all US3 tests pass

**Checkpoint**: All three artifact targets work; print is testable without platform channels via the fake presenter.

---

## Phase 6: User Story 4 - Discover and wire export through the public API (Priority: P3)

**Goal**: `JetReportPreview` gains optional `onExportPdf`/`onPrint` toolbar actions (absent when callbacks are null — 011 behavior bit-preserved), localized en/de/tr and keyboard-operable; the playground demonstrates save-as-PDF and print end-to-end in under 10 integration lines.

**Independent Test**: Using only `package:jet_print/jet_print.dart`, extend the 011 rendered-invoice example with export and print; verify no `src/` import is needed, the toolbar actions appear, and the flows run end-to-end.

**Note**: Preview callback plumbing is independent of US1–US3 (callbacks only — the library performs no I/O), but the playground wiring (T031) consumes US1's exporter and US3's printer.

### Tests for User Story 4 (write FIRST — must fail before implementation)

- [ ] T026 [P] [US4] Extend `packages/jet_print/test/designer/preview/jet_report_preview_test.dart`: with both callbacks null, the widget tree/semantics are identical to 011 (no buttons, no reserved space); a non-null `onExportPdf`/`onPrint` adds its toolbar action with stable `ValueKey`s (`jet_print.preview.export`, `jet_print.preview.print`); tap AND keyboard activation invoke the callback; actions expose localized accessible names (contract B8; FR-014/015)
- [ ] T027 [P] [US4] Extend the preview localization tests in `packages/jet_print/test/designer/preview/` (existing `preview_localization_*.dart` pattern): `previewExport` and `previewPrint` strings render correctly in en/de/tr and fall back to English for unsupported locales (FR-014)
- [ ] T028 [P] [US4] Extend `apps/jet_print_playground/test/rendered_invoice_example_test.dart`: the example renders **once** and feeds preview + export + print from the same `RenderedReport`; export/print toolbar actions are present and wired through the public API only — no `src/` import anywhere in the playground (SC-008; US4 acceptance 1–3)

### Implementation for User Story 4

- [ ] T029 [US4] Add `previewExport` ("Export as PDF") and `previewPrint` ("Print") keys with translations to `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, and `jet_print_tr.arb`, then run `flutter gen-l10n` (or the package's localization generation step) to regenerate the localizations (FR-014)
- [ ] T030 [US4] Add optional `VoidCallback? onExportPdf` and `VoidCallback? onPrint` parameters to `packages/jet_print/lib/src/designer/preview/jet_report_preview.dart` with dartdoc; non-null callbacks render ghost icon toolbar actions (matching the existing toolbar style) with localized tooltips/accessible names, keyboard operability, and the stable `ValueKey`s from T026; null callbacks render nothing — the library invokes the callback and performs no I/O (contract B8; FR-013/015)
- [ ] T031 [US4] Wire the playground in `apps/jet_print_playground/lib/rendered_invoice_example.dart`: `onExportPdf` saves the `toPdf` bytes via `file_selector` (host-owned I/O), `onPrint` delegates to `const JetReportPrinter().printReport(report)` — staying under 10 integration lines beyond the 011 example (SC-001, SC-008; quickstart.md shape)
- [ ] T032 [US4] Verify the public-surface pin in `packages/jet_print/test/architecture/layer_boundaries_test.dart` now matches contract §1 **exactly** (exporter, printer, presenter typedef, exception, two preview callbacks — nothing more); run `flutter test packages/jet_print apps/jet_print_playground` and confirm all US4 tests pass

**Checkpoint**: All four stories complete — design → fill → preview → artifact/paper, end-to-end in the playground.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, hygiene, and final verification across all stories.

- [ ] T033 [P] Update `packages/jet_print/CHANGELOG.md` with the export slice: `JetReportExporter` (PDF/PNG), `JetReportPrinter` + presenter seam + `PrintUnavailableException`, preview `onExportPdf`/`onPrint`, new dependencies `pdf`/`printing`/`image` (Constitution VI)
- [ ] T034 [P] Audit dartdoc completeness for every new public symbol — `JetReportExporter.toPdf`/`pageToPng`, `JetReportPrinter.printReport`, `PrintDialogPresenter`, `PrintUnavailableException`, both preview callbacks — including throws/return semantics (cancellation returns `false`, never throws) (FR-013)
- [ ] T035 Run `dart format .` and `flutter analyze` from the repo root; fix until zero warnings (Constitution VI)
- [ ] T036 Run the full suite `flutter test packages/jet_print apps/jet_print_playground` from the repo root; all tests green, none skipped (Constitution III)
- [ ] T037 Validate quickstart.md end-to-end on the macOS playground: `flutter run` in `apps/jet_print_playground`, save the invoice as PDF via the toolbar action, open it in a PDF viewer (selectable text, correct pages — SC-003), open the print dialog and print-to-file, compare against the preview page-for-page (SC-008); confirm the SC-001 line budget (< 10 lines)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately. T001 blocks everything (the `pdf`/`printing`/`image` imports).
- **Foundational (Phase 2)**: Empty — 011 is the foundation.
- **User Story 1 (Phase 3)**: After Setup. No story dependencies. **The MVP.**
- **User Story 2 (Phase 4)**: After US1's T011 (extends the `JetReportExporter` facade file). Test tasks T015–T016 can be written in parallel with US1 implementation.
- **User Story 3 (Phase 5)**: After US1's T011 (`printReport` consumes `toPdf`). T025 (entitlements) is independent and can run any time.
- **User Story 4 (Phase 6)**: Preview tasks (T026–T030) depend only on Setup; playground wiring (T031) needs US1 + US3; final surface pin (T032) needs US1–US3 export tasks done.
- **Polish (Phase 7)**: After all desired stories.

### Within Each User Story

- Test tasks first; confirm they FAIL before implementing (Constitution III).
- `pdf_painter.dart` tasks are sequential (T008 → T009 → T010, same file); the facade (T011) follows; public export (T012), architecture pin (T013), and golden (T014) close the story.
- Architecture-test extensions (T013/T019/T024/T032) each touch `layer_boundaries_test.dart` — sequential across stories, never [P] with each other.

### Parallel Opportunities

- **US1 tests**: T003, T004, T005, T006, T007 — five different files, all parallel.
- **US2 tests**: T015 ∥ T016 (T016 touches `export_fallback_test.dart` — parallel with T015, not with US1's T006 if US1 is still in flight).
- **US3**: T021 ∥ T025 (test vs. playground entitlements).
- **US4 tests**: T026, T027, T028 — three different files, all parallel.
- **Cross-story**: once US1's T011 lands, US2 implementation, US3 implementation, and US4's preview work (T029/T030) can proceed in parallel — they touch disjoint files except `lib/jet_print.dart` (T012/T018/T023) and `layer_boundaries_test.dart` (T013/T019/T024/T032), which must be sequenced.
- **Polish**: T033 ∥ T034.

---

## Parallel Example: User Story 1

```bash
# Launch all US1 test-writing tasks together (all different files):
Task: "Write PDF structure test in packages/jet_print/test/rendering/export/pdf_export_test.dart"
Task: "Write determinism test in packages/jet_print/test/rendering/export/pdf_determinism_test.dart"
Task: "Write painter parity test in packages/jet_print/test/rendering/export/pdf_painter_parity_test.dart"
Task: "Write fallback test (PDF cases) in packages/jet_print/test/rendering/export/export_fallback_test.dart"
Task: "Write performance test in packages/jet_print/test/rendering/export/export_performance_test.dart"

# Then implement sequentially (same file): T008 → T009 → T010, then T011 → T012 → T013 → T014
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup (T001–T002)
2. Phase 3: US1 — tests red (T003–T007), then `PdfPainter` → facade → surface → golden (T008–T014)
3. **STOP and VALIDATE**: open the exported invoice PDF in a viewer; select/search text; export twice and hash-compare
4. Ship: the product is now a document generator, not just a viewer

### Incremental Delivery

1. Setup → US1 (PDF) → validate → **MVP**
2. US2 (PNG) → validate dimensions/parity → ship
3. US3 (print) → validate via fake presenter + entitlements → ship
4. US4 (preview actions + playground) → validate end-to-end SC-008 → ship
5. Polish (T033–T037) → final green suite, format, analyze, quickstart walk-through

### Suggested Single-Developer Order

T001 → T002 → T003–T007 (parallel) → T008 → T009 → T010 → T011 → T012 → T013 → T014 → T015–T016 → T017 → T018 → T019 → T020 → T021 → T022 → T023 → T024 → T025 → T026–T028 (parallel) → T029 → T030 → T031 → T032 → T033–T034 (parallel) → T035 → T036 → T037

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- Verify every test fails before implementing it green (Constitution III — no merge with failing/skipped tests)
- Golden artifacts (`invoice.pdf`, `invoice_page1_2x.png`) are deliberate-update pins: PDF bytes may shift across Dart SDK/dart_pdf upgrades (zlib), PNG goldens compare decoded pixels (engine encoder not cross-machine byte-stable) — see research.md §2/§4
- Commit after each task or logical group; run `git` from the repo root (cwd can drift after `flutter` commands)
- The single public entry point `package:jet_print/jet_print.dart` is the only import consumers (including the playground) may use — the architecture test enforces this
