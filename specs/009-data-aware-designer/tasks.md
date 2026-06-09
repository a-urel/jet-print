---
description: "Task list for 009-data-aware-designer (Invoice MVP — Data-Aware Designer)"
---

# Tasks: Invoice MVP — Data-Aware Designer (Bindable Datasets & Master/Detail Authoring)

**Input**: Design documents from `/specs/009-data-aware-designer/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/data-aware-designer-api.md](contracts/data-aware-designer-api.md), [quickstart.md](quickstart.md)

**Tests**: MANDATORY (Constitution III — Test-First, NON-NEGOTIABLE). Every story writes failing tests first, then implements to green. Rendered output is protected by golden tests (Constitution IV).

**Organization**: Tasks are grouped by user story. Stories are independently testable increments in priority order (US1/US2 = P1, US3 = P2, US4 = P3).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1–US4 (user-story phases only)
- All paths are repo-relative. Library = `packages/jet_print/`; playground = `apps/jet_print_playground/`.

## Conventions for this feature

- Run everything from the **repo root** (`flutter` leaves cwd inside the package — run `git`/scripts from root).
- Verify loop: `dart format --output=none --set-exit-if-changed .` → `flutter analyze` → `flutter test packages/jet_print apps/jet_print_playground`.
- New localized strings: edit the three ARB files then run `flutter gen-l10n` (in `packages/jet_print/`); never hand-edit the generated `jet_print_localizations*.dart`.
- Goldens: `flutter test --update-goldens packages/jet_print` after intentional visual changes; tolerant comparator already installed (`test/flutter_test_config.dart`).

---

## Phase 1: Setup

**Purpose**: Establish an attributable green baseline; confirm tooling. No new dependencies are required.

- [X] T001 From repo root, record a clean baseline: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, and `flutter test packages/jet_print apps/jet_print_playground` all pass — so any failure introduced later is attributable to this feature.
- [X] T002 [P] Confirm the gen-l10n pipeline is clean: run `flutter gen-l10n` in `packages/jet_print/` and verify it produces no diff against the current ARBs (de-risks later string additions).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The schema vocabulary + designer plumbing every story binds against: `JetFieldType.collection`, a recursive `FieldDef`, the public `JetDataSchema`, exports, and the `dataSchema` → scope wiring.

**⚠️ CRITICAL**: No user story can begin until this phase is complete.

### Tests (write first; must fail)

- [X] T003 [P] Test recursive `FieldDef` + `JetFieldType.collection`: a `collection` field carries child `fields`; deep value-equality; an empty `collection` is valid; `FieldDef.inferType` still returns scalar types only — in `packages/jet_print/test/data/field_def_test.dart`.
- [X] T004 [P] Test `JetDataSchema` construction, value-equality, and a nested (collection-of-collection) tree — in `packages/jet_print/test/data/data_schema_test.dart`.
- [X] T005 [P] Test that `JetReportDesigner(dataSchema: ...)` provides the schema to descendants via the scope (a probe widget reads it) — in `packages/jet_print/test/designer/designer_schema_scope_test.dart`.

### Implementation

- [X] T006 Add `collection` to `JetFieldType` in `packages/jet_print/lib/src/domain/value_type.dart` (with dartdoc).
- [X] T007 Make `FieldDef` recursive — add `final List<FieldDef> fields` (default `const []`), extend equality/`hashCode`/`toString`; document that `fields` is non-empty only for `collection` — in `packages/jet_print/lib/src/data/field_def.dart` (depends on T006).
- [X] T008 Create `JetDataSchema` (`name` + `List<FieldDef> fields`, value-equality, dartdoc) in `packages/jet_print/lib/src/data/data_schema.dart` (depends on T007).
- [X] T009 Export `FieldDef` and `JetDataSchema` from `packages/jet_print/lib/jet_print.dart` (keep `JetDataSource`/`DataSet`/`DataRow` internal — tokens-only needs structure only).
- [X] T010 Add the `dataSchema` (`JetDataSchema?`) param to `JetReportDesigner` and create `DesignerSchemaScope` (`InheritedWidget`) provided in the designer shell so panels/canvas can read it — in `packages/jet_print/lib/src/designer/jet_report_designer.dart` and `packages/jet_print/lib/src/designer/designer_schema_scope.dart` (depends on T008).
- [X] T011 Run the architecture tests and confirm `packages/jet_print/test/encapsulation_test.dart` and `packages/jet_print/test/architecture/layer_boundaries_test.dart` stay green with the new exports/types.

**Checkpoint**: Schema vocabulary is public and reachable inside the designer; stories can begin.

---

## Phase 3: User Story 1 — See the real data structure in the designer (Priority: P1) 🎯 MVP

**Goal**: The Data Source panel renders the attached `JetDataSchema` as an expandable tree (incl. nested collections), replacing the hardcoded `SalesDB`/`Orders` mock; an empty state shows when no schema is attached.

**Independent Test**: Attach the invoice schema → panel lists invoice fields with types, a `lines` node expands to its child fields; with no schema, an empty state shows and no placeholder names appear. (Spec US1; contract T6.)

### Tests (write first; must fail)

- [X] T012 [P] [US1] Replace the placeholder assertions in `packages/jet_print/test/designer/data_source_tree_test.dart` (and/or add `data_source_schema_tree_test.dart`) to assert: root dataset name + scalar fields with type indicators; a `collection` field expands to its child fields (≥2 levels); and the empty state (no `dataSchema`) shows zero field names.
- [X] T012a [P] [US1] Localization test: with no `dataSchema` attached, the Data Source panel empty-state string renders in en/de/tr and falls back to English for an unsupported locale — extend `packages/jet_print/test/designer/localization_de_test.dart` and `localization_tr_test.dart`. (Precedes the ARB task T015.)

### Implementation

- [X] T013 [US1] Rewrite `packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart` to read the `JetDataSchema` from `DesignerSchemaScope` and render a recursive tree (collection fields expandable to children), with per-type icons; remove the `_sampleDatabase` placeholder entirely (depends on T010).
- [X] T014 [US1] Add the empty-state body to the Data Source panel (clear, localized message; no fields) in the same file.
- [X] T015 [P] [US1] Add the empty-state string to `jet_print_en.arb`/`_de.arb`/`_tr.arb` and run `flutter gen-l10n` — in `packages/jet_print/lib/src/designer/l10n/`.

**Checkpoint**: An attached schema (incl. nested collections) is visible; US1 is independently demoable.

---

## Phase 4: User Story 2 — Bind an element to a data field (Priority: P1)

**Goal**: Bind text/image elements to a field/expression via drag-from-panel and a Properties editor; bound elements show a design-time token; bindings clear and persist losslessly (reopen without source still shows tokens).

**Independent Test**: Drag `customerName` onto the canvas → bound text element shows a token; set/clear via Properties; save→reopen (even without the schema) keeps the token. (Spec US2; contracts T5/T7/T8/T11.)

### Tests (write first; must fail)

- [ ] T016 [P] [US2] Test `SetBindingCommand`/`clearBinding`/`setImageField`: sets `TextElement.expression` / `FieldImageSource`, reverts to static, supports undo/redo, and a no-op pushes no history — in `packages/jet_print/test/designer/controller/binding_command_test.dart`.
- [ ] T017 [P] [US2] Test the design-time frame shows a delimited, visually-distinct token for a bound text element and a placeholder for a bound image element, via the shared renderer — in `packages/jet_print/test/designer/canvas/bound_token_render_test.dart`.
- [ ] T018 [P] [US2] Test the Properties binding editor: pick a field, type a free-form expression, and clear — in `packages/jet_print/test/designer/properties_binding_editor_test.dart`.
- [ ] T019 [P] [US2] Test dragging a leaf field from the panel onto a band creates a bound text element with a token, and dragging a `collection` (branch) node is a no-op — in `packages/jet_print/test/designer/canvas/drag_field_bind_test.dart`.
- [ ] T020 [P] [US2] Test persistence: a template with text + image bindings round-trips (encode→decode equal), and decoding with **no** `dataSchema` attached still shows tokens (tree empty) — in `packages/jet_print/test/designer/reopen_without_source_test.dart`.
- [ ] T020a [P] [US2] Localization test: the binding chrome (Binding / Field / Expression / Clear labels) renders in en/de/tr with English fallback — extend `packages/jet_print/test/designer/localization_de_test.dart` and `localization_tr_test.dart`. (Precedes the ARB task T028.)

### Implementation

- [ ] T021 [P] [US2] Add the `FieldDragData` payload type (field name, path, type) in `packages/jet_print/lib/src/designer/canvas/field_drag_data.dart`.
- [ ] T022 [US2] Implement `SetBindingCommand` (text → `expression`; image → `FieldImageSource`; and a clear path) following the `SetTextCommand` pattern — in `packages/jet_print/lib/src/designer/controller/commands/set_binding_command.dart`.
- [ ] T023 [US2] Add `setBinding`/`clearBinding`/`setImageField`/`createBoundElement` to the controller, each committing one command via `_commit` — in `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (depends on T022).
- [ ] T024 [US2] In `packages/jet_print/lib/src/designer/canvas/design_time_frame.dart`, emit a token (delimited display copy) for bound text and a placeholder for bound image through the **unchanged** `ElementRenderer` (no renderer edits) — depends on T023.
- [ ] T025 [US2] Make the Data Source panel field rows `Draggable<FieldDragData>` (leaf fields only) in `packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart` (depends on T013, T021).
- [ ] T026 [US2] Extend the canvas drop handling to accept `FieldDragData` (a `DragTarget` discriminating field drags from toolbox drags): drop on empty band space → `createBoundElement`; drop on a bindable element → bind — in `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` (depends on T021, T023).
- [ ] T027 [US2] Add the binding editor (field picker from the in-scope schema + free-form expression input + Clear) to the element inspector in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (depends on T023, scope from T010). The editor branches by element type: for image elements it presents a field picker only (no expression input), and the chosen field sets `FieldImageSource`.
- [ ] T028 [P] [US2] Add binding chrome strings (Binding/Field/Expression/Clear) to the three ARB files + `flutter gen-l10n` — in `packages/jet_print/lib/src/designer/l10n/`.

