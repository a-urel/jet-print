# Implementation Plan: Host & System Fonts in Font Pickers

**Branch**: `022-host-fonts` | **Date**: 2026-06-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/022-host-fonts/spec.md`

## Summary

Spec 021 built the font picker, the per-typeface preview, the unavailable-family
behavior, and the `FontRegistry.families` getter the picker enumerates — but it
**deliberately left no public way for a host to add fonts** ([021 plan §Complexity,
row 2](../021-format-properties/plan.md)): designer-only registration would render
canvas text in families the engine/preview/exporter (each of which builds its own
default-only `FontRegistry`) cannot resolve — a silent WYSIWYG break. 022 opens that
seam correctly.

The whole feature is **host-registered fonts only** (OS-font discovery is deferred —
spec "Resolved Scope Decision"). The clarifications pin the contract: the host supplies
each face as **in-memory bytes**, registers **before a designer/render is built**, and
duplicate family names resolve **last-registration-wins**.

The design rests on one structural fact the exploration surfaced: **`RenderedReport`
is the single IR that preview, the PDF/PNG exporter, and the printer all consume**
([rendered_report.dart](../../packages/jet_print/lib/src/rendering/engine/rendered_report.dart),
[jet_report_preview.dart:73](../../packages/jet_print/lib/src/designer/preview/jet_report_preview.dart#L73)).
So host fonts thread through just **two** host touch-points, and the render chain
carries its own fonts:

1. **Public font value types (rendering layer).**
   [`JetFontFace`](data-model.md) `{bytes, weight, italic}` and
   [`JetFontFamily`](data-model.md) `{name, faces}`. `JetFontFamily` **validates its
   faces eagerly** by parsing each via the existing
   [`parseTtfMetrics`](../../packages/jet_print/lib/src/rendering/text/ttf/ttf_metrics.dart#L13)
   and throwing the (now-exported) `FontFormatException` — so a host detects an
   invalid/empty face **synchronously, at the natural point** (FR-010, SC-006), and
   nothing can throw later inside the widget tree or a render. It requires at least a
   regular face (FR-001). `FontRegistry` itself stays **internal**.

2. **Two host touch-points; the render chain carries its registry.**
   - `JetReportDesigner.fonts` / `JetReportWorkspace.fonts` → the designer's one
     hoisted [`FontRegistry`](../../packages/jet_print/lib/src/designer/jet_report_designer.dart#L115)
     (built `registerDefault()` then host families) → canvas, picker, and the existing
     `preloadUiFontFamilies` preview-preload, all unchanged downstream (021).
   - `RenderOptions.fonts` → `JetReportEngine.render` builds the registry once and
     **attaches it to `RenderedReport`** → `JetReportPreview`, `JetReportExporter`
     (`toPdf`/`pageToPng`), and `JetReportPrinter` **read it off the report** instead of
     each building a default-only one. Those three gain **no new public parameter** and
     become WYSIWYG-safe by construction (Principle IV).

3. **Last-wins + stable order by construction.** `FontRegistry.register` is a map
   assignment keyed by `family|weight|italic`, so applying host families after
   `registerDefault()` overwrites per face = last-wins (FR-009). The existing
   [`families`](../../packages/jet_print/lib/src/rendering/text/font_registry.dart#L77)
   getter lists the default first, then the rest in insertion order — built-ins, then
   host families in the order supplied (FR-008). Built-ins can be shadowed but never
   removed; the default always resolves (FR-006).

4. **Nothing new in the picker, the schema, or the render paths.** The picker already
   enumerates `families` and flags stored-but-unregistered names (021 / US2);
   PDF embedding is already keyed by the byte instance; PNG reuses `CanvasPainter`;
   measurement uses the same registry's metrics. Reports still store only the family
   *name* — `kReportSchemaVersion` is **unchanged**, no migration (Principle V). This
   feature only changes *which fonts are available*, exactly the spec's "Out of Scope"
   boundary.

5. **Playground proves it end-to-end (FR-012).** The playground bundles one custom
   font asset, builds a `List<JetFontFamily>` from its bytes, and passes the **same
   list** to `JetReportWorkspace.fonts` and to the `renderReport` callback's
   `RenderOptions.fonts` — demonstrating the font in the picker and rendered identically
   on canvas, preview, PDF, and PNG.

See [research.md](research.md) (8 grounded decisions), [data-model.md](data-model.md)
(public types, validation, registry/threading specs), [contracts/host-fonts-api.md](contracts/host-fonts-api.md)
(C1–C12 behavioral contracts + test groups), and [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`), sound null-safety.
**Primary Dependencies**: Existing only — `flutter`, `pdf` (already used by `PdfPainter`
for embedding), `shadcn_ui ^0.54.0` (the picker built in 021). The TTF metrics parser,
`FontRegistry`, `CanvasPainter`/`PdfPainter`/`PageRasterizer`, the `_FontFamilyRow`
picker, and `preloadUiFontFamilies` all already exist. **No new dependency** (research §6).
**Storage**: Report JSON via existing codecs, `kReportSchemaVersion` **unchanged**. A
text element already stores a font-family *name* (a `String`); host fonts add no field
and no schema version. Pre-feature reports round-trip byte-identically; a report naming a
font absent in the session uses the 021 unavailable-family path (research §7, US2).
**Testing**: `flutter test packages/jet_print` from repo root. Unit — `JetFontFace`
(weight/italic defaults), `JetFontFamily` eager validation (rejects empty/malformed/
no-regular face with `FontFormatException` naming the family; accepts regular-only),
registry build from host families (last-wins per face, `families` order = built-ins then
host insertion order, default never removed), `RenderedReport` carries the registry,
`RenderOptions.fonts` default empty. Widget — picker lists a host family previewed in its
own typeface and applies it (extends 021 C3); unavailable host family preserved when not
registered (US2). Golden — a page using a host family is byte-identical across canvas,
preview, PNG, and PDF (Principle IV); existing default-only goldens stay byte-identical
(SC-005). PDF — the host face is embedded once and text stays real/selectable (FR-004).
`public_api_test.dart` records the additions. **TDD red→green per contract group**
(Principle III).
**Target Platform**: Flutter desktop/web; reference env: macOS playground
(`apps/jet_print_playground`).
**Project Type**: Existing Dart pub workspace monorepo — library `packages/jet_print` +
consumer app `apps/jet_print_playground`.
**Performance Goals**: No new per-frame cost. Host faces parse once at family
construction and once at registry build (startup only); the picker/preview reuse the 021
path. Large font sets (spec edge case) are the host's `List` length; the picker is the
existing scrollable `ShadSelect`.
**Constraints**: WYSIWYG (IV) — the render chain (engine→`RenderedReport`→preview/
exporter/printer) carries **one** registry, so layout-measurement and every paint/embed
use the identical bytes; no parallel font path, no default-only fallback on the export
side. Layer boundaries (II) — public font types live in **rendering** (they reference the
domain `JetFontWeight` and call the rendering TTF parser; dependencies point inward);
`FontRegistry` stays internal; the engine/exporter/printer keep owning the registry build.
Minimal surface (I) — two value types, one exported exception, one `fonts` field on
`RenderOptions`, one `fonts` param on `JetReportDesigner`/`JetReportWorkspace`; export
paths get nothing new. Backward-compat (V) — schema unchanged, additive-only, default
behavior identical (SC-005). Docs (VI) — dartdoc on all new public symbols, CHANGELOG,
host-facing registration docs + playground demo (FR-012).
**Scale/Scope**: 2 new public value types + 1 newly-exported exception · 1 internal
`registerHostFonts`/family-ingest on `FontRegistry` · `fonts` on `RenderOptions` ·
registry carried on `RenderedReport` · engine builds it · exporter/printer/preview read
it · `fonts` on `JetReportDesigner` + `JetReportWorkspace` (forwarded) · playground custom
-font demo + host docs · test matrix above · 2 user stories (P1 host registration, P2
unavailable-font portability).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | Additions are minimal and additive: two value types (`JetFontFace`, `JetFontFamily`), one re-exported `FontFormatException`, `RenderOptions.fonts`, and a `fonts` parameter on `JetReportDesigner`/`JetReportWorkspace`. **No host code dependency** — fonts are bytes the host hands in (Principle I). `FontRegistry` and the registry carried on `RenderedReport` stay **internal**. `public_api_test` records the additions. |
| II | Layered & Extensible Architecture | ✅ PASS | Dependencies point inward: the public font types reference the domain `JetFontWeight` enum and call the rendering-layer TTF parser; they live in **rendering**, which the designer and engine already consume. The engine/exporter/printer keep owning their registry construction — the change is *where the bytes come from*, not a new cross-layer path. `layer_boundaries_test` stays green. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Red→green per contract group C1–C12: failing tests first for face/family validation (reject empty/malformed/no-regular, accept regular-only), last-wins registry build + `families` order, `RenderedReport` carrying the registry, picker listing/applying a host family, US2 unavailable preservation, and the canvas/preview/PNG/PDF parity golden. No merge with failing/skipped tests. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | The headline guarantee is **structural**: the engine builds one registry and `RenderedReport` carries it, so preview, PNG, and PDF measure-and-paint from the identical bytes layout used — they cannot fall back to a default-only registry (the precise 021-flagged break). The designer shares its own one hoisted registry (021). A parity golden pins a host-font page identical across all four paths; default-only goldens stay byte-identical. No parallel font path is introduced. |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | **No schema change**: a text element already stores only a font-family name; host fonts add no field, so `kReportSchemaVersion` is unchanged and there is no migration. A report naming an unregistered host font loads via the existing 021 unavailable-family path, preserves the name, and re-saves byte-identically (US2 / SC-003). |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on the two value types, the exported exception, and the new parameters/field (incl. the register-before-build contract and last-wins rule). `CHANGELOG.md` updated. Host-facing registration docs + the playground custom-font demo satisfy FR-012. Zero analyzer warnings; `dart format` clean. (No new localized strings: the picker reuses 021's labels and the existing `fontFamilyUnavailable`.) |

**Result: PASS — no violations.** Three items recorded in *Complexity Tracking* for
reviewer visibility: (a) host face bytes parse twice (validation + registry); (b) two
host threading points (designer + `RenderOptions`) rather than one; (c) a host may shadow
(never remove) a built-in family name under last-wins.

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md),
[contracts/host-fonts-api.md](contracts/host-fonts-api.md), and [quickstart.md](quickstart.md):
still **PASS**. The public surface stayed at two value types + one exported exception +
`RenderOptions.fonts` + the designer/workspace `fonts` param; `FontRegistry` and the
report-carried registry stayed internal; export/print/preview gained no parameter and
read the registry off `RenderedReport`; the schema stayed unchanged with byte-identical
pre-feature round-trips. No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/022-host-fonts/
├── plan.md              # This file (/speckit.plan output)
├── spec.md              # Feature spec (+ Clarifications 2026-06-13)
├── research.md          # Phase 0 — 8 decisions: render chain carries its registry (the WYSIWYG seam); public bytes value types; eager validation via existing FontFormatException; last-wins + stable order by construction; regular-face required; picker/preview reuse 021; no schema change; playground demo
├── data-model.md        # Phase 1 — JetFontFace / JetFontFamily (+ validation); FontRegistry host-ingest; RenderOptions.fonts; RenderedReport-carried registry; threading map; state transitions; NO schema change
├── quickstart.md        # Phase 1 — host registers a font → appears in picker → identical on canvas/preview/PDF/PNG → unavailable elsewhere
└── contracts/
    └── host-fonts-api.md # Phase 1 — C1–C12: value-type validation, registry build/last-wins/order, threading & WYSIWYG carry, picker listing/preview, US2 unavailable, no-schema-change, export embedding, default-behavior-unchanged, docs/demo
