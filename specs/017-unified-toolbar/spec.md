# Feature Specification: Unified Context-Switching Toolbar

**Feature Branch**: `017-unified-toolbar`  
**Created**: 2026-06-12  
**Status**: Draft  
**Input**: User description: "improve toolbars. designer toolbar: report name with edit button | [designer], preview | (other buttons). preview toobar: report name with edit button | designer, [preview] | (other buttons). Make them look same toolbar that changing by context."

## Clarifications

### Session 2026-06-12

- Q: When the user clicks the Designer/Preview segment, who owns the mode state and performs the switch? → A: Host owns it — the toolbar emits a "switch requested" event and the host performs the actual switch; the toolbar reflects the active mode it is given.
- Q: Where does the report name live and how does a rename propagate to preview/export/save? → A: The name is a field on the report template; rename updates that field and the change is exposed via the controller/callback so the host can persist it on save.
- Q: In which modes can the user rename the report from the toolbar? → A: Both Designer and Preview modes.
- Q: While editing the name inline, what happens on blur (focus leaves without pressing Enter)? → A: Blur confirms — clicking away commits the typed name (if non-empty); Escape still cancels.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Switch between Designer and Preview from one toolbar (Priority: P1)

A user working on a report sees a single, consistent toolbar at the top of the workspace. In the center of that toolbar is a two-segment switch labelled **Designer** and **Preview**, with the current mode highlighted. The user clicks **Preview** to see the rendered, paginated report, then clicks **Designer** to return to editing — without losing any of their in-progress work. The toolbar's left region (report name) stays put across both modes; only the right-hand action buttons change to match the active mode.

**Why this priority**: This is the heart of the request — making the designer and preview feel like one surface whose toolbar changes by context. It is the single most valuable, demonstrable slice: a user can experience the unified toolbar and round-trip between modes even before rename or any refinements exist.

**Independent Test**: Open a report in Designer mode, confirm the Designer/Preview switch shows Designer as active and designer actions on the right; click Preview, confirm the rendered report appears, the switch now shows Preview as active, and preview actions (e.g. export, print, page navigation) appear on the right; click Designer and confirm the original edits are intact.

**Acceptance Scenarios**:

1. **Given** a report open in Designer mode, **When** the user selects the **Preview** segment, **Then** the workspace shows the rendered preview of the current (live, unsaved) report and the active segment becomes **Preview**.
2. **Given** a report open in Preview mode, **When** the user selects the **Designer** segment, **Then** the workspace returns to the editable design surface with all prior edits and the current selection state preserved.
3. **Given** the user is in either mode, **When** they look at the toolbar, **Then** the report-name region (left) and the Designer/Preview switch (center) are in the same position and visual style in both modes, and only the right-hand actions differ.
4. **Given** the user switches modes repeatedly, **When** they return to Designer, **Then** no edits, undo/redo history, or selection are lost as a result of switching.

---

### User Story 2 - Rename the report inline from the toolbar (Priority: P2)

The report name is shown on the left of the toolbar with an adjacent **edit** affordance. The user activates it, types a new name, and confirms; the new name immediately appears in the toolbar and travels with the report (e.g. it is the name used when previewing, exporting, or saving). If the user changes their mind, they can cancel and the previous name is kept.

**Why this priority**: Renaming is a clear, self-contained usability win called out explicitly in the request, but the unified toolbar (P1) delivers the core value on its own. Rename builds on top of it.

**Independent Test**: With a report open, activate the edit affordance next to the name, change the text, confirm, and verify the displayed name updates and is reflected in a subsequent preview/export. Repeat but cancel the edit and verify the name is unchanged.

**Acceptance Scenarios**:

