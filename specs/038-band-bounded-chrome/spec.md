# Feature Specification: Band-Bounded Selection Chrome

**Feature Branch**: `038-band-bounded-chrome`
**Created**: 2026-06-20
**Status**: Draft
**Input**: Design handles always have to be within band boundaries. Moving or
resizing should not allow handles or selection boxes to move beyond band borders.
A selected element's chrome — the blue selection outline and its eight resize
handles — must render fully inside the element's band at all times: idle, during
a live move, and during a resize. Designer/UI-only — no engine, model,
serialization, or render-path change.

## Problem

The model already guarantees containment: every committed geometry edit routes
through the single `clampToBand` authority
(`controller/element_bounds.dart` lines 27–40), so no element is ever committed
off its band. But the **live selection chrome** drawn by
`DesignerSelectionOverlay` (`canvas/selection_overlay.dart`) can sit outside a
band in two distinct ways:

1. **Live-move drift.** The canvas builds two layouts each frame: `layout` (the
   committed definition) and `displayLayout` (built from
   `controller.displayDefinition`, which bakes the in-progress move/resize/
   band-resize through `clampToBand`). Every live-tracking consumer — the painted
   element picture, the per-element hit regions, the grid, band separators,
   badges — reads `displayLayout` (`canvas/design_canvas.dart` lines 1094, 1104,
   1142). The selection overlay is the **one** consumer still wired to the
   committed `layout` (`design_canvas.dart` line 1147), so it re-derives geometry
   itself: `rectFor(id)` takes the committed element rect and adds the **raw**
   drag delta `move.dx / move.dy` (`selection_overlay.dart` lines 134–140). During
   a move that clamps at a band edge, the painted element stops at the border
   while the outline + handles keep following the cursor — the chrome visually
   **decouples** from the element and slides past the band. (Resize does not
   drift: `rectFor` reuses `controller.previewBoundsFor`, which is the already-
   clamped resize preview.)

2. **Static handle protrusion.** Resize handles are centered **on** the element's
   edges and midpoints (`_handleCenter`, `selection_overlay.dart` lines 396–413).
   The handle is positioned as a box of `kHandleHitSize` (16 screen px, hit area)
   containing a `kHandleVisualSize` (8 screen px) chip, centered on that point
   (`_handle`, lines 333–339). When an element sits **flush** against a band edge
   (e.g. `y == 0` at the top, or `y == band.height - height` at the bottom), the
   edge handle's center lands on the band border, so the box pokes ≈4 px (visual)
   / ≈8 px (hit area) **outside** the band — even at rest, and on both move and
   resize. The outline itself never exceeds the band (it follows the clamped
   element), but the handles do.

The fix must make the live chrome honor the same band boundary the model already
enforces — without duplicating clamp logic or touching the commit path.

## Clarifications

### Session 2026-06-20

- Q: Two ways the chrome can exit a band — live-move drift, and static handle
  protrusion when an element is flush against the edge. Which should the fix
  cover? → A: **Both.** Fix the live-move drift AND keep handles fully inside the
  band even at rest. This matches "handles always have to be within band
  boundaries."
- Q: Where to fix the drift — re-clamp the delta in the overlay, clip the overlay
  to band rects, or wire the overlay to the existing display layout? → A: **Wire
  the overlay to `displayLayout`.** Reuse the single `clampToBand` authority the
  display layout already applies; do not re-implement a clamp or clip (clipping
  only hides the decoupling and slices handles mid-shape).
- Q: How to keep handles inside the band when an element is flush against an edge
  — clip, or clamp the handle box? → A: **Clamp the handle box** to the band
  screen rect (preserves full hit area; only edge-touching handles nudge inward;
  handles away from an edge are unaffected).

## Scope

**In scope**

- **Wire `DesignerSelectionOverlay` to the display layout.**
  `design_canvas.dart` passes `displayLayout` (not `layout`) to the overlay so the
  chrome derives from the same live, clamped geometry the element picture uses.
- **Simplify the overlay's geometry path.** `rectFor(id)` resolves to the
  element's rect in the display layout (`widget.layout.elementRect(id)`), removing
  the raw `moveDelta` addition and the resize `previewBoundsFor` band-local
  conversion from the overlay. (The controller's `moveDelta` / `previewBoundsFor`
  / `activeBandId` getters remain; the overlay's outline/handle geometry simply no
  longer depends on the raw delta.)
- **Clamp each handle box to its band's screen rect.** In `_handle`, after
  computing the handle's positioned box, constrain its `left` / `top` (and the
  resulting right/bottom) so neither the visual chip nor the hit area crosses the
  band border. The element's band rect is resolved from the layout
  (`findBandOfElement` → `bandRect`) and scaled by the view scale.
- **Defensive outline clamp (if needed).** The outline already follows the
  clamped element, so it stays inside the band once change 1 lands; an explicit
  clamp of the outline rect to the band may be added only if a residual sub-pixel
  overflow is observed.
- **Tests** covering live-move tracking, multi-select, the four flush edges, and
  resize-past-edge (regression guard for the existing clamp).

**Out of scope**

- Any change to `clampToBand`, `bandContentWidth`, the controller's
  move / resize / band-resize state machine, or the commit commands
  (`MoveCommand` / `ResizeCommand` / `SetBandHeightCommand`). The model is already
  correct on commit; this slice only makes the **live overlay** match it.
- Any engine, domain model, serialization, `validate()`, or render/export change.
  Selection chrome is transient designer state, not part of the model or undo/redo
  history, and stays that way. Goldens are unaffected.