```

### Source Code (repository root)

```text
packages/jet_print/
├── lib/
│   ├── jet_print.dart                                   # CHANGE: export JetFontFace, JetFontFamily, FontFormatException; (FontRegistry stays unexported). Verify designer/workspace/RenderOptions already exported — only the new symbols add lines
│   └── src/
│       └── rendering/
│           ├── text/
│           │   ├── jet_font.dart                        # NEW (public): JetFontFace {Uint8List bytes; JetFontWeight weight=normal; bool italic=false} + JetFontFamily {String name; List<JetFontFace> faces} with eager validation (≥1 regular face; each face parseTtfMetrics-or-throw FontFormatException naming the family); ==/hashCode
│           │   ├── font_format_exception.dart           # (unchanged; now re-exported from the barrel)
│           │   └── font_registry.dart                   # CHANGE: + void registerHostFonts(List<JetFontFamily>) applying families after registerDefault (last-wins per family|weight|italic); families order already correct. Stays internal
│           └── engine/
│               ├── render_options.dart                  # CHANGE: + List<JetFontFamily> fonts = const [] (dartdoc: register-before-render; threaded to RenderedReport)
│               ├── jet_report_engine.dart               # CHANGE: build FontRegistry()..registerDefault()..registerHostFonts(options.fonts) once; pass to ReportLayouter (measurement) AND attach to RenderedReport
│               └── rendered_report.dart                 # CHANGE: + internal final FontRegistry fonts (set by the engine); preview/exporter/printer read it instead of building default-only
├── lib/src/designer/
│   ├── jet_report_designer.dart                         # CHANGE: + List<JetFontFamily> fonts param; _fonts = FontRegistry()..registerDefault()..registerHostFonts(widget.fonts); preloadUiFontFamilies already iterates families (host fonts preload free)
│   ├── jet_report_workspace.dart                        # CHANGE: + List<JetFontFamily> fonts param; forward to the nested JetReportDesigner. (Preview side inherits via the host's renderReport→RenderOptions.fonts→RenderedReport.)
│   └── preview/jet_report_preview.dart                  # CHANGE: paint with widget.report.fonts (the carried registry) instead of constructing FontRegistry()..registerDefault() at line 120
├── lib/src/rendering/export/jet_report_exporter.dart    # CHANGE: toPdf/pageToPng use report.fonts (carried) instead of building default-only at lines 43/74 — WYSIWYG carry
└── test/
    ├── rendering/text/
    │   ├── jet_font_test.dart                           # NEW: face defaults; family rejects empty/malformed/no-regular (FontFormatException message names family); accepts regular-only; equality
    │   └── font_registry_host_test.dart                 # NEW: registerHostFonts last-wins per face; families = built-ins then host insertion order; default never removed even when shadowed; bytes/metrics resolve to host face
    ├── rendering/engine/
    │   ├── render_options_test.dart                     # EXTEND/NEW: fonts default empty; carried onto RenderedReport.fonts (built default+host)
    │   └── rendered_report_fonts_test.dart              # NEW: RenderedReport exposes the engine-built registry; default-only when options.fonts empty
    ├── rendering/export/
    │   └── pdf_painter_parity_test.dart                 # EXTEND: a host face is embedded once and selectable; export uses the carried registry (not default-only)
    ├── rendering/
    │   └── host_font_parity_golden_test.dart            # NEW: a page using a host family is byte-identical across canvas/preview/PNG/PDF; default-only goldens unchanged (SC-002/SC-005)
    ├── designer/
    │   └── properties_editor_test.dart                  # EXTEND: picker lists a host family previewed in its own typeface and applies it (C3+); a host family absent from the registry shows unavailable + preserved (US2)
    └── public_api_test.dart                             # UPDATE: JetFontFace, JetFontFamily, FontFormatException exported; RenderOptions.fonts; designer/workspace fonts param; FontRegistry still NOT exported

