# Feature Specification: Designer Edit Surface — Direct-Manipulation Element Editing

**Feature Branch**: `003-designer-edit-surface`
**Created**: 2026-06-08
**Status**: Draft
**Input**: User description: "Begin WYSIWYG designer (Tier 3). This part is crucial. Make it industry grade! Do your best!"

## Overview

This feature brings the report designer's central **design surface** to life. Spec 002 delivered the designer shell (toolbox, surface, tabbed Data Source / Outline / Properties panels, top bar) as a non-interactive layout. This feature makes the surface an **interactive WYSIWYG canvas**: report authors place report elements onto the page's bands, then select, move, resize, align, and arrange them by direct manipulation — with snapping and alignment guides, multi-selection, keyboard control, clipboard, draw-order control, and unlimited in-session undo/redo. Every edit mutates an in-memory report model that round-trips **losslessly** through the existing report file format.

The scope is the **element-layout editing core** — the foundation every later designer feature attaches to. Deep per-element property editors, data-field binding, band/section structure editing, and a data-bound rendered preview are explicitly deferred to subsequent designer specs (see *Out of Scope*).

## Out of Scope *(deferred to later designer specs)*

- **Full property-editor suite** — typed editors for every element style/attribute (fonts, colors, borders, image fit, barcode symbology, etc.). This spec covers selection-driven property *reflection* and a basic editable subset (see FR-019 / Q1).
- **Data-source field binding UI** — mapping data fields/expressions onto elements (its own spec; the Data Source panel stays as established in 002).
- **Band & section structure editing** — adding/removing/reordering/resizing bands and groups, and page setup. This spec edits *elements within* the report's existing band structure; the structure itself is displayed as context but not edited here.
- **Expression editor UI.**
- **Data-bound rendered preview / export** — a true paginated, data-filled render of the report is produced by the engine export slice (engine spec 009) and surfaced in a later "Preview" spec. This surface shows **design-time fidelity** (element appearance and placement), not a live data run.
- **Designer chrome theming, templates gallery, collaboration/versioning.**

## Clarifications

### Session 2026-06-08

- Q: Editable-property scope in the Properties panel for this spec → A: Geometry (numeric x / y / width / height) + inline text editing for text elements (double-click to type); the full per-type property suite stays deferred.
- Q: Is saving/opening the design in scope for this spec → A: Yes — basic **open + save** via the existing report file format; new-blank, recent-files, and templates stay deferred.
- Q: Design scale & responsiveness target the surface must meet → A: Up to ~200 elements per design at ~60 fps (≈16 ms/frame) interaction; a 20+ element selection drags without perceptible lag.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Place and position elements on the page (Priority: P1)

A report author drags an element type (text, shape, image, barcode) from the toolbox onto a band on the page, dropping it where they want it. They click an element to select it (selection handles appear) and drag it to reposition it within the page. They have built a basic report layout entirely by direct manipulation.

**Why this priority**: This is the core WYSIWYG act — creating and positioning elements — and is the MVP: with only this, an author can compose a report layout. Everything else refines it.

**Independent Test**: In the playground app designer, drag each toolbox element type onto a band, confirm a corresponding element appears at the drop point; click to select (handles show); drag to move; confirm the element's model position updates and survives a save/reload round-trip.

**Acceptance Scenarios**:

1. **Given** the designer with a report open, **When** the author drags a "Text" entry from the toolbox onto the detail band, **Then** a new text element is created at the drop location inside that band and becomes the selected element.
2. **Given** an element exists, **When** the author clicks it, **Then** it becomes selected and shows selection affordances (outline + handles), and any previously selected element is deselected.
3. **Given** a selected element, **When** the author drags it to a new position, **Then** the element follows the pointer and, on release, its model position updates; the canvas reflects it immediately.
4. **Given** a selected element, **When** the author drags it beyond the page/band bounds, **Then** its position is constrained so it remains within the allowed area (no off-page placement).
5. **Given** the author clicks an empty area of the canvas, **Then** the current selection is cleared.

