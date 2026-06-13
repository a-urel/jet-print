# Tasks: Format Properties — Font & Color Editors

**Input**: Design documents from `/specs/021-format-properties/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/style-editors.md, quickstart.md

**Tests**: MANDATORY per Constitution Principle III (Test-First, NON-NEGOTIABLE). Every test task in a story MUST be written and observed to FAIL (red) before its paired implementation task makes it pass (green). Golden tests cover all rendered output per Principle IV.

**Organization**: Tasks are grouped by user story (US1 text styling P1, US2 shape styling P2, US3 barcode color P3) so each story is independently implementable and testable. Note: US2 and US3 reuse the shared `_ColorField` editor that US1 introduces (an explicitly accepted spec-level dependency — see spec.md "Why this priority" for Story 2/3).

**Test command**: `flutter test packages/jet_print` from repo root (run `git -C /Users/ahmeturel/Projects/oss/jet-print status` afterwards — `flutter` can leave the cwd inside the package).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 / US2 / US3 — user story phase tasks only
- Every description carries exact file path(s)

---

## Phase 1: Setup

**Purpose**: Confirm a clean, green baseline so red tests in later phases are attributable to this feature only.

- [X] T001 Verify baseline: run `dart analyze` (zero warnings) and `flutter test packages/jet_print` (all green) from repo root; record the passing count as the baseline for later checkpoints — **baseline: 1197 passing, 0 analyzer issues**

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Cross-story guards and shared editor primitives that every story relies on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 [P] Create a pre-feature report fixture (text + shape + barcode elements saved with the current codec) and a byte-identical load→re-save round-trip test in `packages/jet_print/test/domain/serialization/report_format_compat_test.dart` (NEW). This test must pass **immediately** and stay green through the whole feature — it pins contract C10 / FR-006 / SC-004 (schema stays 1, no migration, omission rules untouched)
- [X] T003 Write failing widget tests for `_NumberField` min/max clamping in `packages/jet_print/test/designer/properties_editor_test.dart`: typed out-of-range value commits the clamped bound; non-numeric input is rejected, previous value restored, no commit; stepper at a bound stays at the bound as a no-op (contract C4, both ranges 4–144 and 0–20 parameterized)
- [X] T004 Extend `_NumberField` in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` with optional `min`/`max` clamping and reject-and-restore for non-numeric commits, making T003 green (existing X/Y/W/H usages unchanged — no clamp when min/max absent)

**Checkpoint**: Foundation ready — compat guard green, clamping primitive in place. User stories can begin.

---

## Phase 3: User Story 1 — Style text on a report (Priority: P1) 🎯 MVP

**Goal**: A selected text element's font family, size, bold/italic/underline, color, and horizontal alignment are all editable from a new Font section in the Properties panel; changes render identically on canvas, preview, and export; underline is added end-to-end (model → JSON → both painters).

**Independent Test**: Place a text element in the playground, change each attribute in the Properties panel, verify canvas updates ≤100 ms, undo restores each change in one step, and save/preview/export all match the canvas (quickstart.md Part 1).

### Tests for User Story 1 (write FIRST — must FAIL before implementation) ⚠️

- [X] T005 [P] [US1] Extend `packages/jet_print/test/domain/styles/text_style_test.dart`: `underline` defaults to `false`; `==`/`hashCode`/`toString` include it; `copyWith` covers every field including the `fontFamily` sentinel (omitted ≠ set-to-null; explicit `null` clears the family)
- [X] T006 [P] [US1] Extend `packages/jet_print/test/domain/serialization/element_codec_test.dart`: `underline: true` serializes, `false` is omitted, absent ⇒ `false` on load; a fallback-plus-underline style is no longer omitted as fallback; an unknown `fontFamily` string survives load→save untouched (contracts C3, C10)
- [X] T007 [P] [US1] Create `packages/jet_print/test/rendering/text/underline_metrics_test.dart` (NEW): `underlineFor(fontSize)` returns offset ≈ 0.11×size and thickness ≈ 0.06×size; values scale linearly with font size
- [X] T008 [P] [US1] Extend `packages/jet_print/test/rendering/text/font_registry_test.dart`: `families` getter lists registered family names with the default family first, insertion order, deduped
- [X] T009 [P] [US1] Create `packages/jet_print/test/designer/controller/set_text_style_command_test.dart` (NEW): applying a new style is exactly one undo step and notifies once; command returns `before` (no history, no notify) when the target is missing, not a `TextElement`, or the style is equal (contracts C5, C9; mirror `set_shape_kind_command_test.dart`)
- [X] T010 [P] [US1] Extend `packages/jet_print/test/rendering/export/pdf_painter_parity_test.dart`: an underlined text run emits a stroked line segment in the PDF content stream at the offset/width computed by the shared `underlineFor` helper (contract C11)
- [X] T011 [P] [US1] Extend `packages/jet_print/test/rendering/paint/canvas_painter_golden_test.dart` with a styled-text golden page: non-default family, size, bold, italic, underline, translucent color, and left/center/right alignments; assert existing goldens stay byte-identical (contract C11, SC-002)

