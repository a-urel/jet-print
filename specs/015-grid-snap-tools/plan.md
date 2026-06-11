# Implementation Plan: Grid & Snap Helper Tools

**Branch**: `015-grid-snap-tools` | **Date**: 2026-06-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/015-grid-snap-tools/spec.md`

## Summary

Complete the two remaining design-canvas helper tools so they behave as their top-bar icons
promise. Two things change, both small and constitution-aligned:

1. **Draw the grid.** Add a **visible 5 mm grid** as design-time chrome on the page — a new
   `_GridPainter` placed as the **backmost** child of the page `Stack` (behind band separators,
   elements, and all overlays), driven by the existing `controller.gridEnabled`. The grid is drawn
   **per band**, registered to each band's content origin, at the *same* step the snap geometry
   uses — so a drawn line lies exactly on a snap target (true WYSIWYG). Today `gridEnabled` toggles
   nothing visible; this makes "Show grid" honest.

2. **Unify the snap step at 5 mm and decouple grid visibility from grid snapping** (per
   Clarifications 2026-06-11). The snap constant `kGridStep` changes from `8 pt` to `5 mm`
   (`5 · 72/25.4 ≈ 14.17 pt`), so the visible grid and the snap grid coincide and align with the mm
   rulers. The controller stops gating grid snapping on `gridEnabled` (it now passes the grid
   candidates whenever the **snap** tool is active); `gridEnabled` becomes *visibility-only*. So
   any of the four toggle combinations is valid, and elements snap to grid lines even when the grid
   is hidden.

The design reuses the **band chrome** pattern that already exists for band separators
([`_BandChromePainter`](../../packages/jet_print/lib/src/designer/canvas/design_canvas.dart)) and
the mm conversion (`kPointsPerMm`) introduced by the rulers feature. The grid never touches the
report model, the codec, or the shared element render pipeline (`FrameCustomPainter`), so
preview/export/print and saved files are byte-identical — like the band separators and rulers, the
grid is absent from output by construction. The only genuinely tricky bit — **adaptive density** so
the grid never smears into a solid fill when zoomed out — is isolated in a **pure-Dart** helper
(`gridLineOffsets`) that is unit-tested without a widget, satisfying Test-First.

See [research.md](research.md) for the design decisions (origin model, step unification,
decoupling, adaptive density, layer placement), [data-model.md](data-model.md) for the (view-only)
entities, [contracts/grid-snap.md](contracts/grid-snap.md) for behavioral contracts + test groups,
and [quickstart.md](quickstart.md) for the UX and the (zero) host wiring.

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`), sound null-safety.
**Primary Dependencies**: Existing only — `flutter` (`CustomPainter` for the grid strip),
`shadcn_ui` (theme colors for chrome). The mm conversion reuses `kPointsPerMm` from
`ruler_metrics.dart`. **No new dependencies.**
**Storage**: None. The grid is a live view aid — **no** report-model field, **no** codec change,
`schemaVersion` untouched. Grid *visibility* and snap state are in-memory controller view state
(the already-present `gridEnabled`/`snapEnabled`), not persisted to the report.
**Testing**: `flutter test packages/jet_print` (repo root). Unit — `gridLineOffsets` (line
enumeration from the band origin, adaptive thinning so the on-screen gap clears a floor, clamp at
extreme zoom-out → empty/coarsened, exact coincidence with snap multiples). The pure snap helpers
(`snapMove`/`snapResize`) keep their existing unit tests with the new step. Widget — grid visible
when `gridEnabled`, absent when off, backmost in the page stack, per-band registration
(`grid_test.dart`); grid stays page-registered through zoom + scroll
(`grid_alignment_test.dart`, mirroring `ruler_alignment_test.dart`/`zoom_pan_test.dart`);
top-bar grid/snap toggles flip controller state (existing `top_bar_test.dart`). Behavior —
**decoupling**: snapping to the grid occurs with `snapEnabled` regardless of `gridEnabled`; updated
controller-level snap tests. **Step change**: `snapping_test.dart`/`resize_snap_test.dart` expected
positions updated from 8 pt to 5 mm. Goldens — existing invoice canvas/preview/export goldens
**unchanged** (the grid is not element appearance and not in preview/export); one optional new
golden of the page with the grid on at 100 %.
**Target Platform**: Designer UI (Flutter desktop/web canvas). The measurement core
(`gridLineOffsets`, the snap helpers) is pure Dart. Reference environment: macOS desktop playground.
**Project Type**: Existing Dart pub workspace monorepo — library `packages/jet_print` + consumer
app `apps/jet_print_playground`.
**Performance Goals**: No new budget. The cached element picture (`FrameCustomPainter`, repaint
gated on revision/scale) is untouched. The grid painter is gated on `gridEnabled`/scale/layout via
`shouldRepaint` and draws O(lines-in-view) strokes; adaptive thinning bounds the stroke count at low
zoom. Repaints with the page (on zoom/scroll/edit), in line with the existing band-chrome painter.
**Constraints**: WYSIWYG (Principle IV) — the grid is design-only chrome, never routed through the
render pipeline, so canvas/preview/export stay identical; the visible grid and the snap grid share
one step + origin (single source of truth) so "what you see is what you snap to" holds by
construction. Layer boundary — grid code lives in the **designer** seam; the pure `gridLineOffsets`
helper carries no domain/rendering import. Minimal public surface — **zero** new public symbols
(`gridEnabled`/`setGridEnabled` already exist); the painter + helper stay under `src/`. Default-on
(FR-014); existing localized tooltips reused (FR-017).
**Scale/Scope**: 1 tunable change (`kGridStep` → 5 mm) + 1 added tunable (`kGridStepMm`,
`kGridMinLineGapPx`) · 1 pure `gridLineOffsets` helper · 1 `_GridPainter` added to the page `Stack`
in `design_canvas.dart` · 2 controller snap call-sites changed (`grid: _gridEnabled` →
`grid: true`) + `gridEnabled` dartdoc/semantics updated to visibility-only · existing top-bar
toggles unchanged · the test matrix above (new grid tests + updated snap/step tests). 4 user
stories (P1, P1, P2, P3).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | **No new public surface.** The grid is controlled by the already-public `gridEnabled`/`setGridEnabled` pair (now visibility-only) and the existing top-bar toggle. The `_GridPainter` and the pure `gridLineOffsets` helper stay under `src/`, unexported. `public_api_test` stays green unchanged. No host wiring — the grid is on by default inside `JetReportDesigner`. |
| II | Layered & Extensible Architecture | ✅ PASS | Grid code lives in the **designer/canvas** seam. The pure `gridLineOffsets` helper imports only `dart:math` (no Flutter/rendering/domain), keeping it unit-testable and respecting `layer_boundaries_test`. The domain model and the rendering layer are not touched. `kGridStep` stays in `design_tunables.dart` (pure data, domain import only). |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Red→green→refactor. The tricky behavior (adaptive density, exact snap-coincidence, alignment under zoom/scroll) is isolated in the **pure** `gridLineOffsets` helper and unit-tested without a widget; widget tests then pin visibility/backmost-placement/alignment. The **step change** and **decoupling** are driven by first updating the affected snap tests (`snapping_test`, `resize_snap_test`, `move_commit_teardown_test`) to the new expected behavior (Red), then changing the constant/wiring (Green). No merge with failing/skipped tests. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | The grid is **design-time chrome only** — drawn directly like `_BandChromePainter`, never through the shared element render pipeline, and never present in preview or export. Therefore canvas/preview/print stay identical and **no existing golden changes**. The visible grid and the snap grid are single-sourced (one step `kGridStep`, one per-band origin), so the canvas cannot show a line you can't snap to. |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | Zero serialization impact: no report-model field, no codec change, `schemaVersion` untouched, no migration. Grid/snap state is ephemeral view state. Old and new templates load and render byte-identically. (Note: the snap **step** changes, which alters *future* interactive placements, not any *stored* geometry — saved coordinates are unchanged.) |
| VI | Documentation & Developer Experience | ✅ PASS | Updated dartdoc on `gridEnabled`/`setGridEnabled` (now visibility-only) and on `kGridStep`; `CHANGELOG.md` updated (new visible grid; snap step 8 pt → 5 mm; grid/snap decoupled). The playground invoice demonstrates the grid live. Zero analyzer warnings; `dart format` clean. Existing localized grid/snap tooltips reused. |

