# Implementation Plan: Export Support — PDF, Image, and Print Output

**Branch**: `012-export-support` | **Date**: 2026-06-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/012-export-support/spec.md`

> **Branch provenance note**: PR #6 merged only the 011 spec-kit documents; the 011
> *implementation* commits were never pushed and its branch ref was deleted. The full
> implementation (tip `c3656dc`, "full suite green") was recovered from the reflog and
> merged into this branch (`33913d7`); the suite was re-verified green (795 tests) before
> this plan was written. This slice builds directly on that recovered code.

## Summary

Deliver the **export slice** deferred out of 011: turn the same `RenderedReport` the
preview displays into shareable artifacts — a **PDF document** (in-memory bytes, real
selectable text, embedded fonts), **per-page PNG images** at a host-chosen scale, and a
**print job** via the system print dialog — plus optional **export/print toolbar actions**
on `JetReportPreview` that invoke host callbacks, and playground save/print examples.

The architecture makes this slice small by construction. 011's render output is a
`RenderedReport` of `RenderedPage`s over backend-agnostic `PageFrame` display lists, and
painting already flows through the `ReportPainter` abstraction walked by the shared
`paintFrame()` orchestrator ([report_painter.dart](../../packages/jet_print/lib/src/rendering/paint/report_painter.dart)) —
its exhaustive primitive switch was *designed* for a future export backend. So:

1. **PDF export = one new `ReportPainter` backend.** A pure-Dart `PdfPainter` over the
   low-level `package:pdf` API (`PdfDocument`/`PdfPage`/`PdfGraphics`) draws the **same
   pre-measured primitives** the screen draws: `TextRunPrimitive` carries laid-out lines
   with exact baselines (no re-wrapping), fonts come as bytes from the same `FontRegistry`
   that measured them (embedded as TTF), images reuse `computeImageFit`. WYSIWYG is by
   construction — no parallel paint code (Constitution IV, FR-001/FR-003).
2. **PNG export = rasterizing the existing `CanvasPainter`.** A page rasterizer records
   the frame through the *unchanged* `paintFrame` → `CanvasPainter` path (identical to the
   preview), scales the canvas, and encodes via `dart:ui` `Picture.toImage` →
   `ImageByteFormat.png` — the exact mechanism the golden tests already trust.
3. **Print = the PDF artifact handed to `package:printing`.** A `JetReportPrinter` helper
   presents the system print dialog (`Printing.layoutPdf`) for the exported PDF at the
   template's true page size — the one sanctioned exception to headlessness (FR-009a) —
   behind an injectable presenter seam so the capability is swappable and testable.
4. **Determinism (FR-007)** is achieved by zero/fixing the only nondeterministic PDF
   outputs (creation timestamp, document ID — see [research.md](research.md) §2) and by
   the already-deterministic render pipeline; byte-level golden tests pin the artifacts.

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`), sound null-safety.
**Primary Dependencies**: Existing: Flutter SDK, `intl`, `shadcn_ui` (chrome). **New (anticipated by 011's assumptions)**: `pdf` ^3.12.0 (pure-Dart PDF generation; low-level `PdfDocument`/`PdfGraphics` API; Apache-2.0; actively maintained), `printing` ^5.14.3 (system print dialog; same author/repo; Apache-2.0; Android/iOS/macOS/Windows/Linux/web), and `image` (pure-Dart PNG→RGBA decode for PDF embedding; MIT; already transitive via `pdf`, declared direct because we import it). All pub.dev-publication compatible. See [research.md](research.md) §1/§3 for the selection rationale and alternatives.
**Storage**: N/A — no template schema change (FR-012, `schemaVersion` stays 1); artifacts are **in-memory bytes** (FR-009); the host owns persistence (playground: `file_selector`, already a playground dependency).
**Testing**: `flutter test packages/jet_print apps/jet_print_playground` (repo root). Unit — PDF determinism (two exports → byte-identical, SC-004), PDF structure (page count, MediaBox = template points, embedded font objects, real-text operators — FR-004/005/008), PdfPainter primitive coverage (text baseline/align, image fit, line/rect/path parity with CanvasPainter semantics), PNG dimensions at 1x/2x/3x (SC-006) + determinism, out-of-range page error, empty-report/unresolved-image/failed-expression fallbacks (SC-007), print-unavailable error via injected fake presenter (FR-009a). Goldens — pinned invoice PDF bytes + page-1 PNG cross-checked against the existing preview goldens. Widget — preview export/print actions (present with callbacks, absent without — FR-015), keyboard + accessible names, en/de/tr chrome. Performance — SC-005: 1,000-record PDF < 10 s. Architecture — layer-boundary test extended deliberately (see Complexity Tracking).
**Target Platform**: The export core stays platform-agnostic, headless Dart; PNG rasterization uses `dart:ui` (any Flutter engine); print availability is per-platform via `printing` with a structured error where unsupported. Reference environment: macOS desktop playground.
**Project Type**: Existing Dart pub workspace monorepo — library `packages/jet_print` (the product) + consumer app `apps/jet_print_playground`.
**Performance Goals**: SC-005 — the 011 1,000-record performance dataset exports to a complete PDF in **< 10 s** without memory exhaustion (export materializes all pages, FR-011 — lazy preview state is irrelevant to export). PNG at scale *s* has exactly `round(page × s)` pixel dimensions (SC-006).
**Constraints**: **Byte-determinism** (FR-007): identical rendered input + options → byte-identical artifacts; PDF creation date/document ID fixed/zeroed; no clock/random/ambient-locale reads anywhere in the export path. **No parallel paint code** (Constitution IV, FR-001/003): PDF goes through the same `paintFrame` walk; PNG through the same `CanvasPainter`. **Headless for file artifacts** (FR-009), print the sanctioned exception (FR-009a). **Single awaitable call** per export (no progress/cancel this slice; API must allow adding them additively). **Minimal public surface** (Constitution I): everything via `package:jet_print/jet_print.dart`; encapsulation/architecture tests stay green (with deliberate, pinned allowlist extensions). New chrome localized en/de/tr + English fallback, keyboard-operable with accessible names (FR-014).
**Scale/Scope**: 1 export facade (`JetReportExporter`: `toPdf`, `pageToPng`) + 1 pure-Dart PDF painter + 1 dart:ui page rasterizer + 1 print helper (`JetReportPrinter` + injectable presenter seam + `PrintUnavailableException`) + 2 optional preview callbacks (`onExportPdf`, `onPrint`) with toolbar buttons + ~2 ARB keys × 3 locales + playground save/print wiring + the test matrix above. 4 user stories (P1–P3).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | New public symbols, all via the single entry point: `JetReportExporter`, `JetReportPrinter` (+ its presenter seam type and `PrintUnavailableException`), and two optional `JetReportPreview` callbacks. No `src/` exposure; image-export options stay lean (a `scale` parameter — no speculative option classes). The playground consumes export/print strictly through the public API (US4 acceptance: no `src/` import); the encapsulation architecture test extends to pin the new surface. |
| II | Layered & Extensible Architecture | ✅ PASS | PDF export lives in the **rendering** seam as one more `ReportPainter` backend — the extension point that seam already defines; it depends only inward (frame primitives, fonts, domain) plus pure-Dart `package:pdf`. The PNG rasterizer joins `CanvasPainter` as the second declared dart:ui paint backend. Print lives in a **new outermost seam** (`src/print/`) that consumes the rendering seam's PDF bytes and isolates the `printing` plugin behind a swappable presenter abstraction (Tech-standards: "printing … through well-scoped, swappable abstractions so the rendering core stays platform-agnostic"). The domain model imports nothing new. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | TDD red→green→refactor for every public symbol and behavior: determinism byte tests, PDF structure tests, painter-parity tests, PNG dimension/determinism tests, malformed-input matrix (SC-007), fake-presenter print tests, preview widget tests, performance test. `tasks.md` will front-load test tasks (overrides the template's "tests optional"). No merge with failing/skipped tests. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | **No parallel paint code.** PDF: a new backend behind the *same* `ReportPainter` interface, driven by the *same* `paintFrame` exhaustive walk over the *same* `PageFrame` primitives the preview paints — pre-measured text lines (exact baselines, no re-wrap), same `FontRegistry` bytes for measure/embed, same `computeImageFit`. PNG: literally the preview's `CanvasPainter`, rasterized. Goldens pin the invoice PDF + PNG artifacts and cross-check them against the existing preview goldens (SC-002); any visual change is a deliberate golden update. |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | FR-012: zero schema change, zero migration, `schemaVersion` stays 1. Export is read-only over the rendered IR and persists nothing. |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on every new public symbol (FR-013); `CHANGELOG.md` updated; the playground gains runnable save-as-PDF and print examples wired to the rendered-invoice preview (SC-001: < 10 integration lines beyond the 011 example; SC-008 end-to-end). New dependencies justified, minimal, permissively licensed, maintained (Tech-standards). Zero analyzer warnings; `dart format` clean. |

