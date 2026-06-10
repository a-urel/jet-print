# Implementation Plan: Render Report — Data-Filled Paginated Preview (JetReportEngine Facade)

**Branch**: `011-render-export` | **Date**: 2026-06-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/011-render-export/spec.md`

## Summary

Deliver the **render slice**: a host hands a designed `ReportTemplate` plus **actual data** (records + parameter values) to a public engine facade, which **fills** the template (evaluates bound expressions, iterates master/detail collections, computes variables/aggregates), **paginates** the result, and presents it as an **on-screen, paginated, WYSIWYG preview** that matches the design surface. Export (PDF/print) is explicitly out of scope.

This slice is a **public facade over an already-complete internal engine**, not a new engine. Verified against the source (see [research.md](research.md)):

1. **The fill → layout → paginate → paint engine already exists and is tested.** `ReportFiller` ([report_filler.dart](../../packages/jet_print/lib/src/rendering/fill/report_filler.dart)) and `ReportLayouter` ([report_layouter.dart](../../packages/jet_print/lib/src/rendering/layout/report_layouter.dart)) — whose own doc comments name "the 011 JetReportEngine" as their public surface — already do flat + master/detail fill, variables/aggregates (`VariableCalculator`, all `JetCalculation`s), group header/footer boundaries, height-driven pagination, repeated page header/footer, and `PAGE_NUMBER`/`PAGE_COUNT` chrome. The data sources (`JetInMemoryDataSource`, `JetJsonDataSource`, `JetObjectDataSource`, plus `DataSet`/`DataRow`/`FieldDef`) and the structured `ReportDiagnostics`/`Diagnostic` type all exist under `src/`. ~75% of this slice is **exposing** what is there.
2. **One new public facade: `JetReportEngine`.** A thin orchestrator: `render(template, source, {params, locale})` runs fill → layout and returns a `RenderedReport` (+ diagnostics). It owns no rendering logic — it composes `ReportFiller` and `ReportLayouter` and threads the render options.
3. **One real, additive engine change: a lazy pagination seam.** FR-021/SC-009 require the **first page to render without materializing all pages**, but `ReportLayouter.layout()` is **eager** (`List<PageFrame>`) and `PAGE_COUNT` is resolved by a post-pass over `pages.length` ([report_layouter.dart:451](../../packages/jet_print/lib/src/rendering/layout/report_layouter.dart#L451)). We add an **additive, on-demand** page-production seam that reuses **all** existing measurement/pagination/frame logic — only the *driving loop* changes from build-all to yield-on-demand. No parallel render code (Constitution IV preserved); the eager `layout()` becomes a thin wrapper over the lazy seam, keeping every existing test green. PAGE_COUNT is resolved via a cheap boundary-only pass; see [research.md](research.md) §2.
4. **Explicit per-render locale (FR-012a).** Format functions currently read the ambient `Intl.defaultLocale` ([format_functions.dart:16](../../packages/jet_print/lib/src/expression/functions/format_functions.dart#L16)); the engine threads a per-render locale through fill + layout so formatting never depends on the app's UI locale.
5. **Preview widget (net-new, shared pipeline).** A read-only paginated viewer (prev/next, "page X of N", fit-to-width, keyboard-operable) that paints each `RenderedPage` via the **same** `paintFrame`/`CanvasPainter`/`PageFrame` path the designer uses — WYSIWYG by construction (Constitution IV). New chrome is localized en/de/tr with English fallback.
6. **Minimal public-surface expansion (Constitution I).** Export `JetReportEngine`, its render options, `RenderedReport`/`RenderedPage`, the diagnostics types, the **full data-source API** (`JetDataSource` + the three implementations + `DataSet`/`DataRow`), and the preview widget — all through `package:jet_print/jet_print.dart`; `src/` stays private. The playground gains a runnable **rendered-invoice** example.

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`, [pubspec.yaml](../../pubspec.yaml)), sound null-safety.
**Primary Dependencies**: Flutter SDK (`flutter`, `flutter_localizations`); `intl` (already present — drives gen-l10n **and** the per-render locale formatting of FR-012a); `shadcn_ui ^0.54.0` (preview chrome — nav buttons, page indicator, fit-to-width toggle). **No new library dependency** (export-format deps, if any, arrive with the deferred export slice — Assumptions).
**Storage**: The versioned `ReportTemplate` JSON via the existing `report_codec.dart` (`schemaVersion` **1**), consumed **unchanged** — FR-016: no schema change, no migration, round-trip fidelity preserved. Host data is **not** persisted (supplied per render through the data-source API). Library stays headless — no filesystem/print/network I/O (FR-015); the host pre-resolves image bytes (FR-012b).
**Testing**: `flutter test packages/jet_print apps/jet_print_playground` (run from repo root). Unit — facade orchestration (fill→layout wiring, params/locale threading); lazy pagination (first page produced without building all frames; `RenderedReport` page-on-demand + caching; PAGE_COUNT correctness); per-render locale formatting (number/date/currency independent of ambient locale); data-source parity (same logical dataset via in-memory / JSON / object-backed → identical output, SC-006); diagnostics (unknown field, missing param, unresolved image, empty dataset → specific diagnostic + non-crashing render, SC-007). Widget — preview prev/next nav, "page X of N" indicator, fit-to-width sizing, keyboard operation + accessible names, localized chrome (en/de/tr + fallback). Goldens — the **data-filled** invoice (real values, paginated) through the shared pipeline, light/dark (SC-003; closes the 009 deferral). Performance — SC-009: 1,000-record first page < 2 s, no all-pages materialization. The existing **encapsulation** + **layer-boundary** architecture tests ([layer_boundaries_test.dart](../../packages/jet_print/test/architecture/layer_boundaries_test.dart)) stay green with the expanded public surface.
**Target Platform**: macOS desktop (playground preview); the library itself stays platform-agnostic and headless. Preview input is mouse + keyboard (per the 003 accessibility precedent).
**Project Type**: Dart pub workspace monorepo — reusable library (`packages/jet_print`, the product) + sample/playground desktop app (`apps/jet_print_playground`, a consumer).
**Performance Goals**: SC-009 — a 1,000-record dataset reaches a **viewable first page in under 2 s** on the reference desktop environment, **without materializing all pages up front** (FR-021). First-page time MUST NOT scale with total record/page count; per-page frame construction is on demand.
**Constraints**: Constitution IV — the preview MUST reuse the shared `paintFrame`→`CanvasPainter`→`PageFrame` pipeline (no parallel draw code); the lazy seam MUST reuse the existing pagination/frame logic (no divergent layouter). Constitution I — all consumer access through `lib/jet_print.dart`; `src/` stays private (encapsulation test). Rendering MUST be deterministic (FR-010/SC-004): identical template+data+params+locale → byte-identical output. Headless (FR-015); host pre-resolves images (FR-012b). New visible chrome localized (en/de/tr, English fallback, FR-017); keyboard-operable with accessible names (FR-018). No template schema change (FR-016).
**Scale/Scope**: 1 new public facade (`JetReportEngine`) + 1 render-options type (locale, params) + public `RenderedReport`/`RenderedPage` IR + 1 additive lazy-pagination seam on `ReportLayouter` (eager `layout()` kept as wrapper) + per-render locale threading into fill/layout function context + public re-exports of the data-source API (`JetDataSource`, in-memory/JSON/object-backed, `DataSet`, `DataRow`) and diagnostics (`Diagnostic`, `DiagnosticSeverity`, `ReportDiagnostics`) + 1 net-new preview widget (nav, indicator, fit-to-width, keyboard, l10n) + new preview l10n keys (en/de/tr) + the playground rendered-invoice example. 4 user stories (P1–P3). **Export (PDF/image/print) is out of scope** (FR-020) — the `RenderedReport` IR is structured so a later export slice consumes it without rework.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | The new capability ships as library symbols from the single entry point: `JetReportEngine`, render options, `RenderedReport`/`RenderedPage`, the diagnostics types, the **full data-source API** (`JetDataSource` + in-memory/JSON/object-backed + `DataSet`/`DataRow`), and the preview widget. `FieldDef` is already public; `src/` stays private. The playground consumes them strictly as an external consumer (builds a data source, calls `render`, shows the preview). Encapsulation test stays green. |
| II | Layered & Extensible Architecture | ✅ PASS | The facade lives in the **rendering** seam and may depend on `fill`/`layout`/`expression`/`data`/`domain` (inward). The data-source API is the named **Data Binding** layer, promoted public unchanged. The preview is outermost (Flutter) and depends only on the rendered IR + shared painter. The lazy seam stays inside `rendering/layout`; no inward-pointing dependency is introduced. Layer-boundary test stays green. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | TDD throughout (red→green→refactor). Every new public symbol, the facade orchestration, the lazy seam, locale threading, data-source parity, and diagnostics get unit tests; the preview gets widget tests (nav/indicator/fit-to-width/keyboard/l10n); the data-filled invoice gets goldens; SC-009 gets a performance test asserting first-page-without-all-pages. No merge with failing/skipped tests. `tasks.md` front-loads test tasks (overrides the template's "tests optional"). |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | The preview paints each page through the **unchanged** shared `paintFrame`→`CanvasPainter`→`PageFrame` path — the identical pipeline the designer's `DesignTimeFrameBuilder` uses; no divergent draw code. The lazy seam **reuses** the existing layouter measurement/pagination/frame logic (only the driving loop changes); the eager `layout()` is preserved as a wrapper so existing goldens stay byte-stable. This slice **delivers the data-filled invoice golden** the 009 plan deferred — closing Constitution IV's "data-aware invoice scenario" at the rendered-value level, light/dark. |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | FR-016: templates are read through the **existing** format with **no schema change and no migration**; `schemaVersion` stays `1`; round-trip fidelity (incl. `UnknownElement` passthrough) is preserved. The render path is read-only over templates and persists nothing. |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on every new public symbol (facade, render options, `RenderedReport`/`RenderedPage`, diagnostics types, the newly-public data-source types, the preview widget). `CHANGELOG.md` updated. The playground gains a runnable **rendered-invoice** example (Principle VI example + Tech-standards MVP path: "preview it"); SC-008 caps consumer integration at < 30 lines. Zero analyzer warnings; `dart format` clean; docs/changelog updated in-change. |

**Result: PASS — no violations.** The single tracked item is the **additive lazy-pagination seam** required by FR-021/SC-009. It is *not* a Constitution IV violation: it reuses the existing layouter logic and introduces no parallel render path; it is recorded in *Complexity Tracking* for reviewer visibility.

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md) and [contracts/](contracts/) were written: still **PASS**. `RenderedReport`/`RenderedPage` are pure output IR over the existing `PageFrame`; the lazy seam keeps the eager `layout()` as a wrapper (no divergent rendering); the public-surface additions are the facade + data-source API + diagnostics + preview widget; no serialization change. No new violations; Complexity Tracking holds the one tracked seam.

