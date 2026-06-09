---
description: "Task list for Designer Edit Surface — Direct-Manipulation Element Editing"
---

# Tasks: Designer Edit Surface — Direct-Manipulation Element Editing

**Input**: Design documents from `/specs/003-designer-edit-surface/`
**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/designer-edit-api.md](contracts/designer-edit-api.md)

**Tests**: MANDATORY per Constitution Principle III (Test-First, NON-NEGOTIABLE) and Principle IV (golden tests for rendered output). Every story phase writes its tests **before** implementation and they MUST fail first.

**Organization**: Tasks are grouped by user story (priority order) so each story is an independently testable increment built on a shared foundation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: May run in parallel (different files, no dependency on an incomplete task in the same group).
- **[Story]**: US1–US6, mapping to the spec's user stories. Setup / Foundational / Polish carry no story label.
- Every task names an exact file path.

## Path Conventions

- **Library (the product)**: `packages/jet_print/lib/src/...`, tests in `packages/jet_print/test/...`, public entry point `packages/jet_print/lib/jet_print.dart`.
- **Tester app (a consumer)**: `apps/jet_print_tester/...`.
- New library code lives in the **designer** seam under three private clusters — `controller/`, `canvas/`, `interaction/` — plus additive `domain/` helpers and a new public `domain/serialization/report_format.dart` facade (plan §Project Structure).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the new folders, the consumer dependency, and the centralized tunables.

- [x] T001 Create the new private designer-seam folders (`controller/`, `controller/commands/`, `canvas/`, `interaction/`) under `packages/jet_print/lib/src/designer/` and the matching test folders (`controller/`, `canvas/`, `interaction/`, `panels/`, `perf/`) under `packages/jet_print/test/designer/`.
- [ ] T002 [P] Add the `file_selector` dependency (consumer-only) to `apps/jet_print_tester/pubspec.yaml` and run `flutter pub get` from the repo root.
- [x] T003 [P] Add the behavioral-tunable constants (grid 8 pt, snap 6 px, nudge 1 pt / 10 pt, per-type default sizes, 4×4 pt min size, +8/+8 paste offset, 25 %–400 % zoom, 8 px/16 px handle sizes — research D7) in `packages/jet_print/lib/src/designer/canvas/design_tunables.dart`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The public model + serialization, the immutable-snapshot editing controller, and the shared-render canvas shell that EVERY user story builds on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Foundational tests (write FIRST — MUST fail before implementation)

- [x] T004 [P] Extend the public-API import contract test to reference `JetReportDesignerController`, `JetReportFormat`, `ReportTemplate`, the four element types, and geometry/style types through only `package:jet_print/jet_print.dart` (contracts §7.1) in `packages/jet_print/test/public_api_test.dart`.
- [x] T005 [P] Add the `JetReportFormat` lossless round-trip test — `decode(encode(t)) == t` across a fixture incl. `UnknownElement` + parameters/variables/groups, no reordering (contracts §7.4 / SC-002) in `packages/jet_print/test/domain/serialization/report_format_test.dart`.
- [x] T006 [P] Add domain-helper unit tests for `withBounds` (each element type, incl. `UnknownElement` passthrough) and `copyWith` (text/band/template), asserting value-equality and referential preservation of untouched fields (FR-025) in `packages/jet_print/test/domain/elements/element_with_bounds_test.dart` and `packages/jet_print/test/domain/report_template_copywith_test.dart`.
- [x] T007 Add the controller-core unit test — `open` seeds the id sequence past the largest suffix; `undo`/`redo` restore both template and selection; `canUndo`/`canRedo` correct; undo/redo past the ends is a no-op (contracts §7.5 / SC-003) in `packages/jet_print/test/designer/controller/controller_history_test.dart`.

### Additive domain helpers (the move/resize/copy primitives)

