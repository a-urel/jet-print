# Feature Specification: Shape Gallery in Properties Pane

**Feature Branch**: `020-shape-gallery`  
**Created**: 2026-06-12  
**Status**: Draft  
**Input**: User description: "shape properties: add a selectable gallery of shapes to properties pane such as triangle, star, hexagon, etc."

## Clarifications

### Session 2026-06-13

- Q: Which shapes should ship in the v1 gallery? → A: Standard 8 — line, rectangle, ellipse, triangle, diamond, pentagon, hexagon, star.
- Q: When a saved report references a shape form this version doesn't recognize, what should happen on load? → A: Preserve & round-trip — render with a safe default (rectangle) but keep the original form name so re-saving does not lose it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Change a selected shape's form from a visual gallery (Priority: P1)

A report designer has placed a shape on the canvas. Today that shape can only be a line or a
rectangle, and there is no way to see or change which form it is from the Properties pane. The
designer selects the shape and, in the Properties pane, sees a **gallery of shape thumbnails**
(line, rectangle, ellipse, triangle, diamond, pentagon, hexagon, star, …). They click the
**hexagon** thumbnail and the shape on the canvas immediately becomes a hexagon, keeping its
position, size, and fill/stroke appearance. The currently-active shape is visibly highlighted in
the gallery.

**Why this priority**: This is the entire feature. Without it, designers cannot author anything
beyond a line or box, which is the core limitation the request targets. A single, self-contained
slice (gallery → pick → shape updates) delivers the full user value on its own.

**Independent Test**: Select a shape element, open Properties, click a gallery thumbnail other than
the current shape, and confirm the canvas shape changes to the chosen form while position, size,
and styling are preserved. Fully testable with one shape and the gallery alone.

**Acceptance Scenarios**:

1. **Given** a rectangle shape is selected, **When** the designer clicks the "triangle" thumbnail in
   the Properties gallery, **Then** the shape renders as a triangle within the same bounds and its
   fill/stroke are unchanged.
2. **Given** a shape is selected, **When** its Properties pane is shown, **Then** the gallery
   highlights the thumbnail matching the shape's current form.
3. **Given** a non-shape element (text, image, barcode) is selected, **When** its Properties pane is
   shown, **Then** no shape gallery appears.
4. **Given** the designer picks the shape that is already active, **When** they click its thumbnail,
   **Then** nothing changes and no new edit/undo step is recorded.

---

### User Story 2 - Undo and redo a shape change (Priority: P2)

After switching a shape to a star, the designer changes their mind and presses **Undo**. The shape
returns to its previous form (e.g. rectangle) in a single step. Pressing **Redo** restores the star.

**Why this priority**: Shape selection is an editing action; designers expect every such action to be
reversible exactly like every other property edit in the tool. It builds directly on P1 but is not
required to demonstrate the gallery's core value.

**Independent Test**: Pick a new shape from the gallery, press Undo, confirm the shape reverts to its
prior form in one step; press Redo, confirm the new shape returns.

**Acceptance Scenarios**:

1. **Given** the designer changed a rectangle to a star, **When** they Undo once, **Then** the shape
   is a rectangle again.
2. **Given** they then Redo once, **When** the redo completes, **Then** the shape is a star again.

---

### User Story 3 - Chosen shape persists across save, reload, preview, and export (Priority: P3)

The designer saves the report, reopens it later, and the shapes they selected (hexagon, star, etc.)
appear exactly as authored. When they switch to Preview and when they export to PDF/image, every
shape matches what they saw on the design canvas.

**Why this priority**: Persistence and fidelity make the feature trustworthy for real documents, but
the authoring loop in P1/P2 is demonstrable without a save/reload cycle.

**Independent Test**: Set a shape to hexagon, save and reload the report, and confirm it is still a
hexagon; open Preview and export, confirming the hexagon appears identically in both.

**Acceptance Scenarios**:

1. **Given** a shape was set to a hexagon and the report saved, **When** the report is reloaded,
   **Then** the shape is still a hexagon.
2. **Given** a report containing a star and a triangle, **When** the designer views Preview and
   exports the report, **Then** the star and triangle appear identically in the canvas, preview, and
   exported output.
3. **Given** a report authored before this feature (containing only lines/rectangles), **When** it is
   opened, **Then** every existing shape loads unchanged.

---

### Edge Cases

- **Very small or very thin bounds**: A shape selected into a 1×1 or extremely narrow box must still
  render its recognizable form (or degrade gracefully) without errors.
- **Line-specific behavior**: The line form has no enclosed area to fill; switching from a filled
  rectangle to a line must not error, and switching back must restore a fillable form. The
  diagonal-flip option that applies only to lines must remain coherent when the form is not a line.
