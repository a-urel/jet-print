---
description: "Task list for Report Designer Main Layout"
---

# Tasks: Report Designer Main Layout

**Input**: Design documents from `/specs/002-report-designer-layout/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/designer-layout-api.md, quickstart.md

**Tests**: MANDATORY for jet-print per Constitution Principle III (Test-First, NON-NEGOTIABLE) and Principle IV (golden tests for rendered output). Every test task is written and MUST FAIL before its implementation tasks begin.

**Organization**: Tasks are grouped by user story (US1–US4) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1, US2, US3, US4)
- All paths are repository-relative from `jet-print/` (workspace root)

## Path Conventions

- **Library** (the product): `packages/jet_print/`
- **Tester app** (the consumer): `apps/jet_print_tester/`
- **This feature's library code**: `packages/jet_print/lib/src/designer/`
- **This feature's library tests**: `packages/jet_print/test/designer/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add localization dependencies and tooling config so the gen-l10n pipeline can run.

- [X] T001 [P] Add `flutter_localizations` (SDK) + `intl` dependencies and set `flutter: generate: true` in `packages/jet_print/pubspec.yaml`
- [X] T002 [P] Add `flutter_localizations` (SDK) dependency in `apps/jet_print_tester/pubspec.yaml` (consumer needs `GlobalMaterial/Widgets/Cupertino` delegates)
- [X] T003 [P] Create `packages/jet_print/l10n.yaml` with `arb-dir: lib/src/designer/l10n`, `template-arb-file: jet_print_en.arb`, `output-localization-file: jet_print_localizations.dart`, `output-class: JetPrintLocalizations`, `synthetic-package: false`
- [X] T004 [P] Add `analyzer: exclude:` entry for `**/l10n/jet_print_localizations*.dart` in `analysis_options.yaml` (keep the zero-warning gate over generated output)
- [X] T005 Run `flutter pub get` at the workspace root to resolve the new dependencies (depends on T001–T004)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the localized-string seam every region widget depends on (FR-016). The English ARB template + generated delegate + its public export MUST exist before any region widget can source a non-hard-coded label.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T006 Create the English ARB template `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb` with all designer-chrome keys (default/fallback): `reportTitlePlaceholder`; `actionPreview`/`actionSave`/`actionExport` (+ tooltip keys); `tabDataSource`/`tabOutline`/`tabProperties`; `toolboxLabel` + element entries (`toolboxLabelEntry`/`toolboxTextEntry`/`toolboxTableEntry`/`toolboxImageEntry`); `panelDataSourceHint`/`panelOutlineHint`/`panelPropertiesHint`/`surfaceEmptyHint` (per data-model.md)
- [X] T007 Generate `JetPrintLocalizations` by running `flutter gen-l10n` (or `flutter pub get`) and verify `packages/jet_print/lib/src/designer/l10n/jet_print_localizations.dart` is produced as real source (depends on T006)
- [X] T008 Export `JetPrintLocalizations` (class + static `delegate` + `supportedLocales`) from `packages/jet_print/lib/jet_print.dart`, preserving existing `JetPrintPlaceholder`/`jetPrintVersion` exports (depends on T007)

**Checkpoint**: The localization delegate is generated and exported. Region widgets can now read localized chrome strings; all user stories may begin.

---

## Phase 3: User Story 1 - See the full designer workspace at a glance (Priority: P1) 🎯 MVP

**Goal**: Render the complete designer shell — top bar, left toolbox, center design surface, right tabbed panel — inside one resizable, collapsible, theme-driven frame, all regions visible simultaneously at desktop width with the surface occupying the largest share.

**Independent Test**: Launch the tester app; confirm all four regions are present and correctly positioned at default desktop width with the surface largest; toggle light/dark and confirm every region adopts the shadcn theme; drag splitters to resize side regions to their minimums; narrow the window below the breakpoint and confirm side regions collapse to rails and re-expand.

### Tests for User Story 1 (write FIRST, must FAIL before implementation) ⚠️

