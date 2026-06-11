# Phase 1 Data Model: Grid & Snap Helper Tools

**Scope note**: This feature adds **no domain/report-model entities** and **no serialized fields**.
The report model, codec, and `schemaVersion` are untouched (Constitution V). Everything below is
either **ephemeral view state** on the designer controller or a **pure value/helper** in the
designer/canvas seam. Nothing here is exported from the package.

---

## View state (designer controller — already present, semantics refined)

| Field | Type | Default | Meaning | Change in this feature |
|-------|------|---------|---------|------------------------|
| `gridEnabled` | `bool` | `true` | Whether the alignment grid is **drawn** on the canvas. | **Semantics change**: was "grid snapping active" → now **visibility-only**. No longer passed to the snap helpers. Drives `_GridPainter`. Dartdoc updated. |
| `snapEnabled` | `bool` | `true` | Master on/off for **all** snapping (grid + sibling + band) during move/resize. | Unchanged field; now the **sole** gate for grid snapping (D3). |

- Both are per-session preferences, mutated via the existing `setGridEnabled`/`setSnapEnabled`
  (each notifies listeners only on change). Neither is serialized (FR-015).
- All four on/off combinations are valid and independent (FR-010, US4 edge cases).

---

## Tunables (`design_tunables.dart` — pure data, domain import only)

| Constant | Type | Value | Notes |
|----------|------|-------|-------|
| `kGridStepMm` | `double` | `5` | The grid/snap spacing in millimetres (the unit of record for this decision). **New.** |
| `kGridStep` | `double` | `kGridStepMm · 72/25.4 ≈ 14.173` (pt) | The spacing in **points**, consumed by `snapping.dart` and `_GridPainter`. **Changed** from `8`. `72/25.4` mirrors `kPointsPerMm`. |
| `kGridMinLineGapPx` | `double` | `4` | Minimum on-screen gap, in device px, between drawn grid lines. Below it, `gridLineOffsets` coarsens, then hides (FR-006). **New.** |
| `kGridMaxCoarsenFactor` | `int` | `4` | Max coarsening multiplier (effective step ≤ `4·5 mm = 20 mm`). Past it, the grid HIDES rather than draw lines coarser than 20 mm. **New.** |
| `kSnapThresholdPx` | `double` | `6` (unchanged) | Snap activation distance in screen px; converted to points via live zoom by the canvas. |

---

## Pure helper (`grid_geometry.dart` — `dart:math` only; no Flutter/domain/render)

### `gridLineOffsets(extent, step, scale, minGapPx) → List<double>`

Returns the ascending list of line positions (in **points**, from `0` up to and including
`extent` where it lands on a multiple) to draw along **one axis of one band**.

| Param | Meaning |
|-------|---------|
| `extent` | Band width (for vertical lines) or band height (for horizontal lines), in points. |
| `step` | `kGridStep` (points). Lines fall on `0, step, 2·step, …` — exactly the snap multiples. |
| `scale` | View pixels per point (the live zoom). |
| `minGapPx` | `kGridMinLineGapPx`. |

**Rules**:
- Lines are multiples of `step` measured from the band origin → **coincident with snap candidates**
  by construction (D1/D2).
- **Adaptive density** (FR-006): `f = max(1, ⌈minGapPx / (step · scale)⌉)`; **if
  `f > kGridMaxCoarsenFactor` return `[]`** (grid hidden — never coarser than
  `kGridMaxCoarsenFactor · step`); else emit multiples of `step · f`. So at low zoom the grid
  coarsens up to 20 mm, then disappears — the page never renders as a solid fill.
- Monotonic ascending; clamped to `[0, extent]`; deterministic (pure).

> The same helper serves both axes (call once with `extent = bandWidth`, once with
> `extent = bandHeight`). It is the only new unit-tested logic.

---

## Painter (`_GridPainter` — `CustomPainter` in `design_canvas.dart`, private)

| Input | Source |
|-------|--------|
| `layout` (`DesignTimeLayout`) | the per-band rects (`bandRects`) — same source `_BandChromePainter` uses |
| `scale` | `controller.viewScale` |
| `step` | `kGridStep` |
| `color` | muted paper-chrome grid color (lighter than the band separator) |

- **Visibility**: constructed only when `controller.gridEnabled` (else absent from the stack).
- **Placement**: backmost child of the page `Stack` (before `_BandChromePainter`), so it sits behind
  all elements/overlays (FR-003).
- **Per band**: for each `bandRect`, draw vertical lines at `gridLineOffsets(band.width, …)` and
  horizontal lines at `gridLineOffsets(band.height, …)`, each offset translated by the band's origin
  and `· scale`, clipped to the band rect (D5).
- `shouldRepaint`: true iff `scale`, `layout`, or `color` change (repaints with the page, not on
  hover — D7).

---

## What is explicitly NOT changed

- **No report-model / domain entity** (no grid field on the template, band, or element).
- **No codec / `schemaVersion` / migration.**
- **No public API addition** (`gridEnabled`/`setGridEnabled`/`snapEnabled`/`setSnapEnabled` already
  exist; the painter + helper are `src/`-private).
- **No change to `FrameCustomPainter` / the shared render pipeline** → preview/export/print and
  goldens unchanged.