- [x] T008 Add abstract `withBounds(JetRect)` to `ReportElement` in `packages/jet_print/lib/src/domain/report_element.dart`.
- [x] T009 [P] Implement `withBounds` + `copyWith({text, style, bounds})` on `TextElement` in `packages/jet_print/lib/src/domain/elements/text_element.dart` (after T008).
- [x] T010 [P] Implement `withBounds` on `ShapeElement` in `packages/jet_print/lib/src/domain/elements/shape_element.dart` (after T008).
- [x] T011 [P] Implement `withBounds` on `ImageElement` in `packages/jet_print/lib/src/domain/elements/image_element.dart` (after T008).
- [x] T012 [P] Implement `withBounds` on `BarcodeElement` in `packages/jet_print/lib/src/domain/elements/barcode_element.dart` (after T008).
- [x] T013 [P] Implement `withBounds` passthrough on `UnknownElement` (preserve the raw map byte-for-byte) in `packages/jet_print/lib/src/domain/unknown_element.dart` (after T008).
- [x] T014 [P] Add `copyWith({type, height, elements, group})` to `ReportBand` in `packages/jet_print/lib/src/domain/report_band.dart`.
- [x] T015 [P] Add `copyWith({name, page, bands, ...})` to `ReportTemplate`, preserving parameters/variables/groups, in `packages/jet_print/lib/src/domain/report_template.dart`.

### Serialization facade (public file-format contract)

- [x] T016 Implement the public `JetReportFormat` facade — `encode`/`decode`/`encodeJson`/`decodeJson`, pre-wiring the built-in element codecs + migrations, stamping `schemaVersion`, throwing `ReportFormatException` on invalid/newer version (contracts §4) in `packages/jet_print/lib/src/domain/serialization/report_format.dart`. Makes T005 pass.

### Editing-state core (controller + snapshots + history)

- [x] T017 [P] Implement `Selection` (immutable id set; `isEmpty`/`contains`/`single`/`with`/`without`/`toggled`) in `packages/jet_print/lib/src/designer/controller/selection.dart`.
- [x] T018 [P] Implement `DesignerDocument` snapshot (`{template, selection}`, value-equal) in `packages/jet_print/lib/src/designer/controller/designer_document.dart`.
- [x] T019 [P] Implement the `EditCommand` abstract base (`String get label`; `DesignerDocument apply(DesignerDocument before)`) in `packages/jet_print/lib/src/designer/controller/edit_command.dart`.
- [x] T020 [P] Implement `EditHistory` (undo/redo snapshot stacks; `push` clears redo; `revision` counter for `shouldRepaint`) in `packages/jet_print/lib/src/designer/controller/edit_history.dart`.
- [ ] T021 [P] Implement `Clipboard` (in-memory `List<ReportElement>`; deep-copy with fresh ids + offset on paste) in `packages/jet_print/lib/src/designer/controller/clipboard.dart`.
- [x] T022 [P] Implement `ElementIdFactory` (monotonic `int`; `'<typeKey><n>'`; seed past the max suffix on `open`) in `packages/jet_print/lib/src/designer/controller/element_id_factory.dart`.
- [x] T022a [P] Add a default-blank-`ReportTemplate` factory (a sensible default `PageFormat` + a default band structure per the spec assumption) in `packages/jet_print/lib/src/designer/controller/default_template.dart`; the no-arg `JetReportDesignerController()` and `const JetReportDesigner()` seed from it (contracts §2).
- [x] T023 Implement the `JetReportDesignerController` skeleton (`ChangeNotifier`; `template`/`selection`/`canUndo`/`canRedo` getters; `open`; `select`/`clearSelection`; `undo`/`redo`; `beginInteraction`/`updateInteraction`/`commitInteraction`/`cancelInteraction` scaffolding; one-history-entry-per-commit plumbing; `notifyListeners`) in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (depends on T017–T022a). Makes T007 pass.

### Public surface

- [x] T024 Export the controller, `JetReportFormat`, and the `ReportTemplate`-reachable model graph (model + geometry + style + parameter/variable/group types) from `packages/jet_print/lib/jet_print.dart` (contracts §1). Makes T004 pass (depends on T016, T023).

### Canvas base infrastructure (shared-render reuse — Constitution IV)