**Result: PASS — no violations.** Two items are recorded in *Complexity Tracking* for
reviewer visibility: the two new third-party dependencies, and the deliberate
architecture-test allowlist extensions.

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md), [contracts/export-api.md](contracts/export-api.md),
and [quickstart.md](quickstart.md) were written: still **PASS**. The public surface stayed
minimal (two capability classes, one exception, one presenter typedef, two widget
callbacks); the PDF painter remained a pure `ReportPainter` implementation with no layout
logic of its own; print stayed isolated in its own seam; no serialization change emerged.
No new violations; Complexity Tracking holds the two tracked items.

## Project Structure

### Documentation (this feature)

```text
specs/012-export-support/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — backend choice, determinism mechanics, print seam
├── data-model.md        # Phase 1 — export entities & relationships
├── quickstart.md        # Phase 1 — consumer adds export/print in < 10 lines (SC-001)
├── contracts/
│   └── export-api.md    # Phase 1 — public API + behavior contracts + test groups
└── tasks.md             # Phase 2 — /speckit.tasks (NOT created here)
```

### Source Code (repository root)

```text
packages/jet_print/
├── pubspec.yaml                                  # CHANGE: + pdf, + printing
├── lib/jet_print.dart                            # CHANGE: export JetReportExporter,
│                                                 #   JetReportPrinter, PrintUnavailableException,
│                                                 #   presenter seam type
└── lib/src/
    ├── rendering/
    │   ├── export/
    │   │   ├── jet_report_exporter.dart          # NEW: facade — toPdf(report) / pageToPng(report, i, scale)
    │   │   └── pdf_painter.dart                  # NEW: ReportPainter → package:pdf PdfGraphics
    │   │                                         #   (pure Dart; fixed metadata for determinism)
    │   └── paint/
    │       ├── canvas_painter.dart               # (reused unchanged — PNG + preview)
    │       └── page_rasterizer.dart              # NEW: frame → ui.Picture → ui.Image → PNG bytes
    │                                             #   (dart:ui; joins canvas_painter on the declared allowlist)
    ├── print/
    │   └── jet_report_printer.dart               # NEW: print helper over package:printing;
    │                                             #   injectable dialog-presenter seam;
    │                                             #   PrintUnavailableException
    └── designer/
        ├── preview/jet_report_preview.dart       # CHANGE: optional onExportPdf/onPrint
        │                                         #   toolbar actions (absent when callbacks null)
        └── l10n/
            ├── jet_print_en.arb                  # CHANGE: + previewExport/previewPrint strings
            ├── jet_print_de.arb                  # CHANGE   (then `flutter gen-l10n`)
            └── jet_print_tr.arb                  # CHANGE

apps/jet_print_playground/
├── lib/
│   ├── main.dart                                 # CHANGE (if needed): route unchanged
│   └── rendered_invoice_example.dart             # CHANGE: wire onExportPdf (file_selector save)
│                                                 #   + onPrint (JetReportPrinter) — SC-001/SC-008
└── macos/Runner/
    ├── DebugProfile.entitlements                 # CHANGE: + com.apple.security.print
    └── Release.entitlements                      # CHANGE: + com.apple.security.print

packages/jet_print/test/                          # TDD — tests precede implementation
├── rendering/export/
│   ├── pdf_export_test.dart                      # NEW: page count, MediaBox points, embedded fonts,
│   │                                             #   real-text operators, image placement (US1)
│   ├── pdf_determinism_test.dart                 # NEW: export twice → byte-identical; golden PDF pin (SC-004)
│   ├── pdf_painter_parity_test.dart              # NEW: per-primitive semantics vs CanvasPainter contract
│   ├── png_export_test.dart                      # NEW: dimensions ×scale, page order, determinism,
│   │                                             #   out-of-range error (US2/SC-006)
│   ├── export_fallback_test.dart                 # NEW: empty report / unresolved image / failed
│   │                                             #   expression → faithful fallback, 0 crashes (SC-007)
│   └── export_performance_test.dart              # NEW: 1,000-record PDF < 10 s (SC-005)
├── print/jet_report_printer_test.dart            # NEW: presenter receives PDF + page size;
│                                                 #   unavailable → PrintUnavailableException (US3)
├── designer/preview/jet_report_preview_test.dart # EXTEND: export/print actions present/absent,
│                                                 #   keyboard + a11y, callbacks invoked (US4/FR-015)
├── designer/preview/preview_localization_*.dart  # EXTEND: new strings en/de/tr + fallback
├── goldens/                                      # NEW: invoice.pdf + invoice_page1_2x.png pins
└── architecture/layer_boundaries_test.dart       # EXTEND: export/ files Flutter-free except
                                                  #   page_rasterizer; print/ seam rules; public surface

apps/jet_print_playground/test/
└── rendered_invoice_example_test.dart            # EXTEND: export/print actions wired end-to-end (SC-008)
```

