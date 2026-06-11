# Implementation Plan: Simplified Label Value & Format Properties

**Branch**: `013-label-value-format` | **Date**: 2026-06-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/013-label-value-format/spec.md`

## Summary

Replace the label (text element) Properties panel's two separate inputs — **Text** and
**Binding** — with **one Value field**, and add a **Format** field. The Value field recognizes
three forms by a deterministic parse: a whole-value `[fieldName]` token = a simple field
binding; a `{ … }` wrapper = an advanced template (functions / multiple fields, e.g.
`{upper[name]}`, `{[firstName] [lastName]}`); anything else = literal text (with a backslash
escape for literal brackets/braces). The Format field is a free-text ICU pattern with seven
quick-pick presets (None, Integer, Decimal, Currency, Percent, Date, Date & time).

The design keeps the change small and constitution-aligned by treating the Value field and
`{ … }` template as a **designer-facing projection** of the existing `TextElement.expression`
(no new binding field, no render-path fork): a pure string↔string compiler turns templates into
canonical **expression strings** that the existing `Expression.parse`/evaluator already
understand, and reverse-compiles stored expressions back for display so field and canvas stay
identical. The only new persisted state is an optional `TextElement.format`, applied at render
time through a shared `applyJetFormat` helper extracted from the existing `FORMAT` function
(one formatter, no drift). An unresolved binding renders a configurable `#ERROR` token threaded
through the fill layer as a `String` (default `#ERROR`; the designer/preview supply the
localized value) so the headless renderer stays Flutter-free and deterministic.

See [research.md](research.md) for the design decisions, [data-model.md](data-model.md) for the
model delta, [contracts/label-value-format.md](contracts/label-value-format.md) for behavioral
contracts + test groups, and [quickstart.md](quickstart.md) for the UX.

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`), sound null-safety.
**Primary Dependencies**: Existing only — `intl` (already used by `FORMAT`/`NumberFormat`/
`DateFormat`), `shadcn_ui` (panel chrome), Flutter `gen-l10n` (ARB → localizations). **No new
dependencies.**
**Storage**: One additive optional field `TextElement.format` in the report JSON; `schemaVersion`
stays **1** (pre-1.0 additive-optional carve-out in `report_codec.dart`); no migration.
**Testing**: `flutter test packages/jet_print` (repo root). Unit — template compiler
(forward/reverse/round-trip/escape/normalization/legacy fallback), `applyJetFormat` (parity +
type-mismatch/malformed fallback), serialization round-trip with/without `format`, resolver
format application, unresolved-token (with/without schema) + determinism. Widget — single value
field (no second binding field), three-form parse + escape as single undoable edits, format
field + presets, canvas token == field (SC-002), localization en/de/tr + English fallback.
Goldens — existing invoice canvas/preview unchanged (WYSIWYG); one formatted-number preview.
**Target Platform**: Designer UI (Flutter) for the panel/canvas; the rendering/format/token core
stays headless platform-agnostic Dart. Reference environment: macOS desktop playground.
**Project Type**: Existing Dart pub workspace monorepo — library `packages/jet_print` + consumer
app `apps/jet_print_playground`.
**Performance Goals**: No new perf budget; template compile is O(input length) at edit time
(not on the render hot path — bindings store the compiled expression). Render adds at most one
`applyJetFormat` call per bound text element, matching today's `FORMAT(...)` cost.
**Constraints**: WYSIWYG via the single `ElementResolver` → paint/export pipeline (no parallel
render code). Headless determinism for export preserved (the `#ERROR` token is a `String`
parameter; no l10n import in the rendering layer). Minimal public surface — only
`TextElement.format` added; compiler/value-field/presets/`applyJetFormat` stay under `src/`.
New chrome localized en/de/tr with English fallback; keyboard-operable with accessible names.
**Scale/Scope**: 1 model field + codec change · 1 bidirectional template compiler · 1 shared
`applyJetFormat` (refactor `FORMAT`) · resolver format + token threading · 1 unified `_ValueField`
+ 1 `_FormatField` + preset list replacing `_TextField`/`_BindingField` for text elements · 1
`SetFormatCommand` + `controller.setFormat` · reverse-compile in `binding_token`/design-time
display · ~10 ARB keys × 3 locales · the test matrix above. 2 user stories (P1, P2).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | Single new public symbol — the additive `TextElement.format` (already-public type), reachable via the one entry point. Template compiler, `_ValueField`/`_FormatField`, format presets, and `applyJetFormat` stay under `src/`, unexported. No host wiring required (quickstart). Encapsulation test extended to pin the new field and keep `src/` internals private. |
| II | Layered & Extensible Architecture | ✅ PASS | Dependencies still point inward. The template compiler is a **designer-layer** concern that emits text for the existing expression parser; the domain model gains only a plain `String? format`. The rendering layer adds `applyJetFormat` (pure Dart, `intl` only) and a `String` token parameter — **no Flutter/l10n import** (pinned by the layer-boundary test). Localization of `#ERROR` happens in the designer/preview layer that owns `BuildContext`. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | TDD red→green→refactor for every unit: compiler, `applyJetFormat`, codec, resolver, token, value-field parse, panel widget, localization. `tasks.md` front-loads test tasks (overrides the template's "tests optional"). No merge with failing/skipped tests. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | **No parallel paint/resolve code.** Bindings still flow through `Expression.parse` → `ElementResolver` → the shared paint/export pipeline; the template is only an editing projection. `format` is applied in the one resolver, so canvas-preview, preview, and export agree by construction. Goldens pin that existing bindings render unchanged and a formatted value is correct; canvas value token == panel value (SC-002). |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | `format` is additive/optional, written only when set; absent ⇒ `null` ⇒ identical render. `schemaVersion` stays 1 under the documented pre-1.0 carve-out; no migration; old templates load unchanged (FR-013/FR-015, SC-005). |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on `TextElement.format` and any new public-facing behavior; `CHANGELOG.md` updated; playground invoice can demonstrate a formatted amount. Zero analyzer warnings; `dart format` clean; new ARB strings localized en/de/tr. |

**Result: PASS — no violations.** One item is recorded in *Complexity Tracking* for reviewer
visibility: the unified value field changes existing designer behavior (two fields → one) and
introduces the `{ … }` template projection — deliberate, spec-mandated, and fully test-pinned.

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md), [contracts/label-value-format.md](contracts/label-value-format.md),
and [quickstart.md](quickstart.md): still **PASS**. The public surface stayed at one additive
field; the binding stayed a single source of truth (`expression`); the render path stayed
shared; the `#ERROR` token stayed a `String` so the rendering layer gained no Flutter/l10n
dependency. No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/013-label-value-format/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — value-field model, template grammar, format, token, schema
├── data-model.md        # Phase 1 — TextElement.format + projections
├── quickstart.md        # Phase 1 — designer UX + the one public-API touchpoint
├── contracts/
│   └── label-value-format.md   # Phase 1 — behavioral contracts + test groups
├── checklists/
│   └── requirements.md  # Spec quality checklist (/speckit.specify)
└── tasks.md             # Phase 2 — /speckit.tasks (NOT created here)
```

### Source Code (repository root)

```text
packages/jet_print/
├── lib/src/
│   ├── domain/
│   │   ├── elements/text_element.dart                # CHANGE: + String? format (ctor, copyWith, ==, hashCode, toString)
│   │   └── serialization/text_element_codec.dart     # CHANGE: read/write optional 'format'
│   ├── expression/
│   │   └── functions/format_functions.dart           # CHANGE: extract applyJetFormat; FORMAT delegates to it
│   │   └── format/apply_jet_format.dart              # NEW: shared pure formatter (number/date/fallback)
│   ├── rendering/fill/
│   │   ├── element_resolver.dart                     # CHANGE: apply format to resolved value; emit unresolved token
│   │   └── fill_eval_context.dart                    # CHANGE: optional known-field set; surface unresolved-field signal
│   └── designer/
│       ├── canvas/binding_token.dart                 # CHANGE: reverse-compile expression → [field] / { … } token
│       ├── template/value_template_compiler.dart     # NEW: compileTemplate / reverseCompile (string↔string)
│       ├── layout/panels/
│       │   ├── properties_panel.dart                 # CHANGE: one _ValueField + _FormatField for text elements
│       │   ├── value_field.dart                      # NEW: unified value input (parse 3 forms, escape)
│       │   └── format_field.dart                     # NEW: format input + preset quick-picks
│       ├── format_presets.dart                       # NEW: 7 preset (labelKey, pattern) pairs
│       ├── controller/
│       │   ├── jet_report_designer_controller.dart   # CHANGE: + setFormat(id, pattern); value-edit routing
│       │   └── commands/set_format_command.dart       # NEW: SetFormatCommand (mirrors SetTextCommand)
│       └── l10n/
│           ├── jet_print_en.arb                      # CHANGE: + value/format/preset/#ERROR keys
│           ├── jet_print_de.arb                      # CHANGE   (then flutter gen-l10n)
│           └── jet_print_tr.arb                      # CHANGE

