# Phase 1 — Contract: Clipboard UI Surfaces

Behavioral contracts for the two new surfaces and the backend plumbing they require. Each contract
maps to functional requirements and to a test group. **All operations route through the existing
controller methods — this feature MUST NOT add a second clipboard implementation (FR-003).**

Stable widget keys (for tests), following the existing
`jet_print.designer.action.*` convention:

| Control | Key |
|---------|-----|
| Toolbar Cut | `jet_print.designer.action.cut` |
| Toolbar Copy | `jet_print.designer.action.copy` |
| Toolbar Paste | `jet_print.designer.action.paste` |
| Context menu region | `jet_print.designer.canvas.contextMenu` |
| Menu item Cut | `jet_print.designer.menu.cut` |
| Menu item Copy | `jet_print.designer.menu.copy` |
| Menu item Paste | `jet_print.designer.menu.paste` |
| Menu item Duplicate | `jet_print.designer.menu.duplicate` |
| Menu item Delete | `jet_print.designer.menu.delete` |

---

## C1 — Controller plumbing (backend, the only non-UI change)

**Contract**:
- `copy()` MUST call `notifyListeners()` after filling the clipboard, and MUST NOT create an undo
  entry (`canUndo` unchanged across a Copy). *(FR-007, FR-009; research D1)*
- `canCopy` MUST return `selection.ids.isNotEmpty`. *(FR-004, FR-005a)*
- `canPaste` MUST return `!clipboard.isEmpty` and MUST flip `false→true` on the first Copy/Cut of a
  session and stay `true` thereafter (clipboard never re-empties). *(FR-005)*
- `cut()`, `paste()`, `duplicate()`, `delete()` behavior MUST remain unchanged. *(FR-003, FR-017)*

**Test group** (`test/designer/controller/clipboard_reactivity_test.dart`, unit — no widget tree):
- `copy()` notifies exactly once; `canUndo` unchanged after copy. *(Red today)*
- `canCopy`/`canPaste` track the truth table in [data-model.md](../data-model.md) across:
  empty→select→copy→cut sequences.
- After `cut()`, `canCopy` is `false` (selection emptied) and `canPaste` is `true` (edge case).
- Regression: existing `bulk_commands_test.dart` cut/copy/paste/duplicate assertions stay green
  (FR-017, SC-005).

---

## C2 — Toolbar clipboard group (User Story 1, P1)

**Contract**:
- The top bar MUST present **Cut, Copy, Paste** as distinct icon buttons, fenced as a group beside
  History (undo/redo). *(FR-001)*
- Cut and Copy MUST be enabled iff `controller.canCopy`; disabled otherwise. *(FR-004)*
- Paste MUST be enabled iff `controller.canPaste`; disabled when empty. *(FR-005)*
- Pressing Cut/Copy/Paste MUST invoke `controller.cut/copy/paste` respectively. *(FR-003)*
- Cut and Paste MUST each be a single undoable step; Undo MUST restore the prior state. *(FR-009)*
- Each button MUST expose a localized tooltip including its shortcut hint, and an accessible name.
  *(FR-013, FR-014, FR-015)*

**Test group** (`test/designer/top_bar_test.dart`, extend; widget):
- All three buttons present by key.
- Nothing selected ⇒ Cut & Copy disabled; clipboard empty ⇒ Paste disabled. (SC-003)
- Select element → Copy enabled; tap Copy → Paste becomes enabled **without further interaction**
  (verifies the D1 notify path through `DesignerScope`).
- Tap Copy then Paste (mouse only) ⇒ element count +1, the pasted copy is selected. (SC-001)
- Tap Cut ⇒ element removed + held; tap Paste ⇒ re-inserted. (Acceptance 1.2)
- Tap Cut then Undo ⇒ document restored (single step). (Acceptance 1.5)
- Tooltip text contains the localized label and the platform shortcut glyph (⌘ on apple,
  `Ctrl+` otherwise). (FR-014)

