# Tasks: Simplified Label Value & Format Properties

**Input**: Design documents from `/specs/013-label-value-format/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/label-value-format.md](contracts/label-value-format.md)

**Tests**: MANDATORY per Constitution Principle III (Test-First, NON-NEGOTIABLE) and golden tests per Principle IV. Every test task below is written to FAIL first, then made green.

**Organization**: Grouped by user story. US1 (P1) = the unified value field (simple binding, literal, `{ … }` template, `#ERROR`); US2 (P2) = the Format property. Each story is independently testable.

## Path Conventions

Dart pub workspace monorepo. Library source: `packages/jet_print/lib/src/`. Tests: `packages/jet_print/test/`. Playground: `apps/jet_print_playground/`. Run from repo root: `flutter test packages/jet_print`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the red/green baseline before any change.

- [x] T001 Run `flutter test packages/jet_print` and `dart analyze packages/jet_print` from repo root; confirm the suite is green and analyzer clean — this is the reference state TDD will preserve.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared test scaffolding both stories rely on (a designer pumped with an attached data source whose schema has known fields, so unresolved-field and format tests can bind to real/unknown fields).

**⚠️ CRITICAL**: Complete before starting US1 or US2.

- [x] T002 [P] Add/extend a designer widget-test helper that pumps the designer with an attached data source + schema (known fields e.g. `customerName`, `firstName`, `lastName`, `qty`, `amount`, an invoice `date`) and a selectable text element, in `packages/jet_print/test/designer/_support/` (reuse/extend the existing `pumpDesignerWith`). Used by US1 (unresolved/display) and US2 (format) widget tests.

**Checkpoint**: Test harness can attach a schema → user stories can begin.

---

## Phase 3: User Story 1 - One value field for bound & literal labels (Priority: P1) 🎯 MVP

**Goal**: Replace the Text + Binding inputs with a single Value field that parses three forms — `[fieldName]` (simple binding), `{ … }` (advanced template), and literal text (with backslash escape) — displays a binding identically to the canvas token, surfaces unknown fields as a localized `#ERROR` at render, and routes every change as one undoable edit. Bindings remain single-sourced in `TextElement.expression`.

**Independent Test**: Select a label; type `[customerName]` → canvas + field show `[customerName]` and the model binds; type `{[firstName] [lastName]}` → renders the concatenation; type `sample text` → literal; type `\[draft]` → literal `[draft]`; type `[unknownField]` → not-found hint while editing and `#ERROR` in preview. No second binding field exists.

### Tests for User Story 1 (write first, ensure they FAIL) ⚠️

- [x] T003 [P] [US1] Unit test the template compiler in `packages/jet_print/test/designer/template/value_template_compiler_test.dart`: forward (`{[firstName] [lastName]}`→`CONCAT($F{firstName}, " ", $F{lastName})`, `{upper[name]}`→`UPPER($F{name})`, `{Total: [qty]}`→`CONCAT("Total: ", $F{qty})`), reverse-compile inverse, round-trip stability, canonical normalization (`{[name]}`≡`[name]`≡`$F{name}`), backslash escaping, and out-of-grammar expression → read-only `{ raw }` fallback (contract C2).
- [x] T004 [P] [US1] Widget test the value-field parsing in `packages/jet_print/test/designer/value_field_parse_test.dart`: each of the three forms + empty + escape + brackets-mid-text-stays-literal, each a single undoable commit; bound↔literal toggle is one `canUndo` step (contract C1, FR-002/003/005).
- [x] T005 [P] [US1] Unit test reverse-compile/design-time display in `packages/jet_print/test/designer/binding_token_test.dart` (extend if present): `$F{x}`→`[x]`, template expression→`{ … }`, legacy expression shown verbatim (SC-002).
- [x] T006 [P] [US1] Unit test the unresolved-binding token in `packages/jet_print/test/rendering/fill/unresolved_token_test.dart`: with a known-field set, `$F{unknown}` resolves to the `unresolvedFieldToken`; without a set, missing field stays empty (no regression); determinism — same inputs → same output (contract C4, FR-007, SC-005).
- [x] T007 [US1] Widget test the panel in `packages/jet_print/test/designer/properties_editor_test.dart` (extend): a selected text element shows exactly one Value field and NO separate Binding field; the canvas token equals the value-field content (SC-001, SC-002, FR-001).
- [x] T008 [US1] Extend localization tests `packages/jet_print/test/designer/localization_test.dart` (+ `_de`/`_tr` siblings): `propertiesValue`, `valueFieldHint`, and the `errorUnresolvedToken` are localized en/de/tr with English fallback; no raw ARB keys leak (FR-014, SC-006).