### Implementation for User Story 1

- [X] T012 [US1] Add `bool underline` (default `false`) to `JetTextStyle` in `packages/jet_print/lib/src/domain/styles/text_style.dart`: constructor, `==`/`hashCode`/`toString`, sentinel-based `copyWith` (per data-model.md §1), `toJson` writes `underline` only when `true`, `fromJson` tolerant (missing/non-bool ⇒ `false`) — makes T005 + T006 green; T002 must stay green
- [X] T013 [P] [US1] Create `packages/jet_print/lib/src/rendering/text/underline_metrics.dart` (NEW, private): `({double offset, double thickness}) underlineFor(double fontSize)` with the em-fraction constants — the single underline geometry source (Constitution IV) — makes T007 green
- [X] T014 [US1] Canvas underline: in `packages/jet_print/lib/src/rendering/paint/canvas_painter.dart` `drawTextRun`, stroke an explicit line per underlined text line at the existing per-line aligned `dx`/measured width using `underlineFor` (NOT `ui.TextDecoration`)
- [X] T015 [US1] PDF underline: in `packages/jet_print/lib/src/rendering/export/pdf_painter.dart` `drawTextRun`, draw the same segment via `underlineFor` inside the existing per-line alignment math (with `_mapY`) — makes T010 + T011 green together with T014
- [X] T016 [P] [US1] Add `List<String> get families` to `FontRegistry` in `packages/jet_print/lib/src/rendering/text/font_registry.dart` (default family first, insertion order, deduped; registry stays internal) — makes T008 green
- [X] T017 [US1] Create `packages/jet_print/lib/src/designer/controller/commands/set_text_style_command.dart` (NEW) replacing a `TextElement`'s `style` with no-op rules per data-model.md §4, and add `void setTextStyle(String id, JetTextStyle style)` to `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` routing through `_commit` (dartdoc: single-undo + no-op semantics) — makes T009 green
- [X] T018 [US1] Hoist one `FontRegistry` instance into the designer state in `packages/jet_print/lib/src/designer/jet_report_designer.dart` and pass it to both the canvas frame builder and the Properties panel; change `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` (line ~91) to accept the hoisted registry instead of constructing `DesignTimeFrameBuilder()` privately
- [X] T019 [US1] Add localization keys (Font section title, family/size labels, bold/italic/underline tooltips, alignment labels, color label, None, unavailable-family marker, swatch names — ~15 of the ~20 keys) with `@description` metadata to `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`; regenerate `jet_print_localizations*.dart`
- [X] T020 [US1] Write failing widget tests in `packages/jet_print/test/designer/properties_editor_test.dart` covering the US1 contracts: C1 gating (Font section for `TextElement` only — none for image/band/report/none/multi), C2 binding (all controls show effective values incl. pre-feature fallback element), C3 family picker (enumeration from registry, per-item typeface preview, unavailable-family entry preserved until repicked), C4 size clamp 4–144, C5 B/I/U (bold active ⟺ `weight == bold`; medium/semiBold show inactive and are preserved on unrelated edits; press maps to bold/normal), C6 color editor (swatch+hex display, alpha-preserving 6-digit/swatch pick, 8-digit sets alpha, malformed hex rejects+restores+no history), alignment segments (left/center/right; a stored `justify` shows no active segment and is preserved verbatim on unrelated edits), C9 undo round-trip per editor + no-op commits record nothing + selection-switch discards uncommitted input, labels resolve in en/de/tr
- [X] T021 [US1] Create `packages/jet_print/lib/src/designer/layout/panels/style_editors.dart` (NEW, private): `_ColorField` (ShadPopover trigger with swatch + hex code; palette grid ~16 swatches, hex ShadInput with regex `^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$`, optional None entry; alpha rule per research §5), `_FontFamilyRow` (ShadSelect, items rendered in own typeface, unavailable marker), `_StyleToggleGroup` (B/I/U on the `_OrientationToggle` precedent, lucide icons), `_AlignSegments` (left/center/right — stored `justify` shows no active segment)
- [X] T022 [US1] Wire the Font section into the `TextElement` branch of `_elementInspector` in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`: family select, size `_NumberField` (min 4, max 144), B/I/U group, `_ColorField` (no None), alignment segments — each commit = one `copyWith` + one `controller.setTextStyle` — makes T020 green
- [X] T023 [US1] Extend `packages/jet_print/test/designer/accessibility_semantics_test.dart`: B/I/U toggles, alignment segments, color swatches, and family select expose semantic button roles with localized labels and are keyboard-operable (contract C12); fix widgets in `style_editors.dart` as needed
- [X] T024 [US1] Update `packages/jet_print/test/public_api_test.dart`: record `JetTextStyle.underline`, `JetTextStyle.copyWith`, and `JetReportDesignerController.setTextStyle`; assert `FontRegistry` is still NOT exported; verify `packages/jet_print/lib/jet_print.dart` needs no new export line

**Checkpoint**: Full suite green (`flutter test packages/jet_print`). US1 is the demoable MVP — walk quickstart.md Part 1 in `apps/jet_print_playground`.

---

## Phase 4: User Story 2 — Style shape fill and outline (Priority: P2)

**Goal**: A selected shape gets an Appearance section: fill color (with None), outline color (with None), and outline width 0–20 (0 hides the outline but keeps the color); line shapes offer outline controls only.

**Independent Test**: Place a rectangle and a line in the playground, set fill/outline/width including both None states and width 0, verify canvas/preview/export parity and the design-time placeholder for an invisible shape (quickstart.md Part 2).

### Tests for User Story 2 (write FIRST — must FAIL before implementation) ⚠️

- [X] T025 [P] [US2] Extend `packages/jet_print/test/domain/styles/box_style_test.dart`: sentinel-based `copyWith` — omitted preserves, explicit `null` clears `fill`/`stroke`, `strokeWidth` replaceable
- [X] T026 [P] [US2] Extend `packages/jet_print/test/domain/serialization/shape_element_codec_test.dart`: `fill: null` / `stroke: null` omitted on write and `null` on read; translucent (`#AARRGGBB`) fill/stroke colors round-trip with alpha intact (contract C10)
- [X] T027 [P] [US2] Extend `packages/jet_print/test/rendering/elements/shape_element_renderer_test.dart`: `strokeWidth <= 0` ⇒ emitted primitives carry `stroke: null` on all three emission paths (rect/path/line) while the stored stroke color is retained on the style (contract C7, research §6)
- [X] T028 [P] [US2] Create `packages/jet_print/test/designer/controller/set_shape_style_command_test.dart` (NEW): same matrix as T009 — single undo step, notify once, `before` on missing/wrong-type/equal
- [X] T029 [P] [US2] Extend `packages/jet_print/test/rendering/paint/canvas_painter_golden_test.dart` with a shape-style golden page: filled+stroked, fill-only, stroke-only, none+none (design-time placeholder still visible on canvas), width-0 (contract C7/C11)
- [X] T030 [P] [US2] Extend `packages/jet_print/test/rendering/export/pdf_painter_parity_test.dart`: a shape with `strokeWidth: 0` emits no stroke operators in the PDF content stream

