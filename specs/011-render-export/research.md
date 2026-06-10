# Phase 0 Research — Render Report (JetReportEngine Facade)

This slice exposes an **already-complete internal engine**. Research here resolved the *integration* and the *one genuine design tension* (lazy first-page pagination), grounded in a full read of the existing source. Each decision is recorded as **Decision / Rationale / Alternatives considered**.

## 0. Premise verification — does the engine actually exist?

**Decision**: Treat the slice as **facade + preview over a complete engine**, not an engine build.

**Rationale**: Direct source verification confirms the spec's central claim:
- `ReportFiller` ([report_filler.dart](../../packages/jet_print/lib/src/rendering/fill/report_filler.dart)) — complete flat + master/detail fill, variable calculator, diagnostics. Doc comment line 4: *"INTERNAL — the public surface is the 011 JetReportEngine."*
- `ReportLayouter` ([report_layouter.dart](../../packages/jet_print/lib/src/rendering/layout/report_layouter.dart)) — complete height-driven pagination, repeated page header/footer, group keep-together/reprint, `PAGE_NUMBER`/`PAGE_COUNT` chrome. Doc comment line 5: *"INTERNAL; the public surface is the 011 JetReportEngine."*
- `VariableCalculator` — all `JetCalculation`s (sum/count/average/min/max/first/last) with group + report reset scopes.
- Data sources — `JetInMemoryDataSource`, `JetJsonDataSource`, `JetObjectDataSource<T>`, plus `DataSet`/`DataRow`/`FieldDef`, all implemented and tested.
- Diagnostics — `Diagnostic`/`DiagnosticSeverity`/`ReportDiagnostics`, carried on both `FillResult` and `LayoutResult`.
- Shared paint pipeline — `paintFrame`/`CanvasPainter`/`PageFrame`, already shared by the designer's `DesignTimeFrameBuilder`.
- Extensive existing tests under `test/rendering`, `test/expression`, `test/data`.

**Alternatives considered**: *Build a fresh fill/layout pipeline* — rejected; it would duplicate a complete, tested engine and violate "no parallel render code" (Constitution IV).

## 1. Engine facade shape

**Decision**: A thin `JetReportEngine` with one primary method:

```dart
RenderedReport render(
  ReportTemplate template,
  JetDataSource source, {
  RenderOptions options = const RenderOptions(),
});
```

`RenderOptions` carries `Map<String, Object?> parameters` and an explicit `Locale locale` (FR-012a). The engine composes `ReportFiller.fill(...)` then the lazy layout seam, merges both passes' `ReportDiagnostics`, and returns a `RenderedReport` exposing pages (lazy) + diagnostics. The facade holds **no** rendering logic.

**Rationale**: Smallest seam that satisfies FR-001/FR-002 and keeps the public surface minimal (Constitution I). A single value object (`RenderOptions`) keeps the call site < 30 lines (SC-008) and is forward-compatible (an export slice adds options without breaking callers).

**Alternatives considered**: *Separate `fill()` and `layout()` public methods* — rejected; leaks the two-pass internal structure and invites callers to misuse it. *Positional params/locale args* — rejected; an options object is extensible and self-documenting.

## 2. Lazy first-page pagination (the one real design tension)

**Decision**: Add an **additive on-demand page-production seam** to `ReportLayouter` that **reuses all existing measurement/pagination/frame logic**; keep the eager `layout()` as a thin wrapper over it. `RenderedReport` produces a page's `PageFrame` **on demand** and caches it, so the first page is built without constructing the rest. Total page count (for `PAGE_COUNT` and the "page X of N" indicator) is resolved by a **cheap boundary-only pass** that measures/places bands to find page breaks **without** building paint primitives; the expensive glyph/frame construction happens per **visible** page.

