# Feature Specification: Clipboard Operations in the Designer UI

**Feature Branch**: `016-clipboard-operations`  
**Created**: 2026-06-12  
**Status**: Draft  
**Input**: User description: "add clipboard operations. create clipboard commands if needed. add cut, copy, paste to designer ui in both toolbar and context menu."

## Overview

The report designer can already cut, copy, and paste selected elements — the operations
exist and are reachable by keyboard shortcut (⌘/Ctrl+X, ⌘/Ctrl+C, ⌘/Ctrl+V), backed by a
session-scoped clipboard, and they participate in undo/redo. What is missing is a **visible,
mouse-reachable way to invoke them**. There are no clipboard buttons in the designer toolbar,
and the canvas has no right-click context menu at all.

This feature makes the existing clipboard operations **discoverable and operable without the
keyboard** by surfacing Cut, Copy, and Paste in two places: the designer toolbar and a new
canvas context menu. The value is purely in the interaction surface — users who don't know (or
can't use) the keyboard shortcuts can still cut, copy, and paste.

## Clarifications

### Session 2026-06-12

- Q: Right-click on empty canvas space while elements are already selected — keep or clear the selection? → A: Keep the existing selection (secondary-click never deselects; the menu acts on the still-selected elements, Paste enabled if clipboard has content).
- Q: Should the context-menu items show keyboard-shortcut hints? → A: Yes — each item displays its shortcut equivalent (Cut ⌘/Ctrl+X, Copy ⌘/Ctrl+C, Paste ⌘/Ctrl+V, Duplicate ⌘/Ctrl+D, Delete).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Cut / Copy / Paste from the toolbar (Priority: P1)

A user editing a report selects one or more elements and wants to copy them and paste a duplicate
without reaching for keyboard shortcuts. They find Cut, Copy, and Paste controls in the designer
toolbar, alongside the existing undo/redo and arrange controls, and operate the clipboard entirely
with the mouse.

**Why this priority**: The toolbar is the primary, always-visible command surface of the designer.
Adding the clipboard controls here is the single highest-value, most-discoverable slice and is a
complete, demonstrable improvement on its own.

**Independent Test**: Open the designer, select an element, click Copy then Paste from the toolbar,
and confirm a duplicate appears and is selected — all without using the keyboard. Fully testable
in isolation; delivers mouse-only clipboard access.

**Acceptance Scenarios**:

1. **Given** an element is selected, **When** the user clicks the toolbar Copy control and then the
   toolbar Paste control, **Then** an offset duplicate of the element is inserted and becomes the
   new selection.
2. **Given** an element is selected, **When** the user clicks the toolbar Cut control, **Then** the
   element is removed from the canvas and held on the clipboard; clicking Paste re-inserts a copy.
3. **Given** nothing is selected, **When** the user views the toolbar, **Then** the Cut and Copy
   controls are disabled.
4. **Given** the clipboard is empty (nothing has been cut or copied this session), **When** the
   user views the toolbar, **Then** the Paste control is disabled.
5. **Given** the user performs a Cut or Paste from the toolbar, **When** they invoke Undo, **Then**
   the document returns to its prior state (the operation is a single undoable step).

---

### User Story 2 - Cut / Copy / Paste from a right-click context menu (Priority: P2)

A user wants clipboard actions at the point of interaction. They right-click (secondary-click) on
the canvas and get a context menu offering Cut, Copy, and Paste, so they can act on the element
under the cursor without traveling to the toolbar.

**Why this priority**: A context menu is the conventional, fast path for clipboard actions and is
net-new UI (the canvas has no context menu today). It builds on the same underlying operations as
P1 but is independently valuable and independently testable.

**Independent Test**: Right-click an element on the canvas, choose Copy, right-click again, choose
Paste, and confirm a duplicate appears — without using the toolbar or keyboard.

**Acceptance Scenarios**:

1. **Given** an element is present, **When** the user right-clicks it, **Then** that element becomes
   selected (if not already part of the selection) and a context menu with Cut, Copy, and Paste
   appears.
2. **Given** an element is selected, **When** the user opens the context menu and chooses Copy then,
   in a second context-menu invocation, chooses Paste, **Then** an offset duplicate is inserted and
   selected.