**Checkpoint**: Elements can be bound (drag + Properties), show tokens, clear, and persist (incl. reopen-without-source). US2 is independently demoable.

---

## Phase 5: User Story 3 — Represent invoice lines with master/detail (Priority: P2)

**Goal**: Designate a band as bound to a nested-collection field (the lines); support arbitrary nesting; resolve element scope (master vs child) and flag unresolved bindings; persist the master/detail relationship losslessly.

**Independent Test**: Designate a detail band as bound to `lines`; place line-field-bound elements inside and header-field-bound elements outside; nest a deeper collection-bound band; confirm scope resolution, an unresolved-binding indicator, and save/open fidelity. (Spec US3; contracts T3/T4/T5/T9/T10.)

### Tests (write first; must fail)

- [ ] T029 [P] [US3] Test `ReportBand.copyWith` for the new `collectionField` and `children` (non-destructive; other fields preserved referentially) — in `packages/jet_print/test/domain/report_band_collection_test.dart`.
- [ ] T030 [P] [US3] Test codec round-trip for `collectionField` + nested `children` (and existing `expression`): encode→jsonDecode→decode→re-encode is stable; `schemaVersion` stays 1 — in `packages/jet_print/test/domain/serialization/band_collection_round_trip_test.dart`.
- [ ] T031 [P] [US3] Test `SetBandCollectionCommand` (designate/clear) + band-**path** addressing for nested bands + undo/redo — in `packages/jet_print/test/designer/controller/band_collection_command_test.dart`.
- [ ] T032 [P] [US3] Test designation + arbitrary nesting + scope resolution (master vs child) and that an unresolved binding (missing field / wrong scope) is flagged and **preserved** — in `packages/jet_print/test/designer/band_collection_binding_test.dart`.
- [ ] T033 [P] [US3] Test the design-time layout renders nested collection-bound band regions recursively — in `packages/jet_print/test/designer/canvas/nested_band_layout_test.dart`.
- [ ] T033a [P] [US3] Localization test: the collection-binding and unresolved-binding chrome (e.g. "Bind to collection", unresolved tooltip) renders in en/de/tr with English fallback — extend `packages/jet_print/test/designer/localization_de_test.dart` and `localization_tr_test.dart`. (Precedes the ARB task T041.)