- [X] T009 [P] [US1] Extend the public-API import test in `packages/jet_print/test/public_api_test.dart` to reference `JetReportDesigner` through `package:jet_print/jet_print.dart` (proves the exported surface is sufficient)
- [X] T010 [P] [US1] Region-presence widget test in `packages/jet_print/test/designer/jet_report_designer_test.dart`: pump `JetReportDesigner` in a `ShadApp` at desktop width and assert top bar, toolbox, design surface, and right panel are all found, with the surface occupying the largest horizontal share and the full layout fitting the default desktop width with no horizontal overflow/scrolling (FR-001/002/003, SC-004, US1 Acceptance 1–2)
- [X] T011 [P] [US1] Responsive-collapse widget test in `packages/jet_print/test/designer/responsive_collapse_test.dart`: pump below the 1024px breakpoint and assert both side regions collapse to icon rails with a visible expand affordance, and that expanding restores the panel (FR-011/FR-014, SC-004)
- [X] T011a [US1] Splitter-resize widget test in `packages/jet_print/test/designer/responsive_collapse_test.dart` (same file as T011 — author together, not parallel): at desktop width, drag the toolbox↔surface and surface↔right-panel splitters and assert each side region stops at its enforced minimum width while the surface absorbs the remaining space (FR-013, SC-004)
- [X] T012 [P] [US1] Light/dark golden test in `packages/jet_print/test/designer/goldens/jet_report_designer_light_dark_test.dart`: capture the shell in both theme variants, extending the WYSIWYG harness pattern from `jet_print_placeholder_test.dart` (SC-003)

### Implementation for User Story 1

- [X] T013 [P] [US1] Create `DesignerTopBar` (private) in `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart`: horizontal strip with localized report-title placeholder + ≥1 `ShadButton.ghost` action (non-functional `onPressed`), all captions/tooltips from `JetPrintLocalizations` (FR-001/FR-015/FR-016)
- [X] T014 [P] [US1] Create `DesignerToolbox` (private) in `packages/jet_print/lib/src/designer/layout/designer_toolbox.dart`: left-docked, independently scrollable palette container shell with a localized header (FR-002/FR-010); sample entries added in US3
- [X] T015 [P] [US1] Create `DesignerSurface` (private) in `packages/jet_print/lib/src/designer/layout/designer_surface.dart`: center primary area showing a bounded page/canvas placeholder distinct from chrome, independently scrollable, never a blank void (FR-003/FR-010)
- [X] T016 [P] [US1] Create `DesignerRightPanel` (private) in `packages/jet_print/lib/src/designer/layout/designer_right_panel.dart`: `ShadTabs<String>` container with three localized captions in order Data Source / Outline / Properties (tab bodies stubbed; switching wired in US2) (FR-004/FR-016)
- [X] T017 [US1] Create the shell `JetReportDesigner` (public `StatefulWidget`, no required params) in `packages/jet_print/lib/src/designer/jet_report_designer.dart`: compose the four regions in a frame using `ShadResizablePanelGroup` (horizontal) inside a `LayoutBuilder`; ≥1024px → three resizable panels honoring min widths with the surface absorbing the remainder (FR-013); <1024px → icon rails + overlay expand per side, holding collapse + active-tab state (FR-011/FR-014); read `ShadTheme` (FR-008/009); add dartdoc noting layout-only scope (Principle VI) (depends on T013–T016; verified by T010, T011, T011a)
- [X] T018 [US1] Export `JetReportDesigner` from `packages/jet_print/lib/jet_print.dart` (depends on T017)
- [X] T019 [US1] Render `JetReportDesigner` as `home` in `apps/jet_print_tester/lib/main.dart`, wiring `localizationsDelegates: [JetPrintLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate]` and `supportedLocales: JetPrintLocalizations.supportedLocales`; keep the existing theme toggle (depends on T018)
- [X] T020 [US1] Update `apps/jet_print_tester/test/app_consumes_library_test.dart` to assert the app root renders exactly one `JetReportDesigner` inside a `ShadApp` (depends on T019)

