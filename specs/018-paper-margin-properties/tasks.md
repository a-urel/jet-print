---
description: "Task list for Editable Paper Type & Margins in Report Properties"
---

# Tasks: Editable Paper Type & Margins in Report Properties

**Input**: Design documents from `/specs/018-paper-margin-properties/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/page-properties.md, quickstart.md

**Tests**: MANDATORY per Constitution Principle III (Test-First, NON-NEGOTIABLE) and Principle IV (golden tests for rendered output). Every behavior is pinned by a **failing** test before implementation. No merge with failing/skipped tests.

**Organization**: Tasks are grouped by user story (P1 paper type → P2 margins → P3 orientation/custom) so each story is an independently testable, shippable increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 / US2 / US3 — maps to spec.md user stories. Setup, Foundational, and Polish tasks carry no story label.
- All paths are relative to the repository root `/Users/ahmeturel/Projects/oss/jet-print/`.

## Path Conventions

This is an existing Dart pub-workspace monorepo. Library code lives under `packages/jet_print/lib/src/`, tests under `packages/jet_print/test/`, the consumer app under `apps/jet_print_playground/`. No new top-level structure is created.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish a clean, attributable baseline before any change.

- [X] T001 From repo root, confirm the baseline is green so later regressions are attributable: run `flutter test packages/jet_print`, `flutter analyze packages/jet_print`, and `dart format --output=none --set-exit-if-changed packages/jet_print`. Record that the suite passes before edits begin.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared seam every user story composes against — additive `copyWith` on the two immutable value types, the clamp helper, the `SetPageFormatCommand`, and the single `setPageFormat` controller op. No paper/margin control can be built until this exists.

**⚠️ CRITICAL**: No user-story work (Phase 3+) can begin until this phase is complete.

### Tests for Foundational (write FIRST — must FAIL before implementation)

- [X] T002 [P] Extend `packages/jet_print/test/domain/page_format_test.dart`: assert `PageFormat.copyWith({width,height,margins})` replaces only named fields and preserves the rest, and that a `copyWith`-edited page round-trips losslessly through `toJson`/`fromJson`. Add a sibling group (or `packages/jet_print/test/domain/geometry_test.dart` if one exists) covering `JetEdgeInsets.copyWith({left,top,right,bottom})` per-side replacement.
- [X] T003 [P] Create `packages/jet_print/test/designer/controller/set_page_format_command_test.dart` covering the contract rows in contracts/page-properties.md: C3.1 orientation swap (A4 portrait → 841.89 × 595.28); C3.4/C4.1/C4.3 clamp leaves a positive content area when margins meet/exceed the extent and when a side is sub-minimum; C4.2 clamp is idempotent on a valid page; C5.1 a page change undoes in a single step to the exact prior `PageFormat` (`canUndo` was true); C5.2 redo re-applies; C5.3 `setPageFormat` with the current page is a no-op (nothing pushed, no notify); C6.1 an edited page (Letter, Narrow, landscape) survives a codec round-trip; C8.1 changing to a smaller page preserves element top-left anchors (no reposition/delete).

### Implementation for Foundational

- [X] T004 [P] Add `PageFormat copyWith({double? width, double? height, JetEdgeInsets? margins})` to `packages/jet_print/lib/src/domain/page_format.dart` (domain stays UI/render-free; additive only — no new field, `toJson`/`fromJson` untouched).
- [X] T005 [P] Add `JetEdgeInsets copyWith({double? left, double? top, double? right, double? bottom})` to `packages/jet_print/lib/src/domain/geometry.dart` (additive; no new field).
- [X] T006 Create `packages/jet_print/lib/src/designer/controller/page_format_clamp.dart`: `clampPageFormat(PageFormat) → PageFormat` plus constants `kMinPageSide` and `kMinContentExtent`. Pull width/height up to `kMinPageSide`; cap offending side(s) so `left+right ≤ width − kMinContentExtent` and `top+bottom ≤ height − kMinContentExtent`; idempotent on a valid page (FR-009/SC-006). Depends on T004/T005.
- [X] T007 Create `packages/jet_print/lib/src/designer/controller/commands/set_page_format_command.dart`: an `EditCommand`/transform mirroring `set_format_command.dart`. `apply(before)` returns `before` when the page is identical/equal (no-op), else `before.withTemplate(before.template.copyWith(page: format))`. Pure and total — does NOT clamp and does NOT move elements (FR-013).
- [X] T008 Add `void setPageFormat(PageFormat format)` to `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`: `clampPageFormat(format)` then `_commit(SetPageFormatCommand(clamped))` — one undoable, notifying step routed through the existing `_commit` identity check. Mirrors the `setBandHeight` idiom. Depends on T006, T007.
- [X] T009 Update `packages/jet_print/test/public_api_test.dart` to record the additive public surface: `JetReportDesignerController.setPageFormat(PageFormat)`, `PageFormat.copyWith`, `JetEdgeInsets.copyWith`. Confirm `SetPageFormatCommand`, `clampPageFormat`, presets, and recognition stay private (not exported). Depends on T004, T005, T008.

**Checkpoint**: `setPageFormat` clamps, commits as one undo step, round-trips through the codec, and preserves content — verified by T002/T003 going green. The render path is untouched. User stories can now begin.

---

## Phase 3: User Story 1 - Choose a standard paper type (Priority: P1) 🎯 MVP

**Goal**: Turn the read-only page Size text into a named paper-type picker (A4/A3/A5/Letter/Legal + Custom) with an Office-style page-sample thumbnail; selecting a size resizes the canvas/preview/export and persists.

**Independent Test**: Open a report, change the paper type from the presets list, confirm the canvas/preview/export adopt the new dimensions, a non-preset size shows "Custom", and the choice survives save/reload — without touching margins.

### Tests for User Story 1 (write FIRST — must FAIL)

- [X] T010 [P] [US1] Create `packages/jet_print/test/designer/paper_presets_test.dart`: each standard size is recognized by name in **both** orientations (C1.5); rounded A4 (595 × 842) still names "A4" via the ε-tolerance (C1.4); a non-matching size (500 × 700) reports `isCustom` without altering dimensions (C1.3); `applyPaper(preset, {landscape})` builds the correct size and preserves current margins.
- [X] T011 [US1] Extend `packages/jet_print/test/designer/properties_editor_test.dart` with paper-type widget cases: an A4 page shows the control labeled "A4" by name not raw numbers (C1.1); selecting Letter resizes the page to 612 × 792 and leaves margins unchanged (C1.2); the `_PagePreview` renders a sheet at the page's aspect ratio with margin guide lines (C9.1); the PAGE controls are present and editable with no element selected (C9.4).

### Implementation for User Story 1

- [X] T012 [P] [US1] Create `packages/jet_print/lib/src/designer/paper_presets.dart` (private): `kPaperPresets` (ordered A4/A3/A5/Letter/Legal stored portrait, values per research D1), `PaperPreset`/`PaperMatch` types, `recognizePaper(PageFormat) → PaperMatch` (sort sides, match within `1e-2` in either orientation, else `isCustom`), and `applyPaper(PaperPreset, {landscape}) → PageFormat` preserving current margins. Display-only — never rewrites the model.
- [X] T013 [US1] Add paper-section l10n keys (e.g. "Paper", "Custom") with `@`-descriptions to `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, and `jet_print_tr.arb`; standard size names (A4, Letter, …) stay un-localized per research D1. Regenerate `jet_print_localizations*.dart` (`flutter gen-l10n`). Shared ARB files — sequence before T018/T022.
- [X] T014 [US1] Rebuild the PAGE section of `_reportInspector` in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`: remove the two `_ReadonlyRow` page rows; add the `_PagePreview` `CustomPaint` thumbnail (sheet rect + margin guides, proportional to the live `PageFormat`) and the paper-type dropdown wired to `recognizePaper` for its label and to `controller.setPageFormat(applyPaper(...).copyWith(margins: page.margins))` on select. Reuse existing `_LabeledRow`/picker patterns. Depends on T008, T012, T013.

**Checkpoint**: Paper type is selectable by name, the thumbnail reflects it, a non-preset page reads "Custom", and the change resizes canvas/preview/export and persists — US1 is independently demoable (MVP).

---

## Phase 4: User Story 2 - Set page margins (Priority: P2)

**Goal**: Add margin presets (Normal/Narrow/Wide/None) plus editable per-side fields (left/top/right/bottom); a preset writes all four sides, editing one side marks the set Custom, and the content area/thumbnail updates.

**Independent Test**: Open a report, apply a margin preset and/or type specific side values, confirm the content guides update, an uneven set reads "Custom", invalid entry reverts, and values persist across save/reload — independent of the paper-type control.

### Tests for User Story 2 (write FIRST — must FAIL)

- [X] T015 [P] [US2] Create `packages/jet_print/test/designer/margin_presets_test.dart`: four equal sides matching a preset value (within `1e-2`) recognize as that preset; uneven or unmatched sides → `isCustom` (C2.3).
- [X] T016 [US2] Extend `packages/jet_print/test/designer/properties_editor_test.dart` with margin widget cases: choosing Narrow sets all four sides to 14.17 and the content area updates (C2.1); setting Left to 50 changes only Left, leaves the others at 28.35, and flips the preset label to Custom (C2.2); empty/non-numeric entry in a margin field reverts to the last valid value on blur (C2.4); changing a margin moves the `_PagePreview` guide insets proportionally (C9.3).

### Implementation for User Story 2

- [X] T017 [P] [US2] Create `packages/jet_print/lib/src/designer/margin_presets.dart` (private): `kMarginPresets` (Normal 28.35 / Narrow 14.17 / Wide 56.69 / None 0 per research D2), `MarginPreset`/`MarginMatch` types, and `recognizeMargin(JetEdgeInsets) → MarginMatch` (four equal sides matching within `1e-2` → that preset, else `isCustom`). Labels resolved via l10n at the call site.
- [X] T018 [US2] Add margin-preset name l10n keys (Normal/Narrow/Wide/None) plus side labels (Left/Top/Right/Bottom if not already present) with `@`-descriptions to the three ARB files (`jet_print_en.arb`/`_de.arb`/`_tr.arb`); regenerate `jet_print_localizations*.dart`. Shared ARB files — sequence after T013, before T022.
- [X] T019 [US2] Extend the PAGE section in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`: add the margin-preset dropdown (labeled via `recognizeMargin`, applies `page.copyWith(margins: JetEdgeInsets.all(preset.value))`) and four per-side `_NumberField`s (each commits `page.copyWith(margins: page.margins.copyWith(<side>: v))`, reverting to last valid on empty/non-numeric). Depends on T014, T017, T018.

