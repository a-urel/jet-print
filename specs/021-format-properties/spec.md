# Feature Specification: Format Properties — Font & Color Editors

**Feature Branch**: `021-format-properties`
**Created**: 2026-06-13
**Status**: Draft
**Input**: User description: "enhence format properties: add font (name, size and other attributes) and color properties to report objects where appropriate. create industry standard property editors. prefer shadcn ui."

## Clarifications

### Session 2026-06-13

- Q: How should the font weight editor work for text elements (model supports Normal/Medium/SemiBold/Bold)? → A: Bold toggle only — classic B/I/U group; intermediate weights are not editable in the UI.
- Q: Should underline be included even though it is net-new across model, rendering, and export? → A: Include underline — complete the standard B/I/U group in this feature.
- Q: Where should the font and color editors appear (Properties panel only, or also toolbar quick-controls)? → A: Properties panel only — toolbar quick-format is an explicit follow-up, out of scope here.
- Q: Should the alignment control offer justify, given the render pipeline draws justified text flush-left (identical to left) on all paths? → A: Drop justify from the UI — segments offer left/center/right only. A stored justify value (settable programmatically; the model keeps the enum value) shows no active segment and is preserved untouched until the user picks an alignment. Justified rendering plus its UI is a follow-up.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Style text on a report (Priority: P1)

A report designer selects a text element (label, bound value, or template text) on the canvas and uses the Properties panel to change its font family, font size, weight (bold), italic, underline, text color, and horizontal alignment. The canvas updates immediately, and the styled text appears identically in print preview and exported documents.

**Why this priority**: Text is the dominant element type on real-world reports (invoices, labels, lists), and today none of its existing style attributes can be edited — the designer ships with rendering support for fonts and colors that users cannot reach. This single story turns the designer from "layout only" into a genuine formatting tool.

**Independent Test**: Can be fully tested by placing a text element, changing each style attribute in the Properties panel, and verifying the canvas, preview, and exported output all reflect the change. Delivers value with no other story implemented.

**Acceptance Scenarios**:

1. **Given** a text element is selected, **When** the user opens the Properties panel, **Then** a Font section shows the element's current font family, size, weight, italic, underline, color, and alignment.
2. **Given** a text element is selected, **When** the user picks a different font family from the family picker, **Then** the canvas immediately re-renders the text in that family and the choice persists in the saved template.
3. **Given** a text element is selected, **When** the user changes the font size (typing a value or stepping up/down), **Then** the text re-renders at the new size and out-of-range entries are clamped to the supported range.
4. **Given** a text element is selected, **When** the user toggles bold, italic, or underline, **Then** the toggle reflects the active state and the canvas updates immediately.
5. **Given** a text element is selected, **When** the user picks a new text color (from swatches or by entering a hex value), **Then** the text re-renders in that color and the editor displays the chosen color as both a swatch and its hex code.
6. **Given** a text element is selected, **When** the user changes horizontal alignment (left / center / right), **Then** the text re-aligns within the element's bounds.
7. **Given** any style change was made, **When** the user invokes Undo, **Then** the element returns to its previous style and the Properties panel reflects the restored values.
8. **Given** a styled text element, **When** the report is exported to a document or image, **Then** the exported output matches the canvas styling (family, size, weight, italic, underline, color, alignment).

---

### User Story 2 - Style shape fill and outline (Priority: P2)

A report designer selects a shape (rectangle, ellipse, triangle, line, etc.) and uses the Properties panel to set its fill color, outline (stroke) color, and outline width — including the ability to remove the fill or outline entirely (e.g., an unfilled rectangle used as a border box).

**Why this priority**: Shapes already carry fill/stroke style in the model and are commonly used for separators, boxes, and emphasis bands; without editors they can only ever appear in their default style. Depends on the same color editor introduced in Story 1, so it lands naturally second.

**Independent Test**: Can be fully tested by placing a shape, setting fill color, stroke color, and stroke width in the Properties panel, and verifying canvas, preview, and export. Removing fill/stroke ("none") must also render correctly.

**Acceptance Scenarios**:

