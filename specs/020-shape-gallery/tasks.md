---
description: "Task list for Shape Gallery in Properties Pane"
---

# Tasks: Shape Gallery in Properties Pane

**Input**: Design documents from `/specs/020-shape-gallery/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/shape-gallery.md, quickstart.md

**Tests**: MANDATORY per Constitution Principle III (Test-First, NON-NEGOTIABLE) and Principle IV
(golden tests for rendered output). Every implementation task is preceded by a test that must be
written RED and confirmed failing before the implementation makes it GREEN.

**Organization**: Tasks are grouped by user story. The shared `domain` + `rendering` seams that all
three stories depend on are isolated into Phase 2 (Foundational) so each story stays independently
testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 / US2 / US3 (Setup, Foundational, Polish carry no story label)
- All paths are repo-relative; the library lives in `packages/jet_print/`.

## Verify commands (run from repo root)

```bash
flutter test packages/jet_print
flutter analyze packages/jet_print
dart format --output=none --set-exit-if-changed packages/jet_print
```

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm a clean baseline before touching the seams.

- [X] T001 Confirm baseline green: run `flutter test packages/jet_print`, `flutter analyze packages/jet_print`, and `dart format --output=none --set-exit-if-changed packages/jet_print` from repo root; record that the suite is green before any change (Constitution III: no merge with pre-existing failures).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The additive domain types + the shared geometry + the renderer branch. Both the canvas
renderer and the gallery thumbnail consume `shapePath`, so this phase MUST complete before any story.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests (write RED first)

- [X] T002 [P] Write `shapePath` geometry tests (RED) in `packages/jet_print/test/rendering/elements/shape_path_test.dart`: for each closed form (ellipse, triangle, diamond, pentagon, hexagon, star) assert the path starts with `MoveTo`, has the expected `LineTo` vertex count (ellipse 64, triangle 3, diamond 4, pentagon 5, hexagon 6, star 10), ends with `ClosePath`, every vertex lies within/on `bounds`, pentagon/hexagon are point-up & equilateral on square bounds, and a 1×1 / 1×N degenerate box does not throw (C6.1–C6.4).
- [X] T003 [P] Write `ShapeElement` domain tests (RED) in `packages/jet_print/test/domain/elements/shape_element_test.dart`: `copyWith` changes each field independently, `clearUnknownForm: true` nulls `unknownForm` while a normal `copyWith` preserves it, and `==`/`hashCode`/`withBounds`/`toString` include `unknownForm`.
- [X] T004 [P] Extend renderer tests (RED) in `packages/jet_print/test/rendering/elements/shape_element_renderer_test.dart`: each new form emits exactly one `PathPrimitive` whose `commands` equal `shapePath(kind, bounds)` and whose fill/stroke/strokeWidth come from `style`; rectangle still emits `RectPrimitive` and line still emits `LinePrimitive` unchanged (C7.1, C7.3).

### Implementation (make GREEN)

- [X] T005 Add the six new `ShapeKind` enum values (ellipse, triangle, diamond, pentagon, hexagon, star) after the existing line/rectangle in `packages/jet_print/lib/src/domain/elements/shape_element.dart` (additive, serialized by `.name`).
- [X] T006 In `packages/jet_print/lib/src/domain/elements/shape_element.dart` add the `String? unknownForm` field, a `copyWith({JetRect? bounds, ShapeKind? kind, JetBoxStyle? style, bool? flipDiagonal, bool clearUnknownForm = false})`, and thread `unknownForm` through `withBounds`, `==`, `hashCode`, and `toString` (depends on T005).
- [X] T007 Create the private geometry source `packages/jet_print/lib/src/rendering/elements/shape_path.dart`: `List<PathCommand> shapePath(ShapeKind kind, JetRect bounds)` returning a closed inscribed polygon per the data-model form table, with `const int kEllipseSegments = 64;`; degenerate-safe; line/rectangle are NOT routed here (depends on T005).
- [X] T008 Add the shape-kind branch to `ShapeElementRenderer.emit` in `packages/jet_print/lib/src/rendering/elements/renderers/shape_element_renderer.dart`: keep `rectangle`→`RectPrimitive` and `line`→`LinePrimitive`; route ellipse/triangle/diamond/pentagon/hexagon/star to one `PathPrimitive(commands: shapePath(el.kind, bounds), ...)` carrying `style` fill/stroke/strokeWidth and `el.id` (depends on T005, T007).

**Checkpoint**: New forms render on the canvas via the shared `shapePath`; domain value type carries `unknownForm`. T002–T004 now GREEN.

---

## Phase 3: User Story 1 - Change a selected shape's form from a visual gallery (Priority: P1) 🎯 MVP

**Goal**: With a shape selected, the Properties pane shows eight thumbnails, highlights the active
form, and a single click switches the shape's form (preserving bounds + style); picking the active
form is a no-op.

**Independent Test**: Select a shape, open Properties, click a thumbnail other than the current form,
and confirm the canvas shape changes to that form with position/size/fill/stroke preserved; re-click
the active form and confirm nothing changes.

### Tests (write RED first)

- [X] T009 [P] [US1] Write command tests (RED) in `packages/jet_print/test/designer/controller/set_shape_kind_command_test.dart`: a pick changes `kind` while preserving `bounds`/`style`; picking the already-active form returns `before` unchanged (no-op, no history, no notify — C3.4/FR-005); switching off `line` resets `flipDiagonal` to false (C5.2); a pick clears `unknownForm` (C8.4); the command is a single notifying step.
- [X] T010 [P] [US1] Extend Properties widget tests (RED) in `packages/jet_print/test/designer/properties_editor_test.dart`: the Shape section with exactly eight thumbnails appears only for a single selected `ShapeElement`, never for text/image/barcode, no-selection, or multi-selection (the multi-selection and no-selection cases fall through to the existing `_EmptyState`, so the gallery is structurally absent — properties_panel.dart:121-128) (C1.1–C1.4, FR-010); the active form's thumbnail is the only highlighted one (C2.1) and an `unknownForm` shape does not falsely highlight rectangle (C2.2); clicking a non-active thumbnail calls `setShapeKind` and updates the model preserving bounds/style (C3.1–C3.3); switching a rectangle to line and back works via the UI (C5.1, C5.3).
- [X] T011 [P] [US1] Extend accessibility tests (RED) in `packages/jet_print/test/designer/accessibility_semantics_test.dart`: each gallery thumbnail exposes a button role + a localized accessible name (its form name) and `selected` for the active one, and is keyboard reachable/activatable (C9.1–C9.2, FR-012).
- [X] T012 [P] [US1] Extend localization tests (RED) in `packages/jet_print/test/designer/localization_test.dart` (and the `_de`/`_tr` variants): `propertiesShape` and the eight `shapeForm*` keys resolve in English, German, and Turkish (C9.3, FR-012).

### Implementation (make GREEN)

- [X] T013 [US1] Create `packages/jet_print/lib/src/designer/controller/commands/set_shape_kind_command.dart`: `SetShapeKindCommand extends EditCommand` whose `apply` finds the `ShapeElement` by id, returns `before` when `kind` is unchanged AND `unknownForm == null` (no-op), else replaces it with `element.copyWith(kind: kind, flipDiagonal: kind == ShapeKind.line ? element.flipDiagonal : false, clearUnknownForm: true)` (depends on T006).
- [X] T014 [US1] Add `void setShapeKind(String id, ShapeKind kind) => _commit(SetShapeKindCommand(id: id, kind: kind));` with dartdoc (single-undo + no-op semantics) to `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (depends on T013).
- [X] T015 [P] [US1] Add the nine localization keys (`propertiesShape`, `shapeFormLine`, `shapeFormRectangle`, `shapeFormEllipse`, `shapeFormTriangle`, `shapeFormDiamond`, `shapeFormPentagon`, `shapeFormHexagon`, `shapeFormStar`) with `@`-descriptions to `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, plus German translations in `jet_print_de.arb` and Turkish in `jet_print_tr.arb`, then regenerate `jet_print_localizations*.dart`.
- [X] T016 [US1] Add the type-gated Shape section to `_elementInspector` in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`: `if (element is ShapeElement)` → `SectionLabel(l10n.propertiesShape)` + a private `_ShapeGallery` of eight `_ShapeThumbnail`s; each thumbnail is a `CustomPaint` drawing `shapePath(kind, thumbRect)` (line/rectangle special-cased) wrapped in `Semantics(button: true, selected: active, label: l10n.<formName>)`, keyboard-focusable, highlighting `element.kind` only when `unknownForm == null`, and tapping a non-active one calls `controller.setShapeKind(element.id, kind)` (depends on T007, T014, T015).
- [X] T017 [US1] Update `packages/jet_print/test/public_api_test.dart` to record the new `ShapeKind` values, `ShapeElement.copyWith`/`unknownForm`, and `JetReportDesignerController.setShapeKind`; confirm `shapePath`/`SetShapeKindCommand`/`_ShapeGallery` stay unexported (depends on T005, T006, T014).