**Checkpoint**: The full designer layout renders at desktop width in light and dark, resizes via splitters, and collapses/expands below the breakpoint. US1 is independently demoable as the MVP.

---

## Phase 4: User Story 2 - Switch between the three right-side context panels (Priority: P2)

**Goal**: The right tabbed panel switches among Data Source, Outline, and Properties; exactly one is active by default (Data Source), the active tab is highlighted, and selecting a tab shows its body while hiding the others.

**Independent Test**: With the designer shown, click each of the three right-side tabs in turn and confirm the correct placeholder body appears, the other two are hidden, and the active tab is highlighted.

### Tests for User Story 2 (write FIRST, must FAIL before implementation) ⚠️

- [X] T021 [P] [US2] Tab-switching widget test in `packages/jet_print/test/designer/right_panel_tabs_test.dart`: assert Data Source is active by default and its body is shown; tapping Outline then Properties swaps the visible body, hides the others, and marks the new tab active; exactly one body visible at all times; and each panel body scrolls independently when its content overflows, without displacing sibling regions (FR-004/005/006, FR-010, US2 Acceptance 1–3)

### Implementation for User Story 2

- [X] T022 [P] [US2] Create `DataSourcePanel` (private) stub body in `packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart` (localized placeholder hint; independently scrollable; sample field rows added in US3)
- [X] T023 [P] [US2] Create `OutlinePanel` (private) stub body in `packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart` (localized placeholder hint; independently scrollable; sample tree added in US3)
- [X] T024 [P] [US2] Create `PropertiesPanel` (private) stub body in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (localized placeholder hint; independently scrollable; sample rows added in US3)
- [X] T025 [US2] Wire the three panels as `ShadTab` bodies in `packages/jet_print/lib/src/designer/layout/designer_right_panel.dart` with Data Source default-active and show/hide handled by `ShadTabs` (FR-005/006) (depends on T022–T024)

**Checkpoint**: All three right-side tabs are reachable; switching shows the selected body and hides the others. US1 + US2 both work independently.

---

## Phase 5: User Story 3 - Recognize the purpose of each region from placeholder content (Priority: P3)

**Goal**: Each region shows representative placeholder content — toolbox element palette, Data Source field list, Outline element tree, Properties property rows, and a bounded empty page — so reviewers grasp each region's intended role at a glance.

**Independent Test**: Inspect each region and confirm theme-consistent placeholder content that plausibly represents its future purpose, with no empty gaps that misrepresent the region's role.

### Tests for User Story 3 (write FIRST, must FAIL before implementation) ⚠️

- [X] T026 [US3] Add representative-placeholder-content assertions in `packages/jet_print/test/designer/jet_report_designer_test.dart` (toolbox lists multiple element entries — Label/Text/Table/Image; surface shows a bounded empty-page placeholder) and in `packages/jet_print/test/designer/right_panel_tabs_test.dart` (each panel body shows content shaped like a field list / element tree / property rows) (FR-007, US3 Acceptance 1–3)

### Implementation for User Story 3

- [X] T027 [US3] Populate `DesignerToolbox` with a vertical palette of localized sample element entries (Label, Text, Table, Image, …) as placeholder rows in `packages/jet_print/lib/src/designer/layout/designer_toolbox.dart` (FR-002/FR-007)
- [X] T028 [P] [US3] Populate `DataSourcePanel` with sample field-list rows in `packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart` (sample data values illustrative, not translated) (FR-007)
- [X] T029 [P] [US3] Populate `OutlinePanel` with a sample hierarchical element tree (bands/sections/elements) in `packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart` (FR-007)
- [X] T030 [P] [US3] Populate `PropertiesPanel` with sample property rows (name/value pairs) in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (FR-007)
- [X] T031 [US3] Refine `DesignerSurface` into a clearly bounded empty-page mock distinct from surrounding chrome in `packages/jet_print/lib/src/designer/layout/designer_surface.dart` (FR-003/FR-007, empty-surface edge case)

