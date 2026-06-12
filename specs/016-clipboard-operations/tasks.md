---
description: "Task list for Clipboard Operations in the Designer UI"
---

# Tasks: Clipboard Operations in the Designer UI

**Input**: Design documents from `/specs/016-clipboard-operations/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/clipboard-ui.md, quickstart.md

**Tests**: MANDATORY per Constitution Principle III (Test-First, NON-NEGOTIABLE). Each behavioral change is pinned by a FAILING test before implementation. Principle IV (WYSIWYG): this feature adds invocation surfaces only — no render-path change — so existing golden suites must stay green by construction (SC-006); no new goldens are added.

**Organization**: Tasks are grouped by user story (P1 → P2 → P3). The single blocking prerequisite (controller plumbing) is isolated in Phase 2 because both UI surfaces read the same two predicates it introduces.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 (toolbar), US2 (context menu), US3 (l10n/a11y). Setup/Foundational/Polish carry no story label.

## Path Conventions

Existing Dart pub workspace monorepo. Library code under `packages/jet_print/lib/src/designer/`; tests under `packages/jet_print/test/`. Run tests from repo root with `flutter test packages/jet_print` (note: `flutter` leaves cwd inside the package — always `cd` back to repo root for git).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish a green baseline so later red tests are unambiguous.

- [X] T001 Establish baseline: run `flutter test packages/jet_print` from repo root and confirm the existing clipboard suites are green — `test/designer/interaction/keyboard_clipboard_test.dart`, `test/designer/controller/bulk_commands_test.dart`, and the codec/golden suites — and confirm the backend ops `copy()/cut()/paste()/duplicate()/delete()` exist in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`. Record the pass count as the regression baseline (no code change).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Controller plumbing (contract C1) that BOTH UI surfaces depend on. Adds two read-only getters mirroring `canUndo`/`canRedo` and the one missing `notifyListeners()` so Paste re-enables after a mouse Copy.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete — US1 and US2 both read `canCopy`/`canPaste`.

- [X] T002 [P] Write FAILING unit test `packages/jet_print/test/designer/controller/clipboard_reactivity_test.dart`: (a) `copy()` notifies its listeners exactly once AND leaves `canUndo` unchanged (no undo entry); (b) `canCopy`/`canPaste` track the data-model truth table across the sequence empty → select → copy → cut; (c) after `cut()`, `canCopy` is `false` (selection emptied) and `canPaste` is `true` (edge case "Selection lost after Cut"). Confirm it fails (getters/notify absent today).
- [X] T003 In `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`: add `bool get canCopy => _document.selection.ids.isNotEmpty;` and `bool get canPaste => !_clipboard.isEmpty;` (with dartdoc), and make `copy()` call `notifyListeners()` after filling the clipboard WITHOUT creating an undo entry (do not route through `_commit`). Make T002 green. (FR-004, FR-005, FR-007, FR-009; research D1)
- [X] T004 [P] Update `packages/jet_print/test/public_api_test.dart` to record the two new exported getters `canCopy` and `canPaste`; confirm no other public surface changed. (Constitution I)

**Checkpoint**: Controller reactively exposes `canCopy`/`canPaste`; Copy notifies. Both UI surfaces can now be built against a stable, tested predicate pair.

---

## Phase 3: User Story 1 - Cut / Copy / Paste from the toolbar (Priority: P1) 🎯 MVP

**Goal**: A fenced Cut / Copy / Paste `_IconButton` group in the designer top bar (after the History group), fully mouse-operable, localized, and accessible.

**Independent Test**: Open the designer, select an element, click toolbar Copy then toolbar Paste — an offset duplicate appears and is selected, no keyboard used (SC-001).

### Tests for User Story 1 (write first, ensure they FAIL)

- [X] T005 [US1] Extend `packages/jet_print/test/designer/top_bar_test.dart` with FAILING widget tests (find by keys `jet_print.designer.action.cut|copy|paste`): all three present; nothing selected ⇒ Cut & Copy disabled; clipboard empty ⇒ Paste disabled (SC-003); select element ⇒ Copy enabled, tap Copy ⇒ Paste becomes enabled with NO further interaction (verifies the D1 notify path through `DesignerScope`); tap Copy then Paste ⇒ element count +1 and pasted copy selected (SC-001); tap Cut ⇒ element removed, then Paste ⇒ re-inserted (Acceptance 1.2); tap Cut then Undo ⇒ document restored as a single step (Acceptance 1.5); tooltip contains the localized label and the platform shortcut glyph (⌘ on apple, `Ctrl+` otherwise) (FR-014). Confirm failing.

### Implementation for User Story 1

