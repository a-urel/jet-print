---
description: "Task list for Flutter Library + Tester App Scaffold"
---

# Tasks: Flutter Library + Tester App Scaffold

**Input**: Design documents from `/specs/001-flutter-library-scaffold/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/public-api.md, quickstart.md

**Tests**: MANDATORY for jet-print per Constitution Principle III (Test-First, NON-NEGOTIABLE). Every user story writes its tests **before** implementation, and the rendered placeholder gets a golden test per Principle IV. The generic Spec Kit "tests are optional" note does NOT apply here.

**Organization**: Tasks are grouped by user story so each story can be implemented, tested, and demoed independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1, US2, US3)
- Every task includes an exact file path

## Path Conventions

Dart pub workspace monorepo (per plan.md):

- Workspace root: `/Users/ahmeturel/Projects/oss/jet-print/`
- Library: `packages/jet_print/`
- Tester app: `apps/jet_print_tester/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Stand up the workspace skeleton so both packages exist and resolve through one lockfile.

- [ ] T001 Create the workspace root manifest `pubspec.yaml` declaring `environment: sdk: ^3.6.0`, `workspace: [packages/jet_print, apps/jet_print_tester]`, and `name: jet_print_workspace`. (FR-006a)
- [ ] T002 [P] Create the shared strict static-analysis config `analysis_options.yaml` at the workspace root: include `package:flutter_lints/flutter.yaml`, enable strict language modes (`strict-casts`, `strict-inference`, `strict-raw-types`), and set `analyzer.errors:` to promote key lints (e.g. `unused_import`, `dead_code`) to `error` so a clean checkout reports **zero analyzer warnings** (not merely zero errors), satisfying Constitution §VI. (FR-009, SC-003)
- [ ] T003 [P] Create the library package manifest `packages/jet_print/pubspec.yaml` with `name: jet_print`, `version: 0.1.0` (SemVer baseline), `resolution: workspace`, `environment: sdk: ^3.6.0`, and a `flutter:` SDK dependency; then run `flutter pub add shadcn_ui` inside `packages/jet_print/` so the **actual resolved `^x.y.z` constraint** is written (not a placeholder), satisfying FR-012's explicit-constraint requirement. Also create the seeded `packages/jet_print/CHANGELOG.md` with a `## 0.1.0` entry. (FR-001, FR-012)
- [ ] T004 Scaffold the tester app: run `flutter create --template=app --platforms=macos apps/jet_print_tester`, then run `flutter pub add jet_print shadcn_ui` inside `apps/jet_print_tester/` (writes real resolved constraints), and edit `apps/jet_print_tester/pubspec.yaml` to add `resolution: workspace`, set `environment: sdk: ^3.6.0`, and drop the explicit `jet_print` version so it resolves through the workspace. (FR-002, FR-006a)
- [ ] T005 Run `flutter pub get` from the workspace root and confirm a single root `pubspec.lock` is produced resolving every member; commit the lockfile. (FR-006a, SC-002)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the compilable skeleton (public entry point + three layer-seam directories) that every user story builds on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T006 [P] Create the three layer-seam directories with placeholder library files so each seam exists and analyzes clean: `packages/jet_print/lib/src/domain/domain.dart`, `packages/jet_print/lib/src/rendering/rendering.dart`, `packages/jet_print/lib/src/designer/designer.dart` — each containing only a `library` directive and a dartdoc comment describing the seam and its inward-dependency rule. (FR-006)
- [ ] T007 Create the single public entry point `packages/jet_print/lib/jet_print.dart` containing a library directive and a header dartdoc, but **no exports yet** (exports are added test-first in US1). (FR-003)

**Checkpoint**: `flutter analyze` is clean and the package compiles — user stories can now begin.

---

## Phase 3: User Story 1 - Consume the library through its public API (Priority: P1) 🎯 MVP

**Goal**: A consumer can import only `package:jet_print/jet_print.dart`, render `JetPrintPlaceholder`, and read `jetPrintVersion` — with nothing under `lib/src/` reachable.

