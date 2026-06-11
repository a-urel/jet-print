# Feature Specification: Grid & Snap Helper Tools

**Feature Branch**: `015-grid-snap-tools`
**Created**: 2026-06-11
**Status**: Draft
**Input**: User description: "implement helper tools: show/hide grid and snap to grid"

## Clarifications

### Session 2026-06-11

- Q: Should turning the grid off also stop snapping to grid lines, or is grid-line snapping governed solely by the magnet/snap button? → A: Decoupled — the grid button controls visibility only; the magnet governs all snapping (grid + sibling + band) regardless of grid visibility (elements can snap to an invisible grid).
- Q: What spacing should the visible grid use, and should snapping match it? → A: 5 mm for both — the visible grid is drawn at 5 mm and snapping aligns to that same 5 mm grid (replacing the existing ~8pt snap step), so the grid and snap targets coincide and align with the mm rulers.

## User Scenarios & Testing *(mandatory)*

The design canvas already has three helper-tool buttons in the top bar (grid, ruler, magnet/snap).
The ruler tool was completed in the previous feature. This feature completes the remaining two
helper tools so they behave as their icons promise: the **grid** button shows or hides a visible
alignment grid on the canvas, and the **snap** (magnet) button makes elements align to that grid
(and to neighbouring elements / band edges) while the designer drags or resizes them.

> **Current-state note for planners**: snapping geometry already exists and works; the *visible*
> grid does not — today the grid button toggles an internal flag that only influences snapping and
> draws nothing, so "Show grid" shows nothing. The primary user-visible gap this feature closes is
> drawing the grid; the snapping stories below codify the already-expected behaviour so the two
> tools form one coherent, honest feature.

### User Story 1 - Show and hide an alignment grid (Priority: P1)

A report designer wants to align elements by eye against a regular reference grid. They click the
grid button in the top bar and a light, evenly-spaced grid appears across the page area of the
canvas. They click it again and the grid disappears, leaving the page clean.

**Why this priority**: This is the core missing capability and the feature's headline value — the
grid button currently shows nothing, which is a visible defect. A visible grid is independently
useful for manual alignment even with no snapping at all.

**Independent Test**: With snapping turned off, toggle the grid button and confirm a grid becomes
visible over the page and disappears again, with element appearance and positions unchanged.

**Acceptance Scenarios**:

1. **Given** the designer is open with the grid currently hidden, **When** the user activates the grid tool, **Then** a regularly-spaced grid is drawn across the page area and the grid button shows an active state.
2. **Given** the grid is visible, **When** the user deactivates the grid tool, **Then** the grid is removed from the canvas and no grid marks remain over the page or elements.
3. **Given** the grid is visible, **When** the user inspects an element on the canvas, **Then** the grid sits behind the elements as a faint background and never obscures or recolours element content.
4. **Given** the designer opens for the first time in a session, **When** no preference has been changed, **Then** the grid is shown by default and the grid button reflects the active state.

---

### User Story 2 - Snap elements to the grid while editing (Priority: P1)

A report designer drags or resizes an element. With the snap tool active, the element's edges
gently lock onto the nearest grid line (and to aligned neighbouring elements and band boundaries)
as it nears them, so layouts stay tidy without pixel-perfect mouse control.

**Why this priority**: Snapping is the practical reason a grid exists; together with US1 it makes the
two helper tools coherent. It is independently testable from US1 (snapping can be verified without the
grid being visible).

**Independent Test**: With snap active, drag an element so an edge approaches a grid position and
confirm the committed position lands exactly on the grid step; turn snap off and confirm the same
drag lands at the free (un-snapped) position.

**Acceptance Scenarios**:

1. **Given** the snap tool is active, **When** the user drags an element so an edge comes within the snap distance of a grid line, **Then** that edge aligns exactly to the grid line and an alignment guide is shown during the drag.
2. **Given** the snap tool is active, **When** the user resizes an element so a resized edge nears a grid line, **Then** that edge snaps to the grid line on commit.
3. **Given** the snap tool is inactive, **When** the user drags or resizes an element, **Then** no snapping occurs and the element follows the pointer freely.
4. **Given** the snap tool is active and the grid tool is inactive (grid hidden), **When** the user drags an element, **Then** the element still snaps to grid lines — as well as to aligned neighbouring elements and band edges — even though no grid is drawn (snapping is independent of grid visibility).
5. **Given** the user is dragging with snapping active, **When** the user holds the snap-bypass modifier key, **Then** snapping is temporarily suspended for that drag and the element moves freely.

---

### User Story 3 - Grid stays aligned and readable across zoom and pan (Priority: P2)