packages/jet_print/test/                              # TDD — tests precede implementation
├── designer/template/value_template_compiler_test.dart   # NEW: forward/reverse/round-trip/escape/legacy
├── designer/value_field_parse_test.dart                  # NEW: 3 forms + escape, single undoable edit
├── designer/properties_editor_test.dart                  # EXTEND: one value field; format field + presets; undo
├── designer/properties_binding_editor_test.dart          # EXTEND/REPLACE: binding via value field
├── designer/localization_test.dart (+ _de/_tr siblings)  # EXTEND: value/format/preset/#ERROR strings + fallback
├── expression/functions/format_functions_test.dart       # EXTEND: FORMAT delegates (parity)
├── expression/format/apply_jet_format_test.dart          # NEW: number/date/mismatch/malformed fallback
├── rendering/fill/element_resolver_format_test.dart      # NEW: format applied to resolved value
├── rendering/fill/unresolved_token_test.dart             # NEW: token w/ schema; empty w/o; determinism
├── domain/serialization/text_element_codec_test.dart     # EXTEND: round-trip ± format; absent ⇒ null
└── architecture/…                                        # EXTEND: + format in surface; no l10n in rendering

apps/jet_print_playground/
└── lib/…                                             # OPTIONAL: demonstrate a formatted amount on the invoice
```

**Structure Decision**: Existing workspace monorepo, no new top-level structure. The new
template compiler and value/format widgets live in the **designer** seam (editing/presentation);
the shared formatter lives beside the expression functions it factors out; the only domain
change is one optional field. This keeps bindings single-sourced in `expression` and the render
path shared.

## Complexity Tracking

> No Constitution **violations** to justify. One tracked item for reviewer visibility.

| Item | Why | Note |
|------|-----|------|
| Unified value field + `{ … }` template projection replaces the Text/Binding pair | The feature's core intent (spec US1, FR-001/006): one field, with advanced bindings authored as `{ … }` instead of raw `$F{}`. | Deliberate behavior change, fully test-pinned. Bindings remain single-sourced in `TextElement.expression`; the template is a pure string↔string projection over the existing parser, so no render-path fork and no schema change. Legacy/out-of-grammar expressions are shown read-only and never lost (research §2). |
