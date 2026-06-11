---
description: "Task list for Vertical & Horizontal Canvas Rulers"
---

# Tasks: Vertical & Horizontal Canvas Rulers

**Input**: Design documents from `/specs/014-canvas-rulers/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/canvas-rulers.md ✓, quickstart.md ✓

**Tests**: MANDATORY per Constitution Principle III (Test-First, NON-NEGOTIABLE). Every behavioral
contract (C1–C7) has a failing test written **before** its implementation. WYSIWYG (Principle IV) is
guarded by verifying existing goldens stay byte-identical — rulers are design-time chrome and never
flow through the render pipeline.

**Organization**: Tasks are grouped by the four user stories from spec.md (US1/US2 = P1, US3 = P2,
US4 = P3) so each story is an independently testable increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1–US4 (Setup / Foundational / Polish carry no story label)
- Every task names an exact file path. All paths are repo-root relative.

## Path Conventions

Existing Dart pub-workspace monorepo (per plan.md):

- Library source: `packages/jet_print/lib/src/designer/`
- Library tests: `packages/jet_print/test/designer/`
- Run tests from repo root: `flutter test packages/jet_print`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add the shared tunable constants and establish a clean baseline so new tests' red state
is attributable to the feature.

- [X] T001 [P] Add ruler tunables to `packages/jet_print/lib/src/designer/canvas/design_tunables.dart`: `kRulerThickness = 20.0`, `kRulerMinLabelGapPx = 56.0`, the ascending nice-step ladder `kRulerStepLadderMm = <const [1,2,5,10,20,50,100,200,500,1000]>`, a minor-subdivision divisor `kRulerMinorDivisions = 5`, and a minor-spacing floor `kRulerMinMinorGapPx = 6.0` (so subdivisions stop refining near ~1 mm at max zoom). Concrete single values (not ranges) so the `RulerScale` test thresholds are deterministic
- [X] T002 Confirm baseline `flutter test packages/jet_print` is fully green (no failing/skipped) from repo root, so subsequent new-test failures are attributable to the feature

**Checkpoint**: Shared constants present; baseline green.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The single source-of-truth visibility flag on the controller. Both US1 (canvas viewport
inset reads it) and US2 (top-bar toggle drives it) depend on this, so it must land first.

**⚠️ CRITICAL**: No user-story work begins until this phase is complete.

- [X] T003 Write FAILING controller unit test — `rulersEnabled` defaults to `true` (FR-017); `setRulersEnabled(false)` flips it and calls `notifyListeners()`; `setRulersEnabled(<same>)` is a no-op (no notify) — in `packages/jet_print/test/designer/controller/rulers_visibility_test.dart` (mirrors the existing `gridEnabled` test style)
- [X] T004 Implement `_rulersEnabled = true` (private), `bool get rulersEnabled`, and `void setRulersEnabled(bool)` in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`, mirroring `_gridEnabled`/`setGridEnabled` exactly (controller lines ~300–316) → makes T003 pass

**Checkpoint**: Controller exposes ruler visibility; foundation ready — user stories can begin.

---

## Phase 3: User Story 1 - Read element position and size in millimetres (Priority: P1) 🎯 MVP

**Goal**: A horizontal ruler along the top and a vertical ruler down the left, calibrated in
millimetres from the page's physical top-left (0,0), with adaptive labelled ticks + finer
subdivisions, rendered correctly at default zoom.

**Independent Test**: Open the designer with the default invoice template, rulers enabled. Verify a
top ruler and left ruler appear, labelled in mm, zero at the page origin, labels increasing
right/down, evenly spaced, with no overlap and the corner box blank.

### Tests for User Story 1 (write first — must FAIL) ⚠️

- [X] T005 [P] [US1] Write FAILING `RulerScale` unit test (C1: strictly-increasing in-bounds ticks; labelled-gap ≥ `kRulerMinLabelGapPx` across the `pxPerMm` range; ≥1 major tick on any non-empty strip; nice-step = smallest ladder value with `step·pxPerMm ≥ minGap`; alignment exactness `offsetPx == originPx + k·pxPerMm`; minor subdivisions with `label == null`; origin-off-strip emits only `offsetPx ≥ 0` with correct label values; extreme-zoom clamps) in `packages/jet_print/test/designer/canvas/ruler_scale_test.dart`
- [X] T006 [P] [US1] Write FAILING ruler-metrics conversion unit test (C2.1–2: `kPointsPerMm == 72/25.4`; `pointsToMm`/`mmToPoints` round-trip parity; page point 0 → 0 mm; page-width point → page-width mm) in `packages/jet_print/test/designer/canvas/ruler_metrics_test.dart`
- [X] T007 [P] [US1] Write FAILING widget test (C3.1 + C3.5: with default controller + invoice template, a horizontal ruler is present at the top and a vertical ruler at the left, each showing numbered mm marks; the top-left corner box renders no measurement) in `packages/jet_print/test/designer/canvas/rulers_test.dart`

