# Implementation Plan: Vertical & Horizontal Canvas Rulers

**Branch**: `014-canvas-rulers` | **Date**: 2026-06-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/014-canvas-rulers/spec.md`

## Summary

Add a **horizontal ruler** (top edge) and a **vertical ruler** (left edge) to the design canvas,
calibrated in **millimetres** from the page's physical top-left corner (0,0), that stay aligned
with the page through zoom and pan, give live cursor-position markers and a selected-element
**union-bounding-box** extent highlight, and are shown/hidden by the existing (currently inert)
top-bar ruler toggle (default **on**).

The design keeps the change small and constitution-aligned by treating the rulers as **design-time
chrome** — like the existing band separators and band badges — that never touches the report model,
the codec, or the shared render pipeline (so preview/export and saved files are untouched). The
rulers live **inside `DesignCanvas`** as fixed overlays along the canvas edges, siblings of the
existing scrollbars, reading the *same* `viewScale` + centering `pageOffset` + `_vScroll`/`_hScroll`
the canvas already computes — so a page point maps to a ruler pixel by the one formula
`p · scale + pageOffset − scrollOffset`, and alignment is correct by construction at every zoom/scroll.

The only persisted-in-controller state is one `bool rulersEnabled` (default true), added to mirror
the existing `gridEnabled`/`snapEnabled` exactly. All measurement is computed by a **pure-Dart
`RulerScale`** (no Flutter import): given the origin pixel, pixels-per-mm, and strip length it emits
an ordered list of ticks (major/labelled + minor) chosen from a "nice-step" ladder so labels never
crowd or vanish — making the hard parts (alignment, adaptive density, label spacing) unit-testable
without a widget, satisfying Test-First. Cursor hover and the selection extent are transient view
state driven into the two thin ruler painters via a `ValueNotifier`, so pointer moves repaint only
the rulers (bounded cost), never the cached page picture.

See [research.md](research.md) for the design decisions, [data-model.md](data-model.md) for the
(view-only) model, [contracts/canvas-rulers.md](contracts/canvas-rulers.md) for behavioral
contracts + test groups, and [quickstart.md](quickstart.md) for the UX and the (zero) host wiring.

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`), sound null-safety.
**Primary Dependencies**: Existing only — `flutter` (CustomPaint/CustomPainter for the ruler strips),
`intl` (locale-aware number formatting of mm labels; already a dependency), `shadcn_ui` (theme
colors for chrome). **No new dependencies.**
**Storage**: None. Rulers are a live view aid — **no** report-model field, **no** codec change,
`schemaVersion` untouched. Ruler *visibility* is in-memory controller view state (like grid/snap),
not persisted to the report.
**Testing**: `flutter test packages/jet_print` (repo root). Unit — `RulerScale` (tick monotonicity,
nice-step selection, labelled-spacing ≥ minimum across the full zoom range, alignment exactness,
sub-division density, clamp at extremes) and the points↔mm conversion + selection-extent union
helper (single/multi/band/empty, clamp). Widget — rulers appear when enabled and vanish when off
with the canvas reclaiming the strip (`rulers_test.dart`); toggle drives `controller.rulersEnabled`
and reflects active state (`top_bar_test.dart` extension); cursor hover marker tracks + clears on
exit; selection union highlight matches edges and updates on move/resize; alignment holds across
zoom+scroll (extend `zoom_pan_test.dart`/`page_scroll_test.dart` patterns); localization en/de/tr
label formatting (`localization_*` extension). Goldens — existing invoice canvas/preview goldens
**unchanged** (rulers are not element appearance); one optional new golden of a ruler strip at 100%.
**Target Platform**: Designer UI (Flutter desktop/web canvas). The measurement core (`RulerScale`,
points↔mm, selection-extent) is pure Dart. Reference environment: macOS desktop playground.
**Project Type**: Existing Dart pub workspace monorepo — library `packages/jet_print` + consumer app
`apps/jet_print_playground`.
**Performance Goals**: No new budget. The page picture stays cached (`FrameCustomPainter`,
`shouldRepaint` gated on revision/scale). Cursor-hover repaints **only** the two thin ruler painters
(driven by a `ValueNotifier`, behind `RepaintBoundary`), not the canvas — so high-frequency hover
costs two small CustomPaints per frame, in line with the existing scrollbar-overlay repaint cost.
**Constraints**: WYSIWYG (Principle IV) — rulers are design-only chrome, never routed through the
render pipeline, so canvas/preview/export stay identical; no parallel render code. Alignment
single-sourced through the existing `viewScale`/`pageOffset`/scroll values (no second transform).
Layer boundary — all ruler code lives in the **designer** seam; the pure measurement helpers carry
no domain/rendering import. Minimal public surface — only two methods (`rulersEnabled`/
`setRulersEnabled`) on the already-reachable controller; ruler widgets/painters/scale stay under
`src/`. Default-on (FR-017); localized labels en/de/tr with English fallback.
**Scale/Scope**: 1 controller view-state field (+getter/setter) · 1 pure `RulerScale` + `RulerTick`
· 1 points↔mm helper · 1 selection-extent union helper · 2 ruler painters (H + V) + a corner box +
viewport inset, all inside `DesignCanvas` · 1 hover `MouseRegion` + `ValueNotifier` · top-bar toggle
rewire (delete local `_ruler`) · the test matrix above. 4 user stories (P1, P1, P2, P3).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | No host wiring — rulers ship inside `JetReportDesigner` and are controlled by the existing top-bar toggle (quickstart). The only API delta is two methods (`rulersEnabled` getter / `setRulersEnabled`) on the designer controller, mirroring the existing `gridEnabled`/`setGridEnabled` pair; all ruler widgets, painters, `RulerScale`, and the mm/extent helpers stay under `src/` and are not exported. `public_api_test` continues to pass through the single entry point unchanged. |
| II | Layered & Extensible Architecture | ✅ PASS | All new code lives in the **designer** seam (`designer/canvas/`). The pure measurement units (`RulerScale`, points↔mm, selection-extent) import only `dart:math` + `domain/geometry.dart` (inward), no rendering/Flutter-UI import — keeping them unit-testable and respecting `layer_boundaries_test`. The domain model and rendering layer are not touched at all. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Red→green→refactor for every unit. The genuinely tricky behavior (alignment under zoom/scroll, adaptive label density with no overlap, union-extent, mm conversion) is isolated in **pure** helpers that are unit-tested *without* a widget; widget tests then pin visibility/toggle/hover/selection wiring. `tasks.md` front-loads tests (overrides the template's "tests optional"). No merge with failing/skipped tests. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | Rulers are **design-time chrome only** — like the existing `_BandChromePainter`/band badges — drawn directly, never through the shared element render pipeline, and never present in preview or export. Therefore canvas/preview/print stay identical and **no existing golden changes**. Alignment reuses the one `viewScale`/`pageOffset`/scroll source (no divergent transform). |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | Zero serialization impact: no report-model field, no codec change, `schemaVersion` untouched, no migration. Ruler visibility is ephemeral view state. Old and new templates load and render byte-identically. |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on the new controller methods and any public-facing behavior; `CHANGELOG.md` updated; the playground invoice demonstrates the rulers live. Zero analyzer warnings; `dart format` clean. Tick labels localized via `intl` per active locale (en/de/tr); the toggle tooltip key already exists. |

**Result: PASS — no violations.** One item recorded in *Complexity Tracking* for reviewer
visibility: the rulers must compose with the canvas's nested-scroll viewport (they fold in the live
scroll offset, not just the view transform) — a deliberate reuse of the existing scrollbar-overlay
pattern rather than new state.

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md), [contracts/canvas-rulers.md](contracts/canvas-rulers.md),
and [quickstart.md](quickstart.md): still **PASS**. The public surface stayed at two controller
methods; measurement stayed in pure helpers in the designer seam; the render path was not forked;
no model/codec/schema change. The deferred clarify-phase concern (hover repaint cost) is resolved by
the `ValueNotifier`-into-painter design (rulers repaint, canvas does not). No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/014-canvas-rulers/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — placement, pure scale, alignment, units, tracking, extent, visibility
├── data-model.md        # Phase 1 — view-only entities (RulerScale/RulerTick/visibility/transients); NO domain change
├── quickstart.md        # Phase 1 — designer UX + (zero) host wiring
├── contracts/
│   └── canvas-rulers.md  # Phase 1 — behavioral contracts + test groups
├── checklists/
│   └── requirements.md  # Spec quality checklist (/speckit.specify)
└── tasks.md             # Phase 2 — /speckit.tasks (NOT created here)
```

### Source Code (repository root)

```text
packages/jet_print/
├── lib/src/designer/
│   ├── canvas/
│   │   ├── design_canvas.dart                # CHANGE: inset viewport by ruler thickness when enabled;
│   │   │                                     #         add H/V ruler overlays + corner (siblings of scrollbars);
│   │   │                                     #         add hover MouseRegion → hover ValueNotifier
│   │   ├── ruler_scale.dart                  # NEW: pure RulerScale + RulerTick (tick layout, nice-step, no Flutter)
│   │   ├── ruler_overlay.dart                # NEW: horizontal & vertical ruler widgets + CustomPainters (the strip chrome)
│   │   ├── ruler_metrics.dart                # NEW: kPointsPerMm + pointsToMm/mmToPoints; selectionExtent(layout, selection)
│   │   ├── design_tunables.dart              # CHANGE: + kRulerThickness, + ruler label-spacing/step-ladder constants
│   │   └── canvas_view_transform.dart        # (unchanged — reused as-is)
│   ├── controller/
│   │   └── jet_report_designer_controller.dart  # CHANGE: + _rulersEnabled (default true), rulersEnabled, setRulersEnabled
│   └── layout/
│       └── designer_top_bar.dart             # CHANGE: ruler toggle reads controller.rulersEnabled / setRulersEnabled
│                                             #         (delete local _ruler field)

