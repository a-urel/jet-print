# Phase 0 Research: Vertical & Horizontal Canvas Rulers

All clarifications from the spec are resolved (units = mm, interactivity = display + tracking,
origin = paper corner 0,0, highlight = union bbox, default = on). This document records the design
decisions that turn those requirements into an implementable, constitution-aligned shape. Each entry:
**Decision / Rationale / Alternatives considered**.

## D1 — Where the rulers live (widget placement)

**Decision**: Render the rulers **inside `_DesignCanvasState.build`**, as fixed overlays along the
top and left edges of the same `Stack` that already hosts the scrollbars — not in
`designer_surface.dart` wrapping the canvas. The scroll viewport is inset by `kRulerThickness` (top +
left) when rulers are enabled; the freed strips hold the horizontal ruler (top), the vertical ruler
(left), and a blank corner box at their intersection.

**Rationale**: The canvas already computes the three quantities a ruler needs to map page→pixel —
`scale` (`controller.viewScale`), the centering `pageOffset`, and the live scroll positions
(`_vScroll`/`_hScroll`) — all *locally* in the build method. Placing the rulers there lets them read
those values directly, with **zero new shared state**. It is the exact pattern the existing
scrollbars already use (fixed `Positioned` overlays in the same `Stack`, redrawn via `AnimatedBuilder`
on the scroll controllers). One view source → alignment correct by construction.

**Alternatives considered**: (a) Rulers in `designer_surface` around `DesignCanvas`. Rejected — the
true pan offset lives in the widget-local scroll controllers, so this would force lifting scroll
state into the controller (duplicated state, sync bugs, and a larger public surface). (b) A separate
`InteractiveViewer`-style transform. Rejected — the canvas deliberately uses nested scroll views (see
`_CanvasScrollBehavior`) for 2D scrolling + scrollbars; introducing a parallel transform would fork
the view math and risk WYSIWYG drift.

## D2 — Pure `RulerScale` (the testable seam)

**Decision**: A pure-Dart value type `RulerScale` (in `ruler_scale.dart`, importing only `dart:math`)
computes tick layout. Input: `originPx` (pixel of page-0 on the strip), `pxPerMm` (current pixels per
millimetre), `lengthPx` (strip length), and spacing tunables. Output: an ordered `List<RulerTick>`
where each `RulerTick` is `{ offsetPx, label /* null for minor */, isMajor }`. A companion
`CustomPainter` simply draws what the scale yields.

**Rationale**: Alignment, adaptive density, and "labels never overlap" (SC-002/SC-004/FR-010) are the
hard, regression-prone parts — and they are *pure functions of numbers*. Isolating them from Flutter
painting makes them unit-testable red→green without pumping a widget (Principle III), and keeps the
painter trivial.

**Alternatives considered**: Compute ticks inline in the painter. Rejected — un-unit-testable without
goldens; ties the math to a `Canvas`. Goldens for tick math are brittle (text rendering) and weak at
asserting exact spacing invariants.

## D3 — Nice-step ladder for adaptive label density

**Decision**: Pick the labelled millimetre interval from an ascending ladder
`{1, 2, 5, 10, 20, 50, 100, 200, 500, 1000} mm`, choosing the smallest step whose on-screen spacing
(`step · pxPerMm`) is ≥ `kRulerMinLabelGapPx` (target ≈ 48–60 px). Minor ticks subdivide the labelled
step (step/5 or step/10, whichever keeps minor spacing ≥ a small floor). Clamp so an extreme zoom-out
never drops below the largest ladder step and an extreme zoom-in never subdivides below ~1 mm.

**Rationale**: Guarantees SC-004 (labels never overlap, at least one labelled interval always legible)
and FR-010 (finer when zoomed in, coarser when out) with a deterministic, testable rule. The
1/2/5 progression is the standard "nice numbers" axis-labelling choice and keeps labels at round mm
values.

**Alternatives considered**: Continuous step = `niceCeil(minGap / pxPerMm)`. Workable but yields
odd labels (e.g., 37 mm); the fixed ladder reads better and is easier to assert in tests.

## D4 — Alignment formula (zoom + scroll)

**Decision**: A page point `p` (in points, page-absolute) maps to a ruler pixel by
`rulerPx = p · scale + pageOffset − scrollOffset`, using the horizontal pair
(`pageOffset.dx`, `_hScroll.offset`) for the top ruler and the vertical pair for the left ruler.
`pxPerMm = scale · kPointsPerMm`. The origin pixel handed to `RulerScale` is the ruler pixel of
page point 0, i.e. `pageOffset − scrollOffset`. Rulers rebuild on scroll (an `AnimatedBuilder`
listening to the scroll controllers) and on controller `notifyListeners` (zoom/selection/visibility).

**Rationale**: Single source of truth for the view (no second transform) → FR-008/FR-009/SC-002 hold
by construction. Mirrors how the scrollbars and the page `Positioned` already derive screen position.

**Alternatives considered**: Track pan in `CanvasViewTransform.pan`. Rejected — in this canvas `pan`
is only the centering offset; the real pan is the scroll offset.

## D5 — Cursor tracking (hover) with bounded repaint

**Decision**: Add a `MouseRegion` over the canvas content; `onHover` converts the local pointer to a
page point and writes it to a `ValueNotifier<JetOffset?> _hoverPage`; `onExit` writes `null`. The two
ruler painters listen to that notifier (via `ValueListenableBuilder`/`AnimatedBuilder`) behind a
`RepaintBoundary`, drawing a 1-px position marker at the pointer's projected ruler pixel.

