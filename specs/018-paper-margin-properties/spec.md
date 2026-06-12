# Feature Specification: Editable Paper Type & Margins in Report Properties

**Feature Branch**: `018-paper-margin-properties`
**Created**: 2026-06-12
**Status**: Draft
**Input**: User description: "improve report properties. add paper type and margin selection option."

## User Scenarios & Testing *(mandatory)*

Today the report's **Properties** panel shows a **PAGE** section with the page **Size** (e.g. "595 × 842 pt")
and **Margins** (e.g. "28 · 28 · 28 · 28") as **read-only text**. To change either, a designer has no
in-app path — the values are fixed to the template's defaults. This feature turns that section into an
editable set of controls so a designer can pick a standard paper type and set the page margins, with the
change reflected everywhere the page is drawn (canvas, preview, export, print) and saved with the template.

## Clarifications

### Session 2026-06-12

- Q: Which standard paper-size presets should the paper-type control offer (plus Custom)? → A: A4, A3, A5, Letter, Legal (+ Custom)
- Q: What margin controls should the PAGE section provide? → A: Margin presets (Normal / Narrow / Wide / None) **and** editable per-side fields (left/top/right/bottom)
- Q: How should the system respond to a size/margin that leaves no usable content area or is below the minimum? → A: Clamp the value to the nearest valid range so the page stays usable
- Q: What measurement units should the PAGE controls expose? → A: Points (pt) only — no unit switching

### User Story 1 - Choose a standard paper type (Priority: P1)

A designer opens the Properties panel, sees the current paper type named (e.g. "A4"), and selects a
different standard size (e.g. "Letter") from a list. The page on the canvas immediately resizes to the
chosen dimensions, and all existing content keeps its position relative to the page origin.

**Why this priority**: Picking the right paper is the single most common page-setup task and the headline
ask ("add paper type"). It delivers visible value on its own — a designer can target A4, Letter, A5, etc.
without editing raw numbers.

**Independent Test**: Open a report, change the paper type from the presets list, and confirm the canvas
page (and preview/export) adopts the new dimensions and the choice survives save/reload — without touching
margins or any other property.

**Acceptance Scenarios**:

1. **Given** a report whose page is A4, **When** the designer opens Properties, **Then** the PAGE section
   shows the paper type identified by name (e.g. "A4") rather than only raw numbers.
2. **Given** the paper-type control, **When** the designer selects a different standard size, **Then** the
   page dimensions change to that size and the canvas re-renders at the new size.
3. **Given** a paper-type change, **When** the designer presses undo, **Then** the page returns to its
   previous size in a single step; redo re-applies it.
4. **Given** a changed paper type, **When** the report is saved and reopened, **Then** the new size is
   preserved.
5. **Given** a page whose dimensions match no standard preset, **When** Properties opens, **Then** the
   paper-type control indicates a non-standard / "Custom" size rather than mislabeling it.

---

### User Story 2 - Set page margins (Priority: P2)

A designer adjusts the page margins so content sits closer to or further from the page edges. They can pick
a margin preset (e.g. Normal, Narrow, Wide, None) for a one-click change, and/or set the four side margins
(left, top, right, bottom) to specific values. The content area updates to reflect the new margins.

**Why this priority**: Margin control is the second explicit ask and frequently needed for fitting content
or matching print requirements, but it builds on the page being editable (P1) and is independently shippable
after it.

**Independent Test**: Open a report, apply a margin preset and/or type specific side values, and confirm the
content area / margin guides update, the values display correctly, and they persist across save/reload —
independent of the paper-type control.

**Acceptance Scenarios**:

1. **Given** the PAGE section, **When** the designer chooses a margin preset, **Then** all four side margins
   update to that preset's values and the page's content area reflects them.
2. **Given** the margin controls, **When** the designer sets an individual side margin to a specific value,
   **Then** only that side changes and the others are unaffected.
3. **Given** margins that would exceed the page (no room left for content), **When** the designer applies
   them, **Then** the system clamps the offending side(s) to the nearest valid value so a usable content
   area remains, rather than producing an unusable page.
4. **Given** a margin change, **When** the designer presses undo, **Then** the margins revert in a single
   step; redo re-applies them.
5. **Given** changed margins, **When** the report is saved and reopened, **Then** the margin values are
   preserved.

---

### User Story 3 - Orientation and custom dimensions (Priority: P3)

A designer switches the page between portrait and landscape, or—when no standard size fits—enters a custom
width and height for non-standard stock (labels, receipts, oversized layouts).

**Why this priority**: Orientation and fully custom sizes cover the long tail of layouts. They round out the
feature but are not required for the common A4/Letter + margins workflow to be useful.

**Independent Test**: Toggle orientation on a standard size and confirm width/height swap; choose "Custom"
and enter dimensions, then confirm the page adopts them and they persist.

**Acceptance Scenarios**:

1. **Given** a portrait standard size, **When** the designer switches to landscape, **Then** the page's
   width and height swap and the canvas re-renders accordingly.
2. **Given** the paper-type control set to "Custom", **When** the designer enters a width and height, **Then**
   the page adopts those exact dimensions.
3. **Given** a custom width or height at or below the minimum usable size, **When** the designer confirms,
   **Then** the value is clamped to a valid minimum rather than producing a zero/negative page.

---

### Edge Cases

- **Margins ≥ page extent**: combined left+right (or top+bottom) margins must not consume the entire page;
  the system clamps the affected side(s) so a usable content area always remains.
- **Non-preset current value**: a template whose size or margins don't match any named preset must display
  as "Custom" (size) or show the actual per-side values (margins), never a wrong preset name.
