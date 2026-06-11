# Behavioral Contracts: Vertical & Horizontal Canvas Rulers

These are the testable contracts the implementation must satisfy, grouped by component, each mapped to
spec requirements (FR-/SC-) and to the test files in the plan. Per Principle III, every contract has a
**failing test written first**. The pure contracts (C1, C2, C5) are unit-tested without a widget.

## C1 — `RulerScale` tick layout (pure) — `ruler_scale_test.dart`

Maps to FR-002, FR-008, FR-010, SC-002, SC-004.

1. **Monotonic & in-bounds**: for any `(originPx, pxPerMm > 0, lengthPx > 0)`, ticks have strictly
   increasing `offsetPx`, all within `[0, lengthPx]`.
2. **Label-gap guarantee**: the pixel distance between consecutive **major** (labelled) ticks is
   ≥ `minLabelGapPx` — at every zoom across `[kMinZoom, kMaxZoom]` mapped to `pxPerMm`. (SC-004: labels
   never overlap.)
3. **At least one label**: for any non-empty strip the output contains ≥ 1 major tick. (SC-004: never
   barren.)
4. **Nice-step selection**: the chosen labelled step is the smallest ladder value
   (`{1,2,5,10,20,50,100,…}`) whose `step·pxPerMm ≥ minLabelGapPx`; zooming in selects a smaller step,
   zooming out a larger one. (FR-010.)
5. **Alignment exactness**: a major tick labelled `k` mm sits at `offsetPx == originPx + k·pxPerMm`
   (within float epsilon). (SC-002.)
6. **Subdivisions**: minor ticks subdivide the labelled step and never fall below the configured minor
   floor; `label == null` for all minor ticks.
7. **Origin off-strip**: when `originPx < 0` (page scrolled), only ticks with `offsetPx ≥ 0` are
   emitted, and label values stay correct (e.g., first visible label may be > 0 mm). (FR-009.)
8. **Extreme clamp**: at `pxPerMm` for max zoom the step never subdivides below ~1 mm; at min zoom the
   labelled step never exceeds the largest ladder value. (FR-010 edge cases.)

## C2 — Ruler metrics (pure) — `ruler_metrics_test.dart`

Maps to FR-003, FR-005, FR-012.

1. **Conversion parity**: `pointsToMm(mmToPoints(x)) ≈ x` and `mmToPoints(pointsToMm(y)) ≈ y`;
   `kPointsPerMm == 72/25.4`. (FR-005.)
2. **Origin**: page point 0 → 0 mm (paper corner origin). A point at the page width converts to the
   page width in mm. (FR-003.)
3. **`selectionExtent` — single element**: returns exactly that element's page-absolute rect. (FR-012.)
4. **`selectionExtent` — multiple elements**: returns the union (min-left/top → max-right/bottom) of
   all selected element rects — one combined rect, not per-element. (FR-012, clarified union bbox.)
5. **`selectionExtent` — band**: returns the selected band's rect. (FR-012.)
6. **`selectionExtent` — report/empty**: returns `null`. (FR-012, US4-scenario 5.)
7. **Stability**: independent of selection insertion order (union is order-free).

## C3 — Visibility & toggle — `rulers_test.dart`, `top_bar_test.dart`

Maps to FR-001, FR-006, FR-007, FR-017, US1, US2.

1. **Default on**: a freshly constructed controller reports `rulersEnabled == true`; on first open the
   horizontal ruler (top) and vertical ruler (left) are present. (FR-017, FR-001.)
2. **Toggle hides**: activating the ruler toggle sets `rulersEnabled == false`; both ruler strips are
   gone and the canvas viewport expands into the freed space. (FR-006, FR-007, US2-1.)
3. **Toggle shows**: activating again restores both rulers aligned with the page. (US2-2.)
4. **Active reflects state**: the toggle's `active` styling equals `controller.rulersEnabled` at all
   times (parity with grid/snap). (FR-006, US2-3.)
5. **Corner blank**: the corner box at the ruler intersection renders no measurement/label. (FR-013.)