1. **Given** a shape element is selected, **When** the user opens the Properties panel, **Then** an Appearance section shows the shape's current fill color, outline color, and outline width.
2. **Given** a shape element is selected, **When** the user picks a fill color, **Then** the shape's interior re-renders in that color immediately.
3. **Given** a shape with a fill, **When** the user chooses "No fill", **Then** the shape renders with outline only and the editor clearly indicates the "none" state.
4. **Given** a shape element is selected, **When** the user changes the outline width, **Then** the outline re-renders at the new width, and width zero or "No outline" removes the outline.
5. **Given** a line shape is selected, **When** the user opens the Properties panel, **Then** only outline color and width are offered (no fill, since a line has no interior).
6. **Given** any shape style change, **When** the user invokes Undo/Redo, **Then** the style steps back and forward correctly.

---

### User Story 3 - Set barcode color (Priority: P3)

A report designer selects a barcode element and changes the bar color in the Properties panel (e.g., dark navy bars to match brand guidelines on a label).

**Why this priority**: Smallest surface — a single color property that already exists in the model — and the least frequently changed in practice (most barcodes stay black for scanner contrast). Reuses the color editor from Story 1 with no new interaction patterns.

**Independent Test**: Can be fully tested by placing a barcode, changing its color, and verifying canvas and export output.

**Acceptance Scenarios**:

1. **Given** a barcode element is selected, **When** the user opens the Properties panel, **Then** a color editor shows the current bar color.
2. **Given** a barcode element is selected, **When** the user picks a new color, **Then** the bars re-render in that color on canvas and in exported output.
3. **Given** a barcode color change, **When** the user invokes Undo, **Then** the previous color is restored.

---

### Edge Cases

- **Unknown font family**: A template references a font family that is not available in the current session (e.g., file authored elsewhere). The family picker must show the stored name (marked as unavailable) rather than silently substituting, and rendering falls back to the default family without losing the stored value.
- **Invalid color input**: User types a malformed hex string. The editor rejects it without applying, restores the last valid value, and gives visual feedback.
- **Font size extremes**: Values below the minimum or above the maximum supported size are clamped; non-numeric input is rejected and the previous value restored.
- **Fill and outline both "none"**: A shape with neither fill nor outline would be invisible; the designer must still show a selectable placeholder on canvas (design-time affordance) so the element is not lost.
- **Transparency**: Colors may carry an alpha component from existing templates. The editor must display and preserve alpha correctly even if the picker primarily offers opaque colors.
- **Rapid repeated changes**: Dragging a size stepper or clicking many swatches in quick succession must coalesce sensibly in undo history (one undo step per committed change, not per keystroke).
- **Selection switches while editing**: If the user selects a different element while a style editor is open/focused, pending uncommitted input is discarded and the editor re-binds to the new selection.

## Requirements *(mandatory)*

### Functional Requirements

**Text styling (Story 1)**

- **FR-001**: Users MUST be able to view and edit the font family of a selected text element, choosing from the set of fonts available to the report (including the built-in default), via a picker that previews each family name in its own typeface where possible.
- **FR-002**: Users MUST be able to view and edit the font size of a selected text element via numeric entry with increment/decrement stepping; the system MUST clamp values to a supported range (assumed 4–144 pt) and reject non-numeric input.
- **FR-003**: Users MUST be able to toggle bold, italic, and underline on a selected text element via toggle buttons that visibly indicate the active state (the industry-standard B/I/U control group). Intermediate stored weights (medium, semi-bold) display the Bold toggle as inactive and are preserved untouched until the user operates the toggle, at which point the weight becomes bold (toggle on) or normal (toggle off).
- **FR-004**: Users MUST be able to set the text color of a selected text element via a color editor (see FR-009/FR-010).
- **FR-005**: Users MUST be able to set the horizontal alignment of a selected text element (left, center, right) via a segmented control that indicates the active alignment. A stored justify alignment displays no active segment and is preserved untouched until the user picks an alignment (justified rendering is out of scope — clarified 2026-06-13).
- **FR-006**: Text elements whose stored style predates this feature MUST continue to render unchanged and MUST display their effective values in the new editors.

**Shape styling (Story 2)**

