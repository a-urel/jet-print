# Implementation Plan: Invoice MVP — Data-Aware Designer (Bindable Datasets & Master/Detail Authoring)

**Branch**: `009-data-aware-designer` | **Date**: 2026-06-09 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/009-data-aware-designer/spec.md`

## Summary

Make the report designer **data-aware**. A host application describes a data source's **structure** — a named dataset of typed fields, where a field may be a **nested collection** carrying its own child schema (invoice → line items) — and attaches it to the designer. The designer **displays that real structure** in the Data Source panel (replacing the hardcoded `SalesDB`/`Orders` placeholder), and the author **binds** report elements to fields (drag a field onto the canvas, or edit a binding in the Properties panel). Bound elements show a **design-time token**; master/detail is authored by designating a band as **bound to a nested-collection field**, with **arbitrary nesting**. The playground ships an **invoice sample** (structure + a bound template) proving the public data API.

This iteration is the **authoring surface** only: **tokens, not values** — no expression evaluation, no data-filled render, no preview/export (those are the deferred render slice, whose engine already exists internally).

Technical approach (see [research.md](research.md)):

1. **Reuse what already exists; the binding model is mostly built.** `TextElement.expression` (a `$F{}`/`$P{}`/`$V{}` string) and `FieldImageSource(field)` already exist **and already serialize** ([text_element_codec.dart](../../packages/jet_print/lib/src/domain/serialization/text_element_codec.dart), [image_source.dart](../../packages/jet_print/lib/src/domain/elements/image_source.dart)). Text/image binding therefore needs **no new model** — the work is the designer UI plus a schema to bind against.
2. **One new model concept: the nested-collection field.** Add `JetFieldType.collection` ([value_type.dart](../../packages/jet_print/lib/src/domain/value_type.dart)) and make `FieldDef` **recursive** (a `collection` field carries `List<FieldDef> fields`). A `JetDataSchema` (dataset name + root `FieldDef`s) is the structure handed to the designer. The schema is **host-supplied and NOT embedded** in the template (spec Q2).
3. **Master/detail via recursive data bands.** Add optional `ReportBand.collectionField` (the nested-collection field this band iterates) + `ReportBand.children` (nested bands) — additive, so the **pre-1.0 carve-out** applies (no schema bump, schemaVersion stays `1`). Arbitrary depth falls out of the recursion.
4. **Tokens on the shared render pipeline (Constitution IV).** The design-time frame builder ([design_time_frame.dart](../../packages/jet_print/lib/src/designer/canvas/design_time_frame.dart)) substitutes a token string into a *display copy* of a bound element and emits it through the **unchanged** `ElementRenderer` — token logic lives in the designer seam; the paint path stays single-sourced. Image field bindings show a design-time placeholder.
5. **Reuse the 003 seams.** The `EditCommand`/`_commit`/history pattern (new `SetBindingCommand`, `SetBandCollectionCommand`), the `DesignerScope` `InheritedNotifier` (new sibling `DesignerSchemaScope`), the `Draggable`/`DragTarget` drop flow (new field-drag payload), the Properties panel editor pattern, the ARB→gen-l10n pipeline (en/de/tr + English fallback), and the keyed widget-test harness.
6. **Minimal public-surface expansion (Constitution I).** Export `FieldDef` and the new `JetDataSchema`, and add a `dataSchema` param to `JetReportDesigner`. The data-*bearing* API (`JetDataSource`/`DataSet`/`DataRow`) stays internal — tokens-only needs structure, not rows; exposing the fill API is the render slice.

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`, [pubspec.yaml](../../pubspec.yaml)), sound null-safety.
**Primary Dependencies**: Flutter SDK (`flutter`, `flutter_localizations`); `intl` (gen-l10n); `shadcn_ui ^0.54.0` (chrome — tree rows, inputs, buttons, tabs). **No new library dependency.** The playground already depends on `file_selector` for open/save; the invoice sample adds **no new dependency**.
**Storage**: The versioned `ReportTemplate` JSON via the existing `report_codec.dart` (schemaVersion **1**), surfaced through the public `JetReportFormat` facade. New band fields (`collectionField`, `children`) are additive-optional; element bindings (`expression`, `FieldImageSource`) already serialize. The **data-source structure is NOT persisted** in the template (host-supplied each session). Library performs no filesystem/network I/O (headless); the consumer owns I/O.
**Testing**: `flutter test packages/jet_print apps/jet_print_playground` (run from repo root). Unit (recursive `FieldDef`, `JetDataSchema`, band copyWith, codec round-trip for the new optional fields, binding commands + history/undo), widget (Data Source panel renders the injected schema incl. nested collection + empty state; drag-field-to-canvas bind; Properties binding editor set/clear; collection-bound band designation + nesting; reopen-without-source token persistence), localization (en/de/tr + fallback for new chrome), goldens (data-aware invoice **design surface** with tokens + the populated Data Source panel — light/dark, via the shared pipeline). The existing **encapsulation** + **layer-boundary** architecture tests stay green.
**Target Platform**: macOS desktop (playground); the library stays platform-agnostic/headless. Input is mouse + keyboard (drag-to-bind + keyboard-operable Properties editor, per 003 accessibility precedent).
**Project Type**: Dart pub workspace monorepo — reusable library (`packages/jet_print`, the product) + sample/playground desktop app (`apps/jet_print_playground`, a consumer).
**Performance Goals**: No new runtime target; reuses the 003 design canvas (cached `ui.Picture`, ~200 elements/60 fps). Token substitution is design-time-frame-build work, proportional to element count, not per-frame.
**Constraints**: Constitution IV — token rendering MUST reuse the shared `ElementRenderer` pipeline (no parallel draw code). Constitution I — all consumer access through `lib/jet_print.dart`; `src/` stays private (encapsulation test). Domain/data seams stay Flutter-free; the new field/schema types add no UI imports (layer-boundary test). Zero analyzer warnings; `dart format` clean; no skipped tests; goldens current. New visible chrome localized (en/de/tr, English fallback); new affordances keyboard-operable with accessible names. Bindings round-trip losslessly and are self-describing (reopen without source still shows tokens).
**Scale/Scope**: 1 new field type value + recursive `FieldDef` + 1 new public schema type (`JetDataSchema`) + 2 new `ReportBand` fields + 1 changed public widget param (`JetReportDesigner.dataSchema`) + ~3 new controller methods + 2 new edit commands + Data Source panel rewrite (schema-driven, draggable) + Properties binding editor + design-time token substitution + recursive design-time band layout + the playground invoice sample. 4 user stories (P1–P3). Barcode binding, fill/preview/export, and live data backends are out of scope.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Initial gate (post-Technical-Context)

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | New capability ships as library symbols from the single entry point: `JetFieldType.collection` (already-exported enum), newly-exported `FieldDef`, new `JetDataSchema`, `JetReportDesigner.dataSchema`, new controller methods, `ReportBand` additions. The playground consumes them as an external consumer (builds a `JetDataSchema`, passes it in, drives drag/bind via the public widget). The data-bearing API (`JetDataSource`/`DataSet`/`DataRow`) stays under `src/` — tokens-only needs only structure, so the public surface stays minimal. Encapsulation test stays green. |
| II | Layered & Extensible Architecture | ✅ PASS | `JetFieldType.collection`, recursive `FieldDef`, and `JetDataSchema` live in the `domain`/`data` seams (pure Dart, inward-only). `ReportBand.collectionField`/`children` are domain structure. **Data Binding** is a named constitution layer; binding UI lives in the outermost `designer` seam; token substitution lives in the designer's `design_time_frame`, not the shared renderer. The recursive band model flows through the existing codec/renderer registries (open/closed). Layer-boundary test stays green. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | TDD throughout: red→green→refactor. Every new public symbol, model operation, and serialization path gets unit tests; layer boundaries keep contract tests; widget tests cover panel/drag/properties/nesting/reopen; goldens cover the data-aware invoice design surface. No merge with failing/skipped tests. `tasks.md` will front-load test tasks (overrides the template's "tests optional"). |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS (with a noted slice boundary) | Tokens render through the **unchanged** shared `ElementRenderer`→`FrameBuilder`→`CanvasPainter` path — the design-time frame feeds a token string as ordinary text; no divergent draw code. Goldens protect the data-aware invoice **design surface** (tokens) light/dark. The **data-filled** invoice golden (real values, paginated) belongs to the deferred render slice — see *Complexity Tracking* note; this is a slice boundary, not divergent rendering. |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | New `ReportBand` fields are **additive-optional** (absent ⇒ default), so the **pre-1.0 carve-out** ([report_codec.dart](../../packages/jet_print/lib/src/domain/serialization/report_codec.dart) §18–22) applies: `schemaVersion` stays `1`, no migration. `TextElement.expression`/`FieldImageSource` already serialize. The data-source **structure is not serialized** (host-supplied), so bindings persist as self-describing references (reopen-without-source still shows tokens). Lossless round-trip preserved (incl. `UnknownElement` passthrough); round-trip tests extended. |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on every new public symbol (`FieldDef`, `JetDataSchema`, `dataSchema`, new controller methods, `ReportBand` fields). `CHANGELOG.md` updated. The playground gains a runnable **invoice sample** (Principle VI example + the Tech-standards MVP path: "build a data-aware invoice designer"). Zero analyzer warnings; `dart format` clean; docs/changelog updated in-change. |