### Implementation for User Story 2

- [X] T031 [US2] Add sentinel-based `copyWith({Object? fill = _unset, Object? stroke = _unset, double? strokeWidth})` to `JetBoxStyle` in `packages/jet_print/lib/src/domain/styles/box_style.dart` (data-model.md §2) — makes T025 green; T002 + T026 stay green (no serialization change)
- [X] T032 [US2] Renderer stroke seam in `packages/jet_print/lib/src/rendering/elements/renderers/shape_element_renderer.dart`: every emission passes `stroke: el.style.strokeWidth > 0 ? el.style.stroke : null` (line shapes keep their existing stroke-null default-black design-time render) — makes T027 + T029 + T030 green
- [X] T033 [US2] Create `packages/jet_print/lib/src/designer/controller/commands/set_shape_style_command.dart` (NEW) and add `void setShapeStyle(String id, JetBoxStyle style)` to `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` through `_commit`, with dartdoc — makes T028 green
- [X] T034 [US2] Add Appearance-section localization keys (section title, fill/outline labels, width label, no-fill/no-outline texts) to `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`; regenerate localizations
- [X] T035 [US2] Write failing widget tests in `packages/jet_print/test/designer/properties_editor_test.dart`: C1 gating (Appearance for `ShapeElement`; line ⇒ outline controls only, no fill control), C7 None commits `fill: null`/`stroke: null` with distinct none-state display, width clamp 0–20, width 0⇒outline hidden then width >0 restores remembered color, C9 undo round-trips and selection-switch discard for shape editors
- [X] T036 [US2] Wire the Appearance section into the `ShapeElement` branch of `_elementInspector` in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`: fill `_ColorField` with None (hidden for `ShapeKind.line`), stroke `_ColorField` with None, width `_NumberField` (min 0, max 20) — commits via `copyWith` + `controller.setShapeStyle` — makes T035 green
- [X] T037 [US2] Extend `packages/jet_print/test/designer/accessibility_semantics_test.dart` for the Appearance controls (roles, localized labels, keyboard operation)
- [X] T038 [US2] Update `packages/jet_print/test/public_api_test.dart`: record `JetBoxStyle.copyWith` and `JetReportDesignerController.setShapeStyle`

**Checkpoint**: Full suite green. US1 + US2 each independently demoable.

---

## Phase 5: User Story 3 — Set barcode color (Priority: P3)

**Goal**: A selected barcode element gets a color row (shared `_ColorField`, no None) bound to `BarcodeElement.color`; the placeholder renderer is tinted with it so the change is visible and WYSIWYG-consistent on canvas/preview/export.

**Independent Test**: Place a barcode in the playground, change its color, verify canvas + export tint and one-step undo (quickstart.md Part 3).

### Tests for User Story 3 (write FIRST — must FAIL before implementation) ⚠️

- [X] T039 [P] [US3] Extend `packages/jet_print/test/domain/serialization/element_codec_test.dart`: `BarcodeElement.color` omitted when black, round-trips otherwise including alpha (contract C8/C10)
- [X] T040 [P] [US3] Extend `packages/jet_print/test/rendering/elements/barcode_element_renderer_test.dart`: placeholder primitives (glyph/border) carry `el.color` instead of the hardcoded tint
- [X] T041 [P] [US3] Create `packages/jet_print/test/designer/controller/set_barcode_color_command_test.dart` (NEW): same matrix — single undo step, notify once, `before` on missing/wrong-type/equal-color

### Implementation for User Story 3

- [X] T042 [US3] Verify `BarcodeElement.copyWith` supports `color` in `packages/jet_print/lib/src/domain/elements/barcode_element.dart`; add it if absent (with unit coverage in the corresponding domain test)
- [X] T043 [US3] Tint the placeholder primitives with `el.color` in `packages/jet_print/lib/src/rendering/elements/renderers/barcode_element_renderer.dart` (research §8) — makes T040 green
- [X] T044 [US3] Create `packages/jet_print/lib/src/designer/controller/commands/set_barcode_color_command.dart` (NEW) and add `void setBarcodeColor(String id, JetColor color)` to `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` through `_commit`, with dartdoc — makes T041 green
- [X] T045 [US3] Add barcode color-row localization key(s) to `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`; regenerate localizations
- [X] T046 [US3] Write failing widget tests in `packages/jet_print/test/designer/properties_editor_test.dart`: C1 gating (color row for `BarcodeElement` only), C8 editor shows current color, pick commits one `setBarcodeColor`, **no None entry**, undo restores
- [X] T047 [US3] Wire the barcode color row into the `BarcodeElement` branch of `_elementInspector` in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` using `_ColorField` without None — makes T046 green
- [X] T048 [US3] Update `packages/jet_print/test/public_api_test.dart`: record `JetReportDesignerController.setBarcodeColor`