### Implementation for User Story 1

- [x] T009 [P] [US1] Create the bidirectional template compiler `packages/jet_print/lib/src/designer/template/value_template_compiler.dart` — `compileTemplate(String)→String` and `reverseCompile(String)→String`, emitting canonical expression source for the existing `Expression.parse`; out-of-grammar → read-only marker (makes T003 green).
- [x] T010 [P] [US1] Update `packages/jet_print/lib/src/designer/canvas/binding_token.dart` (+ design-time display in `design_time_frame.dart`) to reverse-compile a stored `expression` into its `[field]` / `{ … }` token form (makes T005 green).
- [x] T011 [US1] Add value-edit routing on the controller `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` — a `setValue(id, raw)` that parses the three forms (using the compiler) into either `setText`+`clearBinding` or `setBinding(compiledExpression)` as one undoable commit (depends on T009).
- [x] T012 [US1] Create the unified value input `packages/jet_print/lib/src/designer/layout/panels/value_field.dart` — single `ShadInput` modeled on `_TextField`/`_BindingField`, commit-on-blur/Enter, showing the reverse-compiled binding and the read-only state for legacy expressions (depends on T009, T010; makes T004 green).
- [x] T013 [US1] Wire the panel `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` — replace `_TextField`(Text) + `_BindingField`(Binding) for `TextElement` with the single `_ValueField`; keep the unresolved hint (depends on T012; makes T007 green).
- [x] T013a [US1] Update/replace `packages/jet_print/test/designer/properties_binding_editor_test.dart` — its assertions target the now-removed Binding field; fold binding-via-value-field cases into `value_field_parse_test.dart` (T004) and delete or rewrite this file so the suite stays green after T013 (depends on T013).
- [x] T014 [US1] Thread the unresolved token through fill: add optional known-field set to `packages/jet_print/lib/src/rendering/fill/fill_eval_context.dart` and `unresolvedFieldToken` (default `'#ERROR'`) to the fill entry point + `packages/jet_print/lib/src/rendering/fill/element_resolver.dart`, emitting the token for a `$F{}` outside the known-field set; unchanged when no set is provided (makes T006 green; keep render layer Flutter-free).
- [x] T015 [US1] Add ARB keys `propertiesValue`, `valueFieldHint`, `errorUnresolvedToken` (`#ERROR`) to `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`; run `flutter gen-l10n` (from `packages/jet_print`); remove the now-unused `propertiesBinding`/`bindingExpressionHint` only if no longer referenced (makes T008 green).
- [x] T016 [US1] Surface the unresolved-binding token on the public render API so a schema-aware host (the designer preview) shows the localized `#ERROR` (FR-007). `RenderOptions` gained additive `knownFields` (`Set<String>?`) + `unresolvedFieldToken` (default `#ERROR`) fields; `JetReportEngine.render` threads them to `ReportFiller.fill` → `ElementResolver`. A host with a `BuildContext` passes `JetPrintLocalizations.of(context).errorUnresolvedToken` and the attached schema's field names. Verified end-to-end through the public engine in `packages/jet_print/test/rendering/engine/render_unresolved_token_test.dart` (token with schema; localized token verbatim; empty without schema — no regression).

**Checkpoint**: US1 fully functional — one value field, all three forms, `#ERROR` in preview, single undoable edits, localized. MVP deliverable.

---

## Phase 4: User Story 2 - Format property for labels (Priority: P2)

**Goal**: Add a Format field (free-text ICU pattern + 7 quick-pick presets) that formats a bound value at render time via a shared `applyJetFormat` helper (the same logic as the existing `FORMAT` function), persisted as an optional `TextElement.format` with no schema bump.

**Independent Test**: Select a label bound to a numeric field, pick the Decimal preset (or type `#,##0.00`) → preview renders `1,234.50`; pick Date on a date field → `2026-06-11`; clear Format → unformatted; a number pattern on a text value or a malformed pattern → unformatted (no error). Saved + reloaded template keeps the format.