3. **Given** the user right-clicks an empty area of the canvas with nothing selected, **When** the
   context menu opens, **Then** Cut and Copy are disabled and Paste is enabled only if the clipboard
   has content.
4. **Given** the context menu is open, **When** the user clicks elsewhere or presses the dismiss key,
   **Then** the menu closes without performing any action.
5. **Given** an element is selected, **When** the user opens the context menu and chooses Duplicate or
   Delete, **Then** the corresponding existing operation runs as a single undoable step (Duplicate
   inserts an offset copy and selects it; Delete removes the selection).
6. **Given** one or more elements are selected, **When** the user right-clicks an empty area of the
   canvas, **Then** the existing selection is preserved (secondary-click does not deselect) and the
   menu's Cut/Copy/Duplicate/Delete act on that selection.

---

### User Story 3 - Discoverable, accessible, localized affordances (Priority: P3)

A user who relies on tooltips, assistive technology, or a non-English UI can recognize and operate
the clipboard controls. Each control shows a descriptive tooltip (including its keyboard-shortcut
equivalent), exposes an accessible name, and appears in the user's selected language.

**Why this priority**: This is the polish layer that makes P1/P2 usable for all users and consistent
with the rest of the designer. It is valuable but depends on the controls existing first.

**Independent Test**: Hover each clipboard control to confirm a localized tooltip with the shortcut
hint; switch the UI language and confirm labels/tooltips update; inspect accessible names via the
semantics tree.

**Acceptance Scenarios**:

1. **Given** the pointer hovers a toolbar clipboard control, **When** the tooltip appears, **Then**
   it names the action and indicates the equivalent keyboard shortcut.
2. **Given** the UI is set to any supported language, **When** the clipboard controls render, **Then**
   their labels and tooltips appear in that language.
3. **Given** assistive technology inspects a clipboard control, **When** it reads the control,
   **Then** an accessible name describing the action is exposed.

---

### Edge Cases

- **Empty clipboard at session start**: Paste is disabled everywhere until the first Cut/Copy.
- **Selection lost after Cut**: After Cut, the selection is empty, so Cut/Copy become disabled while
  Paste remains enabled.
- **Right-click on an element that is part of a multi-selection**: The existing multi-selection is
  preserved (the menu acts on the whole selection); right-clicking an unselected element replaces the
  selection with that element before showing the menu.
- **Paste with the source element deleted**: Paste reproduces from the clipboard's stored copy, so it
  still works even if the original was deleted after copying.
- **Pasting near a band edge**: The pasted copy is offset but clamped to remain within its band
  (existing behavior).
- **Band or report (page) selected rather than elements**: Copy/Cut act only on element selections;
  with a band/report selected and no elements, Cut and Copy are disabled.
- **Repeated Paste**: Each Paste produces a new offset copy with a fresh identifier; repeated pastes
  do not collide.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The designer toolbar MUST present distinct Cut, Copy, and Paste controls.
- **FR-002**: The canvas MUST provide a right-click (secondary-click) context menu that includes Cut,
  Copy, and Paste actions, plus Duplicate and Delete actions (which act on the current selection).
- **FR-003**: All clipboard controls (toolbar and context menu) MUST invoke the designer's existing
  cut/copy/paste operations; this feature MUST NOT introduce a second, divergent clipboard
  implementation.
- **FR-004**: Cut and Copy controls MUST be enabled only when one or more elements are selected, and
  disabled otherwise.
- **FR-005**: Paste controls MUST be enabled only when the clipboard holds content, and disabled when
  it is empty.
- **FR-005a**: The context menu's Duplicate and Delete actions MUST follow the same selection-based
  enablement as Cut/Copy (FR-004) — enabled only when one or more elements are selected — MUST act on
  the existing selection, and MUST each be a single undoable step.
- **FR-006**: Cut MUST remove the selected element(s) from the canvas and retain a copy on the
  clipboard for later paste.
- **FR-007**: Copy MUST place a copy of the selected element(s) on the clipboard without changing the
  document.
- **FR-008**: Paste MUST insert offset copies of the clipboard contents with fresh identifiers and
  select the newly inserted copies (existing paste behavior).
- **FR-009**: Cut and Paste MUST each be a single undoable step; Copy MUST NOT create an undo entry.
- **FR-010**: Right-clicking an element that is not already selected MUST select it before the
  context menu's actions apply; right-clicking within an existing multi-selection MUST preserve that
  selection; right-clicking empty canvas space MUST NOT change the current selection.