### Implementation for User Story 1

- [X] T008 [US1] Implement pure `RulerScale` + `RulerTick` (`dart:math` only; `originPx`, `pxPerMm`, `lengthPx`, `minLabelGapPx`, injected `formatLabel`; emits visible ordered ticks with nice-step ladder + subdivisions) in `packages/jet_print/lib/src/designer/canvas/ruler_scale.dart` → makes T005 pass
- [X] T009 [US1] Implement `kPointsPerMm`, `pointsToMm`, `mmToPoints` (display-only conversion; no domain/render import) in `packages/jet_print/lib/src/designer/canvas/ruler_metrics.dart` → makes T006 pass (leave `selectionExtent` for US4)
- [X] T010 [P] [US1] Implement the H/V ruler widgets + `CustomPainter`s (strip chrome: tick lines, mm labels via the injected locale-aware `formatLabel`, major/minor styling) in `packages/jet_print/lib/src/designer/canvas/ruler_overlay.dart`
- [X] T011 [US1] Integrate rulers into `packages/jet_print/lib/src/designer/canvas/design_canvas.dart`: when `controller.rulersEnabled`, inset the viewport by `kRulerThickness`, add the top + left ruler overlays and the blank top-left corner box as siblings of the existing scrollbars, feeding each painter `originPx = pageOffset − scrollOffset` and `pxPerMm = viewScale·kPointsPerMm` → makes T007 pass

**Checkpoint**: A correct, readable measured ruler is visible at default zoom — MVP delivers core value.

---

## Phase 4: User Story 2 - Show and hide rulers from the top bar (Priority: P1)

**Goal**: The existing (currently inert) top-bar ruler toggle shows/hides both rulers, the canvas
reclaims the freed space when hidden, and the toggle's active styling tracks visibility — at parity
with grid/snap.

**Independent Test**: Toggle rulers off → both rulers vanish and the canvas grows into the space;
toggle on → they reappear aligned. The toggle's highlighted state matches visibility at each step.

### Tests for User Story 2 (write first — must FAIL) ⚠️

