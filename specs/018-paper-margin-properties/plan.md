# Implementation Plan: Editable Paper Type & Margins in Report Properties

**Branch**: `018-paper-margin-properties` | **Date**: 2026-06-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/018-paper-margin-properties/spec.md`

## Summary

Turn the Properties panel's **PAGE** section from read-only text into an editable page-setup control,
mirroring **Microsoft Office's print-settings layout**: a **live page-preview thumbnail** (a proportional
sheet with margin guides that reflects orientation), a **paper-type** picker (A4, A3, A5, Letter, Legal,
Custom), a **portrait/landscape** toggle, **Custom** width/height fields, and **margins** (Normal / Narrow /
Wide / None presets plus editable per-side left/top/right/bottom). Today
[`_reportInspector`](../../packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart#L355)
renders two `_ReadonlyRow`s — `'595 × 842 pt'` and `'28 · 28 · 28 · 28'` — straight off
[`controller.template.page`](../../packages/jet_print/lib/src/domain/page_format.dart#L8).

The change is small and follows the seam already proven by 013 (format presets) and 017 (rename):

1. **One undoable controller op** — `JetReportDesignerController.setPageFormat(PageFormat)` commits a new
   `SetPageFormatCommand` through the existing
   [`_commit`](../../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart#L956)
   path (`before.template.copyWith(page:)`), **clamping** first so the content area stays positive (FR-009).
   Every page edit — size, orientation, or a single margin side — is one command = one undo step (FR-007).

2. **Presets as a designer-layer lookup, never persisted** — new `paper_presets.dart` / `margin_presets.dart`
   beside [`format_presets.dart`](../../packages/jet_print/lib/src/designer/format_presets.dart): the standard
   sizes/margins plus pure *recognition* functions that name the current page by its matching preset **in
   either orientation**, or report **Custom** when nothing matches — without touching the dimensions (FR-002,
   FR-003, FR-005). Only the resulting `PageFormat` ever reaches the model, exactly as only an ICU pattern
   reaches `TextElement.format` today.

3. **The PAGE section rebuilt** — the two `_ReadonlyRow`s become: a `_PagePreview` thumbnail (a small
   `CustomPaint`, the Office-style sample), a paper-type dropdown, an orientation toggle, Custom W/H fields
   (shown for Custom), a margin-preset dropdown, and four per-side margin `_NumberField`s — all reusing the
   panel's existing `_LabeledRow` / `_NumberField` / picker patterns and committing via `setPageFormat`.

Because canvas, preview, and export/print all read the same
[`template.page`](../../packages/jet_print/lib/src/rendering/frame/page_frame.dart#L15), one
`notifyListeners()` propagates everywhere with **no render-path fork** (WYSIWYG, IV). `PageFormat` already
serializes width/height/margins; `kReportSchemaVersion` stays **1**, no migration, old templates load
unchanged (V).

See [research.md](research.md) for the grounded decisions (preset values + recognition tolerance, clamp
strategy, single `setPageFormat` op, the Office-style preview, zero serialization impact),
[data-model.md](data-model.md) for the entities (the one new command, `PageFormat.copyWith`, the preset
tables, the recognition truth table), [contracts/page-properties.md](contracts/page-properties.md) for the
behavioral contracts + test groups, and [quickstart.md](quickstart.md) for the end-to-end walk.

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`), sound null-safety.
**Primary Dependencies**: Existing only — `shadcn_ui ^0.54.0` (`ShadInput`/`ShadSelect`-style pickers,
`ShadButton` segmented toggle), `flutter` (`CustomPaint` for the page-preview sample, `TextEditingController`,
`Focus`, `Semantics`). Same widgets the panel's `_NumberField` / `_FormatPicker` already use. **No new deps.**
**Storage**: None new. `PageFormat{width,height,margins}` already serializes via
[`page_format.dart`](../../packages/jet_print/lib/src/domain/page_format.dart#L41) inside `ReportTemplate.page`
([`report_codec.dart`](../../packages/jet_print/lib/src/domain/serialization/report_codec.dart#L23),
`kReportSchemaVersion = 1`). This feature only *edits* those existing fields. Preset identity and orientation
are **derived, not stored**. No new field, no migration.
**Testing**: `flutter test packages/jet_print` (from repo root). Unit — `PageFormat.copyWith`; preset
recognition (each standard size → its name in both orientations; non-match → Custom; rounded display still
matches); margin-preset recognition (four equal sides → preset; uneven → Custom); clamp (margins ≥ extent and
sub-minimum size corrected to nearest valid, content area stays positive); `setPageFormat` is one undoable,
notifying step that survives a codec round-trip; content not repositioned (top-left preserved, FR-013). Widget
— paper dropdown resizes the page; orientation swaps W/H; Custom reveals W/H fields; margin preset sets four
sides; per-side edit changes only that side and marks Custom; empty/non-numeric reverts; the `_PagePreview`
reflects size/orientation/margins; controls present + localized across en/de/tr; available with no selection.
Golden — a Letter / landscape page propagates identically to canvas, preview, and export (new goldens for the
non-default page; existing default-A4 goldens stay byte-identical). Regression — codec, layout, existing
property/golden suites green; `public_api_test.dart` records the additions.
**Target Platform**: Designer Properties UI (Flutter desktop/web). Reference env: macOS desktop playground
(`apps/jet_print_playground`).
**Project Type**: Existing Dart pub workspace monorepo — library `packages/jet_print` + consumer app
`apps/jet_print_playground`.
**Performance Goals**: No new budget. `setPageFormat` is one `_commit`; the `_PagePreview` is a tiny
`CustomPaint` (a few rects) rebuilt only on page change via the existing `DesignerScope` `InheritedNotifier`.
The render pipeline and the cached element picture (`FrameCustomPainter`) are untouched.
**Constraints**: WYSIWYG (IV) — canvas/preview/export all read the one `template.page`; no parallel render
path is added, so a size/margin change shows identically in all three. The `_PagePreview` is a **schematic
inspector affordance** (proportional sheet + guide lines), explicitly *not* a second report renderer. Layer
boundary (II) — domain gains only `copyWith` (no UI/render import); presets, recognition, command, and panel
live in the **designer** seam; rendering keeps reading `page` as before. Minimal public surface (I) — one
controller method + `PageFormat.copyWith` (+ `JetEdgeInsets.copyWith`); presets/recognition/preview stay
private. Clamp-not-reject (FR-009) keeps every produced page usable. l10n (FR-012) — all new labels in en/de/tr.
**Scale/Scope**: 1 new controller op (`setPageFormat`) + 1 new command (`SetPageFormatCommand`) · `copyWith`
on `PageFormat` (+ `JetEdgeInsets`) · 2 preset/recognition files · the rebuilt PAGE section (paper picker,
orientation toggle, custom W/H, margin preset, 4 side fields, `_PagePreview` thumbnail) · ~14 new ARB keys ×
3 locales · the test matrix above · 3 user stories (P1 paper type, P2 margins, P3 orientation + custom).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | New public surface is minimal and additive: `JetReportDesignerController.setPageFormat(PageFormat)` (undoable, mirrors `setBandHeight`/`setGeometry`) plus `PageFormat.copyWith` and `JetEdgeInsets.copyWith` on already-public immutable value types. Paper/margin preset tables, the recognition functions, the `SetPageFormatCommand`, and the `_PagePreview` thumbnail all stay **private** under `src/` (presets follow the `format_presets.dart` precedent — preset identity is never exported or persisted). `public_api_test` updated to record the additions. |
| II | Layered & Extensible Architecture | ✅ PASS | Dependencies point inward: the **domain** change is purely additive `copyWith` on `PageFormat`/`JetEdgeInsets` — no Flutter/UI/render import enters the domain. Presets, recognition, `SetPageFormatCommand`, and the rebuilt panel live entirely in the **designer** seam; `apply()` is `template.copyWith(page:)`. Rendering still reads `page` from the model — untouched. `layer_boundaries_test` stays green. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Red→green→refactor. The load-bearing behaviors are pinned by **failing** tests first: clamp keeps content area positive; recognition maps each preset (both orientations) and falls back to Custom; `setPageFormat` is a single undoable, notifying step that round-trips through the codec and does not move content (FR-013). Widget tests drive each control (paper, orientation, custom W/H, margin preset, per-side, revert-on-invalid, preview) before they exist. No merge with failing/skipped tests. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | Canvas (`design_time_layout`), preview, and export (`page_rasterizer` / exporter) read the **same** `template.page`; this feature forks no render path, so a paper/margin/orientation change is identical in all three (SC-003). New goldens for a Letter/landscape page prove propagation; existing default-A4 report goldens stay byte-identical (the default template is unchanged). The `_PagePreview` is schematic designer chrome, **not** a substitute renderer, and is covered by a widget test, not by report goldens. Any deliberate golden move is called out in review. |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | `PageFormat{width,height,margins}` is already serialized inside `ReportTemplate.page`; this feature only edits existing fields. No new field, `kReportSchemaVersion` stays **1**, no migration. Orientation and preset name are **derived at display time, never stored**. A codec round-trip test proves an edited page is lossless and pre-feature templates open unchanged (SC-005). |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on `setPageFormat` (notes clamp + single-undo semantics), `PageFormat.copyWith`, and the preset/recognition helpers; `CHANGELOG.md` updated. All new labels localized in en/de/tr (FR-012). The playground demonstrates picking Letter, toggling landscape, applying Narrow margins, and seeing canvas + preview + export agree. Zero analyzer warnings; `dart format` clean. |

**Result: PASS — no violations.** Two items recorded in *Complexity Tracking* for reviewer visibility:
(a) the Office-style `_PagePreview` is new custom-painted chrome (justified: explicit user request, schematic
only); (b) a single `setPageFormat(PageFormat)` op rather than granular `setPaperType`/`setOrientation`/
`setMargin` setters (smaller surface; the panel composes the next `PageFormat` and the controller clamps it).

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md), [contracts/page-properties.md](contracts/page-properties.md),
and [quickstart.md](quickstart.md): still **PASS**. Public surface stayed at one method + two `copyWith`s; the
presets/recognition/command/preview stayed private; the render path was not forked; no model/codec/schema
change (orientation + preset name remain derived). Clamp guarantees a positive content area on every produced
page (SC-006). No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/018-paper-margin-properties/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — preset values + recognition tolerance; clamp strategy; single setPageFormat op; Office-style preview; zero serialization impact
├── data-model.md        # Phase 1 — SetPageFormatCommand; PageFormat/JetEdgeInsets copyWith; paper + margin preset tables; recognition truth table; derived orientation; NO schema change
├── quickstart.md        # Phase 1 — end-to-end: pick Letter → landscape → Narrow margins → custom side; canvas/preview/export agree; save/reload
├── contracts/
│   └── page-properties.md  # Phase 1 — behavioral contracts (paper pick, orientation, custom W/H, margin preset, per-side, clamp, undo, persistence, preview) + test groups
├── checklists/          # (pre-existing)
└── tasks.md             # Phase 2 — /speckit.tasks (NOT created here)
```

### Source Code (repository root)

```text
packages/jet_print/
├── lib/
│   ├── jet_print.dart                                   # CHANGE: re-export already covers controller + PageFormat;
│   │                                                    #         setPageFormat is a method, copyWith is on exported types — no new export line
│   └── src/
│       ├── domain/
│       │   ├── page_format.dart                         # CHANGE: add PageFormat copyWith({width,height,margins})
│       │   └── geometry.dart                            # CHANGE: add JetEdgeInsets copyWith({left,top,right,bottom})
│       └── designer/
│           ├── paper_presets.dart                       # NEW (private): standard sizes (A4/A3/A5/Letter/Legal) + recognizePaper() → name|Custom, in either orientation
│           ├── margin_presets.dart                      # NEW (private): Normal/Narrow/Wide/None values + recognizeMargin() → preset|Custom
│           ├── controller/
│           │   ├── jet_report_designer_controller.dart  # CHANGE: add void setPageFormat(PageFormat) → clamp → _commit(SetPageFormatCommand)
│           │   ├── page_format_clamp.dart               # NEW (private): clampPageFormat() — min side + positive content area (FR-009); kMinPageSide/kMinContentExtent
│           │   └── commands/
│           │       └── set_page_format_command.dart     # NEW: EditCommand applying template.copyWith(page:) (no-op when equal)
│           ├── layout/panels/
│           │   └── properties_panel.dart                # CHANGE: rebuild _reportInspector PAGE section — _PagePreview + paper picker + orientation toggle + custom W/H + margin preset + 4 side fields; remove the two _ReadonlyRow page rows
│           └── l10n/
│               ├── jet_print_en.arb                     # CHANGE: + paper/orientation/margin/preview keys (+@desc)
│               ├── jet_print_de.arb                     # CHANGE: same keys, German
│               └── jet_print_tr.arb                     # CHANGE: same keys, Turkish
│                                                        #   (regenerate jet_print_localizations*.dart)
└── test/
    ├── domain/
    │   └── page_format_test.dart                        # EXTEND: copyWith per-field; round-trip unchanged
    ├── designer/
    │   ├── paper_presets_test.dart                      # NEW: recognition each size both orientations; non-match → Custom; rounded display still matches
    │   ├── margin_presets_test.dart                     # NEW: four-equal → preset; uneven → Custom
    │   ├── controller/
    │   │   ├── set_page_format_command_test.dart        # NEW: clamp; single undo/redo; notifies once; codec round-trip; content not moved (FR-013); orientation swap
    │   │   └── ...
    │   ├── properties_editor_test.dart                  # EXTEND: paper pick resizes; orientation swaps; Custom reveals W/H; margin preset 4 sides; per-side → Custom; revert-on-invalid; preview reflects state; no-selection availability; en/de/tr
    │   ├── goldens/
    │   │   └── page_letter_landscape_*.png              # NEW goldens: non-default page identical across canvas/preview/export
    │   └── ...
    └── public_api_test.dart                             # UPDATE: record setPageFormat + PageFormat.copyWith + JetEdgeInsets.copyWith
```

**Structure Decision**: Existing workspace monorepo, no new top-level structure. The domain stays UI-free —
only additive `copyWith` lands there. Everything else (preset tables + recognition, the clamp helper, the
`SetPageFormatCommand`, and the rebuilt PAGE section incl. the Office-style `_PagePreview`) lives in the
**designer** seam beside the precedents it copies (`format_presets.dart`, `set_format_command.dart`,
`_NumberField`/`_LabeledRow` in `properties_panel.dart`). The single state-of-record stays the controller,
which gains exactly one mutator (`setPageFormat`) routed through the existing `_commit`/history path so every
page edit is one undoable step.

## Complexity Tracking

> No Constitution **violations** to justify. Two tracked items for reviewer visibility.

| Item | Why | Note |
|------|-----|------|
| New custom-painted `_PagePreview` (Office-style page sample) | Explicit user request: the PAGE section should show a page sample like Microsoft Office print settings, so a designer sees orientation + margin proportions at a glance — not just numbers. | A tiny `CustomPaint` (sheet rect + four margin-guide lines), proportional to the live `PageFormat`, rebuilt only on page change. It is **schematic inspector chrome**, not a second report renderer (IV is satisfied by the shared `template.page`, not by this widget). Covered by a widget test (reflects size/orientation/margins), not by report goldens. |
| Single `setPageFormat(PageFormat)` rather than granular `setPaperType` / `setOrientation` / `setMargin*` setters | A page edit is one conceptual change to one immutable `PageFormat`; the panel composes the next value (apply preset, swap W/H, set one side via `copyWith`) and hands it over. One op keeps the public surface minimal (I) and clamping/validation in exactly one place (FR-009), and naturally yields one undo step per edit (FR-007). | Each Properties control builds `current.copyWith(...)` (or a preset) and calls `setPageFormat`; the controller clamps then `_commit`s. No-op edits (equal page) record nothing, matching `_commit`'s identity check. |