**Checkpoint**: MVP complete — a designer can change a selected shape to any of the eight forms in one click; gallery gating, highlight, no-op, a11y, and l10n all pass. STOP and validate US1 independently.

---

## Phase 4: User Story 2 - Undo and redo a shape change (Priority: P2)

**Goal**: A form change is a single reversible step — one Undo restores the prior form, one Redo
reapplies the new form, with no orphaned intermediate steps.

**Independent Test**: Pick a new form, press Undo (shape reverts in one step), press Redo (new form
returns).

### Tests (write RED first)

- [X] T018 [P] [US2] Add undo/redo tests (RED) in `packages/jet_print/test/designer/controller/set_shape_kind_command_test.dart`: after `setShapeKind` to a star, one `undo()` restores the prior form and one `redo()` reapplies the star (C4.1–C4.2); a sequence rectangle→hexagon→star produces exactly two undo steps and no orphaned intermediate entries (C4.3, SC-005); a no-op pick adds nothing to the undo stack.

### Implementation

- [X] T019 [US2] Confirm `setShapeKind` routes through the existing `_commit`/history path so undo/redo work with no new production code; if T018 reveals any gap (e.g. the no-op still arming undo), fix it in `packages/jet_print/lib/src/designer/controller/commands/set_shape_kind_command.dart` or the `_commit` identity check in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (depends on T013, T014).

