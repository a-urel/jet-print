---
description: "Task list for Grid & Snap Helper Tools"
---

# Tasks: Grid & Snap Helper Tools

**Input**: Design documents from `/specs/015-grid-snap-tools/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/grid-snap.md](contracts/grid-snap.md)

**Tests**: MANDATORY for jet-print (Constitution Principle III — Test-First, NON-NEGOTIABLE). Test tasks precede the implementation they cover; the suite stays green at every checkpoint. Existing invoice goldens (Principle IV) must stay unchanged.

**Organization**: Grouped by user story. US1 and US2 are both P1 and file-disjoint (canvas painter vs controller snap) → parallelizable after Foundational. US3/US4 build on US1's painter.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1–US4 (Setup/Foundational/Polish carry no story label)
- All paths are repo-relative.

## Path conventions

- Library: `packages/jet_print/lib/src/designer/…`
- Tests: `packages/jet_print/test/designer/…`
- Run: `flutter test packages/jet_print` from the repo root.

---

## Phase 1: Setup

**Purpose**: Establish a known-green baseline before any change.

- [X] T001 Confirm baseline green: run `flutter test packages/jet_print` from repo root and record it passes (no skips), so later step/decoupling changes are attributable.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared 5 mm constant and the pure grid-line helper that BOTH the visible grid (US1) and grid snapping (US2/US3) depend on. Changing `kGridStep` ripples into existing snap tests, so their expectations are reconciled here to keep the suite green.

**⚠️ CRITICAL**: No user story work begins until this phase is complete.

- [X] T002 [P] Write `packages/jet_print/test/designer/canvas/grid_geometry_test.dart` covering `gridLineOffsets` ENUMERATION only (contracts C1.1, C1.4, C1.5): multiples of `step` ascending within `[0, extent]`, last line ≤ extent, degenerate `extent = 0`. (Thinning cases C1.2/C1.3 are added later in US3.) Tests fail (no source yet).
- [X] T003 [P] Update tunables in `packages/jet_print/lib/src/designer/canvas/design_tunables.dart`: add `const double kGridStepMm = 5;`, change `kGridStep` to `kGridStepMm * 72 / 25.4` (≈14.173 pt) with a dartdoc cross-referencing `kPointsPerMm`, add `const double kGridMinLineGapPx = 4;` (min on-screen gap between drawn lines), and add `const int kGridMaxCoarsenFactor = 4;` (hide the grid rather than draw lines coarser than `4·5 mm = 20 mm`). (Decision D2/D4.)
- [X] T004 Create `packages/jet_print/lib/src/designer/canvas/grid_geometry.dart` with pure `List<double> gridLineOffsets(double extent, double step, double scale, double minGapPx)` returning multiples of `step` within `[0, extent]` (NO coarsening yet — `f = 1`). `dart:math` only; no Flutter/domain/render import. Makes T002 GREEN. (Depends on T003 for `step` semantics.)
- [X] T005 Reconcile existing snap expectations to the 5 mm step (still coupled semantics): update expected snapped coordinates in `packages/jet_print/test/designer/canvas/snapping_test.dart` and `packages/jet_print/test/designer/canvas/resize_snap_test.dart` from multiples of 8 to multiples of `kGridStep`. Run `flutter test packages/jet_print` → suite GREEN. (Depends on T003.)

**Checkpoint**: 5 mm grid step in place, pure line helper unit-tested, full suite green — US1 and US2 can start in parallel.

---

## Phase 3: User Story 1 — Show and hide an alignment grid (Priority: P1) 🎯 MVP

**Goal**: The grid button draws/hides a 5 mm grid as backmost design-time chrome on the page.

**Independent Test**: With snapping off, toggle the grid button → a 5 mm grid appears over the page content and disappears again; element appearance/positions unchanged.

### Tests for User Story 1 (write first, must FAIL)

- [X] T006 [P] [US1] Write `packages/jet_print/test/designer/canvas/grid_test.dart` (contracts C2.1–C2.5): grid painted when `gridEnabled == true`; absent when `false`; painted BEHIND band separators/elements/selection overlay (backmost); per-band registration with ≥2 bands whose heights aren't 5 mm multiples (lines restart at each band top); default-on reflected in the grid button. Tests fail (no painter yet).
- [X] T007 [P] [US1] Extend `packages/jet_print/test/designer/top_bar_test.dart` for contract C5.1: tapping the grid button flips `controller.gridEnabled`, leaves `snapEnabled` unchanged, and reflects active state. (Verify-or-extend existing toggle test.)

### Implementation for User Story 1

- [X] T008 [US1] Add a private `_GridPainter extends CustomPainter` in `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` (mirroring `_BandChromePainter`): inputs `layout`, `scale`, `step = kGridStep`, muted grid `color`; for each `layout.bandRects` draw vertical lines at `gridLineOffsets(band.width, step, scale, kGridMinLineGapPx)` and horizontal lines at `gridLineOffsets(band.height, …)`, translated by the band origin and `· scale`, clipped to the band rect; `shouldRepaint` on `scale`/`layout`/`color`. (Decisions D5/D7.)
- [X] T009 [US1] In `_buildPage` (`design_canvas.dart`), insert `Positioned.fill(child: CustomPaint(painter: _GridPainter(...)))` as the FIRST child of the page `Stack` (before `_BandChromePainter`), constructed only when `controller.gridEnabled`. Makes T006 GREEN. (FR-001/FR-002/FR-003/FR-004.)

**Checkpoint**: Grid visibly toggles on the canvas; suite green. MVP demoable.

---

## Phase 4: User Story 2 — Snap elements to the grid while editing (Priority: P1)

**Goal**: Snapping aligns edges to the 5 mm grid during move/resize, governed solely by the snap tool (decoupled from grid visibility).

**Independent Test**: With snap on, drag an edge near a 5 mm line → commits on the grid; turn snap off → free movement; with snap on + grid hidden → still snaps.

### Tests for User Story 2 (write first, must FAIL)

- [X] T010 [P] [US2] Update `packages/jet_print/test/designer/canvas/snapping_test.dart` for decoupling (contracts C4.1, C4.3, C4.4, C4.6): re-express the two grid-off cases (currently `setGridEnabled(false)`) as `setSnapEnabled(false)`; ADD C4.4 — `snapEnabled == true` with `gridEnabled == false` still snaps to grid lines; keep the pure-helper `grid:true/false` cases (C4.6). C4.4 fails under current coupling.
- [X] T011 [P] [US2] Update `packages/jet_print/test/designer/controller/move_commit_teardown_test.dart` (line ~25): replace `setGridEnabled(false)` with `setSnapEnabled(false)` so the teardown still suppresses snapping under the new semantics.
- [X] T012 [P] [US2] Add a snap-bypass assertion (contract C4.5) in `packages/jet_print/test/designer/canvas/resize_snap_test.dart`: holding the bypass modifier (`bypassSnap`) suspends snapping for the drag without changing toggle state.
- [X] T013 [P] [US2] Extend `top_bar_test.dart` for contract C5.2: tapping the snap button flips `controller.snapEnabled`, leaves `gridEnabled` unchanged, reflects active state.

### Implementation for User Story 2

- [X] T014 [US2] In `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`, change both snap call-sites `grid: _gridEnabled` → `grid: true` (in `updateMove` ~L258 and `updateResize` ~L385), so grid snapping is governed solely by the `_snapEnabled` guard. (Decision D3 / FR-010.) Makes T010–T011 GREEN.
- [X] T015 [US2] Update dartdoc/semantics in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`: `gridEnabled`/`setGridEnabled` now mean "whether the alignment grid is DRAWN" (visibility only, no longer gates snapping); `snapEnabled` doc stays "all snapping (grid + sibling + band)". (FR-010, Principle VI.)