packages/jet_print/test/                      # TDD — tests precede implementation
├── designer/canvas/ruler_scale_test.dart            # NEW: tick monotonicity, nice-step, label spacing ≥ min, alignment, clamp
├── designer/canvas/ruler_metrics_test.dart          # NEW: points↔mm parity; selectionExtent single/multi/band/empty/clamp
├── designer/canvas/rulers_test.dart                 # NEW: rulers shown when enabled / hidden when off; corner blank; viewport reclaim
├── designer/canvas/ruler_tracking_test.dart         # NEW: hover marker tracks + clears on exit; selection union highlight + move/resize update
├── designer/canvas/ruler_alignment_test.dart        # NEW: page point ↔ ruler pixel across zoom + scroll (mirrors zoom_pan/page_scroll)
├── designer/top_bar_test.dart                       # EXTEND: ruler toggle flips controller state + reflects active
├── designer/localization_test.dart (+ _de/_tr)      # EXTEND: mm label formatting per locale; tooltip
└── architecture/… , public_api_test.dart            # VERIFY unchanged: rulers add no exported surface, no domain/render import

apps/jet_print_playground/
└── lib/…                                     # (no code change required; rulers are on by default in the designer)
```

**Structure Decision**: Existing workspace monorepo, no new top-level structure. Everything lives in
the **designer/canvas** seam beside the constructs the rulers compose with (the view transform, the
scroll viewport, the band chrome). The measurement math is factored into pure helpers
(`ruler_scale.dart`, `ruler_metrics.dart`) so it is unit-testable without a widget; the visual strips
(`ruler_overlay.dart`) and the viewport integration live in `design_canvas.dart`. The only state of
record is one controller flag, placed next to `gridEnabled`/`snapEnabled` for parity.

## Complexity Tracking

> No Constitution **violations** to justify. One tracked item for reviewer visibility.

| Item | Why | Note |
|------|-----|------|
| Rulers compose with the canvas's nested-scroll viewport (fold in the live `_vScroll`/`_hScroll` offset, not only the view transform) | The canvas pans via scroll controllers, not via `CanvasViewTransform.pan` (which is just the centering offset). A ruler that read only the transform would drift the moment the page is scrolled. | Deliberate reuse of the existing **scrollbar-overlay** pattern: the rulers are fixed strips in the same `Stack`, driven by the same `AnimatedBuilder`-on-scroll-controller + controller-notify, mapping page→pixel via `p·scale + pageOffset − scrollOffset`. No new pan/scroll state is introduced; alignment is pinned by `ruler_alignment_test.dart`. |