**Checkpoint**: Shape-form changes are fully reversible; US1 + US2 both pass independently.

---

## Phase 5: User Story 3 - Chosen shape persists across save, reload, preview, and export (Priority: P3)

**Goal**: Every chosen form survives save→reload unchanged, renders identically on canvas/preview/
export, pre-feature reports load unchanged, and an unrecognized form round-trips losslessly.

**Independent Test**: Set a shape to hexagon, save and reload (still a hexagon), open Preview and
export (identical); open a pre-feature report (loads unchanged).

### Tests (write RED first)

- [X] T020 [P] [US3] Create codec tests (RED) in `packages/jet_print/test/domain/serialization/shape_element_codec_test.dart`: round-trip every known form (`kind` wire-identical); an unrecognized `kind` (e.g. `octagon`) loads as `rectangle` with `unknownForm == 'octagon'` and re-serializes `kind: octagon` (lossless — C8.3); a pre-feature line/rectangle report loads byte-for-byte unchanged and `kReportSchemaVersion` stays 1 (C8.2); after a deliberate pick on an unknown-form shape, `unknownForm` is cleared and the chosen form serializes (C8.4); cover the full round-trip truth table from data-model §3.
- [X] T021 [P] [US3] Add golden tests (RED) under `packages/jet_print/test/designer/goldens/` (`shape_forms_*`): a page containing each new form renders identically on the design canvas, in preview, and in PDF/PNG export; assert existing line/rectangle goldens stay byte-identical (C7.2–C7.3, SC-003).

### Implementation (make GREEN)

