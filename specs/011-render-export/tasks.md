---
description: "Task list for Render Report — Data-Filled Paginated Preview (JetReportEngine Facade)"
---

# Tasks: Render Report — Data-Filled Paginated Preview (JetReportEngine Facade)

**Input**: Design documents from `/specs/011-render-export/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/render-engine-api.md](contracts/render-engine-api.md)

**Tests**: MANDATORY for this project (Constitution Principle III — Test-First, NON-NEGOTIABLE; Principle IV — golden tests for rendered output). The generic Spec Kit "tests optional" note does NOT apply. Every phase front-loads failing tests before implementation.

**Organization**: Tasks are grouped by user story. This slice is a **public facade over an already-complete internal engine** — the engine plumbing (facade, render IR, lazy seam, locale threading, public exports) lands in **Foundational** because the MVP story (US1) needs `render()` to exist; the four user stories are then thin, independently-testable increments on top of it.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1–US4 maps to the user stories in [spec.md](spec.md); Setup/Foundational/Polish carry no story label
- All paths are repo-relative; the library is `packages/jet_print/`, the consumer app is `apps/jet_print_playground/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the new source/test locations and protect existing goldens before the additive seam lands.

- [ ] T001 Create new source folders `packages/jet_print/lib/src/rendering/engine/` and `packages/jet_print/lib/src/designer/preview/`, plus test folders `packages/jet_print/test/rendering/engine/` and `packages/jet_print/test/designer/preview/`
- [ ] T002 [P] Establish a green baseline by running `flutter test packages/jet_print apps/jet_print_playground` from the repo root, confirming all existing goldens/tests pass before the additive lazy-pagination seam is introduced (regression guard for Constitution IV)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Deliver a working public `JetReportEngine.render(...)` → `RenderedReport` (lazy, locale-aware, with merged diagnostics) plus the public-surface wiring. **Every user story depends on this phase.**

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests for Foundational (write FIRST, ensure they FAIL)

- [ ] T003 [P] Write `packages/jet_print/test/rendering/engine/lazy_pagination_test.dart` (contract C4/C5): `render(...).pageAt(0)` builds a viewable first page without constructing other pages' frames; `pageAt(i)` builds on demand and caches (re-access returns identical frame); a lazily-built frame is byte-identical to the i-th frame from the preserved eager `layout()` wrapper; `pageCount`/`PAGE_COUNT` resolve correctly via the boundary-only pass
- [ ] T004 [P] Write `packages/jet_print/test/rendering/engine/performance_test.dart` (contract C4 / SC-009): **binding assertion is structural** — for a 1,000-record dataset, `pageAt(0)` constructs exactly one page's frame (frame-construction count is independent of total page count; the boundary-only pass does not build paint primitives). Capture first-page wall-clock as an **advisory** measurement logged against the reference desktop env (not a hard `< 2 s` gate, to avoid CI flakiness)
- [ ] T005 [P] Write `packages/jet_print/test/rendering/engine/render_locale_test.dart` (contract C7 / FR-012a): the same template + data rendered under `Locale('en')` vs `Locale('de')`/`Locale('tr')` differ only in number/date/currency formatting; formatting is independent of `Intl.defaultLocale`
- [ ] T006 [P] Write `packages/jet_print/test/rendering/engine/jet_report_engine_test.dart` (contracts C1/C3): flat detail band bound to N rows shows each row's evaluated value (zero residual `$F{}`/`$P{}`/`$V{}` tokens); a parameter-bound element shows the supplied value; content over one page splits at band boundaries with repeated page header/footer; `pageCount` matches content; identical inputs → byte-identical output (determinism)
- [ ] T007 [P] Extend `packages/jet_print/test/architecture/layer_boundaries_test.dart` (contract C12): assert the new public exports (`JetReportEngine`, `RenderOptions`, `RenderedReport`, `RenderedPage`, the diagnostics types, the full data-source API) are reachable via `package:jet_print/jet_print.dart` with no `src/` import, and that the `rendering/engine` facade only depends inward (fill/layout/expression/data/domain). Also assert the render path is read-only over templates (FR-016): `schemaVersion` stays `1` and the existing round-trip / `UnknownElement` passthrough tests remain green (no schema change, no migration)