**Checkpoint**: Margin presets and per-side edits both work, recognition labels Normal vs Custom correctly, invalid input reverts, and the thumbnail follows — US1 AND US2 both function independently.

---

## Phase 5: User Story 3 - Orientation and custom dimensions (Priority: P3)

**Goal**: Add a portrait/landscape toggle (swaps W/H for preset or custom sizes) and Custom width/height fields (shown only when paper type is Custom); prove WYSIWYG propagation with a Letter/landscape golden.

**Independent Test**: Toggle orientation on a standard size and confirm W/H swap; choose Custom, enter dimensions, confirm the page adopts them exactly and they persist; a sub-minimum custom value clamps.

### Tests for User Story 3 (write FIRST — must FAIL)

- [X] T020 [US3] Extend `packages/jet_print/test/designer/properties_editor_test.dart` with orientation/custom widget cases: toggling to Landscape swaps W/H and flips the `_PagePreview` aspect (C3.1 UI, C9.2); with paper type = Custom the W/H fields are revealed and entering 300 × 500 adopts those exact dimensions (C3.2); a custom W or H field given empty/non-numeric input reverts to the last valid value on blur (C3.5 — same revert idiom as C2.4); when paper type ≠ Custom the W/H fields are hidden/disabled (C3.3). (Numeric swap/clamp at the controller level is already covered by T003/C3.1/C3.4.)
- [X] T021 [US3] Add a golden test proving a Letter/landscape page propagates identically to canvas, preview, and export, with goldens written under `packages/jet_print/test/designer/goldens/` as `page_letter_landscape_*.png` (C7.1). Do not regenerate the default-A4 report goldens — they must stay byte-identical (C7.2).