- [x] T025 [P] Implement `CanvasViewTransform` (`scale` + `pan`; `pageToScreen`/`screenToPage`) in `packages/jet_print/lib/src/designer/canvas/canvas_view_transform.dart`.
- [x] T026 [P] Implement `DesignTimeLayout` (template → element id ⇒ absolute page `JetRect` + owning band; band ⇒ page rect; non-paginated top-to-bottom band stacking) in `packages/jet_print/lib/src/designer/canvas/design_time_layout.dart`.
- [x] T027 Implement the design-time frame builder (template + layout → `PageFrame` via the **unchanged** `ElementRenderer.emit` + `FrameBuilder` — Constitution IV, research D1; no duplicated element-drawing code) in `packages/jet_print/lib/src/designer/canvas/design_time_frame.dart` (depends on T026).
- [x] T028 Implement `FrameCustomPainter` wrapping the unchanged `CanvasPainter`, caching the committed frame as a `ui.Picture` and re-blitting under the transform (research D5) in `packages/jet_print/lib/src/designer/canvas/frame_custom_painter.dart` (depends on T027).
- [x] T029 [P] Implement hit-testing (page point → top-most element in z-order; handle hit; hit-area ≥ visual) in `packages/jet_print/lib/src/designer/canvas/hit_test.dart` (depends on T026).
- [x] T030 Implement the `DesignCanvas` host shell (`Focus` + `CustomPaint` + `DragTarget` + pointer/gesture wiring scaffold; base/interaction/overlay paint layers; reads the controller) in `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` (depends on T025, T028, T029).

### Widget shell + test harness

- [x] T031 Convert `JetReportDesigner` to a `StatefulWidget` with optional `controller`/`initialReport`/`onSaveRequested`/`onOpenRequested` (still `const`-constructible with no args over a default blank template), providing the controller down-tree via `InheritedNotifier` (contracts §2, research D6) in `packages/jet_print/lib/src/designer/jet_report_designer.dart`.
- [x] T032 Replace the static A4 placeholder in `DesignerSurface` with the live `DesignCanvas` (reads the controller via the `InheritedNotifier`) in `packages/jet_print/lib/src/designer/layout/designer_surface.dart` (depends on T030, T031).
- [x] T033 [P] Extend the test harness (pump `JetReportDesigner` with a supplied controller; canvas keys/finders; page↔screen helpers) in `packages/jet_print/test/designer/support/designer_harness.dart`.
- [x] T034 [P] Add the backward-compat construction test (`const JetReportDesigner()` still constructs — 002 contract) AND assert the no-arg controller yields the default blank template's band structure (contracts §2, T022a) in `packages/jet_print/test/designer/jet_report_designer_test.dart` (contracts §7.3).

**Checkpoint**: Public model + format exposed and round-trip-tested; controller with undo/redo green; the surface hosts a live (empty-capable) canvas. User stories can now begin.

---

## Phase 3: User Story 1 - Place and position elements on the page (Priority: P1) 🎯 MVP

**Goal**: Drag a toolbox element type onto a band to create a real model element at the drop point; click to select (outline + handles); drag to reposition; positions stay within the band/page and survive a save/reload round-trip.

**Independent Test**: In the designer, drag each toolbox type onto a band → a corresponding element appears at the pointer in that band and is selected; click selects (handles show); empty-click clears; drag moves and commits the model position; dragging past bounds is constrained; the placed/moved positions survive a `JetReportFormat` round-trip.

### Tests for User Story 1 (write FIRST — MUST fail)

- [x] T035 [P] [US1] `CreateElementCommand` + `MoveCommand` unit tests (typed default element at a band point with a fresh id, selected; move via `withBounds` clamped to band ∩ page; non-destructive to siblings) in `packages/jet_print/test/designer/controller/create_move_command_test.dart`.
- [x] T036 [P] [US1] Drop-create + click-select + drag-move widget tests (each toolbox type drops at the pointer in the target band; click selects + shows 8 handles; empty-click clears; drag moves + commits on release; off-page drag constrained — contracts §7.6 / acceptance US1.1–US1.5) in `packages/jet_print/test/designer/canvas/place_select_move_test.dart`.

### Implementation for User Story 1

- [x] T037 [P] [US1] Implement `CreateElementCommand` (insert a typed element with default size/attrs from tunables + fresh id; route/reject an invalid drop band; select the new element) in `packages/jet_print/lib/src/designer/controller/commands/create_element_command.dart`.
- [x] T038 [P] [US1] Implement `MoveCommand` (new bounds via `withBounds`, clamped to owning band ∩ page content area; multi-element aware) in `packages/jet_print/lib/src/designer/controller/commands/move_command.dart`.
- [x] T039 [US1] Add `createElement(type, bandId, atPage)`, single-click `select`, and move-interaction commit (`moveBy` + begin/update/commit) to the controller in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (depends on T037, T038).
- [x] T040 [US1] Implement toolbox drag payloads (`Draggable<DesignerToolType>`) + click-to-place, and the canvas `DragTarget` drop → page-coordinate conversion → `createElement`, in `packages/jet_print/lib/src/designer/interaction/toolbox_drag.dart` and `packages/jet_print/lib/src/designer/layout/designer_toolbox.dart` (depends on T039).
- [x] T041 [US1] Implement the selection overlay (selection outline + 8 resize handles; body-drag move ghost; drop hint) in `packages/jet_print/lib/src/designer/canvas/selection_overlay.dart`.
- [x] T042 [US1] Wire canvas pointer/gesture handling for click-select, empty-click-clear, and body-drag move (begin/update/commit interaction) in `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` (depends on T039, T041).