### Implementation for Foundational

- [ ] T008 [P] Create `RenderOptions` in `packages/jet_print/lib/src/rendering/engine/render_options.dart` (`Map<String, Object?> parameters` = `{}`, `Locale locale` = `Locale('en')`; FR-012/FR-012a), with dartdoc
- [ ] T009 Add the additive lazy page-production seam to `packages/jet_print/lib/src/rendering/layout/report_layouter.dart`: an on-demand page producer that reuses all existing measurement/pagination/frame logic; a cheap boundary-only pass that yields page breaks + `pageCount` + `PAGE_COUNT` without building paint primitives; keep the existing eager `layout()` as a thin wrapper over the seam so every existing layouter test/golden stays byte-stable (research §2; Complexity Tracking)
- [ ] T010 Create `RenderedReport`/`RenderedPage` in `packages/jet_print/lib/src/rendering/engine/rendered_report.dart`: `pageCount`, `pageAt(int)` (lazy build via the T009 seam + cache), `diagnostics`; `RenderedPage` is a thin `{index, frame}` wrapper over the existing `PageFrame` (data-model.md; depends on T009)
- [ ] T011 [P] Thread the per-render locale through formatting in `packages/jet_print/lib/src/expression/functions/format_functions.dart` and at the engine boundary (scope `NumberFormat`/`DateFormat` to `RenderOptions.locale` across fill + layout, e.g. `Intl.withLocale(locale.toLanguageTag(), ...)`), so formatting never reads the ambient `Intl.defaultLocale` (research §3; FR-012a)
- [ ] T012 Create the public facade `JetReportEngine` in `packages/jet_print/lib/src/rendering/engine/jet_report_engine.dart`: `render(ReportTemplate, JetDataSource, {RenderOptions options})` composes `ReportFiller.fill(...)` then the lazy layout seam, threads params + locale, merges fill + layout `ReportDiagnostics` in order, and returns a `RenderedReport`; holds no rendering logic; never throws on malformed data (depends on T008, T009, T010, T011)
- [ ] T013 Add public exports to `packages/jet_print/lib/jet_print.dart`: `JetReportEngine`, `RenderOptions`, `RenderedReport`, `RenderedPage`, the diagnostics types (`Diagnostic`, `DiagnosticSeverity`, `ReportDiagnostics` from `src/rendering/fill/report_diagnostics.dart`), and the full data-source API (`JetDataSource`, `JetInMemoryDataSource`, `JetJsonDataSource`, `JetObjectDataSource`, `DataSet`, `DataRow` from `src/data/`); keep `src/` private (depends on T012; makes T007 pass)

**Checkpoint**: `const JetReportEngine().render(template, source, options: ...)` returns a lazy, locale-aware `RenderedReport` with merged diagnostics, reachable solely through the public entry point. Foundational tests (T003–T007) pass.

---

## Phase 3: User Story 1 - See a designed report filled with real data (Priority: P1) 🎯 MVP

**Goal**: A host hands a designed template + records + parameters to the engine and the user sees a faithful, paginated, WYSIWYG preview with **real values in place of design-time tokens**, and can move between pages.

**Independent Test**: Provide a one-band template bound to a flat dataset of a few rows plus one parameter; render via the public engine; open `JetReportPreview`; verify each row's evaluated values (no `$F{...}` tokens), the parameter value where bound, the correct page count, and working prev/next navigation.

### Tests for User Story 1 (write FIRST, ensure they FAIL)