A designer zooms and pans the canvas. The grid stays locked to the page (a given page position keeps
the same grid line), and the grid never degrades into an unreadable solid fill when zoomed far out or
a sparse scatter when zoomed far in.

**Why this priority**: Without this the grid is misleading or visually noisy at non-default zoom; it
builds on US1 but is a refinement rather than the core capability.

**Independent Test**: Show the grid, then zoom out far and zoom in far, confirming the grid remains
aligned to the page and stays legible (thins out rather than turning into a solid block at low zoom).

**Acceptance Scenarios**:

1. **Given** the grid is visible at default zoom, **When** the user zooms in or out, **Then** the grid lines continue to align to the same page positions and move/scale with the page.
2. **Given** the grid is visible, **When** the user pans/scrolls the canvas, **Then** the grid scrolls together with the page and stays registered to it.
3. **Given** the grid is visible and the user zooms far out, **When** the grid spacing would become too dense to read, **Then** the rendering thins the grid (or hides it) so the page never appears as a solid fill.

---

### User Story 4 - Grid is a design aid only, never in output (Priority: P3)

A designer previews, prints, or exports the report. The grid is a workspace aid and must never appear
in the preview, the printout, the exported file, or the saved template.

**Why this priority**: Protects output fidelity. It is a constraint/guarantee rather than an
interactive capability, so it is lowest priority but must hold.

**Independent Test**: With the grid visible, open the preview and export the report, and confirm
neither contains any grid; reopen a saved template and confirm grid visibility was not stored in it.

**Acceptance Scenarios**:

1. **Given** the grid is visible on the canvas, **When** the user opens the report preview, **Then** no grid appears in the preview.
2. **Given** the grid is visible, **When** the user exports or prints the report, **Then** the output contains no grid.
3. **Given** the grid visibility was changed, **When** the report template is saved and reopened, **Then** the saved file is byte-identical with respect to grid state (grid visibility is not part of the report) and reopening it does not change how the report renders.

### Edge Cases

- **Empty / very small page**: The grid is clipped to the page area; if the page is smaller than one grid step, at least the page outline is respected and no grid marks fall outside the page.
- **Extreme zoom**: At very low zoom the grid thins or hides to avoid a solid fill; at very high zoom it remains aligned and does not vanish entirely within the visible page area.
- **Grid off while snap on**: The grid is hidden, but grid-line snapping (and neighbour/band-edge snapping) still occurs — snapping targets the grid even when it is not drawn (US2 scenario 4).
- **Independent toggles**: The grid and snap tools are fully independent — toggling visibility never changes snap state and toggling snap never changes visibility. Any of the four on/off combinations is valid (e.g. grid shown + snap off = a visible reference grid with free movement).
- **Toggling during an active drag**: Changing a toggle mid-drag does not corrupt the element's position; the change takes effect cleanly for subsequent interactions.
- **Selection / overlays**: The grid never sits on top of selection handles, snap guides, rulers, or element content — it is the backmost design-time layer over the page.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a grid tool in the designer top bar that toggles the visibility of an alignment grid on the canvas, reflecting its active/inactive state in the button appearance.
- **FR-002**: When the grid tool is active, the system MUST draw a grid spaced at 5 mm across the page's content area, registered to the same origin that grid snapping uses (per band), so that drawn grid lines coincide exactly with the positions elements snap to — what the user sees is what elements snap to.
- **FR-003**: The grid MUST be rendered behind all elements and design overlays (selection handles, snap guides, rulers) and MUST NOT alter, obscure, or recolour element content.
- **FR-004**: When the grid tool is inactive, the system MUST draw no grid on the canvas.
- **FR-005**: The grid MUST stay registered to the page across zoom and pan — any grid line that is drawn maps to the same page position at every zoom level and scroll offset (the set of drawn lines may thin per FR-006, but drawn lines never drift).
- **FR-006**: The system MUST keep the grid legible across the zoom range by reducing grid density (thinning or hiding lines) when the spacing would otherwise become too dense to read, so the page never renders as a solid fill.
- **FR-007**: The grid MUST be confined to the page area and MUST NOT draw beyond the page boundary.
- **FR-008**: The system MUST provide a snap tool in the designer top bar that toggles whether elements snap during move and resize, reflecting its active/inactive state in the button appearance.
- **FR-009**: When the snap tool is active, the system MUST align an element's edges to the nearest 5 mm grid line within a snap distance during move and resize, and commit the element at the snapped position.
- **FR-010**: Grid-line snapping MUST be governed solely by the snap tool and MUST be independent of grid visibility — when the snap tool is active, elements snap to grid lines (and to neighbouring elements and band edges) whether or not the grid is currently drawn. Toggling the grid tool MUST NOT change snap behaviour, and toggling the snap tool MUST NOT change grid visibility.
- **FR-011**: When the snap tool is inactive, the system MUST NOT snap during move or resize; elements follow the pointer freely.
- **FR-012**: The system MUST display a transient alignment guide while an edge is snapped during a drag, and remove it when the drag ends.
- **FR-013**: The system MUST let the user temporarily bypass snapping for the duration of a single drag via a modifier key, without changing the snap tool's toggle state.
- **FR-014**: Both the grid tool and the snap tool MUST default to active when the designer is first shown.
- **FR-015**: Grid visibility and snap state are per-session workspace preferences and MUST NOT be persisted into the report template, the codec, or the document schema; saving and reopening a report MUST be unaffected by them.
- **FR-016**: The grid MUST NOT appear in the report preview, print output, or exported files — it is design-time chrome only and must never be routed through the shared render/export pipeline.
- **FR-017**: The grid and snap tool buttons MUST have localized tooltips consistent with the existing top-bar tools.