- **Unknown shape value on load**: A saved report referencing a shape form this version does not
  recognize must load without crashing — rendering as a rectangle while retaining the original form
  name, so saving the report again writes the unknown form back unchanged (FR-009).
- **No selection / multi-selection**: With nothing selected, the gallery is absent. Behavior for a
  multi-selection of several shapes follows the pane's existing multi-selection convention.
- **Keyboard / accessibility**: A designer navigating by keyboard can reach and activate gallery
  items, and each item is labeled with its shape name.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When a single shape element is selected, the Properties pane MUST present a gallery of
  selectable shape forms displayed as visual thumbnails.
- **FR-002**: The v1 gallery MUST offer exactly these eight forms: line, rectangle, ellipse,
  triangle, diamond, pentagon, hexagon, and star. The architecture MUST make adding further forms
  cheap, but no additional forms are in scope for v1.
- **FR-003**: The gallery MUST visually indicate which form the selected shape currently has.
- **FR-004**: Choosing a thumbnail MUST change the selected shape to that form while preserving its
  position, size, and fill/stroke appearance.
- **FR-005**: Choosing the form the shape already has MUST be a no-op that records no edit and no
  undo step.
- **FR-006**: Each shape-form change MUST be a single undoable/redoable step, consistent with other
  property edits.
- **FR-007**: The chosen shape form MUST be saved with the report and restored on reload.
- **FR-008**: The chosen shape form MUST appear identically on the design canvas, in Preview, and in
  exported output (no divergent rendering path).
- **FR-009**: Reports authored before this feature MUST continue to load unchanged. A saved shape
  form that this version does not recognize MUST load without error, rendering with a safe default
  (rectangle) while **preserving the original form name** so that re-saving the report does not
  discard it (lossless round-trip).
- **FR-010**: The gallery MUST NOT appear for non-shape elements (text, image, barcode) or when no
  element is selected.
- **FR-011**: Every shape form in the gallery MUST be drawn within the element's existing bounds box
  (the gallery changes form, not position or size).
- **FR-012**: Gallery items and the section MUST be localized in all locales the designer UI already
  supports (English, German, Turkish) and reachable/operable via keyboard with accessible labels.

### Key Entities *(include if data involved)*

- **Shape Element**: A vector graphic placed on the report, defined by its bounds (position + size),
  its **form** (which the gallery selects), and its appearance (fill color, stroke color, stroke
  width). Currently supports line and rectangle forms; this feature expands the set of forms.
- **Shape Form**: The named geometric kind of a shape (line, rectangle, ellipse, triangle, diamond,
  pentagon, hexagon, star, …). The gallery is the visual selector over the set of available forms;
  the form is the single attribute this feature lets the designer change.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A designer can change a selected shape to any offered form in a single click, with the
  canvas updating immediately (no save or mode switch required).
- **SC-002**: The set of authorable shape forms increases from 2 (line, rectangle) to at least 8.
- **SC-003**: 100% of selected shape forms render identically across the design canvas, Preview, and
  exported output.
- **SC-004**: 100% of shape forms survive a save-and-reload round trip unchanged, and 100% of
  pre-existing reports continue to open with their shapes intact.
- **SC-005**: A shape-form change is fully reversible: one Undo restores the prior form and one Redo
  reapplies the new form, with no orphaned intermediate steps.
- **SC-006**: When a shape is selected, a designer can identify the shape's current form from the
  gallery's highlight within a glance (no reading of numeric or textual fields required).

## Assumptions

- **Shape roster (decided)**: The v1 gallery offers exactly eight forms — line, rectangle, ellipse,
  triangle, diamond, pentagon, hexagon, and star (see Clarifications). This covers the examples in
  the request ("triangle, star, hexagon") plus the existing line/rectangle and common report-design
  shapes. The architecture should keep adding further forms cheap, but they are out of scope for v1.
- **Scope is changing a selected shape's form**, not introducing a new way to create shapes. Designers
  already add shapes via the existing toolbox; the gallery operates on the currently selected shape.
  Whatever form a newly-created shape starts as is unchanged by this feature.
- **Appearance is preserved across form changes**: fill, stroke, and stroke width carry over when the
  form changes; the line form simply has no fillable interior.
- **Star/polygon defaults**: Regular polygons (pentagon, hexagon) are equilateral and inscribed in
  the bounds; the star uses a conventional point count and inner/outer ratio chosen at design time.
  These visual defaults are not user-configurable in this feature.
- **Existing infrastructure is reused**: shape forms render through the existing report rendering
  pipeline so canvas, preview, and export stay consistent automatically; the chosen form serializes
  alongside the shape's existing fields without a breaking format change.
- **No per-vertex editing**: This feature is a form picker, not a freeform path editor; designers
  cannot drag individual vertices or define custom polygons here.
