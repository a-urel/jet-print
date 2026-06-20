# Preview Zoom Parity — Design

**Date:** 2026-06-20
**Status:** Approved (design), pending implementation plan

## Problem

The report **preview** toolbar and the **designer** top bar present zoom
differently, both visually and behaviourally:

| | Designer | Preview (today) |
|---|---|---|
| Control | `[zoom−] [editable % field + dropdown] [zoom+]` | `[zoom−] [tappable % = reset-to-fit] [zoom+]` |
| Model | absolute `viewScale` (1.0 = actual size) + sticky `JetViewFitMode` (`none`/`width`/`page`) | `_zoom` = **multiplier on fit-to-width** (1.0 = fit width) |
| "100%" means | actual size | fit-to-width |
| Fit modes | Fit Width, Fit Page | fit-width only (implicit) |
| Presets | 50 / 75 / 100 / 150 / 200 % | none |
| Re-fit on resize | yes (sticky) | n/a (always fit-relative) |

The two surfaces should feel like one product. The user asked the preview's
zoom section to **match the designer's**.

## Decision

**Full parity.** The preview adopts the designer's zoom *model and widget*:
the shared `ZoomControl` (editable % field + dropdown with Fit Width, Fit Page,
and presets), flanked by zoom-out / zoom-in buttons. "100%" becomes actual
size; fit-to-width remains the default open state; fit-page is added; the page
re-fits on viewport resize while a sticky fit is active.

## Approach (chosen: A — local view-state in the preview)

The fit math (`fitWidthScale` / `fitPageScale`), the `ZoomControl` widget, and
the `JetViewFitMode` enum are already package-internal and shared. The only
architectural question is where the preview's new view-state lives. We keep it
**local to `_JetReportPreviewState`**, replicating the canvas's post-frame
"compute-fit-and-write-back" handshake inside the preview's own `LayoutBuilder`.

Rejected:
- **B — extract a shared `ViewportZoomModel`**: invasive refactor of the
  controller (zoom is woven into its `notifyListeners` and the canvas
  `fitRequest` handshake), touching many passing tests. Far more than the task
  needs (YAGNI).
- **C — shared fit-handshake mixin** across canvas + preview: a new abstraction
  spanning two widgets for ≈15 lines of code; more coupling than it saves.

## Components & changes

### 1. `ZoomControl` (`designer/layout/zoom_control.dart`)
Add an optional `String keyPrefix` parameter, defaulting to
`'jet_print.designer'` (existing designer tests unaffected). The hard-coded
`ValueKey`s (`…action.zoomLevel`, `…zoom.fitWidth`, `…zoom.fitPage`,
`…zoom.menuToggle`, `…zoom.preset.$p`) derive from `keyPrefix`. The preview
passes `'jet_print.preview'` so its field/menu keep `jet_print.preview.*` keys.

### 2. `JetReportPreview` (`designer/preview/jet_report_preview.dart`)
- **State:** replace `double _zoom` with `double _viewScale = 1.0` (absolute) +
  `JetViewFitMode _fitMode = JetViewFitMode.width`. Drop the local
  `_minZoom` / `_maxZoom` / `_zoomStep` constants in favour of shared
  `kMinZoom` / `kMaxZoom` and a `×1.25` step (today's values already match).
  Add `int _fitRequest`, `Size? _lastFitViewport`, `bool _viewInitialized`.
- **Intent methods** (mirroring the controller):
  - `_setViewScale(double)` — clamp to `kMinZoom`..`kMaxZoom`.
  - `_zoomIn` / `_zoomOut` — `× / ÷ 1.25`, *manual* (set `_fitMode = none`).
  - `_setZoomPercent(double percent)` — `_setViewScale(percent/100)`, manual.
  - `_setFitMode(JetViewFitMode)` — set mode, bump `_fitRequest`.
- **Fit handshake in `LayoutBuilder`:** mirror `design_canvas.dart` lines
  718–755. When `(first load ∧ fit active) ∨ (fitRequest changed) ∨
  (viewport changed while a sticky fit is active)`, schedule
  `addPostFrameCallback` that computes
  `fitPageScale / fitWidthScale(JetSize(frame.page.width, frame.page.height),
  viewport, pad)` and writes it into `_viewScale` via `setState`, resetting
  scroll to top-left. Track `_appliedFitRequest` / `_lastFitViewport` /
  `_viewInitialized` to avoid redundant fits.
- **Layout:** the page lays out at the **absolute** `scale = _viewScale`
  (today's `pageWidth = fitWidth * _zoom; scale = pageWidth / page.width`
  collapses to `pageWidth = page.width * _viewScale`). The existing
  center-when-fits / scroll-when-larger wrapping is unchanged and now supports
  vertical fit-page for free.
- **Toolbar:** in `_toolbarActions`, replace the tappable `%` `Text` (and
  `_resetZoom`) with the designer's trio: zoom-out `_ToolbarButton` →
  `ZoomControl(viewScale: _viewScale, fitMode: _fitMode,
  onPercent: _setZoomPercent, onFit: _setFitMode, keyPrefix: 'jet_print.preview')`
  → zoom-in `_ToolbarButton`. Export/print and page-nav groups unchanged.

### 3. Baked-in parity decisions
- **Stable keys:** preview keeps `jet_print.preview.*` via `keyPrefix`.
- **Zoom buttons at bounds:** match the designer — the buttons do **not**
  disable; they clamp silently. (The preview's current disable-at-min/max is
  dropped.)

## Data flow

```
user → ZoomControl.onPercent / .onFit  (or zoom± buttons)
     → _setZoomPercent / _setFitMode / _zoomIn / _zoomOut   (setState)
     → LayoutBuilder re-runs
        ├─ fit active & needs refit? → postFrame → compute fit scale → _viewScale
        └─ page laid out at scale = _viewScale
     → ZoomControl field shows (_viewScale*100).round() %, checkmark on _fitMode
```

## Testing

Already covered (unchanged): `ZoomControl` widget tests, `fitWidthScale` /
`fitPageScale` math tests.

Rewrite the preview test's `group('zoom …')` to the new semantics:
- opens fit-to-width (field shows the **computed** %, not literal "100%");
- zoom-in / zoom-out enlarge / shrink the page;
- picking **Fit Width** / **Fit Page** from the dropdown re-fits (page width
  fills on Fit Width; whole page fits on Fit Page);
- typing a % and picking a preset set the absolute scale;
- scale clamps at `kMinZoom` / `kMaxZoom` (buttons stay enabled).

Add a `keyPrefix` default-vs-override test to `zoom_control_test.dart` if not
implied by the above. The `menuZoomFitWidth` / `menuZoomFitPage` l10n keys
already exist.

## Out of scope (YAGNI)

No controller refactor; no shared zoom model; no new pan / mouse-wheel zoom in
the preview; no change to export / print or page navigation.