### Key Entities *(include if data involved)*

- **Grid visibility preference**: A per-session on/off workspace state indicating whether the alignment grid is drawn. Not part of the report; mirrors the existing ruler/snap visibility preferences.
- **Snap preference**: A per-session on/off workspace state indicating whether elements snap during move/resize. Not part of the report.
- **Grid spacing**: A fixed 5 mm distance between grid lines, shared between the visible grid and the snap target so the two coincide and align with the mm rulers. A workspace constant, not authored per report.
- **Snap guide**: A transient visual indicator shown during a drag to communicate which edge/line an element has snapped to; exists only for the duration of the interaction.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the grid tool active, a visible grid appears over 100% of the page area within one interaction (a single button click), and disappears within one click when deactivated.
- **SC-002**: A page position stays on the same grid line across the full supported zoom range (verified at minimum, default, and maximum zoom) — grid alignment error is zero at every zoom and scroll offset.
- **SC-003**: With snap and grid active, 100% of move/resize edges that approach within the snap distance commit exactly on a grid line (no off-by-fraction drift).
- **SC-004**: With the snap tool inactive, 0% of move/resize operations alter the pointer-driven position (no snapping occurs).
- **SC-005**: The grid appears in 0% of previews, printouts, and exports; saved templates are byte-identical regardless of grid/snap state, and reopening renders identically.
- **SC-006**: At the lowest supported zoom the grid never renders as a solid fill — the rendering thins or hides the grid so individual page content remains distinguishable.
- **SC-007**: A first-time user can show the grid and have elements snap to it without changing any settings (both tools default on), completing an aligned placement in under 10 seconds.

## Assumptions

- **Reuse of existing helper-tool conventions**: The grid and snap tools mirror the existing ruler tool — top-bar buttons bound to per-session workspace preferences, default on, never serialized — established in the canvas-rulers feature.
- **Snapping geometry already exists**: Move/resize snapping (grid, sibling, band) is already implemented and working; the snap user stories codify expected behaviour and act as regression coverage. The principal new build is the visible grid (US1/US3) plus making the grid button drive that rendering.
- **5 mm grid, unified with snap** (per Clarifications 2026-06-11): The drawn grid and the snap step are both 5 mm so "what you see is what you snap to." This replaces the existing ~8pt snap step; the snap constant is changed to 5 mm, which updates existing snap geometry/tests accordingly. Choosing mm aligns the grid with the mm rulers from the previous feature.
- **Grid–snap decoupled** (per Clarifications 2026-06-11): The grid tool controls *visibility only*; the snap tool is the master on/off for all snapping (grid + sibling + band). Elements snap to grid lines whenever the snap tool is active, regardless of grid visibility. This changes the current behaviour, where the grid flag also gates grid-line snapping — that gating moves entirely under the snap tool.
- **Design-time chrome model**: The grid is drawn directly as canvas chrome (like band separators and rulers), never through the element render pipeline, so preview/export/saved output are untouched — satisfying the project's WYSIWYG principle.
- **Grid appearance**: A light, low-contrast grid (lines or dots) themed to sit unobtrusively behind content; exact visual treatment is a design detail for the planning phase, constrained only by FR-003 (must not obscure content) and FR-006 (must stay legible).
- **Snap-bypass modifier**: The existing snap-bypass modifier key used by the current drag logic is reused unchanged (FR-013).
- **Localization scope**: Tooltips are localized for the existing supported locales (English, German, Turkish) with English fallback, consistent with the rest of the designer top bar.