**Independent Test**: From a consumer (the library's own test acts as one), import only the public entry point, reference `JetPrintPlaceholder` + `jetPrintVersion`, confirm it compiles/renders, and confirm no `package:jet_print/src/` import exists.

### Tests for User Story 1 (write FIRST, ensure they FAIL) ⚠️

- [ ] T008 [P] [US1] Write the public-API import test `packages/jet_print/test/public_api_test.dart` that imports **only** `package:jet_print/jet_print.dart`, instantiates `JetPrintPlaceholder`, and asserts `jetPrintVersion` is a non-empty `String`. Must fail initially (symbols not yet exported). (US1, SC-001, SC-007)
- [ ] T009 [P] [US1] Write the encapsulation test `packages/jet_print/test/encapsulation_test.dart` that (a) scans all consumer files (library `test/**` and `apps/jet_print_tester/lib/**`) and asserts none import a `package:jet_print/src/` path, **and (b) scans `packages/jet_print/lib/**` and asserts no library file imports `package:jet_print_tester/...` or other host/app code** (FR-011: library MUST NOT depend on tester/host code). (SC-007, FR-011)

### Implementation for User Story 1

- [ ] T010 [US1] Create `packages/jet_print/lib/src/version.dart` defining `const String jetPrintVersion = '0.1.0';` with dartdoc (kept out of the seams — version is metadata, not domain). (FR-012, contracts/public-api.md)
- [ ] T011 [US1] Implement the placeholder in `packages/jet_print/lib/src/designer/jet_print_placeholder.dart`: a `const`-constructible, theme-aware `StatelessWidget` named `JetPrintPlaceholder` that reads `ShadTheme.of(context)` so its appearance changes with the active shadcn theme, with full dartdoc. (FR-004, contracts/public-api.md, SC-006)
- [ ] T012 [US1] Add the two `export` directives to `packages/jet_print/lib/jet_print.dart` — `export 'src/designer/jet_print_placeholder.dart' show JetPrintPlaceholder;` and `export 'src/version.dart' show jetPrintVersion;` — then run `flutter test test/public_api_test.dart` and confirm US1 tests now pass. (FR-003, SC-001)

**Checkpoint**: Library is consumable through its public API alone; US1 tests green. **This is the MVP.**

---

## Phase 4: User Story 2 - Run the tester app and see shadcn-styled output (Priority: P2)

**Goal**: The tester app launches on macOS and renders `JetPrintPlaceholder` inside a `ShadApp`/`ShadTheme` shell with a working light/dark toggle.

**Independent Test**: Launch the tester app on macOS; confirm the placeholder appears inside a shadcn-themed shell and toggling the theme visibly changes it; confirm the app imports only the public entry point.

### Tests for User Story 2 (write FIRST, ensure they FAIL) ⚠️

- [ ] T013 [US2] Write the consumption widget test `apps/jet_print_tester/test/app_consumes_library_test.dart` that pumps the tester app's root widget, finds exactly one `JetPrintPlaceholder`, and asserts the app is wrapped in a `ShadApp` (theming pipeline present). Must fail initially. (US2, FR-002, FR-005)

### Implementation for User Story 2

- [ ] T014 [US2] Implement `apps/jet_print_tester/lib/main.dart`: a `ShadApp` configured with light & dark `ShadThemeData`, a stateful theme-mode toggle in the UI, and `JetPrintPlaceholder` placed in the widget tree — importing **only** `package:jet_print/jet_print.dart` and `package:shadcn_ui/shadcn_ui.dart`. At entry, fail fast on unsupported platforms (e.g. `if (!Platform.isMacOS) throw UnsupportedError('jet_print_tester targets macOS desktop this iteration')`) so other platforms surface a clear message rather than rendering incorrectly. (FR-002, FR-005, SC-006, spec Edge Cases)
- [ ] T015 [US2] Verify the macOS runner: ensure `apps/jet_print_tester/macos/` exists, run `flutter config --enable-macos-desktop` if needed, then `flutter run -d macos` from `apps/jet_print_tester/` and confirm the themed placeholder renders and the toggle works. (research.md Decision 3, SC-006)

**Checkpoint**: US1 and US2 both work independently; tester app demonstrates live shadcn theming.

---

## Phase 5: User Story 3 - Trust the foundation via a passing, layered test suite (Priority: P3)

**Goal**: A green, meaningful suite covers the public API, every layer seam, the placeholder widget (incl. golden), and the inward-dependency rule.

**Independent Test**: Run `flutter analyze` (zero errors) and `flutter test` (all pass), confirming ≥1 test per seam, a placeholder render test, and an architecture test that catches boundary violations.

### Tests for User Story 3 (write FIRST, ensure they FAIL) ⚠️

- [ ] T016 [P] [US3] Write the domain seam test `packages/jet_print/test/domain/domain_test.dart` exercising the domain placeholder type in isolation (no Flutter UI import). (SC-004)
- [ ] T017 [P] [US3] Write the rendering seam test `packages/jet_print/test/rendering/rendering_test.dart` exercising the rendering placeholder type, confirming it depends only on domain. (SC-004)
- [ ] T018 [P] [US3] Write the designer seam test `packages/jet_print/test/designer/designer_test.dart` exercising the designer seam's `JetPrintPlaceholder` independently of the tester app. (SC-004)
- [ ] T019 [P] [US3] Write the architecture test `packages/jet_print/test/architecture/layer_boundaries_test.dart` that scans `lib/src/domain/**` and asserts no file imports `package:jet_print/src/rendering/...`, `package:jet_print/src/designer/...`, or any Flutter widget/rendering library. (FR-007, SC-005)
- [ ] T020 [P] [US3] Write the placeholder widget + golden test `packages/jet_print/test/jet_print_placeholder_test.dart` that pumps `JetPrintPlaceholder` standalone inside a `ShadApp`, asserts it renders, and includes a `matchesGoldenFile` assertion seeding the WYSIWYG harness. (FR-004, Principle IV)

### Implementation for User Story 3

- [ ] T021 [P] [US3] Add a placeholder domain type (e.g. `ReportDocument`) in `packages/jet_print/lib/src/domain/domain.dart` (pure Dart, zero UI/rendering imports) so the domain seam has real, testable content. (FR-006, FR-007)
- [ ] T022 [US3] Add a placeholder rendering type (e.g. `ReportLayout`) in `packages/jet_print/lib/src/rendering/rendering.dart` that depends on the domain type only, satisfying the inward-dependency rule. (FR-006, FR-007) — depends on T021
- [ ] T023 [US3] Generate the golden baseline: run `flutter test --update-goldens test/jet_print_placeholder_test.dart`, commit the generated golden image under `packages/jet_print/test/`, then confirm the suite passes without `--update-goldens`. (Principle IV)

**Checkpoint**: All three stories independently functional; full layered suite green.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and the end-to-end clean-checkout gate.

- [ ] T024 [P] Verify every public symbol (`JetPrintPlaceholder`, `jetPrintVersion`) carries dartdoc and optionally run `dart doc packages/jet_print` to confirm docs generate without warnings. (FR-009, Principle VI)
- [ ] T025 [P] Write the contributor `README.md` at the workspace root documenting install (`flutter pub get`), run (`flutter run -d macos` in the tester), and test (`dart format`, `flutter analyze`, `flutter test`) steps so a new contributor reproduces them from docs alone; **explicitly state that the tester app supports macOS desktop only this iteration**. (FR-010, SC-002, spec Edge Cases)
- [ ] T026 Run the full quickstart gate from the workspace root and confirm all green: `dart format --output=none --set-exit-if-changed .`, `flutter analyze` (zero warnings), `flutter test` (all pass). (SC-003, quickstart.md)
- [ ] T027 [P] Create `.github/workflows/ci.yml` that runs on push/PR: set up Flutter, run `flutter pub get` at the workspace root, then `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, and `flutter test` — mirroring the local gate (T026) so merge gates are enforced in CI. (Constitution §Technology & Quality Standards, §Development Workflow)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately. T005 (`pub get`) depends on T001–T004.
- **Foundational (Phase 2)**: Depends on Setup. **BLOCKS all user stories.**
- **User Stories (Phase 3–5)**: All depend on Foundational. US1 → US2 → US3 in priority order, but each is independently testable.
- **Polish (Phase 6)**: Depends on all targeted user stories.

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational. Delivers the consumable library (MVP).
- **US2 (P2)**: Depends on Foundational; consumes US1's `JetPrintPlaceholder` (the placeholder must exist to render). Independently testable via its own widget test.
- **US3 (P3)**: Depends on Foundational; its seam/architecture/golden tests are richest once US1's placeholder exists. Independently runnable as a suite.

### Within Each User Story

- Tests are written FIRST and MUST FAIL before implementation (Principle III).
- Domain types before rendering types (inward dependency): T021 before T022.
- Exports (T012) come after the symbols they export (T010, T011).

### Parallel Opportunities

- Setup: T002 and T003 run in parallel (different files); both before T004→T005.
- Foundational: T006 (seam dirs) parallel with prep for T007.
- US1: T008 and T009 (the two tests) run in parallel.
- US3: T016–T020 (all five tests) run in parallel; T021 parallel with the tests, T022 after T021.
- Polish: T024, T025, and T027 (CI workflow) run in parallel; T026 (the full gate) runs last.

---

## Parallel Example: User Story 3

```bash
# Launch all US3 tests together (write-first, all should FAIL):
Task: "Domain seam test in packages/jet_print/test/domain/domain_test.dart"
Task: "Rendering seam test in packages/jet_print/test/rendering/rendering_test.dart"
Task: "Designer seam test in packages/jet_print/test/designer/designer_test.dart"
Task: "Architecture test in packages/jet_print/test/architecture/layer_boundaries_test.dart"
Task: "Placeholder widget + golden test in packages/jet_print/test/jet_print_placeholder_test.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (workspace resolves to one lockfile).
2. Complete Phase 2: Foundational (entry point + seams compile).
3. Complete Phase 3: User Story 1.
4. **STOP and VALIDATE**: library consumable through its public API; US1 tests green.
5. Demo: the library is the product — this is the meaningful MVP.

### Incremental Delivery

1. Setup + Foundational → skeleton ready.
2. US1 → consumable library (MVP) → validate.
3. US2 → running shadcn-themed tester app → validate.
4. US3 → full layered, golden test suite → validate.
5. Polish → docs + clean-checkout gate (SC-003).

### Parallel Team Strategy

After Foundational completes, US1 must land first (US2 renders its placeholder); US3's suite is then layered on. Within each story, the [P]-marked tests fan out across developers.

---

## Format Validation

All 27 tasks follow `- [ ] [TaskID] [P?] [Story?] Description with file path`:

- Setup (T001–T005) and Foundational (T006–T007): no story label (correct).
- US1 (T008–T012), US2 (T013–T015), US3 (T016–T023): every task carries its `[US#]` label (correct).
- Polish (T024–T027): no story label (correct).
- Every task names an exact file path or a concrete command + artifact.

---

## Notes

- [P] = different files, no incomplete dependencies.
- Verify each test FAILS before writing its implementation (Principle III is NON-NEGOTIABLE).
- Auto-commit is enabled; commit after each task or logical group.
- Stop at any checkpoint to validate a story independently.