### Implementation for User Story 3

- [X] T022 [US3] Add orientation l10n keys (Portrait/Landscape) with `@`-descriptions to the three ARB files (`jet_print_en.arb`/`_de.arb`/`_tr.arb`); regenerate `jet_print_localizations*.dart`. Shared ARB files — sequence after T018.
- [X] T023 [US3] Extend the PAGE section in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`: add the portrait/landscape segmented toggle (`page.copyWith(width: page.height, height: page.width)`, orientation derived via `height ≥ width`) and the Custom W/H `_NumberField`s shown only when `recognizePaper(page).isCustom` (`page.copyWith(width:/height:)`, revert-on-invalid; controller clamps sub-minimum). Depends on T019, T022.

**Checkpoint**: All three user stories are independently functional; orientation and custom sizes round out the feature; the new golden proves canvas/preview/export agree.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, localization completeness, regression proof, and the end-to-end walk.

- [X] T024 [P] Add dartdoc to `setPageFormat` (note clamp + single-undo semantics), `PageFormat.copyWith`, `JetEdgeInsets.copyWith`, and the preset/recognition/clamp helpers, per Principle VI.
- [X] T025 [P] Update `packages/jet_print/CHANGELOG.md` with the editable paper-type/margins/orientation entry.
- [X] T026 Regression proof: confirm the existing default-A4 report goldens are byte-identical (C7.2) and a pre-feature template loads unchanged with `kReportSchemaVersion` still 1 (C6.2) — run the full `report_codec`, layout, property, and golden suites.
- [X] T027 Run the quickstart.md walk in `apps/jet_print_playground` (pick Letter → Landscape → Narrow → custom Left → Custom 300×500 → undo/redo → save/reload), confirming canvas/preview/export agree at each step (SC-003) and en/de/tr labels are correct (C9.5/SC-007).
- [X] T028 Final gate from repo root: `flutter test packages/jet_print` (unit + widget + golden all green), `flutter analyze packages/jet_print` (zero warnings), `dart format --output=none --set-exit-if-changed packages/jet_print` (clean).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup. **BLOCKS all user stories** — the panel controls compose against `setPageFormat` + `copyWith`.
- **User Stories (Phase 3–5)**: All depend on Foundational. US1 → US2 → US3 share `properties_panel.dart` and the ARB files, so their **panel and l10n tasks are sequential**; their presets/recognition and test files are independent.
- **Polish (Phase 6)**: Depends on the desired user stories being complete.

### User Story Dependencies

- **US1 (P1)**: Needs Foundational only. The MVP — paper picker + preview.
- **US2 (P2)**: Needs Foundational; its panel task (T019) extends the section US1 built (T014) — same file. Behavior is independently testable.
- **US3 (P3)**: Needs Foundational; its panel task (T023) extends what US2 left (T019) — same file. Behavior is independently testable.

### Within Each Story

- Tests are written FIRST and must FAIL before implementation (Principle III).
- Presets/recognition (own files, `[P]`) before the panel task that consumes them.
- l10n keys before the panel task that references them.
- Story complete and green before moving to the next priority.

### Parallel Opportunities

- **Phase 2 tests**: T002 ∥ T003 (different test files).
- **Phase 2 domain impl**: T004 ∥ T005 (different files); T006→T007→T008 are sequential (clamp → command → controller op).
- **Per story**: the preset/recognition test+impl (`[P]`) run alongside writing the widget tests; e.g. T010 ∥ T012, T015 ∥ T017.
- **Not parallel**: T014/T019/T023 (all `properties_panel.dart`) and T013/T018/T022 (all three ARB files) are strictly sequential.
- **Phase 6**: T024 ∥ T025 (docs vs changelog).

---

## Parallel Example: Foundational Phase

```bash
# Tests first (different files — run together), confirm they FAIL:
Task T002: "Domain copyWith tests in packages/jet_print/test/domain/page_format_test.dart"
Task T003: "Clamp + command + controller tests in packages/jet_print/test/designer/controller/set_page_format_command_test.dart"