**Checkpoint**: Snapping at 5 mm governed by the magnet alone; grid visibility independent; suite green.

---

## Phase 5: User Story 3 — Grid stays aligned and readable across zoom & pan (Priority: P2)

**Goal**: The grid stays page-registered through zoom/pan and thins (then hides) when zoomed out so it never becomes a solid fill.

**Independent Test**: Show grid, zoom out far → grid thins/hides (not a solid block); zoom in / scroll → stays registered to the page.

### Tests for User Story 3 (write first, must FAIL)

- [X] T016 [P] [US3] Extend `packages/jet_print/test/designer/canvas/grid_geometry_test.dart` with adaptive-density cases (contracts C1.2, C1.3): when `step·scale < minGapPx`, output coarsens to `step·f` (smallest integer `f` clearing `minGapPx`), values still multiples of `step`; past a coarsening cap, returns `[]` (hidden). Fails against the no-coarsening T004 impl.
- [X] T017 [P] [US3] Write `packages/jet_print/test/designer/canvas/grid_alignment_test.dart` (contracts C3.1–C3.3, mirroring `ruler_alignment_test.dart`/`zoom_pan_test.dart`): a page position maps to the same grid line at min/100%/max zoom; grid scrolls with the page; zoom far out → grid thins/hides (page not a solid fill).

### Implementation for User Story 3

- [X] T018 [US3] Add adaptive coarsening + hide to `gridLineOffsets` in `packages/jet_print/lib/src/designer/canvas/grid_geometry.dart`: compute `f = max(1, ⌈minGapPx / (step·scale)⌉)`; if `f > kGridMaxCoarsenFactor` return `[]` (grid hidden — never coarser than `kGridMaxCoarsenFactor·step`); else emit multiples of `step·f`. Makes T016 GREEN. (FR-006/SC-006.) Painter already passes `kGridMinLineGapPx` (T008), so T017 alignment/thinning passes GREEN.

