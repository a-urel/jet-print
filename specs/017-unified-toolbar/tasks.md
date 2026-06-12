---
description: "Task list for Unified Context-Switching Toolbar"
---

# Tasks: Unified Context-Switching Toolbar

**Input**: Design documents from `/specs/017-unified-toolbar/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/unified-toolbar.md, quickstart.md

**Tests**: MANDATORY for this project (Constitution III — Test-First, NON-NEGOTIABLE). Every story
writes its tests FIRST and confirms they FAIL before implementation. No render-path change is allowed
(Constitution IV), so all existing report goldens MUST stay green by construction.

**Organization**: Tasks are grouped by user story (P1 → P2 → P3) so each story is independently
implementable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 / US2 / US3 (Setup, Foundational, Polish carry no story label)

## Path Conventions

Existing Dart pub-workspace monorepo. Library code under `packages/jet_print/lib/src/designer/`,
tests under `packages/jet_print/test/`. All commands run from the repository root; tests via
`flutter test packages/jet_print`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish a known-green baseline before any change.

- [X] T001 Confirm baseline: run `flutter test packages/jet_print` from repo root and record it green; note the current `packages/jet_print/test/public_api_test.dart` surface snapshot so the two additive symbols are the only API delta later.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Localized strings and the empty shared shell that every user story composes.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 [P] Add keys `modeDesigner`, `modePreview`, `actionRenameTooltip`, `renameFieldLabel` (each with `@`-description) to `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, following the existing key style (`reportTitlePlaceholder`, `actionPreview`, `action*Tooltip`).
- [X] T003 [P] Add the same four keys translated to German in `packages/jet_print/lib/src/designer/l10n/jet_print_de.arb`.
- [X] T004 [P] Add the same four keys translated to Turkish in `packages/jet_print/lib/src/designer/l10n/jet_print_tr.arb`.
- [X] T005 Regenerate localizations (gen-l10n) and confirm `modeDesigner`/`modePreview`/`actionRenameTooltip`/`renameFieldLabel` resolve on `JetPrintLocalizations` in all three locales with English fallback (depends on T002–T004).
- [X] T006 Create the private shared shell `packages/jet_print/lib/src/designer/layout/unified_top_bar.dart` (`UnifiedTopBar`) that lays out three regions — left, center, and a caller-filled right actions slot — at the existing 52 px height with the shared styling, exposing named slot parameters and the responsive plumbing (label-collapse / scroll pass-through) used by both bars. No mode-switch or rename content yet — just the layout contract.

**Checkpoint**: Strings resolve and the empty shell exists; user stories can now compose it.

---

## Phase 3: User Story 1 - Switch between Designer and Preview from one toolbar (Priority: P1) 🎯 MVP

**Goal**: One toolbar shell rendered by both modes whose center two-segment Designer|Preview switch
emits a host switch-request (reusing `onPreviewRequested`/`onBack`); left name region and switch are
positionally identical across modes, only the right actions differ.

**Independent Test**: Open in Designer → switch shows Designer active + designer actions right; tap
Preview → `onPreviewRequested` fires; in preview the switch shows Preview active + preview actions
right; tap Designer → `onBack` fires; name+switch sit in the same place in both.

### Tests for User Story 1 (write FIRST, confirm they FAIL) ⚠️

- [X] T007 [P] [US1] Extend `packages/jet_print/test/designer/top_bar_test.dart`: designer shell renders the two-segment switch with **Designer** active; tapping **Preview** fires `onPreviewRequested(controller.template)` exactly once; the Preview segment is disabled when `onPreviewRequested == null`; tapping the already-active Designer segment is a no-op (C2.1, C2.2, C2.5).
- [X] T008 [P] [US1] Extend `packages/jet_print/test/designer/preview/jet_report_preview_test.dart`: preview shell renders the switch with **Preview** active; tapping **Designer** fires `onBack()` once; the Designer segment is disabled when `onBack == null` (C2.3, C2.4).
- [X] T009 [P] [US1] Create `packages/jet_print/test/designer/unified_toolbar_test.dart` with the region-parity group: pump the designer shell and the preview shell and assert the name region and the mode switch are found at equivalent positions/sizes in both and that both compose `UnifiedTopBar` (C1.1, C1.3, FR-001, SC-003); assert a very long report name truncates (ellipsis / clipped, no overflow) without displacing the mode switch or the right actions (spec Edge Cases — long names).
- [X] T009b [P] [US1] Extend `packages/jet_print/test/designer/top_bar_test.dart` (or `unified_toolbar_test.dart`): after making an undoable edit, tapping the **Preview** segment fires `onPreviewRequested` **without** mutating the controller — `controller.template`, `canUndo`/`canRedo`, and the current selection are unchanged across the switch request (FR-005, SC-002).

