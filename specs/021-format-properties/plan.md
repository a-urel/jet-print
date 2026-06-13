# Implementation Plan: Format Properties — Font & Color Editors

**Branch**: `021-format-properties` | **Date**: 2026-06-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/021-format-properties/spec.md`

## Summary

Text, shape, and barcode elements already *carry* style in the domain model —
[`JetTextStyle`](../../packages/jet_print/lib/src/domain/styles/text_style.dart) (family,
size, 4-value weight, italic, color, alignment),
[`JetBoxStyle`](../../packages/jet_print/lib/src/domain/styles/box_style.dart) (nullable
fill/stroke + width), and `BarcodeElement.color` — and the shared render pipeline already
honors all of it on canvas, preview, PNG, and PDF. But the Properties panel edits none of it.
This feature adds the industry-standard editors (family select with typeface preview, size
stepper, **B/I/U** toggle group, swatch+hex color editor with None where applicable,
alignment segments, outline width) to the panel, plus the one net-new attribute end-to-end:
**underline**.

The work rides the proven seams:

1. **Model, additive only.** `JetTextStyle` gains `underline` (default `false`, written only
   when `true`) and `copyWith`; `JetBoxStyle` gains a sentinel-based `copyWith` (explicit
   `null` = "no fill"/"no outline"). Pre-1.0 carve-out applies: `kReportSchemaVersion`
   stays **1**, no migration, pre-feature reports round-trip byte-identically
   ([research §2, §9](research.md)).

2. **Three undoable controller ops** — `setTextStyle`, `setShapeStyle`, `setBarcodeColor` —
   each one command through the existing
   [`_commit`](../../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart#L986)
   path, no-op-safe, one history entry per committed editor change (FR-013, research §7).

3. **Underline parity by one geometry source (IV).** Neither painter uses
   `ui.TextDecoration`: a shared `underlineFor(fontSize)` helper feeds an explicit stroked
   line inside both painters' existing per-line alignment math, so canvas/PNG/PDF agree by
   construction — the `shapePath` pattern from 020 applied to text (research §2). Stroke
   width 0 removes the outline via a single renderer seam
   (`stroke: width > 0 ? style.stroke : null`), zero painter changes (research §6).

4. **Editors on existing primitives, type-gated.** `ShadSelect` for family (previewed in its
   own typeface, unknown stored family shown as unavailable), `_NumberField` extended with
   clamping for size (4–144) and width (0–20), hand-rolled B/I/U + alignment groups on the
   `_OrientationToggle` precedent, and one reusable `_ColorField` (ShadPopover: swatches +
   hex + optional None) — no new dependency (research §4–§6). The family list comes from the
   designer's own `FontRegistry` via a new internal `families` getter; the registry is
   hoisted so canvas and panel share one instance, and **no public host-font seam opens
   here** because designer-only registration would break WYSIWYG against the engine/preview/
   exporter's internal registries (research §1 — the key scoping decision).

5. **Barcode color binds to the model today, tints the placeholder renderer** so the change
   is visible and WYSIWYG-consistent until real symbology rendering lands (research §8).

See [research.md](research.md) (10 grounded decisions), [data-model.md](data-model.md)
(field/command/helper specs), [contracts/style-editors.md](contracts/style-editors.md)
(C1–C13 behavioral contracts + test groups), and [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`), sound null-safety.
**Primary Dependencies**: Existing only — `shadcn_ui ^0.54.0` (`ShadSelect`, `ShadPopover`,
`ShadInput`, `ShadContextMenu`, theme tokens), `flutter`, lucide icons, `pdf` (already used
by `PdfPainter`). shadcn_ui 0.54 ships **no** color picker / toggle group / segmented
control — those are hand-rolled like the panel's existing `_OrientationToggle`. **No new
deps** (research §4).
**Storage**: Report JSON via existing codecs, `kReportSchemaVersion = 1` **unchanged**.
Additive optional `underline` on the text style (written only when `true`; absent ⇒ `false`)
under the pre-1.0 carve-out (`report_codec.dart:18-22`). `fill`/`stroke: null` omission and
barcode-color omission rules already exist; pre-feature reports load and re-save
byte-identically. **No migration** (research §9, contract C10).
**Testing**: `flutter test packages/jet_print` from repo root. Unit — `JetTextStyle.underline`
+ `copyWith` (sentinel `fontFamily`), `JetBoxStyle.copyWith` (explicit-null fill/stroke),
codec round-trips incl. pre-feature byte-compare and unknown-family preservation, three
commands (single undo step, notify-once, no-op returns `before`), `underlineFor` values,
renderer `strokeWidth ≤ 0 ⇒ stroke: null`, `FontRegistry.families`. Widget — section gating
per element type (C1), every editor's display/commit/validation contract (C2–C8), undo
round-trips + no-op-no-history + selection-switch discard (C9), en/de/tr labels + semantics
(C12). Golden — styled-text page (family/size/B/I/**U**/translucent color/alignments) and
shape-style page (fill/stroke/none/width-0) identical across canvas/preview/export; existing
goldens stay byte-identical. PDF parity — underline segment at the shared helper's
offset/width. `public_api_test.dart` records the additions.
**Target Platform**: Designer Properties UI (Flutter desktop/web); reference env: macOS
playground (`apps/jet_print_playground`).
**Project Type**: Existing Dart pub workspace monorepo — library `packages/jet_print` +
consumer app `apps/jet_print_playground`.
**Performance Goals**: SC-005 (≤100 ms to canvas) holds by construction: each commit is one
synchronous `_commit` + `notifyListeners`, canvas repaints on `revision` — no new async
hops (C13). The color popover and family select are built per-open; swatch grid is a
fixed ~16-item wrap. No new render-path cost beyond one optional line per underlined text
line.
**Constraints**: WYSIWYG (IV) — underline geometry from **one** shared helper in both
painters; stroke-width-0 handled once in the renderer; barcode tint rides the shared
placeholder renderer; no parallel render path, no `ui.TextDecoration`. Layer boundaries (II)
— domain gains only fields + `copyWith` (no Flutter import); `underlineFor` and the
`families` getter live in **rendering**; commands/editors live in the **designer** seam;
`FontRegistry` stays internal (research §1). Minimal public surface (I) — three controller
methods + `underline` + two `copyWith`s on already-public types. Backward-compat (V) —
schema 1, additive-only, lossless round-trips. l10n (FR-016) — ~20 new ARB keys × en/de/tr.
**Scale/Scope**: 1 new model field + 2 `copyWith`s · 1 `families` getter · 1 underline
helper file · 2 painter touch-points + 1 renderer seam + placeholder tint · 3 commands +
3 controller mutators · 1 Font section + 1 Appearance section + 1 barcode color row in the
panel · 4 new private editor widgets (`_ColorField`, family select row, B/I/U group,
alignment group) + clamping on `_NumberField` · ~20 ARB keys × 3 locales · test matrix
above · 3 user stories (P1 text, P2 shape, P3 barcode).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | Additions are minimal and additive: `JetTextStyle.underline` + `copyWith`, `JetBoxStyle.copyWith` (all on already-exported types), and three controller mutators (`setTextStyle`/`setShapeStyle`/`setBarcodeColor`) mirroring `setText`/`setShapeKind`. Commands, editor widgets, `underlineFor`, and `FontRegistry` (incl. new `families`) stay **private** under `src/`. Deliberately **no** public host-font seam this feature (research §1). `public_api_test` records the additions. |
| II | Layered & Extensible Architecture | ✅ PASS | Dependencies point inward: domain gains pure value fields/`copyWith` only. `underlineFor` + `families` live in rendering; designer consumes rendering (already allowed). Editors reach the model exclusively through controller commands. No element-type switch in painter cores is touched — text/shape/barcode renderers absorb the deltas at their existing extension points. `layer_boundaries_test` stays green. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Red→green per contract group C1–C12: failing tests first for model fields/`copyWith`, codec round-trips (incl. pre-feature byte-compare), command single-undo/no-op semantics, clamp/reject/restore input rules, alpha preservation, none-states, gating matrix, underline parity, goldens. No merge with failing/skipped tests. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | Every existing attribute already flows through the one shared pipeline; this feature adds no fork. The two genuinely new render behaviors are parity-safe by construction: underline = one shared geometry helper consumed by both painters (explicitly **not** Skia's `TextDecoration`, research §2); width-0 = one renderer seam. Goldens cover styled text + shapes across canvas/preview/export; PDF parity test pins the underline segment. |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | Schema stays **1**, no migration: `underline` is additive-optional (omitted when `false`) under the documented pre-1.0 carve-out; all existing omission rules unchanged. Tests prove a pre-feature report loads and re-saves byte-identically and that alpha + none states round-trip (C10, SC-004). |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on the three mutators (single-undo + no-op semantics), `underline`, both `copyWith`s. `CHANGELOG.md` updated. ~20 new labels/tooltips localized en/de/tr (FR-016); editors keyboard-operable with semantic roles (C12). Playground demos the full walk ([quickstart.md](quickstart.md)). Zero analyzer warnings; `dart format` clean. |

**Result: PASS — no violations.** Three items recorded in *Complexity Tracking* for reviewer
visibility: (a) underline drawn from em-fraction constants rather than TTF `post`-table
metrics; (b) no public host-font-registration seam despite the spec's "registered by the
host" assumption; (c) barcode color demonstrated via placeholder tint.

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md),
[contracts/style-editors.md](contracts/style-editors.md), and [quickstart.md](quickstart.md):
still **PASS**. The public surface stayed at three mutators + `underline` + two `copyWith`s;
`FontRegistry`/helper/commands/editors stayed private; no render fork appeared (underline
helper + renderer stroke seam only); schema stayed 1 with byte-identical pre-feature
round-trips. No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/021-format-properties/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — 10 decisions: registry-scoped family list (no public font seam); underline via shared helper (no TextDecoration); bold-toggle mapping; hand-rolled color editor; alpha rule; none/width-0; 3 mutators; placeholder tint; schema stays 1; undo granularity
├── data-model.md        # Phase 1 — JetTextStyle.underline + copyWith; JetBoxStyle.copyWith; 3 commands + mutators; families getter; underlineFor; renderer deltas; state transitions; NO schema change
├── quickstart.md        # Phase 1 — end-to-end: style text → shape fill/outline/none → barcode tint → preview/export/save parity
└── contracts/
    └── style-editors.md # Phase 1 — C1–C13: gating, family picker, size clamp, B/I/U, color editor, shape none/width, barcode, undo, persistence, parity, l10n/a11y, latency
