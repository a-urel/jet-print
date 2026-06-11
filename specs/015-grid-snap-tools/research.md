# Phase 0 Research: Grid & Snap Helper Tools

All Technical-Context unknowns are resolved below. There were no external/library unknowns (the
feature reuses existing dependencies and patterns); the open questions were all internal design
decisions about how the visible grid composes with the existing band-relative snap geometry, the
mm-calibrated rulers, and the WYSIWYG render boundary.

Format per decision: **Decision** / **Rationale** / **Alternatives considered**.

---

## D1 — Grid origin model: per-band (content origin), not page-physical (0,0)

**Decision**: Draw the visible grid **per band**, registered to each band's content origin, at
`kGridStep`. The grid coincides with the snap candidates exactly because the snap geometry
(`snapping.dart`) already computes grid lines in band-relative coordinates.

**Rationale**: Snapping is band-relative — `_xCandidates`/`_yCandidates` emit
`(seed / gridStep).round() * gridStep` in coordinates where `y = 0` is each band's top and `x = 0`
is the content-left edge. For FR-002's guarantee ("what you see is what you snap to") to hold, the
drawn grid must share that origin. A single global `kGridStep` + per-band origin makes the drawn
line and the snap target the *same number*, so coincidence is exact and unit-testable, with no
second source of truth.

**Alternatives considered**:
- *Page-physical registration (align to the mm rulers from 0,0)*: visually tidier (grid lines fall
  on ruler ticks) but **breaks coincidence** with the band-relative snap grid whenever a band's page
  offset or the page margin is not a whole multiple of 5 mm — the canvas would show lines you can't
  snap to. Rejected on WYSIWYG grounds.