**Checkpoint**: An author can place, select, and move elements by direct manipulation; positions round-trip losslessly. MVP is demoable.

---

## Phase 4: User Story 2 - Size and align elements precisely (Priority: P2)

**Goal**: Resize a selected element via handles (live feedback, min-size floor) and snap edges/centers to grid, siblings, and band/page boundaries with on-screen guides; an Alt/Option modifier bypasses snapping.

**Independent Test**: Resize via each handle (min-size enforced, live feedback, model w/h commit on release); drag/resize near a sibling edge/center and a band boundary → snaps and a guide appears; hold the snap-bypass modifier → free placement; grid-enabled positions/sizes snap to the increment.

### Tests for User Story 2 (write FIRST — MUST fail)

- [x] T043 [P] [US2] `ResizeCommand` + snapping unit tests (per-handle resize, 4×4 pt floor, model w/h commit; snap to grid / sibling edges+centers / band+page bounds within threshold; bypass flag) in `packages/jet_print/test/designer/controller/resize_command_test.dart` and `packages/jet_print/test/designer/canvas/snapping_test.dart`.
- [x] T044 [P] [US2] Resize + snap-guide widget test (drag each handle resizes with live feedback; snap + guide line appears; Alt/Option bypasses — contracts §7.6 / SC-004 / acceptance US2.1–US2.4) in `packages/jet_print/test/designer/canvas/resize_snap_test.dart`.

### Implementation for User Story 2

- [x] T045 [P] [US2] Implement `ResizeCommand` (per-handle resize, min 4×4 pt floor with the line one-axis exception, clamp to band ∩ page) in `packages/jet_print/lib/src/designer/controller/commands/resize_command.dart`.
- [x] T046 [P] [US2] Implement snapping (grid + sibling edges/centers + band/page bounds → `SnapResult` + `SnapGuide`s; screen-px threshold converted via the live zoom; Alt/Option bypass) in `packages/jet_print/lib/src/designer/canvas/snapping.dart` (depends on T025).
- [x] T046a [P] [US2] Add a grid-toggle snapping test — with the grid enabled, move/resize snaps positions/sizes to the grid increment; with it disabled, grid snap is suppressed (sibling/band snap unaffected); `snapEnabled == false` suppresses all snapping (US2.4 / FR-011) in `packages/jet_print/test/designer/canvas/snapping_test.dart` (extend; write FIRST — MUST fail).
- [x] T046b [US2] Add `gridEnabled` / `snapEnabled` boolean state to the controller (default on; `setGridEnabled`/`setSnapEnabled`; notifies) in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`, and consult both flags in `packages/jet_print/lib/src/designer/canvas/snapping.dart` (T046). Makes T046a pass.
- [x] T047 [US2] Add `resizeTo` + resize-interaction commit (snapping applied during the gesture, honoring `gridEnabled`/`snapEnabled` — T046b) to the controller in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (depends on T045, T046).
- [x] T048 [US2] Add handle-drag resize gestures + live snap-guide rendering to the canvas and overlay in `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` and `packages/jet_print/lib/src/designer/canvas/selection_overlay.dart` (depends on T047).

**Checkpoint**: Elements resize precisely and snap/align with guides; bypass works. US1 + US2 both functional.

---

## Phase 5: User Story 3 - Undo and redo every change (Priority: P2)

**Goal**: Every state-changing edit is undoable/redoable in order, unbounded in-session, restoring model **and** selection; a new edit after undo discards the redo stack; controls indicate (un)availability at the ends.

**Independent Test**: Perform create/move/resize edits; undo each in reverse (canvas + model + selection revert exactly); redo re-applies in order; a new edit after undo discards redo; undo/redo past the ends is a no-op with the controls disabled.

> The snapshot history engine is foundational (T020, T023); this phase guarantees full edit coverage and binds the user-facing controls/shortcuts.

### Tests for User Story 3 (write FIRST — MUST fail)

- [x] T049 [P] [US3] Undo/redo sequence test — a ≥50-step create/move/resize sequence (SC-003) undoes in reverse and redoes in order with model + selection exact at every step; a new edit after undo discards redo; past-the-end is a no-op (contracts §7.5 / SC-003 / acceptance US3.1–US3.4) in `packages/jet_print/test/designer/controller/undo_redo_sequence_test.dart`.
- [x] T050 [P] [US3] Top-bar undo/redo widget test — buttons reflect `canUndo`/`canRedo` and drive `controller.undo`/`redo`; `⌘Z`/`⇧⌘Z` act only when the canvas is focused in `packages/jet_print/test/designer/interaction/undo_redo_controls_test.dart`.

### Implementation for User Story 3

- [x] T051 [US3] Audit that every command commit pushes the prior `DesignerDocument` and clears redo (create/move/resize) via the controller's single commit path in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`.
- [x] T052 [US3] Wire the top-bar Undo/Redo buttons to `controller.undo`/`redo` with enablement bound to `canUndo`/`canRedo` in `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart`.
- [x] T053 [US3] Introduce canvas-focus-scoped `Shortcuts`/`Actions` with undo/redo bindings in `packages/jet_print/lib/src/designer/interaction/canvas_shortcuts.dart` and mount it on the canvas focus node in `packages/jet_print/lib/src/designer/canvas/design_canvas.dart`.