- Changing handle size constants (`kHandleHitSize`, `kHandleVisualSize`),
  min-element-size (`kMinElementSize`), snapping, or cursors.
- Re-centering handles globally (handles stay centered on the element edge except
  where the band-rect clamp nudges an edge-touching handle inward).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Selection tracks the clamped element during a move (P1)

An author drags an element toward — and past — a band's bottom edge. The element
body stops at the band boundary (today's clamp). The blue selection outline and
all eight handles **stop at the same boundary**, glued to the element. They never
slide below the band into the next band's territory. (Today the outline + handles
keep following the cursor while the element stays put.)

### User Story 2 - Handles stay inside the band when an element is flush (P1)

An author places an element flush against the top of its band (`y == 0`). The top
edge and top-corner handles render **inside** the band, just below the border —
not poking ≈4–8 px above it into the band separator. The same holds for the
bottom, left, and right band edges. Handles that are not near any band edge stay
centered on the element's edge as before.

### User Story 3 - Resize past a band edge keeps handles inside (P1)

An author drags the bottom-right handle far past the band's bottom-right corner.
The resize preview clamps to the band (today's behavior). The handles ride the
clamped preview and stay **inside** the band — the bottom/right handles sit on the
clamped edge, fully within the band rather than protruding past it.

### User Story 4 - Multi-select move stays bounded (P2)

An author selects three elements in different bands and drags them. Each element's
outline + handles track its **own** clamped position in its **own** band; no
selection box drifts beyond its band, even when one element clamps at an edge and
the others do not.

## Requirements *(mandatory)*

### Functional

- **FR-001**: `design_canvas.dart` MUST pass the **display** layout
  (`displayLayout`, built from `controller.displayDefinition`) to
  `DesignerSelectionOverlay`, replacing the committed `layout` currently passed
  (line 1147). When idle, `displayLayout` is the same instance as `layout`, so
  this is a no-op at rest and a correction only while an edit is in progress.
- **FR-002**: The overlay's `rectFor(id)` MUST resolve a selected element's chrome
  rectangle from the display layout (`widget.layout.elementRect(id)`). The raw
  `moveDelta` addition and the `previewBoundsFor` band-local→page conversion MUST
  be removed from the overlay's geometry path. Because `displayDefinition` routes
  every in-progress move / resize / band-resize through `clampToBand`, the
  resulting outline can never exceed the band content box.
- **FR-003**: During a live move that is clamped at a band edge, the selection
  outline MUST coincide with the painted element body (no decoupling): the outline
  stops at the same boundary as the element, for single- and multi-element
  selections.
- **FR-004**: Each resize handle's screen box — both the `kHandleHitSize` hit area
  and the `kHandleVisualSize` chip — MUST be clamped so it lies fully within its
  element's **band** screen rect. No part of any handle may render or hit-test
  outside the band, including when the element is flush against a band edge.
- **FR-005**: The overlay MUST obtain an element's band rect from the layout
  (resolve the owning band via `layout.bandOfElement(id)`, then
  `layout.bandRect(bandId)`) and scale it by the view scale to perform the FR-004
  clamp — reusing the layout as the single source of band geometry rather than
  recomputing band offsets.
- **FR-006**: The FR-004 clamp MUST preserve each handle's full hit area (it MUST
  shift the box inward, NOT clip it). A handle whose box already lies within the
  band MUST be left unchanged (handles away from a band edge stay centered on the
  element edge). In the degenerate case of a band shorter than two handle boxes
  (e.g. a near-minimum-height band fully occupied by an element), opposite-edge
  handles MAY clamp to overlapping positions; this is an accepted inherent space
  constraint — the handles stay inside the band and remain individually hit-
  testable.
- **FR-007**: This slice MUST NOT modify `clampToBand`, the controller's
  move / resize / band-resize state machine, the commit commands, the domain
  model, serialization, or `validate()`. It is confined to the live selection
  overlay and its wiring in the canvas.

### Key Entities

- **`DesignerSelectionOverlay`** *(existing widget, designer canvas)* — now
  consumes `displayLayout`; its `rectFor` derives outline/handle geometry from the
  live clamped layout, and `_handle` clamps each handle box to the band rect.
- **`displayLayout`** *(existing, `design_canvas.dart`)* — the `DesignTimeLayout`
  built from `controller.displayDefinition`; already feeds the element picture,
  hit regions, grid, and badges, and now also the selection overlay.
- **Band screen rect** *(existing, reused)* — `layout.bandRect(bandId)` scaled by
  the view scale; the clamp target for handle boxes.
- **Selection chrome** *(transient designer state)* — outline + eight resize
  handles; not part of the model or undo/redo history.

## Success Criteria *(mandatory)*

- **SC-001**: While an element is dragged past a band edge, the selection-overlay
  rectangle equals the painted (clamped) element rectangle and lies entirely
  within the band content box — verified for both the in-edge axis and the free
  axis. (Today the overlay rect would exceed the band.)
- **SC-002**: During the same clamped move, every one of the element's eight
  handle boxes lies within the band screen rect.
- **SC-003**: With an element placed flush against each of the four band-content
  edges in turn, no handle box exceeds the band screen rect; a handle not adjacent
  to any band edge remains centered on the element's edge.
- **SC-004**: Dragging a resize handle past a band edge keeps the handles on the
  clamped preview and within the band rect (the existing resize clamp is not
  regressed).
- **SC-005**: The full `jet_print` suite is green, `flutter analyze` is clean, and
  existing goldens are **byte-identical** (overlay/transient-state-only change; no
  engine output or `schemaVersion` change).