- **FR-007**: Users MUST be able to set, change, and remove ("none") the fill color of a selected closed shape.
- **FR-008**: Users MUST be able to set, change, and remove ("none") the outline color of a selected shape, and to set the outline width via numeric entry with stepping (assumed range 0–20 pt, where 0 means no outline). Line shapes MUST offer outline controls only, never fill.

**Color editing (shared)**

- **FR-009**: The color editor MUST present the current color as a swatch plus its hex code, and MUST allow choosing a color from a palette of common swatches and by typing a hex value (with or without alpha).
- **FR-010**: The color editor MUST validate typed input, applying only well-formed color values and restoring the previous value otherwise, and MUST preserve any alpha component already stored on the element.

**Barcode styling (Story 3)**

- **FR-011**: Users MUST be able to set the bar color of a selected barcode element using the shared color editor.

**Cross-cutting**

- **FR-012**: Every style change MUST be applied to the canvas immediately on commit (selection from a picker, Enter, or focus loss for typed input).
- **FR-013**: Every style change MUST be a single undoable step, fully reversible via the existing Undo/Redo mechanism, with the Properties panel reflecting undone/redone values.
- **FR-014**: All style properties MUST persist in the saved report template and round-trip through save/load without loss (including alpha and "none" states).
- **FR-015**: Rendered output (print preview, document export, image export) MUST match the canvas presentation of all style properties.
- **FR-016**: All new editor labels and texts MUST be localizable, consistent with the designer's existing localization support.
- **FR-017**: Style editors MUST appear only for element types where the property applies (e.g., no font controls for shapes or images; no fill control for lines or barcodes).

### Key Entities

- **Text Style**: The set of visual attributes on a text element — font family name, font size, weight, italic, underline, color, horizontal alignment. Underline is a new attribute; all others already exist on the element.
- **Box Style**: The appearance of a shape — optional fill color, optional outline color, outline width. Already exists on shape elements; this feature exposes it for editing.
- **Color**: A single color value with optional transparency, displayed and entered as a hex code, selectable from a swatch palette. Shared by text, shape, and barcode editing.
- **Font Family**: A named typeface available to the report. The set of available families is determined by what the host application registers plus the built-in default; templates may reference families that are unavailable in the current session.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can change any single style attribute (font, size, color, etc.) of a selected element in 3 interactions or fewer from the moment the element is selected.
- **SC-002**: 100% of style attributes editable in the Properties panel render identically (same family, size, weight, style, color, alignment) on the design canvas, in print preview, and in exported documents.
- **SC-003**: Every style edit is undoable in exactly one Undo step, verified across all editor types.
- **SC-004**: Templates saved with styled elements reload with zero loss of style information, including transparency and "no fill"/"no outline" states.
- **SC-005**: Style changes appear on the canvas within 100 ms of being committed (perceived as instant).
- **SC-006**: A first-time user asked to "make this label bold, red, and centered" completes the task without documentation, relying on recognizable industry-standard controls (B/I/U toggles, color swatch, alignment segments).

## Assumptions

- **Available fonts** are those registered with the report engine by the host application plus the built-in default family; this feature does not add OS-level font discovery or font file management. The picker lists registered families only.
- **Underline** is included under "other attributes" (completing the industry-standard B/I/U trio) even though it is a new attribute end-to-end; line-spacing, letter-spacing, and strikethrough are out of scope for this feature.
- **Vertical alignment** of text within its bounds is out of scope; only horizontal alignment is exposed (matching the existing model).
- **Image elements** receive no style properties in this feature (no border/tint), as none exist in the model and none were requested.
- **Single selection** is the editing context; bulk-styling a multi-selection is out of scope until multi-select editing exists in the designer.
- **Color picker depth**: a swatch palette plus hex entry is sufficient for v1; a full gradient/HSV picker, recent-colors history, and named brand palettes are out of scope.
- **Visual language**: new editors follow the designer's existing component library and visual conventions (the user explicitly prefers the shadcn-style component set already used throughout the Properties panel).
- **Default styles for new elements** are unchanged; this feature edits existing defaults rather than redefining them.
- **Editor placement**: all style editors live exclusively in the Properties panel; quick-format controls in the designer toolbar are out of scope for this feature (clarified 2026-06-13).