**Checkpoint**: Undo/redo reverses/replays every edit (model + selection); controls reflect availability.

---

## Phase 6: User Story 4 - Edit many elements at once (Priority: P3)

**Goal**: Multi-select (marquee, shift-click, select-all), then move/nudge/delete/duplicate/cut-copy-paste/reorder (z-order)/align/distribute the whole selection — each undoable.

**Independent Test**: Marquee several elements; nudge with arrows (Shift = larger); delete; copy/paste (offset, becomes new selection); duplicate; bring-forward/send-back changes draw order; align-left / distribute act on the group; each is undoable.

### Tests for User Story 4 (write FIRST — MUST fail)

- [x] T054 [P] [US4] Bulk-command unit tests — `Delete`/`Reorder`/`Clipboard`(paste, duplicate)/`Align`/`Distribute`/`Nudge` against a fixture (acts on the whole selection; offset on paste/duplicate with fresh ids; reorder within `band.elements`; undoable) in `packages/jet_print/test/designer/controller/bulk_commands_test.dart`.
- [x] T055 [P] [US4] Multi-select + bulk widget tests — marquee encloses → selects; shift-click add/remove; select-all; arrow nudge (Shift larger); delete; copy/paste; duplicate; bring-forward/send-back; align-left/distribute (contracts §7.6 / acceptance US4.1–US4.6) in `packages/jet_print/test/designer/canvas/marquee_multiselect_test.dart` and `packages/jet_print/test/designer/interaction/keyboard_clipboard_test.dart`.

### Implementation for User Story 4

- [x] T056 [P] [US4] Implement `DeleteCommand` (remove selected elements from their bands) in `packages/jet_print/lib/src/designer/controller/commands/delete_command.dart`.
- [x] T057 [P] [US4] Implement `ReorderCommand` (forward/back/to-front/to-back within `band.elements`) in `packages/jet_print/lib/src/designer/controller/commands/reorder_command.dart`.
- [x] T058 [P] [US4] Implement `ClipboardCommand` (paste/duplicate; +8/+8 offset copies; fresh ids; select the new elements) in `packages/jet_print/lib/src/designer/controller/commands/clipboard_command.dart`.
- [x] T059 [P] [US4] Implement `AlignCommand` (left/center/right/top/middle/bottom) in `packages/jet_print/lib/src/designer/controller/commands/align_command.dart`.
- [x] T060 [P] [US4] Implement `DistributeCommand` (horizontal/vertical) in `packages/jet_print/lib/src/designer/controller/commands/distribute_command.dart`.
- [x] T061 [P] [US4] Implement `NudgeCommand` (1 pt arrow / 10 pt Shift+arrow) in `packages/jet_print/lib/src/designer/controller/commands/nudge_command.dart`.
- [x] T062 [US4] Add `selectAll`/`addToSelection`/`toggle`, `delete`, `cut`/`copy`/`paste`/`duplicate`, `bringForward`/`sendBackward`/`bringToFront`/`sendToBack`, `align`/`distribute`, `nudge` methods to the controller in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (depends on T056–T061).
- [x] T063 [US4] Implement marquee drag (rubber-band rect; enclosed → selection on release) + shift-click add/remove in `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` and `packages/jet_print/lib/src/designer/canvas/selection_overlay.dart` (depends on T062).
- [x] T064 [US4] Extend the canvas shortcuts with nudge/Shift-nudge, delete, copy/cut/paste/duplicate, select-all, Escape-clear (FR-006) (canvas-focus-scoped) in `packages/jet_print/lib/src/designer/interaction/canvas_shortcuts.dart` (depends on T062).
- [X] T065 [US4] Add z-order + align/distribute action affordances (top-bar and/or canvas context menu) wired to the controller in `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart` (depends on T062).