```

### Source Code (repository root)

```text
packages/jet_print/
├── lib/
│   ├── jet_print.dart                                   # VERIFY: JetTextStyle/JetBoxStyle/JetColor/controller already exported; underline/copyWith/mutators are members of exported types — expect no new export line
│   └── src/
│       ├── domain/
│       │   ├── styles/
│       │   │   ├── text_style.dart                      # CHANGE: + bool underline (default false; toJson only when true; fromJson tolerant); + copyWith (sentinel fontFamily); ==/hashCode/toString
│       │   │   └── box_style.dart                       # CHANGE: + copyWith (sentinel fill/stroke so explicit null = none)
│       │   └── elements/
│       │       └── barcode_element.dart                 # CHANGE (if absent): + copyWith(color) for the command
│       ├── rendering/
│       │   ├── text/
│       │   │   ├── underline_metrics.dart               # NEW (private): underlineFor(fontSize) → (offset, thickness) — the one underline geometry source (IV)
│       │   │   └── font_registry.dart                   # CHANGE: + List<String> get families (default first, insertion order, deduped) — stays internal
│       │   ├── paint/
│       │   │   └── canvas_painter.dart                  # CHANGE: drawTextRun strokes underline per line at aligned dx/width via underlineFor (no ui.TextDecoration)
│       │   ├── export/
│       │   │   └── pdf_painter.dart                     # CHANGE: drawTextRun draws the same underline segment via underlineFor (+_mapY)
│       │   └── elements/renderers/
│       │       ├── shape_element_renderer.dart          # CHANGE: emit stroke: style.strokeWidth > 0 ? style.stroke : null (rect/path/line)
│       │       └── barcode_element_renderer.dart        # CHANGE: placeholder primitives tinted with el.color
│       └── designer/
│           ├── jet_report_designer.dart                 # CHANGE: hoist one FontRegistry; hand to canvas frame builder + properties panel
│           ├── canvas/design_canvas.dart                # CHANGE: accept the hoisted registry instead of constructing DesignTimeFrameBuilder() privately (line 91)
│           ├── controller/
│           │   ├── jet_report_designer_controller.dart  # CHANGE: + setTextStyle / setShapeStyle / setBarcodeColor → _commit(...)
│           │   └── commands/
│           │       ├── set_text_style_command.dart      # NEW: replace TextElement.style; before on missing/wrong-type/equal
│           │       ├── set_shape_style_command.dart     # NEW: replace ShapeElement.style; same no-op rules
│           │       └── set_barcode_color_command.dart   # NEW: replace BarcodeElement.color; same no-op rules
│           ├── layout/panels/
│           │   ├── properties_panel.dart                # CHANGE: TextElement → Font section (family/size/B-I-U/color/align); ShapeElement → Appearance section (fill unless line, stroke color+width); BarcodeElement → color row; _NumberField gains min/max clamp
│           │   └── style_editors.dart                   # NEW (private): _ColorField (swatch+hex trigger, ShadPopover palette + hex input + optional None), _FontFamilyRow (ShadSelect, per-item typeface preview, unavailable marker), _StyleToggleGroup (B/I/U), _AlignSegments (l/c/r — stored justify shows no active segment, preserved; clarified 2026-06-13) — _OrientationToggle precedent, lucide icons, theme tokens
│           └── l10n/
│               ├── jet_print_en.arb                     # CHANGE: + ~20 keys (sections, control labels/tooltips, None, unavailable, swatch names) (+@desc)
│               ├── jet_print_de.arb                     # CHANGE: same keys, German
│               └── jet_print_tr.arb                     # CHANGE: same keys, Turkish (regenerate jet_print_localizations*.dart)
└── test/
    ├── domain/styles/
    │   ├── text_style_test.dart                         # EXTEND: underline default/equality/copyWith incl. fontFamily sentinel
    │   └── box_style_test.dart                          # EXTEND: copyWith explicit-null fill/stroke
    ├── domain/serialization/
    │   ├── element_codec_test.dart                      # EXTEND: underline round-trip (true written, false omitted, absent ⇒ false); unknown-family string preserved
    │   ├── shape_element_codec_test.dart                # EXTEND: fill/stroke none + alpha round-trips
    │   └── report_format_compat_test.dart               # NEW/EXTEND: pre-feature report fixture loads + re-saves byte-identically (C10)
    ├── rendering/
    │   ├── text/underline_metrics_test.dart             # NEW: helper values; scale-linearity
    │   ├── paint/canvas_painter_golden_test.dart        # EXTEND/NEW goldens: styled text (B/I/U, translucent color, alignments), shape styles incl. none/width-0
    │   ├── export/pdf_painter_parity_test.dart          # EXTEND: underline segment at shared offset/width; width-0 emits no stroke ops
    │   └── elements/
    │       ├── shape_element_renderer_test.dart         # EXTEND: strokeWidth 0 ⇒ stroke null on all three primitive paths
    │       └── barcode_element_renderer_test.dart       # EXTEND: placeholder primitives carry el.color
    ├── designer/
    │   ├── controller/
    │   │   ├── set_text_style_command_test.dart         # NEW: single undo step; notify once; no-op on equal/missing/wrong type
    │   │   ├── set_shape_style_command_test.dart        # NEW: same matrix
    │   │   └── set_barcode_color_command_test.dart      # NEW: same matrix
    │   ├── properties_editor_test.dart                  # EXTEND: C1 gating matrix; C2–C8 display/commit/clamp/reject/alpha/none; C9 undo + no-op + selection-switch discard; en/de/tr
    │   └── accessibility_semantics_test.dart            # EXTEND: toggle/segment/swatch roles + localized labels, keyboard operation
    └── public_api_test.dart                             # UPDATE: underline, JetTextStyle/JetBoxStyle.copyWith, 3 controller mutators; FontRegistry still NOT exported