## C4 — Alignment under zoom + pan — `ruler_alignment_test.dart`

Maps to FR-004, FR-008, FR-009, SC-002 (mirrors `zoom_pan_test.dart` / `page_scroll_test.dart`).

1. **Default zoom**: an element's left/top edge projects to the ruler pixel
   `edge·scale + pageOffset − scrollOffset`, and the ruler shows the matching mm at that pixel.
   (FR-004.)
2. **Zoom in/out**: after `zoomIn()`/`zoomOut()`, the same edge still aligns with its mm mark; labelled
   spacing stays ≥ minimum and re-steps (finer/coarser). (FR-008, FR-010, SC-002.)
3. **Pan**: after scrolling `_vScroll`/`_hScroll`, both rulers shift with the page so each mark stays
   over its page position; first visible labels update. (FR-009.)
4. **No drift**: across several (zoom, scroll) combinations the mm read at an element edge equals its
   true page-absolute mm within one subdivision. (SC-002.)

## C5 — Cursor tracking & selection highlight — `ruler_tracking_test.dart`

Maps to FR-011, FR-012, US4.

1. **Hover marker**: moving the pointer over the canvas places a marker on the horizontal ruler at the
   pointer's X and on the vertical ruler at its Y. (FR-011, US4-1.)
2. **Exit clears**: when the pointer leaves the canvas the marker is removed from both rulers.
   (FR-011, US4-6.)
3. **Single-selection highlight**: selecting one element highlights its left→right span on the top
   ruler and top→bottom span on the left ruler, matching its edges. (FR-012, US4-2.)
4. **Union highlight**: selecting multiple elements (or a band) highlights one combined span per ruler
   from the outermost edges. (FR-012, US4-3, clarified union bbox.)
5. **Move/resize update**: moving or resizing the selection updates the highlighted span to the new
   outer edges. (FR-012, US4-4.)
6. **Clear on deselect**: clearing the selection removes the highlight from both rulers. (US4-5.)
7. **Clamp**: a selection straddling/exceeding the page edges produces a highlight clamped to the
   strip (never drawn off-ruler / negative). (Edge cases.)

## C6 — Localization — `localization_test.dart` (+ `_de`, `_tr`)

Maps to FR-015, SC-007.

1. **Label formatting**: mm labels use the active locale's number formatting (grouping) in en/de/tr;
   large values (e.g., 1,000 mm) group per locale.
2. **Tooltip**: the ruler toggle tooltip resolves via the existing `toggleRulerTooltip` key in each
   locale, with English fallback for an unset locale.

## C7 — Non-regression (architecture / WYSIWYG) — `public_api_test.dart`, `layer_boundaries_test.dart`, existing goldens

Maps to Principles I, II, IV, V; FR-014, SC-006.

1. **No new exported surface**: `public_api_test` passes unchanged through the single entry point
   (rulers reachable only via `JetReportDesigner`; no new export).
2. **Layer boundary**: `ruler_scale.dart` and `ruler_metrics.dart` import no rendering/Flutter-UI
   library (pure Dart + `domain/geometry.dart`); the domain seam is untouched. `layer_boundaries_test`
   stays green.
3. **WYSIWYG unchanged**: all existing canvas/preview/export goldens are byte-identical (rulers are
   design-only chrome, not in the render pipeline). No codec/schema change. (FR-014, SC-006.)

## Test matrix summary

| Group | File(s) | Type |
|-------|---------|------|
| C1 RulerScale | `ruler_scale_test.dart` | unit (pure) |
| C2 metrics/extent | `ruler_metrics_test.dart` | unit (pure) |
| C3 visibility/toggle | `rulers_test.dart`, `top_bar_test.dart` | widget |
| C4 alignment | `ruler_alignment_test.dart` | widget |
| C5 tracking/highlight | `ruler_tracking_test.dart` | widget |
| C6 localization | `localization_test.dart` (+ `_de`/`_tr`) | widget |
| C7 non-regression | `public_api_test.dart`, `layer_boundaries_test.dart`, goldens | unit/arch/golden |