---

### User Story 2 - Size and align elements precisely (Priority: P2)

The author resizes a selected element by dragging its handles, and the canvas snaps edges/centers to a grid, to sibling elements, and to band/page boundaries — with on-screen alignment guides — so elements line up cleanly without pixel-hunting.

**Why this priority**: Precise sizing and alignment separate a usable layout tool from a toy; snapping and guides are table-stakes for professional output. Builds directly on US1.

**Independent Test**: Resize an element via each handle; confirm min-size enforcement and live feedback; drag an element near another's edge/center and near a band boundary; confirm it snaps and a guide line appears; confirm holding the snap-bypass modifier disables snapping for that gesture.

**Acceptance Scenarios**:

1. **Given** a selected element, **When** the author drags a corner/edge handle, **Then** the element resizes with live feedback, never below a minimum size, and on release the model width/height update.
2. **Given** two elements, **When** the author moves/resizes one so an edge or center aligns with the other (within a snap threshold), **Then** the moving element snaps to alignment and a guide line is shown.
3. **Given** snapping is active, **When** the author holds the snap-bypass modifier, **Then** snapping is suspended for that gesture (free placement).
4. **Given** the grid is enabled, **When** the author moves/resizes an element, **Then** positions/sizes snap to the grid increment.

---

### User Story 3 - Undo and redo every change (Priority: P2)

Every edit — create, move, resize, delete, paste, reorder, basic property change — can be undone and redone in order, without a fixed limit within the session, so the author can experiment fearlessly.

**Why this priority**: Undo/redo is non-negotiable for a professional editor; a single misstep must be reversible. It is cross-cutting over every other edit, so it ranks just below the ability to make edits at all.

**Independent Test**: Perform a sequence of edits (create, move, resize, delete); undo each in reverse order confirming the canvas + model revert exactly; redo confirming they re-apply; confirm a new edit after undo discards the redo stack.

**Acceptance Scenarios**:

1. **Given** a sequence of edits, **When** the author triggers undo, **Then** the most recent edit is reversed (canvas + model) and repeated undo walks back through history.
2. **Given** one or more undos, **When** the author triggers redo, **Then** the next edit is re-applied in order.
3. **Given** an undo has occurred, **When** the author makes a new edit, **Then** the redo stack is discarded.
4. **Given** the history is at an end, **When** the author triggers undo/redo past it, **Then** nothing changes and the controls indicate unavailability.

---

### User Story 4 - Edit many elements at once (Priority: P3)

The author selects multiple elements (rubber-band marquee, shift-click to add/remove, select-all), then moves, nudges (arrow keys), deletes, duplicates, copies/cuts/pastes, reorders (bring forward/send back), and aligns/distributes them as a group.

**Why this priority**: Bulk operations make real layouts efficient but are refinements over single-element editing (US1–US2).

**Independent Test**: Marquee-select several elements; nudge with arrows / modifier-arrows; delete; copy/paste; duplicate; bring-forward/send-back; align-left / distribute; confirm each operates on the whole selection and is undoable.

**Acceptance Scenarios**:

1. **Given** several elements, **When** the author drags a marquee around them, **Then** all enclosed elements become selected as a group.
2. **Given** a multi-selection, **When** the author presses an arrow key, **Then** every selected element moves by the nudge step (a larger step with the modifier).
3. **Given** a selection, **When** the author copies/cuts then pastes, **Then** equivalent element(s) are created (offset from the originals) and become the new selection.
4. **Given** a selection, **When** the author chooses an alignment (e.g., align-left) or a distribute action, **Then** the selected elements align/distribute accordingly.
5. **Given** overlapping elements, **When** the author brings one forward / sends it back, **Then** its draw order within the band changes correspondingly.
6. **Given** a selection, **When** the author presses Delete, **Then** the selected elements are removed (and can be restored by undo).

---