**Checkpoint**: Grid legible and registered across the full zoom range; suite green.

---

## Phase 6: User Story 4 — Grid is a design aid only, never in output (Priority: P3)

**Goal**: Prove the grid never reaches preview/export/print or the saved template, and adds no public/cross-layer surface.

**Independent Test**: With grid visible, open preview/export → no grid; save+reload template → grid/snap state absent and render identical.

### Tests for User Story 4 (write first, must FAIL/confirm)

- [X] T019 [P] [US4] Add a preview/export non-regression assertion (contract C6.1) in `packages/jet_print/test/designer/canvas/grid_output_test.dart` (new): with `gridEnabled == true`, the preview/export path produces output identical to grid-off, and existing invoice preview/export goldens are unchanged. Reuse the existing golden/render harness; assert no grid in the rendered model output.
- [X] T020 [P] [US4] Add/confirm a serialization round-trip test (contract C5.3) in `packages/jet_print/test/` (extend the existing codec round-trip test, else new `test/codec/grid_snap_not_serialized_test.dart`): toggling grid/snap then encode→decode the template is byte-identical and grid/snap state is absent from the document; render identical.
- [X] T021 [P] [US4] Verify architecture/public-API guards (contract C6.2): confirm `grid_geometry.dart` is covered by `layer_boundaries_test` (no Flutter/domain/render import) and `public_api_test` shows no new exported symbol; extend expectations only if the new file isn't auto-scanned.

**Checkpoint**: WYSIWYG + serialization guarantees pinned; no API/boundary drift; suite green.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T022 [P] Update `packages/jet_print/CHANGELOG.md`: new visible 5 mm alignment grid; snap step changed 8 pt → 5 mm (affects new placements only, not stored geometry); grid visibility decoupled from grid snapping.
- [X] T023 [P] (Optional) Add one golden of the invoice page with the grid ON at 100 % zoom under `packages/jet_print/test/designer/canvas/` to lock the grid's appearance (NEW golden only — must not change any existing golden).
- [X] T024 Run `dart analyze` (zero warnings) and `dart format` repo-wide; commit any formatting (CI gate, as in spec 014).
- [ ] T025 Execute the [quickstart.md](quickstart.md) manual walk in `apps/jet_print_playground`: grid on by default, toggle grid (snapping unaffected), toggle magnet (edges lock / free), zoom out (grid thins, never solid), open preview (no grid).

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (P1)**: none.
- **Foundational (P2)**: after Setup. BLOCKS all user stories (provides `kGridStep` 5 mm + `gridLineOffsets`).
- **US1 (P3)** and **US2 (P4)**: both after Foundational; file-disjoint (canvas vs controller) → parallel.
- **US3 (P5)**: after US1 (consumes `_GridPainter`) + Foundational.
- **US4 (P6)**: after US1 (needs a visible grid to prove its absence in output).
- **Polish (P7)**: after all desired stories.

### Within each story

- Tests first and FAILING, then implementation to GREEN. Pure helper before painter; painter before alignment/density tests.

### Parallel opportunities

- Foundational: T002 ∥ T003 (then T004 after T003; T005 after T003).
- US1: T006 ∥ T007 (tests); then T008 → T009.
- US2: T010 ∥ T011 ∥ T012 ∥ T013 (tests); then T014 → T015.
- After Foundational, an US1 dev and an US2 dev can work fully in parallel.
- US4: T019 ∥ T020 ∥ T021. Polish: T022 ∥ T023.

---

## Parallel Example: after Foundational

```bash
# Developer A — US1 (visible grid), Developer B — US2 (snap/decouple), concurrently:
# A: grid_test.dart + top_bar(grid) → _GridPainter → stack insertion
# B: snapping_test/move_commit updates → controller grid:true → dartdoc
```

---

## Implementation Strategy

### MVP (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational → 3. Phase 3 US1 → **STOP & VALIDATE**: grid visibly toggles, suite green, goldens unchanged → demo.

### Incremental delivery

Foundational → US1 (visible grid, MVP) → US2 (snap to 5 mm, decoupled) → US3 (zoom legibility) → US4 (output-fidelity guarantees) → Polish. Each story is an independently testable green increment.

---

## Notes

- [P] = different files, no incomplete-task dependency.
- The **step change (T003)** is the one edit that ripples into existing snap tests — T005 keeps the suite green immediately; **decoupling (T014)** is what inverts the grid-off snap assertions (T010/T011).
- Existing invoice goldens MUST remain unchanged (Principle IV); the only allowed new golden is T023.
- Commit after each task or logical group; never merge with failing/skipped tests.