**Checkpoint**: Every region is self-explanatory placeholder content. US1 + US2 + US3 independently functional.

---

## Phase 6: User Story 4 - Use the designer in my own language (Priority: P3)

**Goal**: All designer chrome renders in the active language (en/de/tr); switching language updates every visible label without restart; an unsupported locale or missing key falls back to English (never blank or a raw key).

**Independent Test**: With the designer shown, switch the active language among English, German, and Turkish and confirm all visible labels change with no blank/untranslated captions; select an unsupported locale and confirm English fallback.

### Tests for User Story 4 (write FIRST, must FAIL before implementation) ⚠️

- [X] T032 [P] [US4] Localization widget test in `packages/jet_print/test/designer/localization_test.dart`: render `JetReportDesigner` under `en`/`de`/`tr` and assert chrome captions match each language; render under an unsupported locale and with a deliberately missing key and assert English fallback (no blank, no raw key) (FR-016/017, SC-007, US4 Acceptance 1–3)

### Implementation for User Story 4

- [X] T033 [P] [US4] Create the German ARB `packages/jet_print/lib/src/designer/l10n/jet_print_de.arb` translating every key in the en template
- [X] T034 [P] [US4] Create the Turkish ARB `packages/jet_print/lib/src/designer/l10n/jet_print_tr.arb` translating every key in the en template
- [X] T035 [US4] Regenerate `JetPrintLocalizations` via `flutter gen-l10n` (or `flutter pub get`) so de + tr are compiled into the delegate (depends on T033–T034)
- [X] T036 [US4] Add a runtime language toggle (cycles en → de → tr) to `apps/jet_print_tester/lib/main.dart` that holds a `Locale` in state and drives `ShadApp.locale` via `setState`, analogous to the existing theme toggle (FR-018, SC-007) (depends on T035)

**Checkpoint**: Designer renders in all three languages with live switching and English fallback. All four user stories independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, longer-text resilience, and the full verification gate across all stories.

- [X] T037 [P] Verify the layout accommodates longer translated captions (e.g. German) via wrap/ellipsize without clipping adjacent controls across `designer_top_bar.dart`, `designer_right_panel.dart`, and `designer_toolbox.dart` (longer-text edge case)
- [X] T038 [P] Ensure dartdoc on all new public symbols (`JetReportDesigner`, `JetPrintLocalizations` export notes) describing purpose, usage, and layout-only scope (Principle VI)
- [X] T039 [P] Update `packages/jet_print/CHANGELOG.md` with the report designer shell + en/de/tr localization delegate
- [X] T040 Run `flutter analyze` and confirm zero warnings (generated l10n excluded per T004) (FR-009)
- [X] T041 Run `dart format --output=none --set-exit-if-changed .` and confirm no formatting drift
- [X] T042 Run `flutter test` from the workspace root — all green, no skips; regenerate goldens with `flutter test --update-goldens` only for intentional visual changes (Principle III/IV)
- [ ] T043 Execute `quickstart.md` validation: run the tester app on macOS and manually confirm tab switch, splitter resize, narrow-window collapse/expand, light/dark theme, and en/de/tr language switch

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately. T005 depends on T001–T004.
- **Foundational (Phase 2)**: Depends on Setup. **BLOCKS all user stories** (every region widget reads `JetPrintLocalizations`).
- **User Stories (Phases 3–6)**: All depend on Foundational completion.
  - US1 (P1) is the MVP and should land first; US2 extends the right panel US1 created; US3 fills content into widgets US1/US2 created; US4 extends the seam US1 wired into the tester app.
  - With sufficient staffing US2/US3/US4 can proceed in parallel after US1, but they share files created in US1 (see notes), so coordinate edits.