- **Orientation of a custom size**: toggling orientation swaps width/height regardless of whether the size is
  a named preset or custom.
- **Empty / non-numeric entry** in a custom dimension or margin field: revert to the last valid value rather
  than applying a blank.
- **Rounding/display**: presets defined in standard units (e.g. A4 = 595.28 × 841.89 pt) should still match
  their preset name even though the panel may display rounded values.
- **No selection vs. report-level edit**: the PAGE controls edit the report page itself and remain available
  whether or not an element is currently selected.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Properties PAGE section MUST let the designer change the page paper type by selecting from
  a list of named standard sizes, replacing today's read-only size text.
- **FR-002**: The system MUST provide these standard paper-size presets — **A4, A3, A5, Letter, Legal** —
  plus a **Custom** option, and MUST identify the current page by its matching preset name when its
  dimensions match one (in either orientation).
- **FR-003**: The system MUST represent a page whose dimensions match no preset as "Custom" without altering
  its actual dimensions.
- **FR-004**: The Properties PAGE section MUST let the designer set the page margins both via margin presets
  and via editable per-side values (left, top, right, bottom).
- **FR-005**: The system MUST provide the margin presets **Normal, Narrow, Wide, None** and apply a chosen
  preset to all four sides at once; editing any individual side afterward is allowed and marks the margin
  set as Custom.
- **FR-006**: Changing paper type, orientation, custom dimensions, or margins MUST update every place the
  page is drawn — design canvas, preview, and exported/printed output — consistently (WYSIWYG).
- **FR-007**: Each page-property change (size, orientation, or margins) MUST be a single undoable/redoable
  step in the existing edit history.
- **FR-008**: Page-property changes MUST be persisted with the report template and restored on reload,
  without breaking templates saved before this feature.
- **FR-009**: The system MUST validate page dimensions and margins so the resulting content area is positive
  and usable, **clamping** any value that would leave no content space (or fall below the minimum usable
  size) to the nearest valid value.
- **FR-010**: The designer MUST be able to switch a standard or custom page between portrait and landscape
  orientation, swapping width and height.
- **FR-011**: The designer MUST be able to enter explicit custom width and height when "Custom" paper type
  is selected.
- **FR-012**: All new UI labels, **margin**-preset names (Normal/Narrow/Wide/None), the **Custom** option, and
  orientation/unit text MUST be localized in the same languages the panel already supports (English, German,
  Turkish). Standard paper-size names (A4, A3, A5, Letter, Legal) are universal and remain un-localized.
- **FR-013**: Changing the page size MUST NOT move existing report content relative to the page origin (the
  top-left anchor is preserved); content that now falls outside a smaller page remains in the model and is
  handled by existing overflow/pagination behavior.
- **FR-014**: The PAGE controls MUST express all dimensions in the existing unit (**logical points, "pt"**);
  no unit-switching (mm/inch) is in scope.

### Key Entities *(include if data involved)*

- **Page format**: the report's page definition — width, height, and four-side margins. Already part of the
  report template and already saved; this feature makes it editable.
- **Paper-size preset**: a named standard size (name + dimensions, e.g. A4, Letter) used to set the page
  size and to label the current size when it matches.
- **Margin preset**: a named set of four-side margin values (e.g. Normal, Narrow, Wide, None) applied as a
  group.
- **Orientation**: portrait vs. landscape, a view over which of width/height is the longer dimension.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A designer can change the report's paper type to a standard size in 2 or fewer interactions
  from the Properties panel, with no manual number entry required.
- **SC-002**: A designer can apply a margin preset in a single interaction, and set a specific side margin in
  one focused edit, without affecting the other sides.
- **SC-003**: After any page-property change, the page shown on the canvas, in the preview, and in exported
  output match each other in size and content area 100% of the time.
- **SC-004**: 100% of page-property changes are reversible with a single undo and re-applicable with a single
  redo.
- **SC-005**: 100% of reports saved with a changed paper type or margins reload with those exact values, and
  100% of reports saved before this feature continue to open unchanged.
- **SC-006**: The system never produces a page with a non-positive content area; attempts to do so are
  prevented or corrected, verified across boundary inputs.
- **SC-007**: All new controls are usable and correctly labeled in English, German, and Turkish.

## Assumptions

- **Paper-size presets** (clarified): **A4, A3, A5, Letter, Legal**, plus **Custom**. Dimensions use the page
  model's existing logical-point unit; presets are recognized in either orientation.
- **Margin presets** (clarified): **Normal** (the current default, ~1 cm all sides), **Narrow**, **Wide**, and
  **None (0)**; designers can also override any side with a custom value, which marks the set as Custom. Exact
  Narrow/Wide values are a planning detail.
- **Units** (clarified): The panel expresses dimensions only in logical points ("pt") as shown today; no
  unit-conversion UI (mm/in) is in scope.
- **Invalid values** (clarified): Out-of-range sizes/margins are clamped to the nearest valid value (silent
  correction), never rejected with a blocking error or left producing an unusable page.
- **Editing idiom**: Page edits reuse the designer's existing command/undo mechanism and immutable page
  model; no new persistence format or schema version is introduced (the page already serializes).
- **Scope of "improve report properties"**: This feature is scoped specifically to **paper type (size +
  orientation + custom) and margins**. Other potential report-level properties (background, default fonts,
  bleed, named units) are out of scope here.
- **Selection independence**: The PAGE controls always edit the report page and do not depend on an element
  being selected.
- **Content reflow**: When a smaller page is chosen, existing elements are not repositioned or deleted;
  visibility/overflow is governed by the existing pagination/rendering behavior, not by this feature.