**Checkpoint**: All three stories independently functional; full suite green.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T049 [P] Documentation pass: verify dartdoc on `setTextStyle`/`setShapeStyle`/`setBarcodeColor` (single-undo + no-op semantics), `underline`, and both `copyWith`s; update `packages/jet_print/CHANGELOG.md`
- [X] T050 [P] Cross-cutting verification: `packages/jet_print/test/architecture/layer_boundaries_test.dart` green (domain has no Flutter import; `underlineFor`/`families` in rendering; commands/editors in designer); all pre-existing goldens byte-identical; T002 compat test still green
- [X] T051 Run `dart format .`, `dart analyze` (zero warnings), and the full `flutter test packages/jet_print` suite from repo root; fix any fallout
- [ ] T052 (PENDING — requires a human at the GUI) Manual quickstart validation: walk all of `specs/021-format-properties/quickstart.md` in `apps/jet_print_playground` (style text → shape fill/outline/none/width-0 → barcode tint → preview/export/save-reload parity, undo at each step ≤3 interactions per SC-001/SC-006)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none — start immediately
- **Foundational (Phase 2)**: after Setup — **blocks all user stories** (T002 guards every later model change; T004 is the clamp primitive used by US1 size and US2 width)
- **US1 (Phase 3)**: after Phase 2 — no story dependencies; introduces shared `_ColorField` (T021)
- **US2 (Phase 4)**: after Phase 2; reuses `_ColorField` from T021 (model/renderer/command tasks T025–T033 are independent of US1 and can start right after Phase 2)
- **US3 (Phase 5)**: after Phase 2; reuses `_ColorField` from T021 (model/renderer/command tasks T039–T044 are independent of US1)
- **Polish (Phase 6)**: after all desired stories