### User Story 5 - See and adjust the selection across panels (Priority: P3)

Selecting an element on the canvas highlights it in the **Outline** tree and shows its details in the **Properties** panel; selecting in the Outline selects it on the canvas; the author can read and adjust the selected element's geometry and (for text elements) its text (see FR-019) from the Properties panel.

**Why this priority**: Cross-panel selection sync makes the designer cohere as one tool and is the bridge to the full property-editing spec. Builds on US1.

**Independent Test**: Select on canvas → confirm Outline highlight + Properties content; select in Outline → confirm canvas selection + handles + scroll-into-view; adjust a basic attribute in Properties → confirm the canvas updates and the change is undoable.

**Acceptance Scenarios**:

1. **Given** an element is selected on the canvas, **When** the selection changes, **Then** the Outline highlights the same element and the Properties panel shows that element's details.
2. **Given** the Outline is visible, **When** the author selects an element row, **Then** that element becomes selected on the canvas with handles shown and scrolled into view if needed.
3. **Given** a selected element, **When** the author edits a basic attribute in the Properties panel, **Then** the canvas reflects the change and the edit is undoable.

---

### User Story 6 - Navigate and view large designs (Priority: P4)

The author zooms the canvas in/out, fits the page to the viewport, and pans, so they can work on detail or see the whole page on any screen.

**Why this priority**: Navigation aids comfort and scales to dense layouts but isn't required to produce a layout.

**Independent Test**: Zoom in/out via controls and shortcuts; fit-to-page/width; pan; confirm element placement/selection stay accurate at all zoom levels (a drop lands where the pointer is in page coordinates).

**Acceptance Scenarios**:

1. **Given** any zoom level, **When** the author places or moves an element, **Then** it lands at the pointer's position in page coordinates (zoom-correct hit-testing).
2. **Given** the page is larger than the viewport, **When** the author pans, **Then** the visible region scrolls without moving elements relative to the page.
3. **Given** the author triggers fit-to-page/width, **Then** the whole page (or width) becomes visible and centered.

---

### Edge Cases

- **Empty report (no elements)**: the canvas shows the page + band structure and accepts the first placement.
- **Drop onto no band / outside the page**: the drop is rejected or routed to the nearest valid band — never creating an orphan element outside the structure.
- **Overlapping elements**: selection picks the top-most under the pointer; cycling to elements beneath (alt-click / repeated click) is the assumed behavior.
- **Zero/negative-size drag**: resize clamps to the minimum size; a click-without-drag create uses a sensible default size.
- **Tiny element / handles smaller than the grab target**: handle hit areas stay grabbable (hit area ≥ visual).
- **Element off-screen when selected via Outline**: the canvas scrolls it into view.
- **Undo and selection**: undo restores both the model and a coherent selection state.
- **Rapid edits / dragging many elements**: the canvas stays responsive (see SC-007).
- **Keyboard focus**: when the canvas has focus, shortcuts (nudge, delete, undo/redo, copy/paste, select-all) act on the selection; when a text field or panel input has focus, they MUST NOT hijack typing.
- **Localization & text length**: all new affordances (menus, tooltips, accessible labels) are localized (en/de/tr) continuing 002; longer translated labels MUST NOT break the chrome.

## Requirements *(mandatory)*

### Functional Requirements

**Creation & model**
- **FR-001**: The surface MUST let the author create a report element by placing a toolbox element type onto a band (via drag-and-drop and/or click-to-place), producing a real element in the report model at the drop position within that band.
- **FR-002**: The toolbox MUST offer, at minimum, the element types supported by the report model (text, shape, image, barcode); placing one MUST create an element of that type with a sensible default size and default attributes.
- **FR-003**: Every edit MUST mutate an in-memory report model whose contents round-trip **losslessly** through the report file format — an edited design saved and reloaded MUST be equivalent to the model at save time, with no attribute loss or reordering.
- **FR-004**: New elements MUST be assigned an identity unique within the report so they can be referenced, selected, and serialized unambiguously.