## Project Structure

### Documentation (this feature)

```text
specs/011-render-export/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — decisions & rationale (facade shape, lazy pagination, locale)
├── data-model.md        # Phase 1 — entities & relationships (render IR, diagnostics, data sources)
├── quickstart.md        # Phase 1 — consumer wires template + data → preview (< 30 lines, SC-008)
├── contracts/
│   └── render-engine-api.md   # Phase 1 — public API + behavior contracts + test groups
└── tasks.md             # Phase 2 — /speckit.tasks (NOT created here)
```

### Source Code (repository root)

```text
packages/jet_print/                      # the library (the product)
├── lib/jet_print.dart                   # CHANGE: export JetReportEngine, render options,
│                                        #   RenderedReport/RenderedPage, diagnostics types,
│                                        #   JetDataSource + 3 impls + DataSet/DataRow,
│                                        #   the preview widget
└── lib/src/
    ├── rendering/
    │   ├── engine/
    │   │   ├── jet_report_engine.dart           # NEW: the public facade (fill→layout orchestrator)
    │   │   ├── render_options.dart              # NEW: per-render params + explicit locale (FR-012a)
    │   │   └── rendered_report.dart             # NEW: RenderedReport / RenderedPage output IR (lazy)
    │   ├── layout/
    │   │   └── report_layouter.dart             # CHANGE: additive lazy page-production seam;
    │   │                                        #   eager layout() kept as a thin wrapper
    │   └── paint/
    │       └── canvas_painter.dart              # (reused unchanged by the preview)
    ├── expression/functions/
    │   └── format_functions.dart                # CHANGE: honor per-render locale (not ambient default)
    ├── designer/
    │   ├── preview/
    │   │   └── jet_report_preview.dart          # NEW: read-only paginated viewer widget
    │   │                                        #   (prev/next, page X of N, fit-to-width, keyboard)
    │   └── l10n/
    │       ├── jet_print_en.arb                 # CHANGE: + preview chrome strings (edit ARBs only)
    │       ├── jet_print_de.arb                 # CHANGE
    │       └── jet_print_tr.arb                 # CHANGE  (then `flutter gen-l10n`)
    └── data/                                    # (JetDataSource + impls — promoted public, code unchanged)

apps/jet_print_playground/
└── lib/
    ├── main.dart                        # CHANGE: add a "Preview" path (template + data → JetReportPreview)
    └── rendered_invoice_example.dart    # NEW: invoice data source + render + preview (the runnable example)

packages/jet_print/test/                 # TDD — tests precede implementation
├── rendering/engine/
│   ├── jet_report_engine_test.dart              # NEW: facade fill→layout, params, deterministic output
│   ├── lazy_pagination_test.dart                # NEW: first page without all pages; page-on-demand; PAGE_COUNT
│   ├── render_locale_test.dart                  # NEW: explicit locale formatting (FR-012a)
│   └── render_diagnostics_test.dart             # NEW: malformed-input diagnostics, non-crashing (SC-007)
├── rendering/engine/data_source_parity_test.dart # NEW: in-memory == JSON == object-backed (SC-006)
├── rendering/engine/performance_test.dart        # NEW: 1,000-record first-page budget (SC-009)
├── designer/preview/
│   ├── jet_report_preview_test.dart             # NEW: nav, page X of N, fit-to-width, keyboard, a11y
│   └── preview_localization_test.dart           # NEW: en/de/tr chrome + English fallback
├── goldens/rendered_invoice_test.dart           # NEW: data-filled invoice, paginated, light/dark
└── architecture/layer_boundaries_test.dart      # extend: assert new public exports / seam boundaries

apps/jet_print_playground/test/
└── rendered_invoice_example_test.dart           # NEW: example renders + previews end-to-end
```