---

## C3 — Canvas context menu (User Story 2, P2)

**Contract**:
- Secondary-click (right-click) on the canvas MUST open a menu with **Cut, Copy, Paste, Duplicate,
  Delete**. *(FR-002)*
- Before the menu shows, selection MUST resolve per FR-010:
  - right-click an element **not** in selection ⇒ that element becomes the selection;
  - right-click an element **in** the current (multi-)selection ⇒ selection preserved;
  - right-click empty canvas ⇒ selection **unchanged** (never deselects). *(FR-010; clarified)*
- Item enablement MUST match the toolbar exactly: Cut/Copy/Duplicate/Delete iff `canCopy`; Paste
  iff `canPaste`. *(FR-005a, FR-012)*
- Each item MUST invoke the matching controller op and the menu MUST close after. *(FR-003)*
- Duplicate and Delete MUST each be one undoable step. *(FR-005a)*
- The menu MUST be dismissible without acting (click-away / dismiss key) and MUST NOT alter the
  document on dismissal. *(FR-011)*
- Each item MUST show its shortcut hint as a trailing affordance (Cut ⌘X, Copy ⌘C, Paste ⌘V,
  Duplicate ⌘D, Delete) and expose an accessible name. *(FR-014a, FR-015)*

**Test group** (`test/designer/canvas/context_menu_test.dart`, new; widget):
- Right-click an element ⇒ menu opens; the element is selected. (Acceptance 2.1)
- Menu Copy then (reopen) menu Paste ⇒ offset duplicate inserted + selected. (Acceptance 2.2, SC-002)
- Right-click empty canvas, nothing selected ⇒ Cut/Copy disabled, Paste enabled iff clipboard has
  content. (Acceptance 2.3)
- Multi-select two elements, right-click empty canvas ⇒ selection preserved; Cut acts on both.
  (Acceptance 2.6 / FR-010)
- Right-click an unselected element while another is selected ⇒ selection replaced with the clicked
  element. (edge case)
- Open menu then dismiss (tap away / Escape) ⇒ no document change, element count unchanged.
  (Acceptance 2.4 / FR-011)
- Menu Duplicate ⇒ offset copy inserted + selected (one undo step); menu Delete ⇒ selection removed
  (one undo step). (Acceptance 2.5 / FR-005a)

---

## C4 — Discoverability / localization / accessibility (User Story 3, P3)

**Contract**:
- Every clipboard control (toolbar + menu) MUST render a localized label/tooltip in **en, de, tr**.
  *(FR-013, SC-004)*
- Toolbar tooltips MUST indicate the keyboard shortcut; menu items MUST display the shortcut hint.
  *(FR-014, FR-014a)*
- Every control MUST expose an accessible name via `Semantics`. *(FR-015)*

**Test group** (`test/designer/clipboard_l10n_test.dart`, new; widget — parametrized over locales):
- For each of en/de/tr: the three toolbar tooltips and five menu labels resolve to non-empty,
  locale-correct strings (no missing-key fallback).
- Each toolbar button and menu item exposes a `Semantics` label (find by semantics).
- The shortcut glyph is platform-correct (⌘ vs Ctrl+) in tooltips and menu trailing.

---

## C5 — Invariants (regression guard; FR-016, FR-017, SC-005, SC-006)

**Contract**:
- Existing keyboard shortcuts (⌘/Ctrl+X/C/V/D, Delete) MUST continue to work unchanged. *(FR-017)*
- No serialization, report-model, or render/preview/export change. *(FR-016)*

**Test group** (existing suites — must stay green, no edits needed beyond `public_api_test`):
- `test/designer/interaction/keyboard_clipboard_test.dart` — unchanged, green. (FR-017, SC-005)
- Codec/golden suites — unchanged, green; saved files + preview/export byte-identical. (SC-006)
- `test/public_api_test.dart` — UPDATED to record the two new getters (`canCopy`, `canPaste`); no
  other exported surface added.