**Result: PASS — no violations.** The only tracked note is the deliberate deferral of the *data-filled* invoice golden to the render slice (below); it is a scope boundary the spec set (tokens only), not an unjustified divergence.

### Post-design gate (re-check after Phase 1)

Re-evaluated after [data-model.md](data-model.md) and [contracts/](contracts/) were written: still **PASS**. The recursive `FieldDef`/`ReportBand` and `JetDataSchema` introduce no inward-dependency violations; the public surface addition is the minimal `FieldDef` + `JetDataSchema` + one widget param; serialization stays additive at version 1. No new violations; Complexity Tracking remains empty of *violations*.

## Project Structure

### Documentation (this feature)

```text
specs/009-data-aware-designer/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 — design decisions & rationale
├── data-model.md        # Phase 1 — entities & relationships
├── quickstart.md        # Phase 1 — how a consumer builds & binds an invoice
├── contracts/
│   └── data-aware-designer-api.md   # Phase 1 — public API + behavior contracts + test groups
├── checklists/
│   └── requirements.md  # (from /speckit.specify)
└── tasks.md             # Phase 2 — /speckit.tasks (NOT created here)
```

### Source Code (repository root)

```text
packages/jet_print/                      # the library (the product)
├── lib/jet_print.dart                   # CHANGE: export FieldDef, JetDataSchema
└── lib/src/
    ├── domain/
    │   ├── value_type.dart              # CHANGE: add JetFieldType.collection
    │   └── report_band.dart             # CHANGE: + collectionField, + children, copyWith
    ├── data/
    │   ├── field_def.dart               # CHANGE: recursive (collection → List<FieldDef> fields)
    │   └── data_schema.dart             # NEW: JetDataSchema (dataset name + root FieldDefs)
    ├── domain/serialization/
    │   └── report_codec.dart            # CHANGE: encode/decode collectionField + children (recursive)
    └── designer/
        ├── jet_report_designer.dart     # CHANGE: + dataSchema param; wire DesignerSchemaScope
        ├── designer_schema_scope.dart   # NEW: InheritedWidget providing the schema to panels/canvas
        ├── controller/
        │   ├── jet_report_designer_controller.dart  # CHANGE: + setBinding/clearBinding/setBandCollection
        │   └── commands/
        │       ├── set_binding_command.dart         # NEW
        │       └── set_band_collection_command.dart # NEW
        ├── canvas/
        │   ├── design_canvas.dart       # CHANGE: accept a field-drag payload (DragTarget)
        │   ├── design_time_layout.dart  # CHANGE: recursive nested-band regions
        │   └── design_time_frame.dart   # CHANGE: substitute token text for bound elements (display copy)
        ├── layout/panels/
        │   ├── data_source_panel.dart   # CHANGE: render injected JetDataSchema; draggable field rows; empty state
        │   └── properties_panel.dart    # CHANGE: binding editor (field picker + expression + clear); band collection editor
        └── l10n/
            ├── jet_print_en.arb         # CHANGE: + new chrome strings (edit ARBs only)
            ├── jet_print_de.arb         # CHANGE
            └── jet_print_tr.arb         # CHANGE  (then `flutter gen-l10n`)

apps/jet_print_playground/
└── lib/
    ├── main.dart                        # CHANGE: build invoice JetDataSchema, pass dataSchema:
    └── invoice_sample.dart              # NEW: the invoice schema + a sample bound ReportTemplate

packages/jet_print/test/                 # TDD — tests precede implementation
├── data/                                # recursive FieldDef, JetDataSchema unit tests
├── domain/serialization/                # round-trip: collectionField + children (+ existing expression)
└── designer/
    ├── data_source_schema_tree_test.dart        # NEW: panel renders injected schema + nested collection + empty state
    ├── canvas/drag_field_bind_test.dart         # NEW: drag field → bound element shows token
    ├── properties_binding_editor_test.dart      # NEW: set/clear binding via Properties
    ├── band_collection_binding_test.dart        # NEW: designate + nest collection-bound bands
    ├── reopen_without_source_test.dart          # NEW: tokens persist, tree empty (FR-019a)
    ├── controller/                              # SetBindingCommand / SetBandCollectionCommand + undo/redo
    ├── goldens/data_aware_invoice_test.dart     # NEW: invoice design surface + populated panel (light/dark)
    └── localization*_test.dart                  # extend for new chrome strings
```

**Structure Decision**: Existing Dart pub workspace monorepo (Option: library + sample app). All library work lands under `packages/jet_print/lib/src/` behind the single entry point; the invoice sample lands in `apps/jet_print_playground/lib/` as an external consumer. No new top-level structure.

## Complexity Tracking

> No Constitution **violations** to justify. One tracked **scope boundary** (not a violation) is recorded for reviewer visibility.

| Item | Why | Note |
|------|-----|------|
| Data-filled invoice golden deferred | Spec is **tokens only** (no fill/render this slice) | Constitution IV asks goldens to cover "the data-aware invoice scenario." This slice covers it at the **design-time/token** level (the populated panel + bound-token surface). The **data-filled** golden (real values, paginated) is delivered by the deferred render/export slice, which owns the fill path. No divergent rendering is introduced. |
| Nested-band addressing (band **path**, not just `int` index) | Arbitrary-depth master/detail makes a flat `int` band index insufficient for selecting/editing nested bands | Smallest viable change: address bands by a path (`List<int>`) in the new commands while preserving the existing top-level `int`-index API for back-compat. Resolved in [research.md](research.md) §5; the alternative (adding stable band ids everywhere) was rejected as broader than this slice needs. |