**Result: PASS — no violations.** One item is recorded in *Complexity Tracking* for reviewer
visibility: the **grid origin model** (per-band, matching the band-relative snap geometry) rather
than page-physical registration — a deliberate WYSIWYG-over-cosmetics tradeoff, see research D1.

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md), [contracts/grid-snap.md](contracts/grid-snap.md),
and [quickstart.md](quickstart.md): still **PASS**. Public surface stayed at zero new symbols;
measurement stayed in a pure helper in the designer seam; the render path was not forked; no
model/codec/schema change. The behaviour change (step + decoupling) is covered by updated tests, not
new public API. No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/015-grid-snap-tools/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — origin model, step unification, decoupling, adaptive density, placement
├── data-model.md        # Phase 1 — view-only entities (visibility/snap state, grid spacing, line offsets); NO domain change
├── quickstart.md        # Phase 1 — designer UX + (zero) host wiring
├── contracts/
│   └── grid-snap.md     # Phase 1 — behavioral contracts + test groups
├── checklists/
│   └── requirements.md  # Spec quality checklist (/speckit.specify)
└── tasks.md             # Phase 2 — /speckit.tasks (NOT created here)
```

### Source Code (repository root)

```text
packages/jet_print/
├── lib/src/designer/
│   ├── canvas/
│   │   ├── design_canvas.dart                # CHANGE: add `_GridPainter` as the BACKMOST child of the page Stack
│   │   │                                     #         (before _BandChromePainter), gated on controller.gridEnabled;
│   │   │                                     #         feed it layout + scale + step; repaints with the page
│   │   ├── grid_geometry.dart                # NEW: pure `gridLineOffsets(extent, step, scale, minGapPx)` (no Flutter)
│   │   ├── design_tunables.dart              # CHANGE: kGridStep → 5 mm (via kGridStepMm); + kGridMinLineGapPx
│   │   ├── ruler_metrics.dart                # (unchanged — reuse kPointsPerMm for the mm→pt conversion)
│   │   └── selection_overlay.dart            # (unchanged — snap guides already drawn here)
│   └── controller/
│       ├── jet_report_designer_controller.dart  # CHANGE: snap call-sites `grid: _gridEnabled` → `grid: true`
│       │                                         #         (decouple); gridEnabled dartdoc → "grid is drawn" (visibility)
│       └── snapping.dart                     # (unchanged logic — receives the new gridStep value via kGridStep)
│   └── layout/
│       └── designer_top_bar.dart             # (unchanged — grid/snap toggles already wired to the controller)

