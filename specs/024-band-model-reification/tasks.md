# Tasks: Band Model Reification

**Feature**: `024-band-model-reification` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Format: `[ID] [P?] [Story] Description with file path`

- **[P]**: parallelizable (different files, no dependency on an incomplete task)
- **[US#]**: the user story a story-phase task serves
- **Tests are MANDATORY** (Constitution III — Test-First, non-negotiable): each
  implementation task is preceded by a failing test; red → green → refactor.

Paths are relative to repo root. Library: `packages/jet_print/`; app:
`apps/jet_print_playground/`. Tests mirror `lib/src/` under `test/`.

---

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 [P] Snapshot a v1 report-JSON corpus (default template, invoice sample, multi-level grouped, deep master/detail, empty-data) into `packages/jet_print/test/fixtures/v1/` for migration + parity tests
- [X] T002 [P] Confirm the current render golden suite is green on this branch and record it as the byte-identity baseline (note the golden files under `packages/jet_print/test/**/goldens/`)

---

## Phase 2: Foundational (Blocking Prerequisites) — design Phase 1 (domain + serialization)

**Blocks all user stories.** The new domain model + v2 codec + 1→2 migration.

### Tests (write first; must fail)

- [X] T003 [P] Failing unit tests for `Band`/`GroupLevel`/`PageFurniture`/`ReportBody` (construction, value equality, copyWith, JSON) in `packages/jet_print/test/domain/band_test.dart`, `group_level_test.dart`, `report_definition_test.dart`
- [X] T004 [P] Failing unit tests for `DetailScope` + sealed `ScopeNode` (BandNode/NestedScope; ordered children; exhaustive pattern-match) in `packages/jet_print/test/domain/detail_scope_test.dart`
- [X] T005 [P] Failing tests for `validate()` — empty for a valid definition; one diagnostic per violated invariant I1–I6 — in `packages/jet_print/test/domain/report_validation_test.dart`
- [X] T006 [P] Failing codec round-trip tests (`decode(encode(def)) == def`; `schemaVersion` stamped 2) in `packages/jet_print/test/domain/serialization/report_codec_v2_test.dart`
- [X] T007 [P] Failing v1→v2 migration tests (each `test/fixtures/v1/*` → expected tree; `root.children` order == v1 band order; `resetGroup` name→id; deterministic ids) in `packages/jet_print/test/domain/serialization/migration_v1_to_v2_test.dart`
- [X] T007a [P] Failing tests that deferred-capability shapes are REPRESENTABLE and flagged: a non-root `DetailScope` carrying `groups`, and a scope with >1 `BandNode`, construct successfully and `validate()` emits an **info** diagnostic "not yet rendered" (I7), in `packages/jet_print/test/domain/deferred_capability_test.dart`

### Implementation (to green)

- [X] T008 [P] `Band { id, type (BandType), height, elements }` in `packages/jet_print/lib/src/domain/band.dart`
- [X] T009 [P] `GroupLevel { id, name, key, header?, footer?, keepTogether, reprintHeaderOnEachPage, startNewPage }` in `packages/jet_print/lib/src/domain/group_level.dart`
- [X] T010 [P] `DetailScope` + sealed `ScopeNode` (`BandNode`, `NestedScope`) in `packages/jet_print/lib/src/domain/detail_scope.dart`
- [X] T011 `PageFurniture` + `ReportBody` + `ReportDefinition` in `packages/jet_print/lib/src/domain/report_definition.dart`
- [X] T012 Point `ReportVariable.resetGroup` at a `GroupLevel` **id** (update dartdoc/meaning) in `packages/jet_print/lib/src/domain/report_variable.dart`
- [X] T013 `validate(ReportDefinition) → List<Diagnostic>` (I1–I6; non-throwing; key parsed via the expression engine) in `packages/jet_print/lib/src/domain/report_validation.dart`
- [X] T014 Codec v2: `kReportSchemaVersion = 2`; encode/decode the tree in `packages/jet_print/lib/src/domain/serialization/report_codec.dart`
- [X] T015 `SchemaMigration(fromVersion: 1)` (flat-bands → tree per the data-model mapping; deterministic ids per the **path-based id scheme** in data-model.md; `resetGroup` name→id) in `packages/jet_print/lib/src/domain/serialization/migrations/v1_to_v2.dart`, registered in the decode path
- [X] T016 Export the tree types from `packages/jet_print/lib/jet_print.dart` (additive; legacy types still exported during transition)

**Checkpoint**: new model + v2 serialization + migration all green; legacy model untouched; full suite green.

---

## Phase 3: User Story 1 — Existing reports render unchanged (Priority: P1) 🎯 MVP — design Phase 2 (native engine)

**Goal**: the rewritten engine consumes `ReportDefinition` and renders every
existing report byte-identically; v1 reports migrate and render identically.
**Independent test**: the full render golden suite passes unchanged; migrated v1
fixtures render identically to their pre-migration baseline.

### Tests (write first; must fail)

- [X] T017 [P] [US1] Engine-parity golden test — each `test/fixtures/v1/*` (migrated) renders **byte-identical** `PageFrame`s vs the recorded baseline, in `packages/jet_print/test/rendering/engine_parity_golden_test.dart` (C6)
- [X] T018 [P] [US1] Migration-render-equality test — a migrated v1 report renders identically to a definition authored directly, in `packages/jet_print/test/rendering/migrated_equals_native_test.dart` (C7)
- [X] T019 [P] [US1] Semantics tests — multi-level grouping cascade, deep master/detail, `keepTogether`/`reprint`/`startNewPage`, `noData`, furniture page-scoped substitution — against the new engine, in `packages/jet_print/test/rendering/native_engine_semantics_test.dart` (C8)
- [X] T019a [P] [US1] Failing test that a definition representing a deferred capability renders today's behavior without error (the extra structure is inert), in `packages/jet_print/test/rendering/deferred_capability_inert_test.dart` (C9)

### Implementation (to green)

- [X] T020 [US1] Temporary internal `ReportTemplate → ReportDefinition` converter (lossless for legacy-producible shapes: flat furniture/title/summary/noData bands; template groups + groupHeader/groupFooter bands; master detail bands; `collectionField` detail bands with nested children) in `packages/jet_print/lib/src/rendering/legacy/report_template_adapter.dart`
- [X] T021 [US1] Rewrite `ReportFiller` to traverse `ReportBody`/`DetailScope`/`GroupLevel` natively (emit the same `FilledBand` stream) in `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- [X] T022 [US1] Rewrite `ReportLayouter` to read furniture from `PageFurniture` and group-pagination flags from `GroupLevel` in `packages/jet_print/lib/src/rendering/layout/report_layouter.dart`
- [X] T023 [US1] `JetReportEngine.render` accepts `ReportDefinition`; the designer/preview path feeds the legacy model through the converter (T020) in `packages/jet_print/lib/src/rendering/engine/jet_report_engine.dart`

**Checkpoint**: full golden suite byte-identical; US1 (MVP) deliverable — every existing report renders unchanged.

---

## Phase 4: User Story 2 — First-class groups & scopes (Priority: P2) — design Phase 3 (designer, part 1)

**Goal**: the designer authors `ReportDefinition`; a group/scope is a selectable
entity with ONE inspector for its key + flags (the 023 two-bands smell gone).
**Independent test**: select a group → single Group inspector with key + all
three flags; the flag is not duplicated on the header and footer bands;
create/delete groups and scopes works and renders.

### Tests (write first; must fail)

- [X] T024 [P] [US2] Failing controller tests — document/controller holds `ReportDefinition`; group/scope are selectable; create/delete group + scope; set group key/flags (undoable) in `packages/jet_print/test/designer/controller/report_definition_controller_test.dart`
- [X] T025 [P] [US2] Failing widget test — selecting a group shows a single Group inspector (key + 3 flags); the flag does NOT appear on both header and footer bands in `packages/jet_print/test/designer/group_inspector_test.dart` (C11)
- [X] T026 [P] [US2] Failing test — author-time `validate()` diagnostics surface in the designer (e.g. duplicate group name; `$F{}` on furniture) in `packages/jet_print/test/designer/author_time_validation_test.dart` (C12)

### Implementation (to green)

- [X] T027 [US2] Migrate `DesignerDocument` + controller to hold `ReportDefinition` in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (+ `designer_document.dart`)
- [X] T028 [US2] Migrate the selection model to stable ids + group/scope selection in `packages/jet_print/lib/src/designer/controller/selection.dart`
- [X] T029 [US2] Migrate Properties + Outline panels to the tree; add the first-class Group/Scope inspector (key + flags in one place) in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` and `outline_panel.dart`
- [X] T030 [US2] Migrate canvas + design-time layout to render the tree in `packages/jet_print/lib/src/designer/canvas/` (`design_canvas.dart`, `design_time_layout.dart`)
- [X] T031 [US2] Group/scope commands (create/delete group, create/delete scope, set group key/flags) — each a single undoable/redoable commit (FR-015) — in `packages/jet_print/lib/src/designer/controller/commands/`
- [X] T032 [US2] Remove the temporary converter (T020) and delete `report_template.dart`, `report_band.dart`, `report_group.dart`; engine + designer consume `ReportDefinition` only
- [X] T033 [US2] Update the playground to build a `ReportDefinition` in `apps/jet_print_playground/lib/invoice_sample.dart` and `rendered_invoice_example.dart`; update `packages/jet_print/test/public_api_test.dart` (tree exported; legacy gone) (C13)

**Checkpoint**: designer authors the tree; first-class groups/scopes; legacy types removed; public API finalized; suite green.

---

## Phase 5: User Story 3 — Band, group, and scope lifecycle (Priority: P3) — design Phase 3 (designer, part 2)

**Goal**: add / remove / reorder / retype bands directly in the designer.
**Independent test**: add a band → appears; reorder → order changes; remove →
gone; retype → moves to the matching slot; each is one undoable step.

### Tests (write first; must fail)

- [X] T034 [P] [US3] Failing command tests — add/remove/reorder/retype band (model + undo/redo; ids stable across reorder) in `packages/jet_print/test/designer/controller/band_lifecycle_test.dart` (C10)
- [X] T035 [P] [US3] Failing widget tests — Outline/canvas lifecycle affordances (add via toolbox, remove, reorder, retype) in `packages/jet_print/test/designer/band_lifecycle_widget_test.dart`

### Implementation (to green)

- [X] T036 [US3] Band lifecycle commands (add/remove/reorder/retype, stable ids; retype updates `type` to match the new slot per FR-001a) in `packages/jet_print/lib/src/designer/controller/commands/`
- [X] T037 [US3] Outline + canvas affordances and toolbox wiring for the lifecycle ops in `packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart` and `packages/jet_print/lib/src/designer/canvas/`

**Checkpoint**: full band/group/scope lifecycle in the designer; US3 done.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T038 [P] `CHANGELOG.md` — breaking `ReportTemplate`/`ReportBand`/`ReportGroup` removal, the v1→v2 schema migration, and the reification summary (Principle V/VI)
- [ ] T039 [P] Dartdoc on every new public symbol; `flutter analyze` clean; `dart format` applied across `packages/jet_print` + `apps/jet_print_playground`
- [ ] T040 [P] `layer_boundaries_test` — `ReportDefinition` and the tree types import no Flutter/rendering (Principle II) in `packages/jet_print/test/layer_boundaries_test.dart`
- [ ] T041 Final golden review — confirm the full suite is byte-identical end-to-end; any deliberate visual change is called out and goldens updated in review (expected: none)
- [ ] T042 Manual GUI walkthrough — author the invoice (page chrome + per-invoice group header/footer + nested lines + one-per-page) entirely in the playground designer (SC-004)

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (P1)**: no dependencies.
- **Foundational (P2)**: after Setup — **blocks all user stories**.
- **US1 (P3)**: after Foundational. The MVP.
- **US2 (P4)**: after US1 (the native engine + converter must exist so the migrating designer's preview renders). Removes the converter + legacy types.
- **US3 (P5)**: after US2 (builds on the migrated, tree-native designer).
- **Polish (P6)**: after all desired stories.

### Story independence notes

- **US1** is independently testable and shippable as the MVP (render unchanged) — it does not require any designer change.
- **US2/US3** are designer stories; because there is **no long-term bridge**, the designer's model migration lands in US2 (which also removes the legacy types). US3 is purely additive lifecycle on top of US2.

### Parallel opportunities

- Setup: T001, T002 in parallel.
- Foundational tests: T003–T007 in parallel; then impl T008–T010 in parallel (separate files), T011–T015 sequential-ish (codec/migration interdependter), T016 last.
- US1 tests T017–T019 in parallel before impl; impl T021/T022 are separate files (parallelizable) but both follow T020.
- Within US2/US3, tests marked [P] run together; the panel/canvas/controller migration tasks touch distinct files but share the model migration (T027) — sequence T027 first, then T028–T031 largely parallel.

## Parallel Example: User Story 1

```text
# Write the failing US1 tests together:
T017 engine-parity golden · T018 migrated==native · T019 native-engine semantics
# Then implement:
T020 converter → (T021 filler ‖ T022 layouter) → T023 engine entry point
```

## Implementation Strategy

### MVP first (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational (CRITICAL — blocks all) → 3. Phase 3
US1. **Stop and validate**: full golden suite byte-identical, v1 reports migrate
+ render identically. This is a shippable MVP — the model is reified and the
engine is native, with zero visual change.

### Incremental delivery

US2 makes the new model **authorable** (first-class groups/scopes; finalizes the
public API by removing the legacy types). US3 adds full band lifecycle. Each
phase ends green per Constitution III. Deferred capabilities (per-scope
grouping, nested aggregation, multiple per-row bands, record-aware chrome) are
separate future features — representable in the model now (FR-005), not rendered
here.