**Structure Decision**: Existing Dart pub workspace monorepo (library + sample app). All library work lands under `packages/jet_print/lib/src/` behind the single entry point; the rendered-invoice example lands in `apps/jet_print_playground/lib/` as an external consumer. The facade and render IR get a new `rendering/engine/` folder; the preview widget lands under `designer/preview/` (the Flutter/widget seam) reusing the shared painter. No new top-level structure.

## Complexity Tracking

> No Constitution **violations** to justify. One tracked **engine seam** (additive, reuses existing logic) and one closed **scope boundary** are recorded for reviewer visibility.

| Item | Why | Note |
|------|-----|------|
| Additive **lazy-pagination seam** on `ReportLayouter` | FR-021 + SC-009 require the first page to render **without materializing all pages**, but `layout()` is eager (`List<PageFrame>`) and `PAGE_COUNT` is a post-pass over `pages.length` ([report_layouter.dart:451](../../packages/jet_print/lib/src/rendering/layout/report_layouter.dart#L451)) | **Not** a Constitution IV violation: the seam **reuses** the existing measurement/pagination/frame logic — only the driving loop changes (build-all → yield-on-demand). The eager `layout()` is kept as a thin wrapper over the seam so every existing test/golden stays byte-stable. PAGE_COUNT/"of N" resolved via a cheap boundary-only pass (frames built per visible page); fallback (defer "of N" until known) recorded in [research.md](research.md) §2. |
| Data-filled invoice golden **delivered here** | The 009 plan deferred the *data-filled* invoice golden to "the render slice" | This **is** the render slice — it closes that deferral. Constitution IV's "data-aware invoice scenario" is now covered at the **rendered-value** level (real values, paginated, light/dark) through the shared pipeline. No divergent rendering introduced. |