### Implementation for User Story 1

- [X] T010 [US1] Create the private `packages/jet_print/lib/src/designer/layout/workspace_mode_switch.dart`: a two-segment Designer|Preview control plus `enum WorkspaceMode { designer, preview }`; highlight the active segment (non-interactive), enable the inactive segment only when its switch callback is wired, and attach Semantics names from `modeDesigner`/`modePreview` (FR-002, FR-014). The inactive segment invokes a generic `onSwitchRequested` callback that the composing bars bind to the existing `onPreviewRequested` (designer) / `onBack` (preview) — no new public mode API is introduced.
- [X] T011 [US1] Refactor `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart` to compose `UnifiedTopBar`: report name (plain text + placeholder) in the left region, `WorkspaceModeSwitch` in the center with `mode: WorkspaceMode.designer` and the Preview segment wired to `onPreviewRequested`, and the existing designer action groups placed into the right slot (depends on T006, T010).
- [X] T012 [US1] Refactor `packages/jet_print/lib/src/designer/preview/jet_report_preview.dart` to compose `UnifiedTopBar`: report name (from `RenderedReport.title`, placeholder fallback) in the left region, `WorkspaceModeSwitch` in the center with `mode: WorkspaceMode.preview` and the Designer segment wired to `onBack`, and the existing preview action groups placed into the right slot (depends on T006, T010).
- [X] T013 [US1] Run the US1 tests (T007–T009b) and confirm green; in `apps/jet_print_playground` confirm left+center parity across modes AND that editing → Preview → Designer preserves edits, undo/redo, and selection.

**Checkpoint**: The unified toolbar round-trips Designer↔Preview from one shell — MVP demonstrable.

---

## Phase 4: User Story 2 - Rename the report inline from the toolbar (Priority: P2)

**Goal**: An edit affordance beside the name (both modes) opens an inline field; Enter/blur(non-empty)
commit, Escape and blur(empty) cancel, empty-Enter → placeholder. Designer commits via undoable
`controller.rename`; preview commits via `onRename` plus an immediate local displayed-name.

**Independent Test**: Activate edit, change text, confirm → name updates and travels forward; cancel →
name unchanged; works identically in Preview; empty confirm shows the placeholder.

### Tests for User Story 2 (write FIRST, confirm they FAIL) ⚠️

- [X] T014 [P] [US2] Create `packages/jet_print/test/designer/controller/rename_test.dart`: `rename(x)` sets `controller.template.name == x`; it is a single undoable step (one `undo()` restores the prior name and selection); it notifies listeners exactly once; `rename(currentName)` records no history entry; a renamed template round-trips losslessly through `JetReportFormat` with `schemaVersion` still 1; an empty/whitespace name stores as `''` (C4).
- [X] T015 [P] [US2] Extend `packages/jet_print/test/designer/top_bar_test.dart` with the rename group: the edit affordance is present; activating it pre-fills and focuses the field; Enter commits via `controller.rename` and shows the value; Escape cancels; blur with a non-empty trimmed value commits; blur with an empty value cancels; empty-Enter commits `''` and shows the placeholder; `undo()` restores the prior name (C3.1–C3.7, C3.9 designer).
- [X] T016 [P] [US2] Extend `packages/jet_print/test/designer/preview/jet_report_preview_test.dart` with the rename group: the affordance shows only when `onRename` is wired (hidden when null); committing calls `onRename(value)` once and updates the locally-displayed name immediately without mutating the passed `RenderedReport`; Escape cancels; an empty stored name shows the placeholder (C3.1, C3.8, C3.9 preview).
- [X] T017 [P] [US2] Update `packages/jet_print/test/public_api_test.dart` to record exactly two additive symbols — `JetReportDesignerController.rename(String)` and `JetReportPreview.onRename` — and assert no other surface change.