### Tests for User Story 2 (write first, ensure they FAIL) ⚠️

- [x] T017 [P] [US2] Unit test `packages/jet_print/test/expression/format/apply_jet_format_test.dart`: number+numeric pattern, date+date pattern, type mismatch → unchanged, malformed pattern (`FormatException`) → unchanged, empty pattern → unchanged (contract C3, FR-011/012).
- [x] T018 [P] [US2] Extend `packages/jet_print/test/expression/functions/format_functions_test.dart`: `FORMAT(value, pattern)` delegates to `applyJetFormat` (behavior parity — no change to existing FORMAT semantics).
- [x] T019 [P] [US2] Extend `packages/jet_print/test/domain/serialization/text_element_codec_test.dart` (and `element_codec_test.dart`): round-trip a `TextElement` with and without `format`; `format` absent ⇒ decodes to `null`; `toJson` omits `format` when null; `kReportSchemaVersion` unchanged (contract C5, FR-013, SC-005).
- [x] T020 [P] [US2] Unit test `packages/jet_print/test/rendering/fill/element_resolver_format_test.dart`: a bound element with `format` applies it to the resolved value before stringify; a literal label is unaffected; a mismatched/malformed pattern renders the unformatted value, never `!ERR` (FR-012).
- [x] T021 [US2] Widget test in `packages/jet_print/test/designer/properties_editor_test.dart` (extend): a selected text element shows a Format field with the 7 presets; picking a preset fills the pattern; editing commits as one undoable step (FR-008/009, SC-004).
- [x] T022 [US2] Extend localization tests (`localization_test.dart` + `_de`/`_tr`): `propertiesFormat`, `formatHint`, and the 7 preset labels are localized en/de/tr with English fallback; no raw keys leak (FR-014, SC-006).

### Implementation for User Story 2