- [X] T006 [P] [US1] Add toolbar tooltip keys to the three ARB files `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`: `actionCutTooltip`, `actionCopyTooltip`, `actionPasteTooltip` (each localized, phrased to carry the action name; shortcut glyph composed at render time) with `@`-descriptions. Regenerate localizations if the project uses generated `AppLocalizations`.
- [X] T007 [US1] In `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart`: add a platform shortcut-glyph helper (⌘ on `defaultTargetPlatform` apple, `Ctrl+` otherwise) and a fenced Cut / Copy / Paste `_IconButton` group immediately after the History (Undo/Redo) group, with a divider matching the existing fencing. Wire Cut/Copy enabled iff `controller.canCopy`, Paste enabled iff `controller.canPaste`; onPressed → `controller.cut()/copy()/paste()`. Assign the keys from contract C1, set localized `ShadTooltip` text composed with the shortcut hint, and a `Semantics` name per button (FR-001, FR-003, FR-004, FR-005, FR-013, FR-014, FR-015). Make T005 green.

**Checkpoint**: Toolbar clipboard group fully functional, localized, accessible, and independently testable — MVP deliverable.

---

## Phase 4: User Story 2 - Cut / Copy / Paste from a right-click context menu (Priority: P2)

**Goal**: A net-new canvas context menu (Cut, Copy, Paste, Duplicate, Delete) opened on secondary-click, with FR-010 selection resolution before the menu shows.

**Independent Test**: Right-click an element → Copy; right-click again → Paste — an offset duplicate appears, no toolbar or keyboard used (SC-002).

### Tests for User Story 2 (write first, ensure they FAIL)

- [X] T008 [US2] Create FAILING widget tests `packages/jet_print/test/designer/canvas/context_menu_test.dart` (keys `jet_print.designer.canvas.contextMenu`, `jet_print.designer.menu.cut|copy|paste|duplicate|delete`): right-click an element ⇒ menu opens and that element is selected (Acceptance 2.1); menu Copy then reopen + menu Paste ⇒ offset duplicate inserted + selected (Acceptance 2.2, SC-002); right-click empty canvas with nothing selected ⇒ Cut/Copy/Duplicate/Delete disabled, Paste enabled iff clipboard has content (Acceptance 2.3); multi-select two elements then right-click empty canvas ⇒ selection preserved and Cut acts on both (Acceptance 2.6 / FR-010); right-click an unselected element while another is selected ⇒ selection replaced with the clicked element (edge case); open then dismiss (tap-away / Escape) ⇒ no document change, element count unchanged (Acceptance 2.4 / FR-011); menu Duplicate ⇒ offset copy inserted + selected as one undo step, menu Delete ⇒ selection removed as one undo step (Acceptance 2.5 / FR-005a). Confirm failing.
- [X] T009 [P] [US2] Add the two menu-only label keys `menuDuplicate`, `menuDelete` to `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb` with `@`-descriptions (menu Cut/Copy/Paste reuse the existing action labels). Regenerate localizations if applicable.

### Implementation for User Story 2

- [X] T010 [US2] In `packages/jet_print/lib/src/designer/canvas/design_canvas.dart`: add an `onSecondaryTapDown` handler that resolves selection via the existing `hitTestElement` (`packages/jet_print/lib/src/designer/canvas/hit_testing.dart`) BEFORE the menu opens — select an unselected element, preserve an existing multi-selection that contains the clicked element, and leave selection unchanged on empty canvas (FR-010). Wrap the canvas content in a `ShadContextMenuRegion` (key `jet_print.designer.canvas.contextMenu`) with five `ShadContextMenuItem`s (Cut, Copy, Paste, Duplicate, Delete) reusing the Arrange menu's widget; enable Cut/Copy/Duplicate/Delete iff `controller.canCopy` and Paste iff `controller.canPaste` (FR-005a, FR-012); each item invokes the matching controller op and closes the menu (FR-003, FR-011); add a trailing shortcut-hint affordance (Cut ⌘X, Copy ⌘C, Paste ⌘V, Duplicate ⌘D, Delete) reusing the US1 glyph helper, plus a `Semantics` name per item (FR-002, FR-014a, FR-015). Make T008 green.

**Checkpoint**: Context menu fully functional and independently testable; US1 and US2 both work via identical predicates (FR-012).

---

## Phase 5: User Story 3 - Discoverable, accessible, localized affordances (Priority: P3)

**Goal**: Verify (and close any gaps in) localization across en/de/tr, accessible names, and platform shortcut hints across BOTH surfaces.

**Independent Test**: Hover each clipboard control for a localized tooltip with shortcut hint; switch UI language and confirm labels/tooltips update; inspect accessible names in the semantics tree.

### Tests for User Story 3 (write first, ensure they FAIL/expose gaps)

- [X] T011 [US3] Create `packages/jet_print/test/designer/clipboard_l10n_test.dart`, parametrized over en/de/tr: the three toolbar tooltips and five menu labels resolve to non-empty, locale-correct strings with no missing-key fallback (SC-004); every toolbar button and menu item exposes a `Semantics` label (find by semantics) (FR-015); the shortcut glyph is platform-correct (⌘ on apple vs `Ctrl+` otherwise) in both toolbar tooltips and menu trailing (FR-014, FR-014a). Confirm it fails for any locale/semantics/glyph gap left by US1/US2.

### Implementation for User Story 3