- *Make snapping page-registered too (offset grid seeds by each band's page origin)*: would restore
  both coincidence **and** ruler-tick alignment, but requires threading each band's page offset into
  the pure snap helpers and reworking working, tested band-relative geometry — larger surface, more
  risk, for a cosmetic gain. Deferred; revisit only if ruler-tick coincidence becomes a requirement.

**Accepted tradeoff** (recorded in plan Complexity Tracking): drawn grid lines coincide with the mm
ruler ticks only when band origins/margins are whole multiples of 5 mm.

---

## D2 — Snap step unification at 5 mm

**Decision**: Change `kGridStep` from `8 pt` to `5 mm`, expressed as `kGridStepMm (= 5) · 72/25.4 ≈
14.173 pt`. Define `kGridStepMm` alongside it in `design_tunables.dart`; keep `kGridStep` in points
because `snapping.dart` and the painter both work in points.

**Rationale**: The clarified decision (2026-06-11) is "5 mm for both" — one constant feeds both the
visible grid and the snap candidates, so they cannot diverge. Expressing it in mm makes the intent
explicit and ties it to the same unit the rulers use. The mm→pt factor is the existing
`kPointsPerMm = 72/25.4` from `ruler_metrics.dart`; to keep `design_tunables.dart` free of the
canvas-layer import, inline `72/25.4` there with a comment cross-referencing `kPointsPerMm`.

**Alternatives considered**:
- *Keep 8 pt for snapping, draw a separate 5 mm grid*: rejected at clarify time — visible lines
  wouldn't mark snap positions (confusing).
- *Make `kGridStep` import `kPointsPerMm`*: would couple the pure tunables file to the canvas seam;
  inlining the literal with a doc cross-reference keeps the dependency graph clean.

---

## D3 — Decouple grid **visibility** from grid **snapping**

**Decision**: The controller stops gating grid snapping on `gridEnabled`. Both snap call-sites in
`updateMove`/`updateResize` change `grid: _gridEnabled` → `grid: true` (they already sit inside the
`_snapEnabled` guard). `gridEnabled` becomes **visibility-only**, consumed solely by `_GridPainter`.
`setSnapEnabled` remains the master on/off for all snapping (grid + sibling + band).

**Rationale**: Matches the clarified "decoupled" model — the magnet governs all snapping regardless
of grid visibility; the grid button only shows/hides. This is also simpler (one fewer condition on
the snap path) and removes the current dishonesty where the "grid" flag silently meant
"grid-snapping."

**Alternatives considered**:
- *Keep coupling (grid flag gates grid snapping)*: the pre-clarification behaviour; rejected by the
  user's choice of Option B.
- *A third "snap to grid" sub-toggle*: out of scope — only two buttons exist (grid, magnet), and the
  spec treats the magnet as the single snap master.

**Test impact**: controller-level assertions that `setGridEnabled(false)` disables grid snapping
(`snapping_test.dart:64,98`, `move_commit_teardown_test.dart:25`) are re-expressed via
`setSnapEnabled(false)`/`bypassSnap` (Red→Green). The **pure** `snapMove`/`snapResize` keep their
`grid` parameter and its direct unit tests (the flag still exists at the helper level).

---

## D4 — Adaptive density isolated in a pure helper

**Decision**: A pure function
`List<double> gridLineOffsets(double extent, double step, double scale, double minGapPx)` returns
the line positions (in points, from `0` to `extent`) to draw along one axis of one band. It sets
`f = max(1, ⌈minGapPx / (step · scale)⌉)`; when `f > kGridMaxCoarsenFactor` (= 4, i.e. an effective
step past 20 mm) it returns empty (grid hidden), otherwise it emits multiples of `step · f` — so the
grid coarsens up to 20 mm then disappears and the page never becomes a solid fill (FR-006/SC-006).
`_GridPainter` calls it per band for x (extent = band width) and y
(extent = band height) and strokes lines at `offset · scale`.

**Rationale**: Density/thinning is the one piece of real logic; isolating it in pure Dart makes it
Test-First-able without pumping a widget (monotonic, clamped, coincident-with-`kGridStep`-multiples,
coarsening crosses the floor). The painter stays a thin consumer, mirroring how `RulerScale` backs
the ruler painters.

**Alternatives considered**:
- *Compute thinning inside `paint()`*: not unit-testable without a golden/widget; rejected
  (Principle III).
- *Fade opacity with zoom instead of dropping lines*: softer but still O(all-lines) strokes at low
  zoom and can still read as a fill; dropping lines bounds cost and guarantees legibility.

---

## D5 — Render placement: backmost design-time chrome, never in the pipeline

**Decision**: Add `_GridPainter` as the **first** child of the page `Stack` in `_buildPage` (a
`Positioned.fill(CustomPaint(...))` before `_BandChromePainter`), so it sits behind band separators,
band badges, the cached element picture (`FrameCustomPainter`), element regions, and the selection/
snap-guide overlay (FR-003). Gate construction on `controller.gridEnabled`.

**Rationale**: This is exactly the band-separator chrome pattern already in the file — direct
drawing in the page's scaled local space, outside the shared element render pipeline. Because the
preview/export paths render only the report model through `FrameCustomPainter` (not the canvas's
design-time `Stack`), the grid is **absent from output by construction** (FR-016), the same way band
separators and rulers already are — so **no golden changes**.

**Alternatives considered**:
- *Fold grid lines into `_BandChromePainter`*: convenient but conflates two concerns and complicates
  `shouldRepaint`; a dedicated painter keeps the gate (`gridEnabled`) and density logic local.
- *Paint the grid over the whole page incl. margins*: rejected — snapping only applies inside bands,
  so a grid outside the content area would not be snappable and would clutter the margins.

---

## D6 — Zoom/pan alignment by construction (no new transform)

**Decision**: The grid painter draws in the page's local pixel space (`point · scale`), inside the
same `Positioned` page subtree the band chrome and elements use, which is already positioned by
`pageOffset` and scrolled by `_vScroll`/`_hScroll`. No new transform or scroll math is introduced.

**Rationale**: Because the grid is a child of the same page `Stack`, zoom (via `scale`) and pan (via
the page's position in the viewport) apply to it identically to the elements — a given page point
maps to the same grid pixel at every zoom/scroll (FR-005), with alignment correct by construction.
`grid_alignment_test.dart` pins it by mirroring `ruler_alignment_test.dart`/`zoom_pan_test.dart`.

**Alternatives considered**: a fixed-overlay grid (like the rulers/scrollbars) folding in the live
scroll offset — unnecessary here because, unlike the edge rulers, the grid lives *on* the page and
inherits its transform for free.

---

## D7 — Appearance and repaint cost

**Decision**: Draw thin (1 device px, hairline) low-contrast lines in a muted paper-chrome color
(reuse the band-separator/paper palette family, lighter than the separators so the grid recedes
behind content, FR-003). `_GridPainter.shouldRepaint` returns true only when `gridEnabled`, `scale`,
or `layout` change — so it repaints with the page on zoom/scroll/edit, not on cursor hover.

**Rationale**: Keeps the grid visually subordinate to content and bounds repaint to page-level
changes, matching the existing band-chrome painter's cost profile. Lines vs dots is left as the
visual detail; lines are chosen for cheaper, clearer alignment reading and simpler density logic.

**Alternatives considered**: dots at intersections (lighter but ambiguous at a glance and more
draw calls); theme-accent color (competes with content/selection). Both rejected for the muted
hairline grid.