**Rationale**: This is the slice's only non-facade work, and it is forced by the spec:
- FR-021 and clarification Q4 make lazy first-page a **firm acceptance gate** (SC-009): 1,000 records → viewable first page < 2 s, "without materializing all pages up front."
- Today the engine is eager: `FilledReport.bands` is a materialized `List<FilledBand>`, `ReportLayouter.layout()` returns `List<PageFrame>` (all frames built), and `PAGE_COUNT` is a post-pass over `pages.length` ([report_layouter.dart:451](../../packages/jet_print/lib/src/rendering/layout/report_layouter.dart#L451)) — structurally requiring all pages.
- The dominant first-page cost is **frame construction** (per-element text measurement + primitive emission), not band placement. Separating *boundary determination* (cheap geometry, yields page count + `PAGE_COUNT`) from *frame construction* (expensive, per-page, on demand) makes first-page time independent of total page count while keeping `PAGE_COUNT` exact.
- Because the seam reuses the existing logic and the eager `layout()` stays as a wrapper, **no parallel render path** is introduced (Constitution IV preserved) and every existing layouter test/golden stays byte-stable.

**Fallback (recorded)**: If, at scale, even the boundary-only pass cannot meet SC-009, the preview shows `Page X` immediately and resolves the `of N` (and any `PAGE_COUNT` token) once the boundary pass completes asynchronously. This keeps the first page firmly under budget; it is a fallback, not the primary plan.

**Alternatives considered**:
- *Eager fill+layout, rely on it being "fast enough"* — rejected; FR-021 explicitly forbids materializing all pages up front, regardless of wall-clock.
- *Fully streaming fill (lazy `FilledReport`)* — rejected for this slice; fill over 1,000 rows produces lightweight resolved data (no measurement), comfortably within budget, and making fill lazy is a larger change than the gate requires. The materialized cost that matters is **frames**, which the seam already defers.
- *Drop `PAGE_COUNT`/"of N" support to stay eager-free* — rejected; FR-008 mandates the "page X of N" indicator and templates legitimately use `PAGE_COUNT`.

## 3. Explicit per-render locale (FR-012a)

**Decision**: Thread `RenderOptions.locale` into the formatting path so number/date/currency formatting follows the **render's** locale, never the app UI locale. Implement by scoping the format functions' `NumberFormat`/`DateFormat` to the supplied locale for the duration of fill + layout (e.g. `Intl.withLocale(locale.toLanguageTag(), ...)` around both passes, or passing the locale into the function registry's format context).

**Rationale**: Format functions currently read the ambient `Intl.defaultLocale` ([format_functions.dart:16](../../packages/jet_print/lib/src/expression/functions/format_functions.dart#L16)), and that file's own doc comment already anticipates "a per-report locale injected." FR-012a requires formatting to be deterministic per render and decoupled from UI chrome locale. Scoping at the engine boundary keeps the change localized and keeps determinism (SC-004).

**Alternatives considered**: *Reuse the app's UI locale* — rejected by FR-012a (the two locales are independent; document formatting need not match chrome language). *Bake locale into the template* — rejected; locale is a render-time concern (the same template renders for different audiences), and FR-016 forbids schema changes.

## 4. Public data-source API surface (FR-011)

**Decision**: Promote the **full** data-source vocabulary to public, code unchanged: `JetDataSource`, `JetInMemoryDataSource`, `JetJsonDataSource`, `JetObjectDataSource<T>`, `DataSet`, `DataRow`. `FieldDef`/`JetFieldType` are already public from 009.

**Rationale**: FR-011 + US3 require a host to supply records (incl. nested collections) through the public API without touching `src/`. The three implementations already exist and are tested; exposure is re-export only. SC-006 (identical output across all three variants) is a parity test, not new code.

**Alternatives considered**: *Expose only a "plain rows" facade* — rejected; the spec's Assumptions explicitly subsume the plain-rows facade into the in-memory source and promote the full API. *Expose an abstract source only* — rejected; US3 names the three concrete variants as the deliverable.

## 5. Diagnostics surface (FR-013/FR-014)

**Decision**: Export the existing `Diagnostic`, `DiagnosticSeverity`, and `ReportDiagnostics`; the engine returns them on `RenderedReport.diagnostics`, merging fill-pass and layout-pass diagnostics in order.

**Rationale**: The render-don't-crash policy is already enforced internally (unknown field, missing param, unresolved image, empty dataset each yield a diagnostic + best-effort render). SC-007 ("0 unhandled crashes" across malformed inputs) is validated against the public surface; no new diagnostic machinery is required — only exposure + a malformed-input test matrix.

**Alternatives considered**: *Throw exceptions for malformed input* — rejected by FR-013/FR-014 (best-effort render, structured diagnostics, no abort). *A new diagnostics type* — rejected; the internal one already identifies element/band + problem.

## 6. Preview widget (FR-008/FR-009/FR-017/FR-018)

**Decision**: A net-new `JetReportPreview` widget: a **read-only** paginated viewer with prev/next navigation, a "page X of N" indicator, and fit-to-width sizing (clarification Q3). It paints the current `RenderedPage` by driving the **shared** `paintFrame`→`CanvasPainter` path inside a `CustomPainter` — the identical pipeline the designer uses. Navigation requests pages from the lazy `RenderedReport` (building on demand). Chrome (nav buttons, indicator, fit label) is localized en/de/tr with English fallback and keyboard-operable with accessible names.

**Rationale**: FR-009 mandates WYSIWYG fidelity *by reusing the same paint pipeline* — `DesignTimeFrameBuilder` already proves the designer paints via `paintFrame`/`CanvasPainter`, so the preview reuses that exact seam (Constitution IV by construction, not by parallel code). Read-only + prev/next + indicator + fit-to-width is exactly the interaction model fixed in clarification Q3 (no zoom/edit/annotation/print). The l10n/keyboard precedents come from the 003/009 designer chrome.

**Alternatives considered**: *Render all pages into a scroll view* — rejected; violates FR-021 (materializes all pages) and the read-only-paginated interaction model. *A new draw path for preview* — rejected; violates Constitution IV. *Add zoom/pan now* — rejected; out of scope per Q3/Assumptions.

## 7. Image resolution (FR-012b)

**Decision**: No new code — confirm the existing behavior satisfies the spec. The host supplies image **bytes** through the data source (`FieldImageSource` resolved at fill; `BytesImageSource` embedded); a URL-only source (`UrlImageSource` with no bytes) renders a placeholder + emits a diagnostic. The library performs no image I/O.

**Rationale**: `ImageElementRenderer` already emits an `ImagePrimitive` for bytes and a placeholder + diagnostic otherwise; this matches clarification Q1 and FR-012b exactly. Headlessness (FR-015) is preserved.

**Alternatives considered**: *Library fetches URLs* — rejected by Q1/FR-012b/FR-015 (no I/O; host pre-resolves).

## 8. Rendered IR structured for a future export slice (FR-020)

**Decision**: `RenderedReport` exposes ordered, on-demand `RenderedPage`s over the existing `PageFrame` IR (positioned, backend-agnostic primitives) plus diagnostics and page count. Export is **not** built here, but the IR is the natural input a later PDF/image/print slice consumes without rework.

**Rationale**: FR-020 keeps export out of scope while asking the preview result to be export-ready. `PageFrame` is already a backend-agnostic primitive stream (the painter is one backend); a PDF/image backend is a future `ReportPainter` implementation over the same frames — no IR rework. Keeping `RenderedPage` thin (a `PageFrame` + page index) avoids over-fitting to preview.

**Alternatives considered**: *Bake preview-only widget state into the IR* — rejected; couples the IR to Flutter and blocks the export slice. *Design the export API now* — rejected; explicitly out of scope (FR-020), risks speculative generality.

## 9. Determinism (FR-010/SC-004)

**Decision**: Keep the render pure over (template, data, params, locale): no clocks, no randomness, no ambient locale. The lazy seam and the eager wrapper MUST produce identical frames for a given page index; re-rendering identical inputs yields byte-identical paint output.

**Rationale**: SC-004 requires byte-identical re-renders; the engine is already deterministic, and the only ambient input (locale) is now explicit (§3). The lazy/eager equivalence is a tested invariant (a page built lazily equals the same page from `layout()`), which also guards the seam against regressions.

**Alternatives considered**: *Allow ambient locale/time in formatting* — rejected; non-deterministic, violates SC-004 and FR-012a.