- [x] T023 [P] [US2] Add `final String? format;` to `packages/jet_print/lib/src/domain/elements/text_element.dart` — constructor named param, `copyWith` carries/sets it, include in `==`/`hashCode`/`toString` (data-model).
- [x] T024 [P] [US2] Create the shared formatter `packages/jet_print/lib/src/expression/format/apply_jet_format.dart` — `applyJetFormat(JetValue, String) → JetValue` (number→`NumberFormat`, date→`DateFormat`, else/`FormatException`→unchanged), locale via `Intl.getCurrentLocale()` (makes T017 green).
- [x] T025 [US2] Refactor `packages/jet_print/lib/src/expression/functions/format_functions.dart` so `FORMAT` delegates to `applyJetFormat` (makes T018 green; depends on T024).
- [x] T026 [US2] Update `packages/jet_print/lib/src/domain/serialization/text_element_codec.dart` to read/write optional `format` (write only when non-null) (makes T019 green; depends on T023).
- [x] T027 [US2] Apply `format` in `packages/jet_print/lib/src/rendering/fill/element_resolver.dart` — when `el.format` is non-empty, pass the resolved value through `applyJetFormat` before `jetStringify` (makes T020 green; depends on T023, T024).
- [x] T028 [P] [US2] Create `packages/jet_print/lib/src/designer/format_presets.dart` — the 7 `(labelKey, pattern)` pairs (None→``, Integer→`#,##0`, Decimal→`#,##0.00`, Currency→`¤#,##0.00`, Percent→`#,##0%`, Date→`yyyy-MM-dd`, Date & time→`yyyy-MM-dd HH:mm`).
- [x] T029 [US2] Add `controller.setFormat(id, pattern)` + `packages/jet_print/lib/src/designer/controller/commands/set_format_command.dart` (mirror `SetTextCommand`'s no-op-aware `apply`) (depends on T023).
- [x] T030 [US2] Create the format input `packages/jet_print/lib/src/designer/layout/panels/format_field.dart` (free-text + preset quick-picks) and wire it into `properties_panel.dart` below the value field for text elements (makes T021 green; depends on T028, T029).
- [x] T031 [US2] Add ARB keys `propertiesFormat`, `formatHint`, and the 7 preset labels (`formatPresetNone`…`formatPresetDateTime`) to en/de/tr ARB files; run `flutter gen-l10n` (makes T022 green).

**Checkpoint**: US1 AND US2 both work independently; a designer can bind and format a label entirely through the panel.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [x] T032 [P] Golden tests: the existing invoice canvas/preview goldens pass **unchanged** for existing bindings (WYSIWYG regression guard, Constitution IV — full golden suite green). Added a new formatted-value preview golden `packages/jet_print/test/goldens/formatted_value_test.dart` (+ `formatted_value_light.png`): a label bound with the new `format` property renders `1,234.50` (number) and `2026-06-11` (date) through the same engine→paintFrame→CanvasPainter pipeline the preview uses — proving the property is WYSIWYG, not a parallel path.
- [x] T033 [P] Extend the architecture/encapsulation tests in `packages/jet_print/test/architecture/`: `TextElement.format` is the only added public symbol; the rendering layer (`element_resolver.dart`, `fill_eval_context.dart`, `apply_jet_format.dart`) imports no Flutter/l10n; compiler/value-field/presets stay unexported (contract C7).
- [x] T034 [P] Dartdoc `TextElement.format` and any new public-facing behavior; update `packages/jet_print/CHANGELOG.md` with the value-field simplification, `{ … }` template, and Format property.
- [x] T035 [US2] Demonstrate a formatted amount on the playground invoice in `apps/jet_print_playground/lib/` (SC-003 end-to-end): the `unitPrice`, `lineTotal`, and `total` labels in `invoice_sample.dart` now carry `format: '#,##0.00'` (rendering `4.50` / `13.50` / `32.00`), and `rendered_invoice_example.dart` passes the schema's field names as `RenderOptions.knownFields` — showing how a host wires the schema-aware `#ERROR` path. Playground suite green.
- [x] T036 Run `dart analyze packages/jet_print` (zero warnings), `dart format`, and the full `flutter test packages/jet_print` suite green; walk [quickstart.md](quickstart.md) to validate the designer UX.

---

## Dependencies & Execution Order

### Phase dependencies
- **Setup (T001)** → no deps.
- **Foundational (T002)** → after Setup; blocks US1/US2 widget tests.
- **US1 (T003–T016)** and **US2 (T017–T031)** → after Foundational. US2 is functionally independent of US1 but shares two files (`properties_panel.dart`, `element_resolver.dart`); when both are done by one developer, do US1 then US2 to avoid merge churn. Each remains independently testable.
- **Polish (T032–T036)** → after the stories it covers.

### Within US1
- Tests T003–T008 first (must fail). Impl order: T009 (compiler) → T010 (token) → T011 (controller routing) → T012 (value field) → T013 (panel) → T013a (retire old binding test) ; T014 (fill token) parallel to the widget chain; T015 (ARB) → T016 (preview wiring).

### Within US2
- Tests T017–T022 first (must fail). Impl order: T023 (model) + T024 (formatter) [P] → T025 (FORMAT delegate), T026 (codec), T027 (resolver) ; T028 (presets) [P] → T029 (command) → T030 (format field/panel) ; T031 (ARB).

### Parallel opportunities
- US1 tests T003–T006 are different files → all [P]. US2 tests T017–T020 → all [P].
- Impl [P] within a story: T009/T010 (US1); T023/T024/T028 (US2).
- Polish T032/T033/T034 → [P].

---

## Implementation Strategy

### MVP first (US1 only)
1. Setup (T001) → Foundational (T002).
2. US1 (T003–T016) — the value field, template, and `#ERROR`.
3. **STOP & VALIDATE**: one value field, three forms, localized `#ERROR`, single undoable edits.
4. Demo — this alone delivers the core request.

### Incremental delivery
- Add US2 (T017–T031) → format property with presets, independently testable.
- Polish (T032–T036) → goldens, architecture pins, docs, analyzer/format/test gate.

---

## Notes
- [P] = different files, no incomplete-task dependency.
- Bindings stay single-sourced in `TextElement.expression`; the template is a designer-only projection — do not add a parallel render path (Constitution IV).
- Verify each test FAILS before implementing (Constitution III).
- No `schemaVersion` bump (pre-1.0 additive-optional carve-out); old templates must keep decoding (SC-005).
- Keep the rendering layer Flutter-free: the `#ERROR` token is a `String` parameter, localized only in the designer/preview layer.
- Commit after each task or logical group.