### Implementation

- [ ] T034 [US3] Add `collectionField` (`String?`) and `children` (`List<ReportBand>`, default `const []`) + extend `copyWith` in `packages/jet_print/lib/src/domain/report_band.dart`.
- [ ] T035 [US3] Encode/decode `collectionField` (when non-null) and `children` (when non-empty, recursing through `_encodeBand`/decode) in `packages/jet_print/lib/src/domain/serialization/report_codec.dart` (depends on T034).
- [ ] T036 [US3] Extend `Selection` and the controller to address/select nested bands by path (`List<int>`), preserving the existing top-level `int`-index API — in `packages/jet_print/lib/src/designer/controller/selection.dart` and the controller (depends on T034).
- [ ] T037 [US3] Implement `SetBandCollectionCommand` and `controller.setBandCollection(bandPath, collectionField)` — in `packages/jet_print/lib/src/designer/controller/commands/set_band_collection_command.dart` + controller (depends on T034, T036).
- [ ] T038 [US3] Make the design-time layout recurse into a collection-bound band's `children` (nested regions) in `packages/jet_print/lib/src/designer/canvas/design_time_layout.dart` (depends on T034).
- [ ] T039 [US3] Make the design-time frame emit nested `children` band elements recursively in `packages/jet_print/lib/src/designer/canvas/design_time_frame.dart` (depends on T038, T024).
- [ ] T040 [US3] Add a scope-resolution helper (derive a band/element's scope from the nesting), an unresolved-binding indicator, and a band collection-field editor in the Properties panel — in `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (+ a small designer helper) (depends on T027, T036).
- [ ] T041 [P] [US3] Add collection/unresolved chrome strings (e.g. "Bind to collection", unresolved tooltip) to the three ARB files + `flutter gen-l10n` — in `packages/jet_print/lib/src/designer/l10n/`.

**Checkpoint**: Arbitrary-depth master/detail is authorable, scope-correct, and persists. US3 is independently demoable.

---

## Phase 6: User Story 4 — Run the invoice sample in the demo app (Priority: P3)

**Goal**: The playground defines an invoice `JetDataSchema` (master + nested lines) and a sample bound template via the public API only, attaches it, and proves the data-aware invoice end-to-end (incl. the Principle IV golden).

**Independent Test**: Launch the playground → Data Source panel shows the invoice structure; the bundled sample template loads with master/detail bindings shown as tokens; code uses only `package:jet_print/jet_print.dart`. (Spec US4; contracts T13/T15.)

### Tests (write first; must fail)

- [ ] T042 [P] [US4] Test the invoice sample: the schema attaches via the public API only (no `src/` import) and the sample template loads with bound tokens — in `apps/jet_print_playground/test/invoice_sample_test.dart`.
- [ ] T043 [P] [US4] Golden test: the data-aware invoice **design surface** (bound tokens, master/detail bands) + the populated Data Source panel, in light and dark — in `packages/jet_print/test/designer/goldens/data_aware_invoice_test.dart`.

### Implementation

- [ ] T044 [US4] Create `apps/jet_print_playground/lib/invoice_sample.dart`: the invoice `JetDataSchema` (master fields + nested `lines` collection) and a sample bound `ReportTemplate` (header master fields + a `lines`-bound detail band with line-field tokens) — public API only.
- [ ] T045 [US4] Wire the sample into `apps/jet_print_playground/lib/main.dart`: pass `dataSchema:` and make the sample template loadable (depends on T044).
- [ ] T046 [US4] Generate and commit the golden PNGs via `flutter test --update-goldens packages/jet_print`, then re-run without the flag to confirm they pass (depends on T043 and all UI work).

**Checkpoint**: The invoice MVP is demoable end-to-end through the public API.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T047 [P] Update `packages/jet_print/CHANGELOG.md` with the data-aware designer additions and the public API surface (`FieldDef`, `JetDataSchema`, `JetReportDesigner.dataSchema`, new controller methods, `ReportBand` fields).
- [ ] T048 [P] Verify dartdoc on every new public symbol (`FieldDef.fields`, `JetDataSchema`, `dataSchema`, `setBinding`/`clearBinding`/`setImageField`/`setBandCollection`, `ReportBand.collectionField`/`children`) — Constitution VI.
- [ ] T049 Run the full verify loop from repo root (`dart format` check, `flutter analyze` zero warnings, `flutter test packages/jet_print apps/jet_print_playground` all green, goldens current).
- [ ] T050 Walk through [quickstart.md](quickstart.md) end-to-end (build schema → attach → bind → master/detail → save/open) and confirm each step matches the shipped behavior.
- [ ] T051 Confirm the architecture suite (`encapsulation_test.dart`, `architecture/layer_boundaries_test.dart`) and the full designer/localization/golden suites are green.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (P1)** → **Foundational (P2)** blocks everything. Then user stories.
- **US1 (P3 phase)**: needs Foundational only.
- **US2 (P4 phase)**: needs Foundational. Its **drag-to-bind** path (T025/T026) also needs US1's panel (T013); its **Properties** path (T027) needs only the schema scope (Foundational), so US2 is partially independent of US1.
- **US3 (P5 phase)**: needs Foundational. Its nested-band **token rendering** (T039) builds on US2's frame token substitution (T024); the model/codec/command work (T034–T037) is independent of US1/US2.
- **US4 (P6 phase)**: needs US1+US2+US3 to demonstrate the full invoice (the golden surface exercises all three).
- **Polish (P7)**: after all desired stories.

### Within each story

- Tests first (red), then implementation to green. Model → command/controller → canvas/panel UI → l10n.

### Parallel opportunities

- Setup: T002 ∥ baseline.
- Foundational tests T003 ∥ T004 ∥ T005 (different files); then impl T006→T007→T008 (sequenced), T009/T010 follow, T011 verifies.
- Each story's test tasks (all marked [P]) are different files and run together before that story's implementation.
- l10n string tasks (T015, T028, T041) are [P] relative to their phase's code (ARB files), but must precede any test asserting the new strings.
- Across stories with staffing: US1, the US2-Properties path, and the US3 model/codec path can progress in parallel after Foundational; converge before US4.

---

## Parallel Example: Foundational tests

```bash
# Write these three failing tests together (different files):
Task: "T003 recursive FieldDef + JetFieldType.collection in test/data/field_def_test.dart"
Task: "T004 JetDataSchema in test/data/data_schema_test.dart"
Task: "T005 dataSchema scope provider in test/designer/designer_schema_scope_test.dart"
```

## Parallel Example: User Story 2 tests

```bash
Task: "T016 binding command + undo/redo in test/designer/controller/binding_command_test.dart"
Task: "T017 token/placeholder render in test/designer/canvas/bound_token_render_test.dart"
Task: "T018 Properties binding editor in test/designer/properties_binding_editor_test.dart"
Task: "T019 drag-field-bind in test/designer/canvas/drag_field_bind_test.dart"
Task: "T020 persistence + reopen-without-source in test/designer/reopen_without_source_test.dart"
```

---

## Implementation Strategy

### MVP (data-aware authoring, P1)

1. Phase 1 Setup → Phase 2 Foundational (schema vocabulary + scope).
2. Phase 3 **US1** (see the structure) → validate independently.
3. Phase 4 **US2** (bind + tokens + persist) → validate independently.
4. **STOP & demo**: an author can see the schema and bind elements — the data-aware MVP.

### Incremental delivery

- Add **US3** (master/detail) → invoice lines authorable → demo.
- Add **US4** (playground invoice sample + golden) → full invoice MVP end-to-end.
- Each story is a working increment; the architecture/encapsulation/layer-boundary tests stay green throughout.

---

## Notes

- [P] = different files, no incomplete-task dependency. [Story] maps each task to its user story for traceability.
- `TextElement.expression` and `FieldImageSource` already exist **and serialize** — US2 needs no codec change; only US3 touches the codec (band `collectionField`/`children`).
- Token rendering MUST stay on the shared `ElementRenderer` pipeline (Constitution IV): substitute display text in `design_time_frame.dart`; do **not** edit `TextElementRenderer`.
- New optional band fields are additive (pre-1.0 carve-out): `schemaVersion` stays 1, no migration.
- Each ARB string task (T015/T028/T041) is gated by a localization test (T012a/T020a/T033a) written first — Constitution III applies to visible text too.
- Commit after each task or logical group; never merge with failing/skipped tests (Constitution III).