```

**Structure Decision**: Existing workspace monorepo; no new top-level structure. The domain
stays UI- and render-free (fields + `copyWith` only). The two cross-path render facts each
live **once** in the rendering layer (`underline_metrics.dart`, the renderer stroke seam) so
canvas/preview/export cannot diverge. All interaction lives in the designer seam: three
commands beside their precedents, editor widgets in a new private `style_editors.dart`
(keeping the already ~1800-line `properties_panel.dart` from doubling), the panel's existing
type-gated `_elementInspector` branches extended. The designer's `FontRegistry` is hoisted
one level so the canvas painter and the family picker provably share the same family set.

## Complexity Tracking

> No Constitution **violations** to justify. Three tracked items for reviewer visibility.

| Item | Why | Note |
|------|-----|------|
| Underline geometry from em-fraction constants (≈0.11/0.06 em), not TTF `post`-table metrics | The TTF parser reads `head/hhea/maxp/hmtx/cmap` only; parsing `post` adds parser surface for a value most report fonts agree on within a pixel at print DPI. | The constants live in **one** shared helper consumed by both painters, so canvas/PDF/PNG are identical by construction (IV); parity test + golden pin it. Swap-in of real `post` metrics later changes one function. Recorded in [research §2](research.md). |
| No public host-font-registration seam, though the spec assumes "fonts registered by the host" | Designer-only registration would render canvas text in families the engine/preview/exporter (which build their own default-only registries) cannot resolve — a silent WYSIWYG break (IV). A correct seam threads one registry through four public entry points: its own cross-cutting feature. | The picker enumerates the designer registry (`families` getter) and flags stored-but-unregistered names, so it is architecturally complete and grows automatically when the seam lands. FR-001 is satisfied: the available set today **is** the built-in default. Recorded in [research §1](research.md). |
| Barcode color demonstrated via placeholder tint | `BarcodeElementRenderer` is placeholder-only by design (symbology rendering is a later spec); "bars re-render" cannot be literally true yet. | The editor binds the real model field and the tint rides the shared renderer, so the edit is visible and WYSIWYG-consistent on canvas/preview/export, and real bar rendering inherits the color unchanged. Recorded in [research §8](research.md). |