apps/jet_print_playground/
├── assets/fonts/                                        # NEW: one custom .ttf the playground bundles (its own asset — keeps the library self-contained)
├── pubspec.yaml                                         # CHANGE: declare the custom font asset
└── lib/main.dart                                        # CHANGE: load the asset bytes → List<JetFontFamily>; pass the SAME list to JetReportWorkspace.fonts AND the renderReport RenderOptions.fonts (FR-012)
```

**Structure Decision**: Existing workspace monorepo; no new top-level structure. The two
public value types live in the **rendering** layer beside `FontRegistry` (they call its
TTF parser and reference the domain weight enum — inward only). The single
WYSIWYG-critical fact — *one* registry per render — is enforced by the engine building it
and `RenderedReport` carrying it, so preview, PNG, PDF, and print physically share it. The
designer keeps its one hoisted registry (021). `FontRegistry` stays internal; the host
sees only bytes-in value types and two threading points, with the playground demonstrating
the single shared list.

## Complexity Tracking

> No Constitution **violations** to justify. Three tracked items for reviewer visibility.

| Item | Why | Note |
|------|-----|------|
| Host face bytes are parsed twice (once validating in `JetFontFamily`, once in `FontRegistry.register`) | Eager validation gives the host **synchronous** rejection at the natural point (assembling the font), keeping widget construction and renders throw-free (FR-010/SC-006); the registry re-parses on register as it does for built-ins. | Cost is startup-only and only for host faces (typically a handful). Could be removed later by having the family carry parsed metrics, but that would leak the internal `FontMetrics` type into the public API — rejected for Principle I. Recorded in [research §3](research.md). |
| Two host threading points (`JetReportDesigner.fonts` and `RenderOptions.fonts`) instead of one | The designer (interactive editing) and the engine (headless render) are genuinely separate lifecycles invoked by different host code at different times; there is no single object both pass through. | Mitigated structurally: the render chain carries its own registry, so preview/export/print — 3 of the 5 candidate points — inherit fonts with **no** host action and cannot diverge (Principle IV). The playground demonstrates passing **one** shared `List<JetFontFamily>` to both. Recorded in [research §1](research.md). |
| A host may **shadow** a built-in family name under last-wins | FR-009 mandates one deterministic rule for all duplicate names; carving out the three built-in names would make the rule conditional and surprising. | Last-wins replaces a built-in face's *bytes* but never removes the family: `registerDefault()` always runs first, `hasDefault` stays true, and the default always resolves (FR-006). Docs recommend distinct names. Recorded in [research §4](research.md). |