### Implementation for User Story 2

- [X] T018 [P] [US2] Create `packages/jet_print/lib/src/designer/controller/commands/set_template_name_command.dart`: an `EditCommand` with `final String newName`, `label = 'Rename'`, `apply` returning `before.withTemplate(before.template.copyWith(name: newName))`, relying on the existing `_commit` identity guard for the no-op-on-same-name case (data-model §2).
- [X] T019 [US2] Add `void rename(String name) => _commit(SetTemplateNameCommand(name));` to `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` with dartdoc noting single-undo-step and empty→placeholder semantics (depends on T018).
- [X] T020 [US2] Upgrade the left region of `packages/jet_print/lib/src/designer/layout/unified_top_bar.dart` to host the inline-rename affordance + `ShadInput` editor implementing the state machine (activate → pre-filled focused; Enter/blur-non-empty commit; Escape/blur-empty cancel; empty stored → localized placeholder), with Semantics from `actionRenameTooltip`/`renameFieldLabel`, exposing a commit callback to the composing bar (FR-006–FR-010, FR-014). Ensure the displayed name truncates with ellipsis (`TextOverflow.ellipsis`, bounded width) so a long name never pushes the switch/actions off-screen (spec Edge Cases).
- [X] T021 [P] [US2] Wire `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart` so the shell's rename commit calls `controller.rename(value)` through the ambient `DesignerScope` (depends on T019, T020).
- [X] T022 [P] [US2] Add `final ValueChanged<String>? onRename;` and a local displayed-name (seeded from `RenderedReport.title`) to `packages/jet_print/lib/src/designer/preview/jet_report_preview.dart`; on commit call `onRename(value)` and update the local name; hide the edit affordance when `onRename == null` (depends on T020; D5).
- [X] T023 [US2] Run T014–T017 and confirm green; confirm the existing codec/golden suites remain green (no serialization or render change).

**Checkpoint**: Inline rename works (undoable) in Designer and (callback-based) in Preview.

---

## Phase 5: User Story 3 - Mode-appropriate actions on the right (Priority: P3)

**Goal**: The right slot shows only the active mode's actions (exclusive by construction) and degrades
gracefully when narrow without ever hiding the name region or the mode switch.

**Independent Test**: Designer shows editing actions and no preview-only actions; Preview shows
viewing actions and no designer-only actions; at narrow widths the name + switch stay visible while
actions collapse/scroll.

### Tests for User Story 3 (write FIRST, confirm they FAIL) ⚠️

> NOTE: C5 exclusivity is structural (each shell passes only its own action group during US1), so T024/T025 act as regression guards and may pass on first run rather than failing first. T026 (responsive + a11y/l10n) is genuine fail-first.

- [X] T024 [P] [US3] Extend `packages/jet_print/test/designer/top_bar_test.dart`: assert the designer right slot shows the editing actions (history, clipboard, zoom, view toggles, arrange, open/save/export) and that **no** preview-only signature action (e.g. page navigation) is present (C5.1, SC-005).
- [X] T025 [P] [US3] Extend `packages/jet_print/test/designer/preview/jet_report_preview_test.dart`: assert the preview right slot shows the viewing actions (export/print, zoom, page nav) and that **no** designer-only signature action (e.g. undo/redo) is present (C5.2, SC-005).
- [X] T026 [P] [US3] Extend `packages/jet_print/test/designer/unified_toolbar_test.dart` with the responsive + a11y/l10n groups: at a narrow width the name region and mode switch remain present and hit-testable while action labels collapse/scroll (C6); each of the four new keys resolves in en/de/tr and the switch segments + edit affordance carry accessible names and keyboard activation (C7).

### Implementation for User Story 3

- [X] T027 [US3] In `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart`, ensure the right slot carries the full editing group exclusively and that the existing `_compactWidth`/`_scrollWidth` breakpoints are preserved through the shell so labels collapse/scroll without touching the name/switch regions (C6.1).
- [X] T028 [US3] In `packages/jet_print/lib/src/designer/preview/jet_report_preview.dart`, ensure the right slot carries the viewing group exclusively and the preview's responsive behavior is preserved through the shell (C6.1).
- [X] T029 [US3] Run T024–T026 and confirm green (exclusivity, responsive degradation, a11y/l10n).