**Checkpoint**: Bulk operations act on the whole selection and are undoable. US1–US4 functional.

---

## Phase 7: User Story 5 - See and adjust the selection across panels (Priority: P3)

**Goal**: Canvas selection ↔ Outline highlight ↔ Properties reflection; edit geometry (x/y/w/h) in Properties and text inline (double-click) on the canvas — all reflected immediately and undoable.

**Independent Test**: Select on canvas → Outline highlights + Properties shows details; select an Outline row → canvas selects + handles + scroll-into-view; edit a Properties number → canvas updates and the edit is undoable; double-click a text element → inline edit commits and is undoable.

### Tests for User Story 5 (write FIRST — MUST fail)

- [x] T066 [P] [US5] `SetGeometryCommand` + `SetTextCommand` unit tests (numeric x/y/w/h set + clamp; text set; non-destructive; undoable) in `packages/jet_print/test/designer/controller/geometry_text_command_test.dart`.
- [X] T067 [P] [US5] Cross-panel sync + inline-edit widget tests — canvas select → Outline highlight + Properties reflect; Outline row → canvas select + scroll-into-view; Properties number edit → canvas updates (undoable); double-click text → inline edit commits (contracts §7.7 / SC-005 / acceptance US5.1–US5.3) in `packages/jet_print/test/designer/panels/cross_panel_sync_test.dart` and `packages/jet_print/test/designer/canvas/inline_text_edit_test.dart`. Scroll-into-view implemented in `design_canvas.dart` (per-element `GlobalKey` + controller listener → `Scrollable.ensureVisible`).

### Implementation for User Story 5