**Selection**
- **FR-005**: The author MUST be able to select a single element by clicking it; the selected element MUST show selection affordances (outline + resize handles).
- **FR-006**: The author MUST be able to select multiple elements via a rubber-band marquee and via additive/subtractive shift-click, and to select-all and clear-selection (click empty / Escape).
- **FR-007**: When multiple elements are selected, manipulation (move, nudge, delete, align, reorder, clipboard) MUST act on the whole selection.

**Move / resize / constrain**
- **FR-008**: The author MUST be able to move selected element(s) by dragging, with live feedback, committing new model positions on release.
- **FR-009**: The author MUST be able to resize a selected element via handles, with live feedback and a minimum-size floor, committing new model size on release.
- **FR-010**: Element position/size MUST be constrained to remain within the page and the owning band; the surface MUST NOT create or leave an element outside a valid area.

**Snapping & alignment**
- **FR-011**: During move/resize the surface MUST provide snapping to a grid, to sibling element edges/centers, and to band/page boundaries, with on-screen alignment guides, plus a modifier to bypass snapping for a gesture.
- **FR-012**: The author MUST be able to align (left/center/right/top/middle/bottom) and distribute a multi-selection.

**Order, deletion, clipboard, keyboard**
- **FR-013**: The author MUST be able to change an element's draw order within its band (bring forward / send backward / to front / to back).
- **FR-014**: The author MUST be able to delete selected element(s).
- **FR-015**: The author MUST be able to cut, copy, paste, and duplicate selected element(s); pasted/duplicated elements MUST be offset from the originals and become the new selection.
- **FR-016**: The author MUST be able to nudge selected element(s) by keyboard (arrow keys = small step, modifier+arrow = larger step) and to invoke delete / undo / redo / copy / paste / select-all / duplicate via standard keyboard shortcuts — but ONLY when the canvas (not a text input) has focus.

**Undo / redo**
- **FR-017**: Every state-changing edit (create, move, resize, delete, reorder, clipboard, basic property change) MUST be undoable and redoable, in order, without a fixed limit within a session; a new edit after undo MUST discard the redo stack; undo/redo MUST restore both the model and a coherent selection.

**Cross-panel sync**
- **FR-018**: Selecting element(s) on the canvas MUST highlight the same element(s) in the Outline and show the selection's details in the Properties panel; selecting in the Outline MUST select on the canvas (with handles, scrolled into view).
- **FR-019**: The Properties panel MUST allow editing the selected element's **geometry** (numeric x / y / width / height); additionally, **text elements** MUST support **inline text editing** on the canvas (double-click to enter an edit mode and type). All such edits MUST reflect on the canvas immediately and be undoable. The full per-type property suite (fonts, colors, borders, image fit, barcode symbology, etc.) is deferred — see *Out of Scope*.

**View / navigation**
- **FR-020**: The surface MUST support zooming (in/out, fit-to-page/width) and panning, and MUST keep hit-testing and placement pointer-accurate (pointer → page coordinate) at every zoom level.

**Structure display (read-only here)**
- **FR-021**: The surface MUST display the report's band structure (the bands and the page) as the placement context for elements; editing the band structure itself is deferred (see *Out of Scope*).

**Persistence**
- **FR-022**: The designer MUST let the author **open** an existing design and **save** the current design via the report file format (the existing serialization). A saved-then-reopened design MUST equal the model at save time (the lossless round-trip of FR-003 / SC-002). Creating a new blank design, recent-files lists, and a templates gallery are deferred — see *Out of Scope*.

**Feedback, accessibility, localization**
- **FR-023**: The surface MUST give continuous visual feedback during manipulation (drag outline/ghost, handles, snap guides, hover and selection states) and a clear indication of which band/area a drop will target.
- **FR-024**: All new interactive affordances MUST be keyboard-operable and expose accessible names/roles (handles, canvas elements, menu actions), and all new user-visible text MUST be localized (en/de/tr) with English fallback, continuing the 002 localization seam.
- **FR-025**: Edits MUST be non-destructive to parts of the model not being edited — editing one element MUST NOT alter other elements, the band structure, or unrelated report settings.

