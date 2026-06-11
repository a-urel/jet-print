# Phase 1 Data Model: Vertical & Horizontal Canvas Rulers

This feature introduces **no domain-model or serialized-schema change**. The "model" here is the
small set of **view-only** constructs in the designer seam. The report model
(`ReportTemplate`/`PageFormat`/bands/elements), its codec, and `schemaVersion` are **untouched**
(FR-014, SC-006).

## View-only entities (designer seam, under `src/`)

### `RulerTick` (pure value — `ruler_scale.dart`)

One tick on a ruler strip.

| Field | Type | Meaning |
|-------|------|---------|
| `offsetPx` | `double` | Pixel offset along the strip (0 = strip start). |
| `label` | `String?` | Formatted mm label for a **major** tick; `null` for a minor tick. |
| `isMajor` | `bool` | Whether this is a labelled major tick (longer line) or a minor subdivision. |

Invariants: ticks are emitted in strictly increasing `offsetPx`; every tick lies within
`[0, lengthPx]`; `label != null ⇒ isMajor`.

### `RulerScale` (pure value/function — `ruler_scale.dart`)

Computes the tick layout for one ruler from view numbers. **Imports only `dart:math`** (no Flutter).

| Input | Type | Meaning |
|-------|------|---------|
| `originPx` | `double` | Strip pixel of page-coordinate 0 (= `pageOffset − scrollOffset`). May be negative/off-strip. |
| `pxPerMm` | `double` | Current pixels per millimetre (`viewScale · kPointsPerMm`). |
| `lengthPx` | `double` | Length of the strip in pixels. |
| `minLabelGapPx` | `double` | Minimum pixels between labelled ticks (`kRulerMinLabelGapPx`). |
| `formatLabel` | `String Function(int mm)` | Locale-aware mm→label (injected so the pure type stays Flutter/intl-free). |

Output: `List<RulerTick> ticks` — only the ticks within the visible strip, with the labelled step
chosen from the nice-step ladder (research D3) so labelled spacing ≥ `minLabelGapPx`, and minor
subdivisions filled in. Deterministic for identical inputs.

### Ruler metrics (pure helpers — `ruler_metrics.dart`)

| Symbol | Type | Meaning |
|--------|------|---------|
| `kPointsPerMm` | `const double` | `72 / 25.4` (≈ 2.834645669). Single conversion constant. |
| `pointsToMm(double pts)` | `double` | `pts / kPointsPerMm`. Display-only (FR-005). |
| `mmToPoints(double mm)` | `double` | `mm * kPointsPerMm`. |
| `selectionExtent(DesignTimeLayout, Selection)` | `JetRect?` | Union bbox of the current selection (research D6): union of selected element rects; the band rect for a band selection; `null` for report/empty. |

### Ruler visibility (controller view state)

Added to `JetReportDesignerController` next to grid/snap:

| Member | Type | Default | Behavior |
|--------|------|---------|----------|
| `_rulersEnabled` | `bool` (private) | `true` (FR-017) | Source of truth for visibility. |
| `rulersEnabled` | `bool get` | — | Read by the top bar (toggle `active`) and the canvas (viewport inset). |
| `setRulersEnabled(bool)` | `void` | — | No-op on no change; else `notifyListeners()`. Mirrors `setGridEnabled`. |

Ephemeral — **not** serialized (it is a per-session view preference, like `gridEnabled`/`snapEnabled`).

### Transient view state (widget-local in `_DesignCanvasState`)

| Member | Type | Meaning | Lifetime |
|--------|------|---------|----------|
| `_hoverPage` | `ValueNotifier<JetOffset?>` | Current pointer position in page coords, or `null`. | While the pointer is over the canvas (FR-011). |
| selection extent | derived `JetRect?` | `selectionExtent(layout, controller.selection)` recomputed per build. | While a selection exists (FR-012). |

### Constants (added to `design_tunables.dart`)

| Constant | Purpose |
|----------|---------|
| `kRulerThickness` | Strip thickness in screen px (fixed chrome), ≈ 20. Drives the viewport inset and corner box (research D8). |
| `kRulerMinLabelGapPx` | Minimum px between labelled ticks (research D3), ≈ 48–60. |
| `kRulerStepLadderMm` | Ascending nice-step ladder `{1,2,5,10,20,50,100,200,500,1000}` mm. |

## Relationships & data flow

```
controller.viewScale ─┐
pageOffset (centering)─┼─► originPx, pxPerMm ─► RulerScale ─► List<RulerTick> ─► Ruler painter (strip)
scrollOffset (_hScroll/_vScroll)┘                          (formatLabel via intl + locale)

controller.selection + DesignTimeLayout ─► selectionExtent() ─► JetRect? ─► highlight span on each ruler
_hoverPage (ValueNotifier) ─────────────────────────────────► position marker on each ruler
controller.rulersEnabled ─► viewport inset + strip visibility (canvas)  &  toggle active (top bar)
```

## Explicitly unchanged (no delta)

- `ReportTemplate`, `PageFormat`, `ReportBand`, all `ReportElement` types — no new field.
- All serialization/codec files — no read/write change; `schemaVersion` constant unchanged; no migration.
- The shared render pipeline (`FrameCustomPainter`, `ElementResolver`, preview, export) — rulers
  never flow through it; preview/export bytes and existing goldens are identical (FR-014, SC-006).
- Public exports (`jet_print.dart` and friends) — no new exported symbol; only two methods added to
  the already-reachable designer controller.