**Rationale**: Hover fires at pointer-frame rate. Routing it through a `ValueNotifier` that *only* the
thin ruler painters listen to means a hover move repaints two small strips — never the cached page
picture or the element regions. This directly answers the perf concern deferred from the clarify
phase. Clearing on exit satisfies FR-011 / US4-scenario-6.

**Alternatives considered**: Store hover in `setState`/controller. Rejected — rebuilds the whole
canvas subtree (or notifies every listener) on every pointer move; unnecessary churn.

## D6 — Selection extent = union bounding box

**Decision**: A pure helper `selectionExtent(DesignTimeLayout layout, Selection selection)
→ JetRect?` returns: the union (min-left/top → max-right/bottom) of the selected **element** rects
(`layout.elementRect`), or the **band** rect (`layout.bandRect`) for a band selection, or `null` for a
report/empty selection. The rulers draw the union's horizontal span on the top ruler and its vertical
span on the left ruler, clamped to the strip. Recomputed each build (cheap; from the already-built
layout), so it tracks moves/resizes automatically.

**Rationale**: One rule covers single element, multi-element, and band selections (the clarified
union-bbox decision, FR-012). The layout already exposes page-absolute rects, so this is pure
arithmetic. Clamping handles the straddle/overflow edge cases. Because it is derived from
`controller.selection` + `layout` on every build, move/resize updates are free (US4-scenarios 3/4).

**Alternatives considered**: Per-element highlight bands. Rejected by the clarification (visual
clutter on large selections). Highlight only single selection. Rejected by the clarification.

## D7 — Ruler visibility in the controller (default on)

**Decision**: Add `bool _rulersEnabled = true` to `JetReportDesignerController` with a `rulersEnabled`
getter and `setRulersEnabled(bool)` that no-ops on no change and otherwise `notifyListeners()` —
byte-for-byte the shape of `gridEnabled`/`setGridEnabled`. Delete the top bar's local `_ruler` field;
the toggle reads `controller.rulersEnabled` for its `active` state and calls
`setRulersEnabled(!controller.rulersEnabled)` on press.

**Rationale**: Parity with the sibling view toggles (grid/snap already route through the controller);
single source of truth; testable without the widget. Default `true` satisfies FR-017 and matches the
toggle's current initial state, so behavior on first open is unchanged except the rulers now actually
appear.

**Alternatives considered**: Keep visibility widget-local. Rejected — inconsistent with grid/snap,
not unit-testable, and the canvas (a different widget) needs to read it to inset its viewport.

## D8 — Ruler thickness, corner, and viewport inset

**Decision**: `kRulerThickness` (≈ 20 px, fixed screen chrome like the scrollbars/badges). When
`rulersEnabled`, inset the scroll viewport by the thickness on top and left; the horizontal ruler
fills the top strip (left-inset by the thickness), the vertical ruler the left strip (top-inset),
and a blank corner box fills the `thickness × thickness` intersection showing **no** measurement
(FR-013). When disabled, no inset and no strips — the canvas reclaims the space (FR-007 / US2).

**Rationale**: A constant-thickness strip keeps the layout stable (FR-007); the blank corner is the
standard, unambiguous treatment of the ruler intersection (FR-013).

## D9 — No serialization, no render-pipeline change

**Decision**: Rulers are drawn as design-time chrome only — never emitted through `FrameCustomPainter`
/ the shared render pipeline, never present in `JetReportPreview` or any export. No report-model
field, no codec change, `schemaVersion` stays as-is.

**Rationale**: Satisfies FR-014, SC-006, and Principles IV (no parallel render path; preview/export
identical → **no existing golden changes**) and V (zero serialization impact) trivially. Rulers join
the same "design-only chrome" category as `_BandChromePainter` and the band badges.

**Alternatives considered**: Persist ruler visibility in the template. Rejected — it is a per-session
view preference, not part of the report definition; persisting it would be a schema change for no user
benefit.

## D10 — Localization of labels

**Decision**: Tick labels are integer millimetre values formatted with `intl`'s `NumberFormat` for
the active locale (so thousands grouping etc. follow en/de/tr conventions); no unit suffix on every
tick (standard ruler convention). The existing `toggleRulerTooltip` ARB key ("Show rulers") already
covers the toggle. No new ARB strings are strictly required; if a unit indicator is desired it is a
single optional key.

**Rationale**: Satisfies FR-015 / SC-007 by reusing the established localization mechanism; keeps the
ARB churn near zero. Labels are numerals, so the main locale effect is grouping separators on large
values.

**Alternatives considered**: Hand-format with `toString()`. Rejected — wrong grouping in de/tr and
inconsistent with the rest of the designer's number handling.

## Resolved unknowns summary

| Unknown | Resolution |
|---------|------------|
| Where do rulers attach without forking the view math? | Inside `DesignCanvas`, as scrollbar-style edge overlays (D1, D4). |
| How to keep alignment correct under zoom **and** scroll? | `p·scale + pageOffset − scrollOffset`; rebuild on scroll + controller (D4). |
| How to make the math test-first? | Pure `RulerScale`/`RulerTick` + pure `selectionExtent`/mm helpers (D2, D6). |
| How to avoid label crowding across zoom? | Nice-step ladder with min label gap + clamps (D3). |
| How to keep hover cheap? | `ValueNotifier` → ruler painters only, behind `RepaintBoundary` (D5). |
| How to control visibility consistently? | Controller flag mirroring grid/snap, default on (D7). |
| Any model/serialization impact? | None — design-time chrome only (D9). |