- [X] T012 [P] [US2] Extend the top-bar test (C3.4: activating the ruler toggle flips `controller.rulersEnabled`; the toggle's `active` styling equals `controller.rulersEnabled` at all times, mirroring the grid/snap toggle assertions) in `packages/jet_print/test/designer/top_bar_test.dart`
- [X] T013 [P] [US2] Extend the rulers widget test (C3.2–3: with `rulersEnabled == false` both ruler strips are absent and the viewport reclaims the strip space; flipping back to `true` restores both rulers aligned with the page) in `packages/jet_print/test/designer/canvas/rulers_test.dart`

### Implementation for User Story 2

- [X] T014 [US2] Rewire the ruler toggle in `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart` to read `controller.rulersEnabled` for its active state and call `controller.setRulersEnabled(...)` on tap; delete the dead local `_ruler` field → makes T012, T013 pass

**Checkpoint**: US1 + US2 together = the minimum viable feature (rulers appear correctly AND are controllable).

---

## Phase 5: User Story 3 - Rulers stay aligned through zoom and pan (Priority: P2)

**Goal**: Marks stay locked to true page positions across the full zoom range and while panning;
labelled density re-steps (finer in, coarser out) without overlap or barrenness; the zero origin
tracks the page as it scrolls.

**Independent Test**: Enable rulers, sweep zoom min→max and pan each direction. At several zoom
levels a known element edge still lines up with its mm mark; label density stays readable throughout.

### Tests for User Story 3 (write first — must FAIL) ⚠️

- [X] T015 [P] [US3] Write FAILING alignment widget test (C4: at default zoom an element edge projects to `edge·scale + pageOffset − scrollOffset` with the matching mm at that pixel; after `zoomIn()`/`zoomOut()` the edge still aligns and labelled spacing re-steps yet stays ≥ minimum; after scrolling `_vScroll`/`_hScroll` both rulers shift with the page and first-visible labels update; no drift within one subdivision across several zoom×scroll combos) in `packages/jet_print/test/designer/canvas/ruler_alignment_test.dart`, mirroring `zoom_pan_test.dart` / `page_scroll_test.dart`

### Implementation for User Story 3

- [X] T016 [US3] In `packages/jet_print/lib/src/designer/canvas/design_canvas.dart`, drive the ruler overlays from the **live** `viewScale`, centering `pageOffset`, and the `_vScroll`/`_hScroll` offsets (wrap in the same `AnimatedBuilder`-on-scroll-controller + controller-notify pattern as the scrollbar overlays) so `originPx` folds the scroll offset and the scale re-steps on zoom → makes T015 pass

**Checkpoint**: Rulers are trustworthy at every zoom and pan position.

---

## Phase 6: User Story 4 - Track the cursor and the selected element on the rulers (Priority: P3)

**Goal**: A thin marker tracks the pointer on both rulers; the current selection's **union bounding
box** is highlighted as one combined span per ruler, updating on move/resize and clearing on
deselect; the marker clears when the pointer leaves the canvas.

**Independent Test**: Move the cursor — markers track on both rulers. Select one/several/a band —
each ruler highlights the single union span matching the outer edges; move/resize updates it;
deselect clears it; pointer-exit clears the marker.

### Tests for User Story 4 (write first — must FAIL) ⚠️

- [X] T017 [P] [US4] Extend the ruler-metrics test (C2.3–7: `selectionExtent` returns a single element's page-absolute rect; the union min/max rect for a multi-selection; the band rect for a band; `null` for report/empty; result is independent of selection insertion order) in `packages/jet_print/test/designer/canvas/ruler_metrics_test.dart`
- [X] T018 [P] [US4] Write FAILING tracking widget test (C5: hover places a marker at pointer X on the top ruler and Y on the left ruler; pointer-exit clears both; single-selection highlights left→right on top and top→bottom on left; multi/band highlights one combined union span; move/resize updates the span; deselect clears it; a selection exceeding page edges is clamped to the strip) in `packages/jet_print/test/designer/canvas/ruler_tracking_test.dart`

### Implementation for User Story 4

- [X] T019 [US4] Implement `selectionExtent(DesignTimeLayout, Selection) → JetRect?` (union bbox of selected element rects; band rect for a band; `null` for report/empty) in `packages/jet_print/lib/src/designer/canvas/ruler_metrics.dart` → makes T017 pass
- [X] T020 [US4] In `packages/jet_print/lib/src/designer/canvas/design_canvas.dart`, add a hover `MouseRegion` writing pointer page-coords into a `_hoverPage` `ValueNotifier<JetOffset?>` (cleared on exit), and feed both the hover marker and the per-build `selectionExtent(...)` highlight (clamped to the strip) into the ruler painters behind a `RepaintBoundary` so only the strips repaint → makes T018 pass

**Checkpoint**: All four user stories are independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Localization, non-regression guards, docs, and the final verification gate.

- [ ] T021 [P] Extend the localization tests (C6: mm labels use the active locale's number grouping for en/de/tr incl. large values like 1,000 mm; the ruler toggle tooltip resolves via the existing `toggleRulerTooltip`/"Show rulers" key with English fallback) in `packages/jet_print/test/designer/localization_test.dart`, `localization_de_test.dart`, and `localization_tr_test.dart`
- [ ] T022 [P] Verify non-regression + extensibility (C7, FR-014, FR-016): `public_api_test.dart` shows no new exported surface; `layer_boundaries_test.dart` confirms `ruler_scale.dart`/`ruler_metrics.dart` import no rendering/Flutter-UI library **and that `RulerScale`/`selectionExtent` take only view/geometry inputs — carrying no coupling to selection-drag or guide state, so draggable alignment guides can be added later without touching the measurement model (FR-016)**; all existing canvas/preview/export goldens under `packages/jet_print/test/designer/goldens/` are byte-identical (no `--update-goldens`)
- [ ] T023 [P] Add dartdoc to `rulersEnabled`/`setRulersEnabled` in `jet_report_designer_controller.dart` and add a CHANGELOG entry in `packages/jet_print/CHANGELOG.md` for the rulers feature
- [ ] T024 Final gate: run `flutter test packages/jet_print` (all green, 0 skipped), `dart analyze` (0 warnings) and `dart format` (clean) from repo root, then walk the `quickstart.md` scenarios in `apps/jet_print_playground` (default-on rulers, hover, selection extent, zoom/pan, toggle)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies — start immediately.
- **Foundational (Phase 2)**: depends on Setup. **Blocks all user stories** (controller flag is shared).
- **US1 (Phase 3)**: depends on Foundational. Delivers the MVP.
- **US2 (Phase 4)**: depends on Foundational; the canvas-reclaim assertion (T013) needs the ruler
  strips from US1 (T011) to be present — sequence US2 after US1.
- **US3 (Phase 5)**: depends on US1 (extends the canvas ruler integration to live zoom/scroll).
- **US4 (Phase 6)**: depends on US1 (paints hover/extent into the existing ruler strips).
- **Polish (Phase 7)**: depends on all targeted stories being complete.

### User Story Dependencies

- US1 (P1): after Foundational — no dependency on other stories.
- US2 (P1): after Foundational — drives the flag from the toggle; pairs with US1 for the MVP.
- US3 (P2): builds on US1's canvas integration.
- US4 (P3): builds on US1's ruler strips and the metrics file.

### Within Each User Story

- Write the failing test(s) first, confirm RED, then implement to GREEN (Principle III).
- Pure helpers (`RulerScale`, metrics) before the widgets that consume them.
- Story complete and independently testable before moving to the next priority.

### Parallel Opportunities

- T001 (setup constant) is independent.
- The three US1 test tasks T005, T006, T007 are different files → run in parallel; likewise the impl
  helpers T008 (scale) and T010 (overlay widget) touch different files. T009 (metrics) is parallel to
  both. T011 (canvas integration) is the join point.
- US2 tests T012 and T013 are different files → parallel.
- US4 tests T017 and T018 are different files → parallel.
- Polish T021/T022/T023 touch different files → parallel; T024 is the final serial gate.

---

## Parallel Example: User Story 1

```bash
# Write all three US1 failing tests together (different files):
Task: "RulerScale unit test in packages/jet_print/test/designer/canvas/ruler_scale_test.dart"
Task: "Ruler-metrics conversion test in packages/jet_print/test/designer/canvas/ruler_metrics_test.dart"
Task: "Rulers presence widget test in packages/jet_print/test/designer/canvas/rulers_test.dart"

# Then implement the independent pure helpers + strip widget in parallel:
Task: "RulerScale + RulerTick in packages/jet_print/lib/src/designer/canvas/ruler_scale.dart"
Task: "Conversion helpers in packages/jet_print/lib/src/designer/canvas/ruler_metrics.dart"
Task: "H/V ruler painters in packages/jet_print/lib/src/designer/canvas/ruler_overlay.dart"
# (then T011 joins them into design_canvas.dart)
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Phase 1 Setup → Phase 2 Foundational (controller flag).
2. Phase 3 US1 → a correct measured ruler at default zoom.
3. Phase 4 US2 → the toggle makes it controllable.
4. **STOP and VALIDATE**: rulers appear correctly and show/hide from the top bar — demo-ready.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 + US2 → MVP (visible + controllable rulers).
3. US3 → trustworthy alignment across zoom/pan.
4. US4 → live cursor tracking + selection-extent highlight.
5. Polish → localization, non-regression, docs, final gate.

---

## Notes

- [P] = different files, no dependency on an incomplete task.
- Tests precede implementation in every story; confirm RED before GREEN (Principle III, non-negotiable).
- WYSIWYG guard (Principle IV): never route rulers through the render pipeline; existing goldens MUST
  stay byte-identical (T022). No report-model/codec/`schemaVersion` change (Principle V).
- Golden decision (V1): rulers are design-time chrome (like band separators), so their appearance is
  pinned by widget tests (T007/T015/T018), **not** a new golden. No ruler golden is added this slice;
  the constitution's golden mandate targets report-rendering fidelity, which T022 preserves.
- Public surface stays at two controller methods (Principle I); pure helpers carry no domain/render
  import (Principle II), guarded by `public_api_test`/`layer_boundaries_test`.
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.