1. **Given** a report with a name shown in the toolbar, **When** the user activates the edit affordance, **Then** the name becomes editable with the current name pre-filled and focused.
2. **Given** the user has typed a new name, **When** they confirm (e.g. press Enter or activate a confirm control), **Then** the toolbar shows the new name and the report carries that name forward.
3. **Given** the user is editing the name, **When** they press Escape, **Then** the edit is discarded and the prior name is retained unchanged.
4. **Given** the user has typed a new (non-empty) name, **When** focus leaves the field (blur) without pressing Enter, **Then** the typed name is committed (blur confirms).
5. **Given** a report with no name yet, **When** the user views the toolbar, **Then** a clear placeholder (e.g. "Untitled report") is shown and the edit affordance is still available.
6. **Given** the user confirms an empty or whitespace-only name, **When** the edit completes, **Then** the report falls back to the placeholder state rather than showing a blank name.
7. **Given** the user is in Preview mode, **When** they activate the edit affordance, **Then** they can rename the report just as in Designer mode.

---

### User Story 3 - Mode-appropriate actions on the right (Priority: P3)

The right-hand portion of the unified toolbar presents only the actions relevant to the active mode: in Designer mode the editing controls (e.g. undo/redo, clipboard, zoom, view toggles, arrange, open/save), and in Preview mode the viewing controls (e.g. export, print, zoom, page navigation). Switching modes swaps these action groups while the shared left/center regions stay constant.

**Why this priority**: This refines the unified experience so each mode is uncluttered and focused. It depends on P1 existing and is a polish layer rather than the core capability.

**Independent Test**: In Designer mode, verify only designer-relevant actions appear on the right; switch to Preview and verify those are replaced by preview-relevant actions; confirm no designer-only action remains visible in Preview and vice versa.

**Acceptance Scenarios**:

1. **Given** Designer mode is active, **When** the user inspects the right-hand actions, **Then** they see the editing actions and none of the preview-only actions.
2. **Given** Preview mode is active, **When** the user inspects the right-hand actions, **Then** they see the viewing/output actions and none of the designer-only editing actions.
3. **Given** the workspace is narrow, **When** the toolbar cannot fit all actions, **Then** it degrades gracefully (e.g. collapses labels to icons or scrolls) without hiding the report-name region or the Designer/Preview switch.

---

### Edge Cases

- **Switching to Preview with an empty or invalid report**: The preview should still open and present a clear empty/placeholder state rather than failing silently.
- **Renaming during Preview mode**: The name region is shared and rename is available in both modes; a rename made in Preview must update the same template name field used by Designer.
- **Very long report names**: The name must truncate gracefully (e.g. ellipsis) without pushing the Designer/Preview switch or actions off-screen.
- **Narrow / small windows**: The toolbar must remain usable; the switch and name must remain reachable even when action buttons collapse or scroll.
- **Rapid mode toggling**: Repeated fast switches must not lose edits, duplicate the preview, or leave the toolbar in an inconsistent active-segment state.
- **Cancelling a rename mid-edit**: Must reliably restore the prior name with no partial application.
- **Unsaved edits when previewing**: Preview must reflect the latest live edits, not a stale saved version.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST present a single toolbar whose visual structure (left report-name region, center mode switch, right action region) is identical in both Designer and Preview modes, so the two read as one toolbar that changes by context.
- **FR-002**: The toolbar MUST include a two-segment mode switch with **Designer** and **Preview** options, visually indicating which mode is currently active. The active mode is supplied to the toolbar by the host.
- **FR-003**: Selecting the **Preview** segment MUST emit a "switch to Preview" request to the host; the host is responsible for displaying the rendered, paginated report, which MUST reflect the current live (including unsaved) report content.
- **FR-004**: Selecting the **Designer** segment MUST emit a "switch to Designer" request to the host; returning to Designer MUST preserve all prior edits, undo/redo history, and selection state.
- **FR-005**: Switching between modes MUST NOT discard or corrupt the user's in-progress work.
- **FR-006**: The toolbar MUST display the report's name in a consistent left-hand region in both modes, showing a clear placeholder when the report has no name.
- **FR-007**: The toolbar MUST provide an edit affordance next to the report name that lets the user rename the report in place, available in **both** Designer and Preview modes.
- **FR-008**: Confirming a rename MUST update the report template's name field, immediately reflect it in the displayed name, and expose the change (via the controller/callback) so the host can persist it; the new name MUST be the one carried forward for subsequent actions (preview, export, save).
- **FR-009**: While editing the name, pressing **Escape** MUST cancel and retain the previous name; **blur** (focus leaving the field) MUST commit the typed name when it is non-empty.
- **FR-010**: Confirming an empty or whitespace-only name MUST result in the placeholder state rather than a blank name.
- **FR-011**: The right-hand action region MUST show only the actions relevant to the active mode — editing actions in Designer, viewing/output actions in Preview — preserving the existing capabilities of each mode.
- **FR-012**: The toolbar MUST degrade gracefully when horizontal space is constrained (e.g. collapse labels to icons or scroll the action region) without hiding the report-name region or the Designer/Preview switch.
- **FR-013**: All toolbar text (segment labels, the placeholder, tooltips, and the edit/rename affordance) MUST be localizable, consistent with the existing multi-language support.
- **FR-014**: The toolbar MUST be keyboard and pointer accessible, including activating the mode switch, opening/confirming/cancelling rename, and reaching the mode-specific actions.