- **FR-011**: The context menu MUST be dismissible without performing an action (clicking away or a
  dismiss key) and MUST not alter the document on dismissal.
- **FR-012**: Toolbar and context-menu clipboard controls MUST behave identically for the same input
  state (same enablement, same result).
- **FR-013**: Each clipboard control MUST expose a localized label/tooltip in every UI language the
  designer already supports.
- **FR-014**: Toolbar clipboard tooltips MUST indicate the equivalent keyboard shortcut for the
  action.
- **FR-014a**: Each context-menu item (Cut, Copy, Paste, Duplicate, Delete) MUST display its
  keyboard-shortcut equivalent alongside its label.
- **FR-015**: Each clipboard control MUST expose an accessible name for assistive technology.
- **FR-016**: Adding these controls MUST NOT change how reports are saved or loaded (no serialization
  or model change) and MUST NOT alter the printed/exported/previewed output.
- **FR-017**: Existing keyboard shortcuts for cut/copy/paste MUST continue to work unchanged after the
  UI controls are added.

### Key Entities *(include if data involved)*

- **Clipboard**: The session-scoped, in-memory holder of the most recently cut or copied element(s).
  It is independent of the operating-system clipboard and is not persisted with the report. (Already
  exists; this feature only adds ways to fill and read it from the UI.)
- **Selection**: The set of currently selected elements (or a band, or the page). Determines whether
  Cut/Copy are available and what they act on. (Already exists.)
- **Report Element**: The unit copied/cut/pasted. A pasted element is a deep copy with a new
  identifier and an offset position. (Already exists.)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can complete a full cut-and-paste and a full copy-and-paste of an element using
  only the mouse (no keyboard), via the toolbar.
- **SC-002**: A user can complete a full cut/copy/paste using only the canvas context menu (no
  toolbar, no keyboard).
- **SC-003**: In every clipboard state combination (selection present/absent × clipboard empty/full),
  every clipboard control shows the correct enabled/disabled state.
- **SC-004**: Clipboard control labels and tooltips render correctly in 100% of the designer's
  supported UI languages.
- **SC-005**: All pre-existing clipboard behavior is preserved: keyboard shortcuts still work, paste
  still offsets and assigns fresh identifiers, and Cut/Paste remain single undoable steps (no
  regressions in the existing test suite).
- **SC-006**: Saved report files and exported/printed/preview output are byte-for-byte unchanged by
  this feature.

## Assumptions

- **Backend already exists**: The clipboard model, the cut/copy/paste/duplicate operations, the
  insert command used by paste, fresh-id assignment, paste offset/clamping, and keyboard shortcuts are
  already implemented. The user's note "create clipboard commands if needed" is satisfied by the
  existing command — no new clipboard command logic is required; the work is the two UI surfaces.
- **Paste placement is unchanged**: Paste keeps its current behavior of inserting offset copies into
  the source band; "paste at the cursor location" is out of scope.
- **Context menu contents**: The context menu's required items are Cut, Copy, Paste, Duplicate, and
  Delete (decided 2026-06-12). Duplicate and Delete reuse the designer's existing operations of the
  same name. Arrange (align/distribute/z-order) is intentionally left out of the context menu — it
  stays in the toolbar.
- **Clipboard scope is unchanged**: The clipboard remains session-scoped and in-memory; integration
  with the operating-system clipboard (pasting between separate app instances) is out of scope.
- **Supported languages**: The designer's existing set of UI languages — currently English (en),
  German (de), and Turkish (tr), per `JetPrintLocalizations.supportedLocales` — is the target; no
  new language is added by this feature. SC-004's "100% of supported languages" therefore means these
  three; if the supported set grows later, the l10n work expands with it.
- **Toolbar placement**: The clipboard controls join the existing toolbar command groups in a manner
  consistent with the current toolbar's responsive/compact behavior.

## Out of Scope

- Operating-system clipboard interoperability (copy/paste across separate application windows or other
  apps).
- Pasting at the pointer location or into a different band than the source.
- A clipboard history or multi-slot clipboard.
- Copying/pasting whole bands or the page itself (only elements).
- Any change to serialization, the report model, or the render/preview/export pipeline.