- [x] T068 [P] [US5] Implement `SetGeometryCommand` (set x/y/w/h numerically, clamped to band ∩ page) in `packages/jet_print/lib/src/designer/controller/commands/set_geometry_command.dart`.
- [x] T069 [P] [US5] Implement `SetTextCommand` (set a text element's `text` via `copyWith`) in `packages/jet_print/lib/src/designer/controller/commands/set_text_command.dart`.
- [x] T070 [US5] Add `setGeometry(...)` and `setText(...)` to the controller in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (depends on T068, T069).
- [X] T071 [US5] Make the Outline panel model-driven (tree from `template`; highlight `selection`; row tap → `controller.select`) in `packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart` (depends on T070). NOTE: canvas scroll/zoom-into-view on selection is deferred to T067 (the cross-panel sync task that exercises it).
- [X] T072 [US5] Make the Properties panel model-driven (x/y/w/h numeric fields bound to `setGeometry`; text field for a single text element bound to `setText`) in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (depends on T070). Context-aware: also edits band height (`setBandHeight`), shows read-only report/page info, and an empty state.
- [x] T073 [US5] Implement the inline text editor overlay (double-click a text element → positioned `ShadInput` at the current scale; commit on Enter/blur via `setText`) in `packages/jet_print/lib/src/designer/canvas/inline_text_editor.dart` and wire it into `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` (depends on T070).

**Checkpoint**: The designer coheres as one tool — selection and geometry/text edits sync across canvas and panels, undoable. US1–US5 functional.

---

## Phase 8: User Story 6 - Navigate and view large designs (Priority: P4)

**Goal**: Zoom in/out, fit-to-page/width, and pan, keeping placement and hit-testing pointer-accurate (pointer → page coordinate) at every zoom level.

**Independent Test**: Zoom in/out via controls and shortcuts; fit-to-page/width centers the page; pan scrolls without moving elements relative to the page; a drop lands at the pointer's page position at every zoom level.

### Tests for User Story 6 (write FIRST — MUST fail)

- [x] T074 [P] [US6] Zoom-accuracy + pan/fit widget test — a drop/placement lands at the pointer's page position across zoom levels; pan scrolls without page-relative movement; fit-to-page/width centers (contracts §7.8 / SC-006 / acceptance US6.1–US6.3) in `packages/jet_print/test/designer/canvas/zoom_pan_test.dart`.

### Implementation for User Story 6

- [x] T075 [US6] Add zoom in/out, fit-to-page, fit-to-width, and pan to the canvas (mouse-wheel/gesture pan + zoom via `CanvasViewTransform`, clamped to 25 %–400 %) in `packages/jet_print/lib/src/designer/canvas/design_canvas.dart`.
- [x] T076 [US6] Wire the top-bar zoom controls (in/out/fit/percentage) to the canvas transform in `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart` (depends on T075).
- [x] T077 [US6] Add zoom/fit keyboard shortcuts (canvas-focus-scoped) in `packages/jet_print/lib/src/designer/interaction/canvas_shortcuts.dart` (depends on T075).

**Checkpoint**: The whole feature is navigable and pointer-accurate at any zoom. All user stories functional.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Localization, fidelity goldens, performance, persistence wiring, docs, and the merge gates.

- [ ] T078 [P] Add the new localized strings (context-menu/tooltip/a11y/drop-hint/align/distribute/z-order/zoom action names) to `jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb` and run `flutter gen-l10n`, in `packages/jet_print/lib/src/designer/l10n/`.
- [ ] T079 [P] Extend the localization tests (new affordance strings render in en/de/tr; English fallback; no blank/raw-key labels — SC-008) in `packages/jet_print/test/designer/localization_test.dart`, `localization_de_test.dart`, `localization_tr_test.dart`.
- [ ] T079a [P] Add an accessibility/semantics widget test — assert localized accessible names + roles on the 8 resize handles, on canvas element regions (e.g. "Text element …"), and on the align/distribute/z-order/zoom/save/open menu actions, and that each new affordance is focus-reachable and keyboard-operable with no mouse (SC-008 / FR-024) in `packages/jet_print/test/designer/accessibility_semantics_test.dart` (write FIRST — MUST fail).
- [ ] T079b Attach `Semantics` labels/roles (using the localized strings from T078) to the selection handles in `packages/jet_print/lib/src/designer/canvas/selection_overlay.dart`, the element hit regions in `packages/jet_print/lib/src/designer/canvas/design_canvas.dart`, and the menu/toolbar actions in `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart` (depends on T078). Makes T079a pass.
- [ ] T080 [P] Add design-surface goldens (representative elements with a selection shown, light + dark, via the shared render pipeline — Constitution IV; generate with `flutter test --update-goldens`) in `packages/jet_print/test/designer/goldens/`.
- [ ] T081 [P] Add the 200-element drag perf smoke (a 20-element selection drag within the frame budget, no exceptions — SC-007) in `packages/jet_print/test/designer/perf/large_design_drag_test.dart`.
- [ ] T082 Wire the tester app to own a `JetReportDesignerController` and implement `onSaveRequested`/`onOpenRequested` via `file_selector` + `JetReportFormat.encodeJson`/`decodeJson` (FR-022 open/save) in `apps/jet_print_tester/lib/main.dart` (research D8).
- [ ] T083 Wire the top-bar Save/Open actions to `onSaveRequested`/`onOpenRequested` and the grid/snap toggles to the controller in `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart` (depends on T031).
- [ ] T084 [P] Update the app consumer test to exercise a basic edit → save → reopen path through the public API in `apps/jet_print_tester/test/app_consumes_library_test.dart`.
- [ ] T085 [P] Add dartdoc to all new public symbols (controller operations; designer params noting geometry + text-only editing this iteration; `JetReportFormat`; model types) and update `packages/jet_print/CHANGELOG.md` (Constitution VI).
- [ ] T086 Verify the encapsulation + layer-boundary architecture tests still pass (no `package:jet_print/src/...` import leaks; domain stays UI-free) in `packages/jet_print/test/encapsulation_test.dart` and `packages/jet_print/test/architecture/layer_boundaries_test.dart`.
- [ ] T087 Run the full merge gate from `packages/jet_print`: `flutter gen-l10n`, `flutter analyze` (zero warnings), `dart format --output=none --set-exit-if-changed .`, `flutter test` (all green, no skips); then run the `quickstart.md` §6 acceptance walkthrough.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — **BLOCKS all user stories**. Within it: tests (T004–T007) first; domain helpers (T008 → T009–T015); format facade (T016); controller core (T017–T023, incl. T022a default-template factory); public export (T024, after T016 + T023); canvas infra (T025–T030); shell + harness (T031–T034).
- **User Stories (Phases 3–8)**: All depend on Foundational. Ordered by priority (US1 → US2 → US3 → US4 → US5 → US6). Each is an independently testable increment; later stories layer onto, but do not break, earlier ones.
- **Polish (Phase 9)**: Depends on all targeted user stories being complete.

### User Story Dependencies

- **US1 (P1)**: Foundational only. The MVP.
- **US2 (P2)**: Foundational; reuses US1's interaction plumbing but is independently testable (resize + snapping).
- **US3 (P2)**: Foundational history; coverage test exercises US1/US2 edits — independently testable.
- **US4 (P3)**: Foundational + controller selection; bulk commands are independent of US2/US3 internals.
- **US5 (P3)**: Foundational + controller; panels/inline-edit are independent of US4.
- **US6 (P4)**: Foundational transform; independent of US2–US5.

### Within Each User Story

- Tests are written FIRST and MUST fail before implementation (Constitution III).
- Command/value files (often `[P]`) → controller integration method → canvas/panel wiring.
- The single-file hotspots — `jet_report_designer_controller.dart`, `canvas/design_canvas.dart`, `canvas/selection_overlay.dart`, `interaction/canvas_shortcuts.dart` — are touched across stories, so their per-story tasks are **sequential**, not `[P]`, with each other.

### Parallel Opportunities

- All `[P]` Setup tasks (T002, T003).
- Foundational tests T004–T006 together; domain-helper impls T009–T015 together (after T008); controller value types T017–T022 together; canvas value types T025, T026, T029 together.
- Within a story, the `[P]` command/value files run together before their (sequential) integration + wiring tasks — e.g. US4's T056–T061.
- Most Polish tasks (T078–T081, T084, T085) run together.

---

## Parallel Example: User Story 4

```bash
# After the US4 tests (T054, T055) are written and failing, build the commands in parallel:
Task: "Implement DeleteCommand in .../controller/commands/delete_command.dart"
Task: "Implement ReorderCommand in .../controller/commands/reorder_command.dart"
Task: "Implement ClipboardCommand in .../controller/commands/clipboard_command.dart"
Task: "Implement AlignCommand in .../controller/commands/align_command.dart"
Task: "Implement DistributeCommand in .../controller/commands/distribute_command.dart"
Task: "Implement NudgeCommand in .../controller/commands/nudge_command.dart"
# Then T062 (controller methods) → T063/T064/T065 (canvas, shortcuts, top-bar) sequentially.
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup.
2. Phase 2: Foundational (CRITICAL — public model + format + controller + shared-render canvas shell).
3. Phase 3: US1 — place, select, move.
4. **STOP and VALIDATE**: drop each element type, select, move, and confirm a `JetReportFormat` round-trip — the spec's US1 Independent Test.
5. Demo the MVP.

### Incremental Delivery

1. Setup + Foundational → foundation ready (canvas live, model public, round-trip green).
2. US1 → place/select/move → demo (MVP).
3. US2 → resize + snapping/guides → demo.
4. US3 → undo/redo controls → demo.
5. US4 → multi-select + bulk ops → demo.
6. US5 → cross-panel sync + properties + inline text → demo.
7. US6 → zoom/pan/fit → demo.
8. Polish → localization, goldens, perf, persistence wiring, docs, gates.

### Parallel Team Strategy

After Foundational completes, US2/US3/US4/US5/US6 can be staffed in parallel (each independently testable), coordinating only on the shared controller/canvas hotspots noted above; US1 is the prerequisite demo that proves the foundation.

---

## Notes

- `[P]` = different files, no incomplete-dependency in the same group; everything else is sequential.
- `[Story]` labels (US1–US6) map every story task to a spec user story for traceability.
- Tests are MANDATORY and written before implementation; verify they fail first (Constitution III). Goldens are updated only for an intended, reviewed visual change (Constitution IV).
- Constitution gates run continuously: zero analyzer warnings, `dart format` clean, no skipped tests, encapsulation + layer-boundary tests green, all new visible text localized (en/de/tr + English fallback).
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.