**Structure Decision**: Existing workspace monorepo, no new top-level structure. PDF export
joins the rendering seam (it is a paint backend); the rasterizer joins `paint/` beside the
`CanvasPainter` it composes; print gets its own small outermost seam (`src/print/`) because
it is the only platform-channel-touching capability in the library and must stay isolated
and swappable. Preview chrome changes stay in `designer/preview/`.

## Complexity Tracking

> No Constitution **violations** to justify. Two tracked items recorded for reviewer
> visibility.

| Item | Why | Note |
|------|-----|------|
| New third-party dependencies: `pdf` + `printing` | PDF generation with real text + embedded fonts is far outside "build it ourselves" scope; the system print dialog requires platform channels per OS | Explicitly anticipated by 011 ("export-format dependencies, if any, arrive with the deferred export slice"). Both Apache-2.0, same maintained repo (DavBfr/dart_pdf), pub.dev-publication compatible (Tech-standards). `pdf` is pure Dart — the rendering seam stays Flutter-free; `printing` is confined to the new `src/print/` seam behind a swappable presenter abstraction. Alternatives evaluated in [research.md](research.md) §1/§5. |
| Architecture-test allowlist extensions | (a) `page_rasterizer.dart` must import `dart:ui` (PNG encoding is an engine capability), joining `canvas_painter.dart` as the **second** declared dart:ui paint backend; (b) the new `src/print/` seam may import `package:printing` and the rendering seam — and nothing may import *it* | Both extensions are deliberate, minimal, and **pinned by the extended layer-boundary test itself** — the test still fails if any other rendering file grows a dart:ui/Flutter import or any library file imports `printing` outside `src/print/`. This *narrows* future drift rather than widening it. |