**Checkpoint**: Each mode is uncluttered and the toolbar stays usable when narrow.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T030 [P] Add dartdoc to `rename` and `onRename` and update `packages/jet_print/CHANGELOG.md` (unified toolbar + inline rename + mode switch).
- [X] T031 [P] Run `dart analyze` (zero warnings) and `dart format` on the changed files.
- [X] T032 Update `apps/jet_print_playground/lib/main.dart` to wire `onRename: controller.rename` and demonstrate the rename → switch-to-preview → see-new-name round-trip (quickstart §"end-to-end round-trip").
- [X] T033 Run the full `flutter test packages/jet_print` suite green and confirm all existing report goldens are unchanged (byte-identical) per Constitution IV.
- [X] T034 Execute the `quickstart.md` walkthrough manually in the playground (designer rename + undo, switch to Preview, preview rename via `onRename`, switch back with edits intact).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup; **blocks all user stories**. T002–T004 are parallel; T005 depends on them; T006 is independent of the ARBs.
- **User Stories (Phase 3–5)**: all depend on Foundational. US2 and US3 build on the US1 shell composition (US1 introduces the shell-composed bars that US2's rename and US3's actions extend), so the recommended order is P1 → P2 → P3.
- **Polish (Phase 6)**: depends on the desired stories being complete.

### User Story Dependencies

- **US1 (P1)**: needs the shell (T006) + mode switch (T010); otherwise self-contained. The MVP.
- **US2 (P2)**: needs the shell-composed bars from US1 (T011/T012) to host the rename affordance; its controller/command work (T018/T019) is independent and can start right after Foundational.
- **US3 (P3)**: refines the right slot already filled during US1; mostly verification + responsive preservation.

### Within Each User Story

- Tests are written and MUST FAIL before implementation.
- Command (T018) before controller mutator (T019); shell rename UI (T020) before bar wiring (T021/T022).
- Each story ends green before moving to the next priority.

### Parallel Opportunities

- Foundational: T002, T003, T004 in parallel (three ARB files).
- US1 tests: T007, T008, T009, T009b in parallel (different test files / independent groups).
- US2 tests: T014, T015, T016, T017 in parallel (four different files).
- US2 impl: T021 and T022 in parallel (different files) once T020 lands.
- US3 tests: T024, T025, T026 in parallel.
- Polish: T030 and T031 in parallel.

---

## Parallel Example: User Story 1 tests

```bash
# Launch the three US1 test tasks together (different files):
Task: "Extend top_bar_test.dart — designer mode switch (Preview→onPreviewRequested)"
Task: "Extend jet_report_preview_test.dart — preview mode switch (Designer→onBack)"
Task: "Create unified_toolbar_test.dart — left+center region parity across modes"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup → known-green baseline.
2. Phase 2 Foundational → strings + empty shell (blocks everything).
3. Phase 3 US1 → one shell, both modes, working mode switch.
4. **STOP and VALIDATE**: round-trip Designer↔Preview from the unified toolbar; region parity holds.
5. Demo the unified toolbar.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 → unified toolbar + mode switch (MVP) → demo.
3. US2 → inline rename in both modes (undoable in designer) → demo.
4. US3 → exclusive mode actions + responsive polish → demo.

---

## Notes

- [P] = different files, no dependency on incomplete tasks.
- Two — and only two — new public symbols: `JetReportDesignerController.rename` and `JetReportPreview.onRename`. The shell, the mode switch, the `WorkspaceMode` enum, and the rename command stay private under `src/` (Constitution I).
- No render-path or serialization change: `kReportSchemaVersion` stays 1 and all report goldens stay byte-identical (Constitution IV/V).
- FR-005/SC-002 (edits preserved across a switch) is pinned on the library side by T009b (a switch request never mutates the controller); the full host round-trip (Navigator push/pop keeping the live controller) is host-owned and confirmed manually via T013/T034.
- Empty/invalid-report preview and rapid mode toggling are pre-existing host/preview behaviors unchanged by this feature; no new tasks cover them by design.
- Verify every story's tests fail before implementing; commit after each task or logical group.