- [X] T012 [US3] Close any gaps surfaced by T011: complete/correct the de/tr translations in the three ARB files, ensure every toolbar button and menu item has a `Semantics` name, and ensure the shortcut-glyph helper renders the platform-correct glyph in both the toolbar tooltips (`designer_top_bar.dart`) and the menu trailing (`design_canvas.dart`). Make T011 green. (FR-013, FR-014, FR-014a, FR-015, SC-004)

**Checkpoint**: All three stories independently functional, localized, and accessible.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Regression guard (C5) and developer-experience polish. WYSIWYG is verified, not modified.

- [X] T013 [P] Confirm regression suites unchanged and green: `packages/jet_print/test/designer/interaction/keyboard_clipboard_test.dart` and `packages/jet_print/test/designer/controller/bulk_commands_test.dart` (FR-017, SC-005) — no edits expected.
- [X] T014 [P] Confirm the codec and golden suites under `packages/jet_print/test/` stay green with no golden moves — saved files and preview/export/print output byte-identical (FR-016, SC-006).
- [X] T015 [P] Developer experience: add a `## Unreleased` entry to `packages/jet_print/CHANGELOG.md` (toolbar clipboard group + canvas context menu); confirm dartdoc on `canCopy`, `canPaste`, and the updated `copy()` (note: notifies without an undo entry); demonstrate both surfaces on the playground invoice in `apps/jet_print_playground`.
- [X] T016 Final gate: from repo root run `dart format` (clean) and `dart analyze` (zero warnings) on `packages/jet_print`, then `flutter test packages/jet_print` (all green, pass count ≥ T001 baseline + new tests), and walk the quickstart.md mouse-only steps in the playground.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup. BLOCKS US1 and US2 (both read `canCopy`/`canPaste`).
- **US1 (Phase 3)** and **US2 (Phase 4)**: Both depend only on Foundational. US2 reuses the shortcut-glyph helper introduced in US1 (T007) — run US1 before US2, or extract the helper first if parallelizing.
- **US3 (Phase 5)**: Depends on US1 and US2 existing (it verifies their controls across locales/semantics).
- **Polish (Phase 6)**: Depends on all desired stories complete.

### User Story Dependencies

- **US1 (P1)**: After Foundational. No dependency on other stories. ← MVP.
- **US2 (P2)**: After Foundational. Independently testable; reuses US1's glyph helper (soft dependency).
- **US3 (P3)**: After US1 + US2 (verification + gap-closing across both surfaces).

### Within Each Story

- Tests are written and confirmed FAILING before implementation (Constitution III).
- ARB keys ([P], different files) can land alongside or just before the widget wiring that renders them.

### Parallel Opportunities

- Phase 2: T002 (test) and T004 (public_api) are [P]; T003 implements between them (T003 needs T002 red first, T004 is independent).
- Phase 3: T006 (ARB, [P]) independent of T005 (test); T007 makes the test green.
- Phase 4: T009 (ARB, [P]) independent of T008 (test); T010 makes the test green.
- Phase 6: T013, T014, T015 are all [P] (distinct files/suites); T016 is the serial final gate.

---

## Parallel Example: Phase 2 (Foundational)

```bash
# T002 and T004 touch different files and can be authored together:
Task: "Write failing unit test in packages/jet_print/test/designer/controller/clipboard_reactivity_test.dart"
Task: "Update packages/jet_print/test/public_api_test.dart to record canCopy/canPaste"
# Then T003 implements the getters + copy() notify to turn T002 green.
```

## Parallel Example: User Story 1

```bash
# ARB keys are independent of the failing widget test:
Task: "Add actionCut/Copy/PasteTooltip keys to jet_print_{en,de,tr}.arb"   # T006 [P]
Task: "Extend top_bar_test.dart with failing clipboard-group widget tests"  # T005
# Then T007 wires the _IconButton group to turn T005 green.
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup → green baseline.
2. Phase 2 Foundational → `canCopy`/`canPaste` + Copy notify (CRITICAL, blocks everything).
3. Phase 3 US1 → toolbar Cut/Copy/Paste group.
4. **STOP and VALIDATE**: mouse-only copy→paste from the toolbar (SC-001). Demo-ready MVP.

### Incremental Delivery

1. Setup + Foundational → reactive predicates ready.
2. US1 → toolbar group → demo (MVP).
3. US2 → context menu → demo.
4. US3 → localized/accessible affordances verified across en/de/tr → demo.
5. Polish → regression + WYSIWYG confirmation + DX.

---

## Notes

- [P] = different files, no incomplete dependencies. [Story] maps each task to its user story for traceability.
- This feature adds **invocation surfaces only**: no model, codec, schema, or render-pipeline change — goldens stay green by construction (SC-006).
- The single subtlest correctness risk is the D1 notify: without `copy()` notifying, Paste silently fails to re-enable after a mouse Copy. It is pinned first by T002.
- Verify each test FAILS before implementing. Commit after each task or logical group. Run git from repo root (`flutter` drifts cwd into the package).
