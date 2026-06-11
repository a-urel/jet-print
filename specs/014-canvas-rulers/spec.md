# Feature Specification: Vertical & Horizontal Canvas Rulers

**Feature Branch**: `014-canvas-rulers`
**Created**: 2026-06-11
**Status**: Draft
**Input**: User description: "add vertical and horizontal rulers"

## Overview

The design canvas already lets a user place, move, resize, and align elements on a paginated
report — with a grid, snapping, and zoom/pan — but it gives no continuous sense of *where* on
the page things sit or *how big* they are in real-world measurements. Designers working toward a
printed sheet think in millimetres ("the logo sits 20 mm from the top, the address block is
50 mm wide"), and today the canvas offers no such reference.

This feature adds the two measurement **rulers** that every desktop report/page designer is
expected to have: a **horizontal ruler** along the top edge of the canvas and a **vertical
ruler** down the left edge, both calibrated in **millimetres**, both staying perfectly aligned
with the page as the user zooms and pans. The rulers also give live feedback: a marker follows
the cursor, and the currently selected element's extent is highlighted on each ruler so its
position and size are readable at a glance.

The top bar already shows a **rulers view-toggle** (the ruler icon next to grid and snap), but
it is presently inert — flipping it changes nothing on screen. This feature makes that toggle
real: turning it on shows the rulers, turning it off hides them, and the canvas reclaims the
space.

**Scope boundary (this slice)**: the two rulers, their millimetre tick/label scale, cursor
tracking, selected-element extent highlighting, the working toggle, and millimetre readouts that
stay correct at every zoom level. **Draggable alignment guides** (pulling a guide line out of a
ruler onto the canvas, elements snapping to it) are explicitly **out of scope** for this version
and must remain addable later without rework. No change to the report model, serialization, or
the printed/exported output — rulers are a design-time aid only.

## Clarifications

### Session 2026-06-11

- Q: What measurement unit should the rulers display? → A: Millimetres (display-only projection over the point-based model; user-selectable unit deferred)
- Q: How interactive should the rulers be this version? → A: Display + cursor tracking + selected-element extent highlight; draggable alignment guides out of scope
- Q: Where should the rulers' zero point sit? → A: The physical page top-left corner (0,0); the margin area is part of the scale
- Q: When something is selected, what should the rulers highlight? → A: The union bounding box (min→max extent) of the current selection — one element, multiple elements, or a band
- Q: Should rulers be visible by default when the designer first opens? → A: Yes, on by default (consistent with the existing toggle's current default)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read element position and size in millimetres (Priority: P1)

A designer is laying out an invoice. With the rulers shown, the horizontal ruler runs across the
top of the page calibrated in millimetres from the page's left edge, and the vertical ruler runs
down the left calibrated from the page's top edge. As the designer reads the page, the tick
marks and number labels give an immediate sense of scale — where the 50 mm mark is, how wide the
content area is — without measuring anything by hand.

**Why this priority**: A ruler that shows nothing useful is not a ruler. The core value — and
the reason the affordance exists in the top bar at all — is giving the designer a trustworthy,
real-world measurement reference for the page. Everything else (tracking, highlighting) enriches
this but depends on the scale being present and correct first. This story alone turns the canvas
from "boxes floating in space" into "a measured sheet of paper".

**Independent Test**: Open the designer with the default invoice template and rulers enabled.
Verify a horizontal ruler appears along the top and a vertical ruler along the left, both
labelled in millimetres, with the zero point at the page's top-left origin and labels increasing
toward the page's right/bottom. Confirm the spacing between labelled marks corresponds to a
correct, evenly spaced millimetre interval.

**Acceptance Scenarios**:

1. **Given** the designer is open with rulers enabled, **When** the canvas displays a page,
   **Then** a horizontal ruler spans the top of the canvas and a vertical ruler spans the left,
   each showing numbered millimetre marks.
2. **Given** the rulers are shown, **When** the user reads the mark aligned with the page's
   physical top-left corner (0,0, outside the margins), **Then** it reads zero, and marks
   increase toward the right (on the horizontal ruler) and downward (on the vertical ruler); the
   margin area falls within the scale rather than before it.
3. **Given** an element positioned a known distance from the page origin, **When** the user
   compares the element's edge to the ruler, **Then** the ruler mark at that edge matches the
   element's real-world millimetre offset.
4. **Given** a page wider/taller than the visible canvas area, **When** the rulers are shown,
   **Then** the rulers cover the full visible extent of the page and remain readable (labels do
   not overlap or disappear).

---

### User Story 2 - Show and hide rulers from the top bar (Priority: P1)

A designer wants more canvas room and turns the rulers off using the existing ruler toggle in
the top bar; the rulers disappear and the canvas grows to fill the space. Turning the toggle
back on restores them. The toggle's highlighted/active state always reflects whether the rulers
are currently visible, consistent with the neighbouring grid and snap toggles.

**Why this priority**: The toggle is already present and users will expect it to work; an inert
control is a visible defect. Making show/hide functional is small but essential — it is how the
user controls the feature at all, and it brings the ruler toggle into parity with the grid and
snap toggles that already drive real canvas state. Tied with US1 as the minimum viable feature:
the rulers must both *appear correctly* and *be controllable*.

**Independent Test**: With the designer open, toggle the rulers control off and confirm both
rulers disappear and the canvas reclaims the vacated space; toggle it on and confirm both rulers
reappear in place. Confirm the toggle's active styling matches the current visibility at each
step.

**Acceptance Scenarios**:

1. **Given** rulers are visible, **When** the user activates the ruler toggle, **Then** both
   rulers are hidden and the canvas expands into the freed space.
2. **Given** rulers are hidden, **When** the user activates the ruler toggle, **Then** both
   rulers reappear aligned with the page.
3. **Given** any ruler visibility state, **When** the user observes the toggle, **Then** its
   active/highlighted styling matches whether rulers are currently shown, the same way the grid
   and snap toggles reflect their state.

---

### User Story 3 - Rulers stay aligned through zoom and pan (Priority: P2)

A designer zooms in to fine-tune a small element and pans across the page. Throughout, the
rulers stay locked to the page: the millimetre marks line up with the actual page positions, the
labels re-space sensibly as the zoom changes (showing finer marks when zoomed in, coarser marks
when zoomed out) so the ruler never becomes an unreadable smear or a barren line, and the zero
origin tracks the page as it pans.

**Why this priority**: Alignment under zoom/pan is what makes the ruler *trustworthy* rather
than decorative — a ruler that drifts from the page when zoomed is worse than none. It is P2
only because US1/US2 deliver a usable ruler at the default view first; this story guarantees it
stays correct everywhere.

**Independent Test**: Enable rulers, then zoom from minimum to maximum and pan in each direction.
At several zoom levels, verify a known element edge still lines up with the correct millimetre
mark, and that label density stays readable (marks neither overlap nor vanish) across the range.

**Acceptance Scenarios**:

1. **Given** rulers are shown at default zoom, **When** the user zooms in, **Then** the marks
   spread apart, finer subdivisions appear as space allows, and every mark still aligns with its
   true page position.
2. **Given** rulers are shown, **When** the user zooms out, **Then** the marks draw closer, the
   labelled interval coarsens to avoid overlapping numbers, and alignment is preserved.
3. **Given** rulers are shown, **When** the user pans the canvas, **Then** both rulers scroll
   with the page so each mark stays aligned with the page position it measures.
4. **Given** any zoom level within the supported range, **When** the user reads an element's
   edge against the ruler, **Then** the millimetre value is correct (no drift between canvas and
   ruler).

---

### User Story 4 - Track the cursor and the selected element on the rulers (Priority: P3)

As the designer moves the pointer over the canvas, a thin marker slides along each ruler showing
the pointer's current horizontal and vertical position. When an element is selected, the span it
occupies is highlighted on both rulers — a band on the horizontal ruler from the element's left
to right edge, and on the vertical ruler from its top to bottom edge — so its placement and size
are readable directly off the rulers.

**Why this priority**: This is the "live feedback" polish that makes rulers feel responsive and
genuinely useful for precise placement, but the rulers are already valuable without it (US1–US3).
It is the natural enhancement once the measured scale exists.

**Independent Test**: Enable rulers, move the cursor across the canvas, and confirm a position
marker tracks along both rulers in step with the pointer. Then select an element and confirm its
horizontal extent is highlighted on the top ruler and its vertical extent on the left ruler,
matching the element's edges; deselect and confirm the highlight clears.

**Acceptance Scenarios**:

1. **Given** rulers are shown, **When** the pointer moves over the canvas, **Then** a marker on
   the horizontal ruler tracks the pointer's horizontal position and a marker on the vertical
   ruler tracks its vertical position.
2. **Given** an element is selected, **When** the user looks at the rulers, **Then** the
   horizontal ruler highlights the band between the element's left and right edges and the
   vertical ruler highlights the band between its top and bottom edges.
3. **Given** several elements (or a band) are selected, **When** the user looks at the rulers,
   **Then** each ruler highlights the single union span from the leftmost/topmost edge to the
   rightmost/bottommost edge of the whole selection (one combined band, not one per element).
4. **Given** a selection highlight is shown, **When** an element is moved or resized, **Then**
   the highlighted union span updates to match the selection's new outer edges.
5. **Given** a selection is highlighted, **When** the user clears the selection, **Then** the
   extent highlight is removed from both rulers.
6. **Given** the pointer leaves the canvas, **When** there is no longer a hover position,
   **Then** the cursor marker is cleared from both rulers.

### Edge Cases

- **Corner where rulers meet**: the small square where the horizontal and vertical rulers
  intersect (top-left) shows no measurement and does not display misleading numbers.
- **Element straddling the page origin or extending past page edges**: the selection highlight
  is clamped to the visible ruler so it never renders outside the ruler or implies negative
  positions where none are meaningful.
- **Extreme zoom-out**: when even the coarsest labelled interval would crowd, labels thin out
  gracefully rather than overlapping into an unreadable blur.
- **Extreme zoom-in**: subdivisions stop refining at a sensible smallest interval rather than
  drawing an infinite ladder of ticks.
- **Very small page or very large page**: the millimetre scale remains correct; labels remain
  legible and correctly spaced regardless of sheet size.
- **Rulers hidden**: cursor tracking and selection highlighting do no visible work and impose no
  behaviour while the rulers are off.
- **Localization**: number labels follow the active locale's digit/number conventions where
  applicable, consistent with the rest of the designer (en/de/tr), and the toggle tooltip is
  localized (already present as "Show rulers").

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The designer MUST display a horizontal ruler along the top edge of the design
  canvas and a vertical ruler along the left edge when rulers are enabled.
- **FR-002**: Both rulers MUST be calibrated in **millimetres**, with numbered labels at evenly
  spaced intervals and finer unlabelled subdivision ticks between labels.
- **FR-003**: The rulers' zero origin MUST correspond to the page's physical top-left corner
  (0,0, outside the margins), with values increasing rightward (horizontal) and downward
  (vertical); the page margin area falls within the measured scale.
- **FR-004**: Ruler measurements MUST accurately reflect real-world distance on the page — an
  element's edge at a given page position MUST line up with the matching millimetre mark.
- **FR-005**: The system MUST convert the page's internal coordinate units to millimetres for
  display purposes only, without altering how geometry is stored or how output is rendered.
- **FR-006**: The existing rulers view-toggle in the top bar MUST show the rulers when active and
  hide them when inactive, and its active/highlighted styling MUST reflect the current
  visibility — consistent with the grid and snap toggles.
- **FR-007**: When rulers are hidden, the canvas MUST reclaim the space they occupied; when shown,
  the rulers MUST occupy a stable, consistent strip without overlapping the canvas content.
- **FR-008**: The rulers MUST stay aligned with the page across the full supported zoom range, so
  every mark corresponds to its true page position at any zoom level.
- **FR-009**: The rulers MUST stay aligned with the page as it is panned, scrolling together with
  the page content.
- **FR-010**: The labelled interval and subdivision density MUST adapt to the zoom level so labels
  remain readable (no overlapping numbers when zoomed out, finer marks when zoomed in) within
  sensible minimum/maximum interval bounds.
- **FR-011**: While the pointer is over the canvas, a position marker MUST track the pointer along
  each ruler, indicating its current horizontal and vertical page position; the marker MUST clear
  when there is no hover position.
- **FR-012**: When a selection exists, each ruler MUST highlight the **union bounding span** of
  the entire selection — the leftmost-to-rightmost edges on the horizontal ruler and the
  topmost-to-bottommost edges on the vertical ruler — as a single combined band covering one
  element, multiple elements, or a selected band. The highlight MUST update as the selection is
  moved or resized and clear when the selection is cleared.
- **FR-013**: The corner where the two rulers meet MUST present no measurement and no misleading
  value.
- **FR-014**: Rulers MUST be a design-time visual aid only and MUST NOT alter the report model,
  its serialization, or the printed/exported output.
- **FR-015**: Ruler labels and the toggle tooltip MUST respect the designer's active locale
  (en/de/tr) consistent with the rest of the designer UI.
- **FR-016**: The design MUST leave room to add draggable alignment guides later without reworking
  the ruler presentation or its measurement model (guides are out of scope for this version).
- **FR-017**: Rulers MUST be visible by default when the designer first opens, with the toggle
  reflecting that active state.

### Key Entities

- **Ruler scale**: the mapping from page position to displayed millimetre value and tick layout —
  which marks are labelled, which are subdivisions, and how that adapts to the current zoom. Has
  no persisted state; derived from the page geometry and the live view (zoom/pan).
- **Rulers visibility**: a single on/off design-time setting controlling whether both rulers are
  shown, surfaced through the top-bar toggle and sitting alongside the existing grid and snap
  view settings.
- **Cursor position indicator**: the transient horizontal/vertical pointer position reflected as a
  marker on each ruler; exists only while the pointer is over the canvas.
- **Selection extent**: the highlighted horizontal and vertical spans on the rulers derived from
  the **union bounding box** of the current selection (one element, multiple elements, or a
  band); exists only while a selection is present.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With rulers enabled, a designer can read any element's distance from the page origin
  in millimetres directly off the rulers without using a separate measuring step or doing manual
  conversion.
- **SC-002**: A measurement read from a ruler matches the element's true page position within one
  labelled subdivision at every zoom level across the full supported zoom range.
- **SC-003**: Toggling rulers off and on returns the canvas to a visually identical state, and the
  toggle's active indication correctly reflects ruler visibility 100% of the time.
- **SC-004**: Across the full zoom range, ruler number labels never overlap and never disappear
  entirely — at least one labelled interval is always legible.
- **SC-005**: When the pointer moves over the canvas, the ruler position markers visibly track it,
  and when an element is selected its extent is highlighted on both rulers, with the highlight
  matching the element's edges as it is moved or resized.
- **SC-006**: Enabling, using, or disabling rulers produces no change to saved report files or to
  exported/printed output compared with the same actions performed with rulers off.
- **SC-007**: Ruler number labels and the toggle tooltip display correctly in English, German, and
  Turkish.

## Assumptions

- **Display unit is millimetres** (decided): rulers present millimetres regardless that the model
  stores geometry in typographic points; a user-selectable unit (cm/inch/points) is **not** part
  of this version and may be added later.
- **Interactivity is display + tracking** (decided): rulers show the scale, track the cursor, and
  highlight the selected element's extent. **Draggable alignment guides are out of scope** for
  this version (FR-016 keeps the door open).
- **Origin is the page's physical top-left corner (0,0)** (decided): measurements run from the
  paper corner outside the margins, so the margin area is part of the scale and positions read as
  page-absolute (matching the design surface's page-absolute geometry). Per-band or
  margin-relative origins are not introduced by this feature.
- **Rulers visibility is a session/view setting**, like the existing grid and snap toggles — it
  governs the live design view and is not part of the saved report. It is **on by default**
  (decided), matching the toggle's current initial state.
- **Standard precision**: ruler readouts target everyday layout precision (whole/half millimetre
  legibility), not engineering-grade measurement; exact sub-pixel tick placement beyond what is
  visually distinguishable is unnecessary.
- **Existing view infrastructure is reused**: the feature builds on the established zoom/pan view
  transform, the existing top-bar toggle affordance, and the existing localization mechanism
  rather than introducing parallel systems.
- **No new external dependencies** are required to render the rulers or compute the millimetre
  scale.