### Key Task-Level Dependencies

- T012 (model) before T014/T015 (painters need `underline` on the style)
- T013 before T014/T015 (painters consume `underlineFor`)
- T016 + T018 before T022 (panel enumerates the hoisted registry)
- T019 before T021/T022 · T034 before T036 · T045 before T047 (widgets reference l10n keys)
- T021 before T022, T036, T047 (all three panels use `_ColorField`)
- T017/T033/T044 before their respective panel wiring (panel commits through the mutators)
- Each test task before its paired implementation task (red → green)

### Parallel Opportunities

- All US1 test tasks T005–T011 — seven different files, fully parallel
- T013 + T016 in parallel (different rendering files); US2 tests T025–T030 in parallel; US3 tests T039–T041 in parallel
- After Phase 2, US2's domain/renderer/command track (T025–T033) and US3's track (T039–T044) can run in parallel with US1 — only their panel-wiring tasks wait on T021
- T049 + T050 in parallel during Polish

---

## Parallel Example: User Story 1

```bash
# Launch all US1 unit/golden/parity tests together (red phase):
Task: "T005 underline + copyWith tests in test/domain/styles/text_style_test.dart"
Task: "T006 underline/unknown-family codec tests in test/domain/serialization/element_codec_test.dart"
Task: "T007 underlineFor tests in test/rendering/text/underline_metrics_test.dart"
Task: "T008 families getter tests in test/rendering/text/font_registry_test.dart"
Task: "T009 SetTextStyleCommand tests in test/designer/controller/set_text_style_command_test.dart"
Task: "T010 PDF underline parity in test/rendering/export/pdf_painter_parity_test.dart"
Task: "T011 styled-text golden in test/rendering/paint/canvas_painter_golden_test.dart"

# Then the independent implementation pair:
Task: "T013 underline_metrics.dart helper"
Task: "T016 FontRegistry.families getter"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 (baseline) → Phase 2 (compat guard + clamp primitive)
2. Phase 3 complete → **STOP and VALIDATE**: full suite green, quickstart Part 1 walk in the playground
3. US1 alone turns the designer into a real formatting tool — demoable as the MVP

### Incremental Delivery

1. Setup + Foundational → guard rails in place
2. US1 → validate → demo (MVP: text styling end-to-end incl. net-new underline)
3. US2 → validate → demo (shape fill/outline/none/width-0)
4. US3 → validate → demo (barcode tint)
5. Polish → format/analyze/full-suite/quickstart → ready for PR

### Notes

- Commit after each task or logical red→green pair (Constitution III: no merge with failing/skipped tests)
- `properties_editor_test.dart` and `properties_panel.dart` are touched by all three stories — sequence those tasks (no [P]) to avoid same-file conflicts
- The three controller commands follow the `set_shape_kind_command.dart` precedent exactly; copy its structure
- Schema version must remain **1** throughout; if T002 ever goes red, stop and fix before proceeding