- [X] T022 [US3] Make `fromJson` tolerant in `packages/jet_print/lib/src/domain/serialization/shape_element_codec.dart`: parse `kind` via `ShapeKind.values.asNameMap()[raw]`; on an unrecognized name set `kind = ShapeKind.rectangle` and `unknownForm = raw`, else `unknownForm = null`; in `toJson` write `element.unknownForm ?? element.kind.name`. No `kReportSchemaVersion` change (depends on T006).
- [X] T023 [US3] Generate the new-form goldens with `flutter test --update-goldens packages/jet_print`, visually confirm each form, and verify line/rectangle goldens are unchanged in git (depends on T008, T021).

**Checkpoint**: All three stories pass independently; persistence + WYSIWYG verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T024 [P] Add dartdoc to the new public surface — the six `ShapeKind` values, `ShapeElement.copyWith`/`unknownForm` in `packages/jet_print/lib/src/domain/elements/shape_element.dart`, `setShapeKind` in the controller, and `shapePath` in `packages/jet_print/lib/src/rendering/elements/shape_path.dart`.
- [X] T025 [P] Update `packages/jet_print/CHANGELOG.md` with the gallery + six new shape forms + lossless unknown-form round-trip.
- [X] T026 Verify `packages/jet_print/lib/jet_print.dart` re-exports already cover `ShapeElement`/`ShapeKind`/controller; add an export line only if `public_api_test` shows the new surface is unreachable.
- [X] T027 Demonstrate the flow in `apps/jet_print_playground`: select a shape, pick hexagon/star, undo/redo, confirm canvas+preview+export agree (quickstart §1–§3).
- [X] T028 Final gate: run `flutter test packages/jet_print`, `flutter analyze packages/jet_print` (zero warnings), and `dart format --output=none --set-exit-if-changed packages/jet_print` (no diff); walk quickstart.md §4–§6 (line/degenerate edge cases, forward-compat round-trip, a11y/l10n).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup. BLOCKS all user stories (geometry + renderer + domain types are shared).
- **US1 (Phase 3)**: depends on Foundational. Delivers the MVP.
- **US2 (Phase 4)**: depends on US1's command (T013/T014). Mostly verification — minimal new code.
- **US3 (Phase 5)**: depends on Foundational (T006 for `unknownForm`, T008 for rendered goldens). Independent of US1/US2's UI.
- **Polish (Phase 6)**: depends on all targeted stories.

### Within Each Story

- Tests written and FAILING before implementation (Constitution III).
- Foundational: T005 (enum) precedes T006/T007; T007 precedes T008.
- US1: T013 (command) → T014 (controller op) → T016 (gallery UI, also needs T015 l10n + T007 geometry); T017 last.
- US3: T022 (codec) before exercising round-trip; T021 (golden tests) before T023 (generate goldens).

### Parallel Opportunities

- Foundational tests T002, T003, T004 run in parallel (different files).
- T007 (`shape_path.dart`) is a different file from the domain edits T005/T006, but it needs the enum values from T005, so it is not marked [P] (run it after T005, optionally alongside T006).
- US1 tests T009–T012 run in parallel; impl T015 (ARB) is [P] vs T013 (command).
- US3 tests T020 and T021 run in parallel.
- Polish T024 and T025 run in parallel.

---

## Parallel Example: User Story 1 tests

```bash
# Launch all US1 RED tests together (different files):
Task: "Command tests in test/designer/controller/set_shape_kind_command_test.dart"
Task: "Properties widget tests in test/designer/properties_editor_test.dart"
Task: "Accessibility tests in test/designer/accessibility_semantics_test.dart"
Task: "Localization tests in test/designer/localization_test.dart"
```

---

## Implementation Strategy

### MVP First (US1 only)

1. Phase 1 Setup → confirm green baseline.
2. Phase 2 Foundational → enum + `shapePath` + renderer + domain type (forms render on canvas).
3. Phase 3 US1 → gallery, command, controller op, l10n.
4. **STOP and VALIDATE**: select a shape, pick forms, confirm canvas updates and no-op/highlight/a11y hold.

### Incremental Delivery

1. Foundational → forms render.
2. US1 → authoring loop (MVP) → demo.
3. US2 → undo/redo → demo.
4. US3 → persistence + preview/export fidelity → demo.

Each story is an independently testable increment; US2 and US3 do not break US1.