# Then the two additive copyWith implementations together:
Task T004: "PageFormat.copyWith in packages/jet_print/lib/src/domain/page_format.dart"
Task T005: "JetEdgeInsets.copyWith in packages/jet_print/lib/src/domain/geometry.dart"
```

## Parallel Example: User Story 1

```bash
# Preset recognition test + impl in parallel with authoring the widget tests:
Task T010: "paper_presets_test.dart — recognition both orientations + Custom"
Task T012: "paper_presets.dart — kPaperPresets, recognizePaper, applyPaper"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup (baseline green).
2. Phase 2: Foundational (CRITICAL — blocks all stories).
3. Phase 3: US1 — paper picker + Office-style preview.
4. **STOP and VALIDATE**: change paper type, see canvas/preview/export resize, "Custom" for non-presets, survives save/reload.
5. Demo if ready.

### Incremental Delivery

1. Setup + Foundational → seam ready.
2. US1 → test → demo (MVP: paper type).
3. US2 → test → demo (margins).
4. US3 → test → demo (orientation + custom).
5. Polish → docs, regression proof, quickstart walk.

Each story adds value without breaking the previous ones; every page edit is one undo step, one shared `template.page`, no schema change.

---

## Notes

- `[P]` = different files, no dependencies on incomplete tasks.
- `[Story]` label maps a task to its user story for traceability.
- Verify every test FAILS before implementing (red → green → refactor).
- The `_PagePreview` is schematic designer chrome, NOT a second renderer — WYSIWYG is guaranteed by the shared `template.page`, so it is covered by widget tests, not report goldens.
- Orientation and preset names are derived at display time, never serialized; `kReportSchemaVersion` stays 1, no migration.
- Commit after each task or logical group; do not merge with failing/skipped tests.