### Key Entities

- **Report Model (design being edited)** — the in-memory report definition (bands and their elements, page setup) the surface mutates; the single source of truth, serializable to/from the report file format.
- **Element** — a placed report item (text/shape/image/barcode) with identity, owning band, position, size, draw order, and type-specific attributes.
- **Band / Page** — the structural containers shown as placement context (read-only this spec); every element belongs to a band.
- **Selection** — the set of currently selected elements; drives handles, panel sync, and the target of manipulation.
- **Edit / Command (history entry)** — a reversible change to the model; the ordered history backs undo/redo.
- **Snap / Alignment Guides** — transient visual aids computed during manipulation from grid + sibling/band/page geometry.
- **Clipboard** — the transient store of cut/copied elements available for paste.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An author can place and arrange a layout of at least 10 elements across multiple bands using only the toolbox and direct manipulation — no code or file editing — in under 5 minutes.
- **SC-002**: A design edited in the surface, saved, and reloaded equals the in-memory model at save time (100% lossless round-trip) — zero attribute loss or reordering.
- **SC-003**: Any sequence of up to 50 consecutive edits can be fully undone to the original state and fully redone to the final state, with the canvas and model matching at every step (100% of steps).
- **SC-004**: When moving/resizing near a grid line, a sibling edge/center, or a band/page boundary, elements snap within a consistent threshold and a guide appears in ≥95% of alignment attempts; snapping can be bypassed on demand.
- **SC-005**: Selecting an element on the canvas reflects in the Outline and Properties within a single interaction (no manual refresh) in 100% of selections, and selecting in the Outline selects on the canvas in 100% of attempts.
- **SC-006**: A dropped or clicked element lands within a small tolerance of the pointer's page position at every supported zoom level in 100% of attempts.
- **SC-007**: On a design of up to ~200 elements, the surface sustains smooth interaction (~60 frames per second, ≈16 ms per frame) while dragging or resizing a selection of 20 or more elements on the target desktop, with no dropped-frame stutter perceptible to the author.
- **SC-008**: Every new affordance is operable by keyboard alone and carries an accessible name; all new visible text renders correctly in en/de/tr with English fallback (zero blank or raw-key labels).
- **SC-009**: First-time authors complete a guided "place a text element, move it, resize it, undo, redo" task on the first attempt in ≥90% of trials without assistance.

## Assumptions

- **Continues 002**: the designer shell (toolbox, surface, Outline / Data Source / Properties panels, top bar), the shadcn_ui component library, the desktop-first target (macOS playground app), and en/de/tr localization are in place and reused.
- **Existing band structure**: a report being designed has a band structure (a new/blank report provides a default one); creating/editing bands is a separate later spec — this spec edits elements *within* bands.
- **Design-time fidelity, not a data run**: the canvas shows element appearance + placement, not a data-bound, paginated render; a true rendered/exported preview depends on the engine export slice (engine spec 009) and is a later designer spec.
- **"Industry grade" reference behaviors**: modeled on established desktop report/diagram designers — select/move/resize handles, marquee, snapping + guides, multi-select, keyboard nudge, clipboard, z-order, align/distribute, unlimited session undo/redo, zoom/pan.
- **Units & tunables**: coordinates/units follow the report model's existing geometry; the grid increment, snap threshold, nudge steps, default element size, and zoom range are reasonable desktop defaults chosen at planning time (the spec fixes behavior, not exact pixel values).
- **Input**: mouse + keyboard (desktop); touch/stylus is not a target this iteration.
- **Single document, single user, in-session**: collaboration, versioning, and auto-save are out of scope.
- **Overlap pick**: the top-most element under the pointer selects; cycling to underlying elements (alt-click / repeated click) is the assumed default.