### Key Entities *(include if feature involves data)*

- **Report (template)**: The document being designed and previewed. Relevant attributes for this feature: a human-readable **name/title field** carried on the template (editable via the toolbar, may be empty → placeholder) and its content (used to render the preview). The name is the same value across Designer and Preview modes; renaming updates this field and is surfaced to the host for persistence.
- **Workspace Mode**: The current context — **Designer** (editing) or **Preview** (viewing) — that determines which action set the toolbar shows. Exactly one mode is active at a time. The mode is owned by the host; the toolbar requests changes and reflects the host-supplied active mode.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can move from editing to viewing the rendered report and back using only the toolbar mode switch, in **2 interactions or fewer** per direction (one click to switch).
- **SC-002**: After any number of mode switches, **100%** of the user's edits and undo/redo history are still present when returning to Designer.
- **SC-003**: The left (report name) and center (mode switch) regions occupy the **same position** in both modes, verified by visual comparison, so users perceive a single toolbar.
- **SC-004**: A user can rename a report and see the new name reflected in a subsequent preview/export in **under 10 seconds** without leaving the toolbar.
- **SC-005**: In Preview mode, **none** of the designer-only editing actions are visible, and in Designer mode **none** of the preview-only actions are visible.
- **SC-006**: At the supported narrow window widths, the report name and the Designer/Preview switch remain visible and reachable in **100%** of cases, with action buttons collapsing or scrolling instead.
- **SC-007**: A user encountering the workspace for the first time can correctly identify how to switch to Preview and how to rename the report **without external instruction**, validated through informal usability observation.

## Assumptions

- The unified toolbar applies to the report designer/preview workspace of the Jet Print component; it does not change the host application's surrounding navigation or its responsibility for actually persisting (saving) files.
- The preview always renders the current live report content (including unsaved edits), consistent with the existing "Preview shows the live template" behavior.
- The host owns mode state and performs the actual Designer↔Preview switch (e.g. via its own navigation or view swap); the toolbar emits switch requests and displays the active mode it is given (see Clarifications).
- Renaming updates the name field on the report template and surfaces that change so the host can persist it through its normal save flow; this feature does not add a separate save-to-disk step for the name alone.
- The set of mode-specific actions reuses the capabilities already available today in the separate designer and preview toolbars (undo/redo, clipboard, zoom, view toggles, arrange, open/save for Designer; export, print, zoom, page navigation for Preview); this feature reorganizes and unifies their presentation rather than adding new commands beyond rename and the mode switch.
- Exactly one mode (Designer or Preview) is active at any time; there is no simultaneous split view.
- "Look the same" means the shared regions (name + mode switch) are visually and positionally consistent and the overall toolbar shell (height, styling) is identical across modes; the right-hand action groups intentionally differ by context.
- Inline rename is available in both Designer and Preview modes; Escape cancels the edit, and blur (or Enter) commits a non-empty name (see Clarifications).

## Dependencies

- Builds on the existing designer surface, preview renderer, undo/redo history, and localization support already present in the Jet Print component.
- Relies on the report model exposing an editable name/title that both modes can read and that rename can update.