- **Polish (Phase 7)**: Depends on all targeted user stories being complete.

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational. Creates the shell + all region widget files. No dependency on other stories.
- **US2 (P2)**: Depends on Foundational; integrates with `DesignerRightPanel` (created in US1). Independently testable via tab-switching.
- **US3 (P3)**: Depends on Foundational; enriches widgets created in US1 (toolbox, surface) and US2 (panel bodies). Independently testable via content inspection.
- **US4 (P3)**: Depends on Foundational; adds de/tr ARBs (extending the en template from T006) and the tester toggle (extending main.dart wiring from US1 T019). Independently testable via language switching.

### Within Each User Story

- Tests are written and MUST FAIL before implementation.
- Region widget files (T013–T016) before the composing shell (T017).
- Shell before export (T018) before tester wiring (T019) before tester test (T020).
- Panel body files (T022–T024) before tab wiring (T025).
- ARB files (T033–T034) before regeneration (T035) before tester toggle (T036).

### Parallel Opportunities

- All Setup tasks T001–T004 are `[P]` (different files).
- Within US1: tests T009, T010, T011, T012 all `[P]` (different files); T011a shares `responsive_collapse_test.dart` with T011 so it is authored together with T011, not in parallel; region widgets T013–T016 all `[P]` (different files) — converge at the shell T017.
- Within US2: panel bodies T022–T024 all `[P]`.
- Within US3: panel population T028–T030 all `[P]` (T027 toolbox and T031 surface touch files also edited elsewhere — sequence per notes).
- Within US4: ARBs T033–T034 `[P]`.
- Polish T037–T039 all `[P]`.

---

## Parallel Example: User Story 1

```bash
# After Foundational completes, launch all US1 tests together (they must fail first):
Task: "Public-API import test references JetReportDesigner in packages/jet_print/test/public_api_test.dart"
Task: "Region-presence widget test in packages/jet_print/test/designer/jet_report_designer_test.dart"
Task: "Responsive-collapse + splitter-resize widget tests in packages/jet_print/test/designer/responsive_collapse_test.dart (T011 + T011a, same file)"
Task: "Light/dark golden test in packages/jet_print/test/designer/goldens/jet_report_designer_light_dark_test.dart"

# Then build the four region widgets in parallel:
Task: "Create DesignerTopBar in packages/jet_print/lib/src/designer/layout/designer_top_bar.dart"
Task: "Create DesignerToolbox in packages/jet_print/lib/src/designer/layout/designer_toolbox.dart"
Task: "Create DesignerSurface in packages/jet_print/lib/src/designer/layout/designer_surface.dart"
Task: "Create DesignerRightPanel in packages/jet_print/lib/src/designer/layout/designer_right_panel.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (localization deps + tooling config).
2. Complete Phase 2: Foundational (en ARB + generated delegate + export) — CRITICAL, blocks all stories.
3. Complete Phase 3: User Story 1 — the full layout shell.
4. **STOP and VALIDATE**: launch the tester app, confirm all regions present, themed, resizable, collapsible.
5. Demo the workspace skeleton for stakeholder sign-off (SC-006).

### Incremental Delivery

1. Setup + Foundational → localization seam ready.
2. US1 → full layout shell → demo (MVP).
3. US2 → tab switching works → demo.
4. US3 → recognizable placeholder content → demo.
5. US4 → en/de/tr + live language toggle → demo.
6. Polish → analyzer/format/test gates green + quickstart validation.

---

## Notes

- `[P]` = different files, no dependency on incomplete tasks.
- `[Story]` label maps each task to its user story for traceability.
- Layout-only iteration: no data binding, element creation, property editing, drag-and-drop, or persistence (Constitution V deferred).
- Some later-story tasks edit files created in earlier stories (US3 fills US1/US2 widgets; US4 extends US1's tester wiring) — these are intentional incremental refinements, not parallelizable across stories on the same file.
- Verify each test FAILS before implementing (Principle III).
- Run `flutter analyze` + `dart format` + `flutter test` before claiming completion (Principle VI).
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.