- [ ] T014 [P] [US1] Write `packages/jet_print/test/designer/preview/jet_report_preview_test.dart` (contracts C6/C11): prev/next navigation bounded at first/last page; "page X of N" indicator; fit-to-width sizing; keyboard-operable with accessible names; the page is painted through the shared `paintFrame`→`CanvasPainter` path over `RenderedPage.frame` (no parallel draw code)
- [ ] T015 [P] [US1] Write `packages/jet_print/test/designer/preview/preview_localization_test.dart` (contract C11 / FR-017): preview chrome (nav, page indicator, fit-to-width label) renders localized in en/de/tr with English fallback for an unsupported locale
- [ ] T016 [P] [US1] Write `packages/jet_print/test/rendering/engine/render_us1_e2e_test.dart` (acceptance scenarios 1–5): using only `package:jet_print/jet_print.dart`, render a flat one-band template + one parameter and pump `JetReportPreview`; assert evaluated values appear (zero tokens), the supplied parameter value shows, page count is correct, navigation moves between pages, and re-rendering identical inputs is deterministic

### Implementation for User Story 1

- [ ] T017 [US1] Add preview chrome strings (nav prev/next, "page X of N", fit-to-width) to `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, and `jet_print_tr.arb`, then run `flutter gen-l10n` to regenerate the localizations (edit ARBs only)
- [ ] T018 [US1] Implement `JetReportPreview` in `packages/jet_print/lib/src/designer/preview/jet_report_preview.dart`: read-only paginated viewer (prev/next bounded, "page X of N", fit-to-width) driving a `CustomPainter` over the shared `paintFrame`→`CanvasPainter` for the current `RenderedPage.frame`; requests pages from the lazy `RenderedReport` (builds on demand); localized chrome + keyboard operation + accessible names (depends on T017 + Foundational)
- [ ] T019 [US1] Export `JetReportPreview` from `packages/jet_print/lib/jet_print.dart` and add dartdoc (depends on T018)

**Checkpoint**: A flat designed template fills with real values and displays in a navigable, localized, WYSIWYG preview through the public API only. **MVP deliverable — stop and validate.**

---

## Phase 4: User Story 2 - Author master/detail and aggregates that actually compute (Priority: P2)

**Goal**: An invoice-style report (master + nested line-item collection, a group, computed totals) renders with the nested collection iterated, group header/footer repeated correctly, and **computed** aggregate/variable values — closing the 009-deferred data-filled invoice golden.

**Independent Test**: Render the playground invoice (one invoice + several line items); verify each line item appears once, the line-total expression computes per row, the invoice total equals the exact sum of line amounts, and the page-number variable increments across pages.

### Tests for User Story 2 (write FIRST, ensure they FAIL)

- [ ] T020 [P] [US2] Add master/detail + aggregate cases to `packages/jet_print/test/rendering/engine/jet_report_engine_test.dart` (contract C2): a collection-bound band repeats once per child record at arbitrary nesting depth with child-field values resolved; a sum variable computes at its reset scope (group + grand total); the invoice total equals the exact sum of line amounts; group header/footer render at key boundaries
- [ ] T021 [P] [US2] Write `packages/jet_print/test/goldens/rendered_invoice_test.dart` (contracts C2/C6 / SC-003): the data-filled invoice, paginated, in light and dark themes, rendered through the shared pipeline (closes the 009 data-filled-invoice golden deferral)

### Implementation for User Story 2

- [ ] T022 [P] [US2] Create `apps/jet_print_playground/lib/rendered_invoice_example.dart`: build a `JetInMemoryDataSource` invoice (master + nested line-item collection) for the existing `invoice_sample.dart` template, render via `JetReportEngine`, and show `JetReportPreview` — the runnable < 30-line example (FR-019 / SC-008)
- [ ] T023 [US2] Add a "Preview" path to `apps/jet_print_playground/lib/main.dart` that opens the rendered-invoice example
- [ ] T024 [US2] Write `apps/jet_print_playground/test/rendered_invoice_example_test.dart`: the example renders + previews the invoice end-to-end (line items appear once, total = sum, navigable preview)
- [ ] T025 [US2] Generate and commit the invoice golden images (light + dark) referenced by T021 (depends on T021, T022)

**Checkpoint**: The headline invoice scenario renders correct master/detail + aggregates, with a committed data-filled golden and a runnable playground example.

---

## Phase 5: User Story 3 - Supply data through the public data-source API (Priority: P3)

**Goal**: A host wires real data via the public data-source API (in-memory, JSON, or object-backed) plus a parameter map, with no `src/` access — discoverable from the single entry point and documented.

**Independent Test**: Using only `package:jet_print/jet_print.dart`, construct each public data-source variant for the same logical dataset (including a nested collection), render with each, and verify identical output.

### Tests for User Story 3 (write FIRST, ensure they FAIL)

- [ ] T026 [P] [US3] Write `packages/jet_print/test/rendering/engine/data_source_parity_test.dart` (contract C8 / SC-006): the same logical dataset (incl. a nested collection) supplied via `JetInMemoryDataSource`, `JetJsonDataSource`, and `JetObjectDataSource<T>` yields byte-identical rendered output; parameter values supplied as a map resolve in expressions/bindings

### Implementation for User Story 3

- [ ] T027 [P] [US3] Add dartdoc to the promoted public data-source types (`JetDataSource`, `JetInMemoryDataSource`, `JetJsonDataSource`, `JetObjectDataSource`, `DataSet`, `DataRow`) describing the public contract and nested-collection (master/detail) usage (FR-011 / FR-019)
- [ ] T028 [US3] Demonstrate the JSON and object-backed variants in `apps/jet_print_playground/lib/rendered_invoice_example.dart` (or a sibling snippet test) to prove discoverability and the < 30-line integration ceiling for all three sources (SC-008)

**Checkpoint**: All three public data-source variants produce identical output for the same dataset and are documented + demonstrated from the public entry point.

---

## Phase 6: User Story 4 - Get clear diagnostics instead of crashes (Priority: P3)

**Goal**: Malformed data/template (unknown field, missing parameter, unresolved/URL-only image, empty dataset) yields a best-effort render plus structured diagnostics — never a crash.

**Independent Test**: Render templates with (a) an expression over a missing field, (b) an unsupplied parameter, (c) an empty dataset, (d) a URL-only image, and (e) an expression that evaluates with an error (type mismatch / divide-by-zero); verify each returns a specific diagnostic identifying the element/band and still produces a renderable result.

### Tests for User Story 4 (write FIRST, ensure they FAIL)

- [ ] T029 [P] [US4] Write `packages/jet_print/test/rendering/engine/render_diagnostics_test.dart` (contracts C9/C10 / SC-007; FR-013 full matrix): unknown field, missing parameter, **expression-evaluation error (type mismatch / divide-by-zero)**, empty dataset, and URL-only image each produce a specific `Diagnostic` (with `elementId` where applicable) and a non-crashing best-effort render (empty/placeholder fallback for the offending element; surrounding content renders normally); 0 unhandled crashes across the matrix

### Implementation for User Story 4

- [ ] T030 [US4] Confirm `RenderedReport.diagnostics` surfaces the merged fill + layout diagnostics in order (in `packages/jet_print/lib/src/rendering/engine/jet_report_engine.dart`) and that per-element fallback (empty/placeholder, URL-only image placeholder) is wired through; adjust the facade merge/fallback only if T029 reveals a gap (internal behavior already exists per research §5/§7)
- [ ] T031 [P] [US4] Add dartdoc to the promoted diagnostics types (`Diagnostic`, `DiagnosticSeverity`, `ReportDiagnostics`) in `packages/jet_print/lib/src/rendering/fill/report_diagnostics.dart` (FR-013 / FR-019)

**Checkpoint**: The defined malformed-input matrix produces specific diagnostics and non-crashing renders, surfaced on the public `RenderedReport.diagnostics`.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, formatting, and full-suite validation across all stories.

- [ ] T032 [P] Dartdoc completeness pass on every new public symbol (`JetReportEngine`, `RenderOptions`, `RenderedReport`, `RenderedPage`, `JetReportPreview`) per FR-019 / Constitution VI
- [ ] T033 [P] Update `packages/jet_print/CHANGELOG.md` with the render slice (facade, render IR, lazy seam, per-render locale, public data-source + diagnostics surface, preview widget)
- [ ] T034 Run `dart format` and `dart analyze` across `packages/jet_print` and `apps/jet_print_playground` from the repo root; resolve to zero warnings
- [ ] T035 Validate [quickstart.md](quickstart.md) end-to-end (template + data → preview in < 30 lines, SC-008) against the shipped example
- [ ] T036 Run the full suite `flutter test packages/jet_print apps/jet_print_playground` from the repo root and confirm all unit/widget/golden/performance tests pass (no skipped tests — Constitution III)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup. **BLOCKS all user stories** — delivers `render()` + `RenderedReport` + public exports.
- **User Stories (Phase 3–6)**: All depend on Foundational. Per [spec.md](spec.md), US2/US3/US4 build on US1's fill/preview being in place, but each remains independently testable.
- **Polish (Phase 7)**: Depends on all targeted user stories being complete.

### User Story Dependencies

- **US1 (P1)**: Needs Foundational only. The MVP.
- **US2 (P2)**: Needs Foundational; exercises US1's preview with the invoice scenario (independently testable via the invoice example + golden).
- **US3 (P3)**: Needs Foundational; the data-source exports it verifies land in T013 (independently testable via the parity test).
- **US4 (P3)**: Needs Foundational; the diagnostics exports it verifies land in T013 (independently testable via the malformed-input matrix).

### Within Each Phase

- Tests are written FIRST and MUST FAIL before implementation (Constitution III).
- Foundational impl order: `RenderOptions` (T008) → lazy seam (T009) → `RenderedReport` (T010) → locale threading (T011) → facade (T012) → public exports (T013).
- US1: ARB strings + gen-l10n (T017) → preview widget (T018) → export (T019).

### Parallel Opportunities

- Setup: T002 runs alongside T001.
- Foundational tests T003–T007 are all `[P]` (different files) and run together; impl T008 and T011 are `[P]` relative to T009/T010.
- US1 tests T014–T016 run together `[P]`.
- US2 tests T020, T021 run together `[P]`; US3 (T026/T027) and US4 (T029/T031) test+doc tasks parallelize.
- Polish T032, T033 are `[P]`.
- After Foundational completes, US1–US4 can be staffed in parallel (each story's tests + impl are isolated, modulo the shared `jet_report_engine_test.dart` between T006 and T020).

---

## Parallel Example: Foundational tests

```bash
# Launch all Foundational test files together (each is a new, independent file):
Task: "lazy_pagination_test.dart"        # T003
Task: "performance_test.dart"            # T004
Task: "render_locale_test.dart"          # T005
Task: "jet_report_engine_test.dart"      # T006
Task: "extend layer_boundaries_test.dart"# T007
```

## Parallel Example: User Story 1 tests

```bash
Task: "jet_report_preview_test.dart"     # T014
Task: "preview_localization_test.dart"   # T015
Task: "render_us1_e2e_test.dart"         # T016
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup.
2. Phase 2: Foundational (CRITICAL — delivers `render()` and the public surface; blocks all stories).
3. Phase 3: User Story 1 — the preview over real values.
4. **STOP and VALIDATE**: a flat designed template fills and previews end-to-end through the public API.

### Incremental Delivery

1. Setup + Foundational → engine reachable from `package:jet_print/jet_print.dart`.
2. US1 → data-filled, navigable, WYSIWYG preview (MVP).
3. US2 → master/detail + aggregates + invoice golden + playground example.
4. US3 → public data-source parity across all three variants.
5. US4 → diagnostics for the malformed-input matrix.
6. Polish → docs, format/analyze clean, full suite green.

---

## Notes

- `[P]` = different files, no dependency on incomplete tasks.
- `[Story]` label ties each task to its user story for traceability; Setup/Foundational/Polish carry none.
- Run all `flutter`/`dart` commands from the repo root, then `cd` back — `flutter` leaves cwd inside the package.
- Verify each test FAILS before implementing (Constitution III); no merge with failing or skipped tests.
- The lazy seam (T009) MUST keep the eager `layout()` byte-stable — existing goldens are the guard (Constitution IV).
- **FR-015 (headless / no filesystem-print-network I/O)** is covered-by-construction — this slice adds no I/O code; the URL-only-image case in T029 exercises the no-I/O policy at the boundary. No dedicated task is required.
- Commit after each task or logical group.