packages/jet_print/test/                      # TDD — tests precede/accompany implementation
├── designer/canvas/grid_geometry_test.dart       # NEW: line enumeration from origin; adaptive thinning ≥ minGap; clamp; snap-coincidence
├── designer/canvas/grid_test.dart                # NEW: grid shown when enabled / hidden when off; backmost in stack; per-band registration
├── designer/canvas/grid_alignment_test.dart      # NEW: grid stays page-registered across zoom + scroll (mirrors ruler_alignment)
├── designer/canvas/snapping_test.dart            # UPDATE: expected snapped positions 8 pt → 5 mm; grid-off cases re-expressed via snapEnabled
├── designer/canvas/resize_snap_test.dart         # UPDATE: expected resized edges to the 5 mm grid
├── designer/controller/move_commit_teardown_test.dart # UPDATE: setGridEnabled(false) no longer disables snapping → use setSnapEnabled(false)
├── designer/top_bar_test.dart                    # VERIFY/EXTEND: grid + snap toggles flip controller state, reflect active
└── architecture/… , public_api_test.dart         # VERIFY unchanged: grid adds no exported surface, no domain/render import
```

**Structure Decision**: Existing workspace monorepo, no new top-level structure. Everything lives
in the **designer/canvas** seam beside the constructs the grid composes with (the band layout, the
band chrome, the snap geometry, the mm conversion). The adaptive-density math is factored into a
pure helper (`grid_geometry.dart`) so it is unit-testable without a widget; the visual strip
(`_GridPainter`) and the stack placement live in `design_canvas.dart`. The only "state of record" is
the two controller flags that already exist; this feature changes their *meaning* (grid = visibility)
and adds the rendering they were always supposed to drive.

## Complexity Tracking

> No Constitution **violations** to justify. One tracked item for reviewer visibility.

| Item | Why | Note |
|------|-----|------|
| Grid **origin model** is per-band (matching the band-relative snap geometry), not the page's physical (0,0) corner used by the mm rulers | `snapping.dart` computes grid candidates in **band-relative** coordinates (`(seed/gridStep).round()*gridStep`, y=0 at each band top). A page-physically-registered visible grid would not line up with those snap targets when a band's page offset or the page margin is not a whole multiple of 5 mm — violating the "what you see is what you snap to" guarantee. | The grid is therefore drawn **per band**, registered to each band's content origin, sharing `kGridStep` with the snap candidates — coincidence is exact by construction (`grid_geometry_test` pins it). Accepted tradeoff: drawn grid lines coincide with the mm **ruler ticks** only when band origins/margins are whole multiples of 5 mm. Making the snap geometry page-registered instead was rejected as a larger, riskier change to working band-relative code for a cosmetic gain (research D1). |
