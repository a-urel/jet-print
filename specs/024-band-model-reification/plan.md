# Implementation Plan: Band Model Reification

**Branch**: `024-band-model-reification` | **Date**: 2026-06-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/024-band-model-reification/spec.md`

## Summary

Replace the flat `ReportTemplate` band list — where a band's role is *inferred*
from `type` + group-name + `collectionField` + sibling position — with an
explicit, id'd `ReportDefinition` section tree: `PageFurniture` (record-blind,
per-page) + `ReportBody` (title/summary/noData + a `DetailScope` tree of
first-class `GroupLevel`s and ordered, heterogeneous `ScopeNode`s). Delivered in
three phases — (1) domain + v2 serialization with a lossless 1→2 migration, (2)
a **native** engine rewrite (fill + layout consume the tree directly;
`ReportTemplate` removed), locked **byte-identical** by the render goldens, (3)
designer migration to author the tree with band lifecycle and first-class
group/scope inspectors. Capabilities the model can *represent* but this feature
does not *render* (per-scope grouping, nested aggregation, multiple per-row
bands, record-aware chrome) are deferred to later features. Full design:
[../../docs/superpowers/specs/2026-06-13-band-model-reification-design.md](../../docs/superpowers/specs/2026-06-13-band-model-reification-design.md).

## Technical Context

**Language/Version**: Dart ≥ 3.6 / Flutter ≥ 3.6 (workspace SDK `^3.6.0`), sound null-safety. `sealed`/pattern-matching for `ScopeNode`.
**Primary Dependencies**: Existing only — `flutter`, `pdf` (PdfPainter), `shadcn_ui ^0.54.0` (designer). **No new dependency.**
**Storage**: Report JSON via the existing codec. `kReportSchemaVersion` **bumped 1 → 2**; one forward `SchemaMigration` (1→2). Human-inspectable JSON (Principle V).
**Testing**: `flutter test packages/jet_print` (+ `apps/jet_print_playground`). Goldens (byte-identical render — the headline gate); engine-equivalence goldens carried from current fixtures; migration round-trip + render-equality; model unit (construction/validation); designer widget (lifecycle, group/scope inspectors); `public_api_test`; `layer_boundaries_test`. **TDD red→green per phase** (Principle III, non-negotiable).
**Target Platform**: Flutter desktop/web; reference env macOS playground (`apps/jet_print_playground`).
**Project Type**: Existing Dart pub workspace monorepo — library `packages/jet_print` + consumer app `apps/jet_print_playground`.
**Performance Goals**: No new per-frame cost; reification is structural. Render traversal is O(bands) as today; no extra passes.
**Constraints**: WYSIWYG byte-identical (IV) — goldens unchanged after the engine phase. Layered (II) — `ReportDefinition` lives in the **domain** layer with no Flutter/rendering imports; the engine depends inward on it. Minimal public surface (I) — the tree types replace `ReportTemplate`; internals stay under `src/`. Versioned (V) — schema bump + migration. Pre-deployment: a clean rewrite is allowed; `ReportTemplate` is **removed** (a breaking public-API change — MAJOR under SemVer).
**Scale/Scope**: Domain (≈7 new public types) + codec v2 + 1→2 migration + native fill/layout rewrite + designer migration (controller, ~15 commands, selection, Properties/Outline panels, canvas) + playground update. 3 prioritized user stories.

### Resolved unknowns (the two items /clarify deferred to planning)

- **Green-between-phases without a long-term bridge** → a **temporary internal
  adapter** (`ReportTemplate` kept until Phase 3; a `ReportTemplate →
  ReportDefinition` converter feeds the rewritten engine in Phase 2) keeps the
  suite green at every phase boundary; both are deleted in Phase 3. See
  [research.md](research.md) §1.
- **Invariant validation: throw vs flag** → **structural** invariants are
  unrepresentable-by-construction (typed tree); **semantic** invariants
  (unique ids/names per scope, parseable keys, record-blind furniture, band
  `type`↔slot consistency) are returned by a non-throwing `validate()` and
  surfaced as author-time diagnostics (the codec still fail-fasts on malformed
  JSON). See [research.md](research.md) §2.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | The tree types (`ReportDefinition`, `PageFurniture`, `ReportBody`, `DetailScope`, `ScopeNode`, `GroupLevel`, `Band`) replace `ReportTemplate` as the single public model; internals stay under `src/`. `public_api_test` records the new surface and the removal. No host coupling. |
| II | Layered & Extensible Architecture | ✅ PASS | `ReportDefinition` is **domain-only** (no Flutter/rendering imports; references the domain expression/element types). Engine and designer depend inward on it. `layer_boundaries_test` stays green. Element extension points unchanged. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Red→green per phase: model construction/validation; codec v2 + migration round-trip; native fill/layout against carried-over goldens; designer commands/widgets. No merge with failing/skipped tests. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | ✅ PASS | The headline gate: **existing render goldens stay byte-identical** after the native-engine phase (canvas/preview/PDF/PNG share the one engine). Engine-equivalence goldens carried from current fixtures pin it; any deliberate change updates goldens in review. |
| V | Versioned & Backward-Compatible Serialization | ✅ PASS | Schema **bumped 1→2** with a forward `SchemaMigration`; every v1 report loads losslessly and renders identically (FR-007/008). JSON stays human-inspectable. Schema MAJOR bump documented in CHANGELOG with the migration. |
| VI | Documentation & Developer Experience | ✅ PASS | Dartdoc on all new public symbols; `CHANGELOG.md` (incl. the breaking `ReportTemplate` removal + migration); playground updated to the new model; analyzer clean; `dart format`. |

**Result: PASS.** One item recorded in *Complexity Tracking* for reviewer
visibility: removing `ReportTemplate` is a breaking public-API change (a
temporary internal adapter exists only during Phases 2–3).

**Post-design re-check (after Phase 1 — [data-model.md](data-model.md),
[contracts/public-api.md](contracts/public-api.md), [quickstart.md](quickstart.md)):**
still **PASS**. The tree types are domain-only (II); the codec v2 + 1→2 migration
keeps every v1 report loading and rendering identically (V); the C6 golden gate
enforces byte-identity (IV); contracts are written test-first (III); the public
surface delta + `public_api_test`/`layer_boundaries_test` are specified (I); docs
+ CHANGELOG + playground update are scoped (VI). No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/024-band-model-reification/
├── plan.md              # This file
├── spec.md              # Feature spec (+ Clarifications 2026-06-13)
├── research.md          # Phase 0 — decisions (green-between-phases; validation; native traversal; migration mapping; id determinism)
├── data-model.md        # Phase 1 — the tree entities, fields, invariants, migration mapping, state transitions
├── quickstart.md        # Phase 1 — host builds/renders a ReportDefinition; author builds one in the designer
├── contracts/
│   └── public-api.md     # Phase 1 — public surface + C1..Cn behavioral contracts (model, codec/migration, engine parity, designer)
└── checklists/
    └── requirements.md   # /speckit.specify quality checklist (passed)
```

### Source Code (repository root)

```text
packages/jet_print/
├── lib/
│   ├── jet_print.dart                          # CHANGE: export the tree types; REMOVE ReportTemplate/ReportBand/ReportGroup exports (deleted in Phase 3)
│   └── src/
│       ├── domain/
│       │   ├── report_definition.dart          # NEW: ReportDefinition (root) + ReportBody + PageFurniture
│       │   ├── detail_scope.dart               # NEW: DetailScope + sealed ScopeNode (BandNode | NestedScope)
│       │   ├── group_level.dart                # NEW: GroupLevel { id, name, key, header?, footer?, flags } (replaces ReportGroup)
│       │   ├── band.dart                       # NEW: Band { id, height, type (BandType), elements }
│       │   ├── report_validation.dart          # NEW: validate(ReportDefinition) -> diagnostics (semantic invariants; non-throwing)
│       │   ├── report_band.dart                # TRANSITIONAL: kept until Phase 3, then DELETED
│       │   ├── report_group.dart               # TRANSITIONAL: kept until Phase 3, then DELETED
│       │   ├── report_template.dart            # TRANSITIONAL: kept until Phase 3, then DELETED
│       │   └── serialization/
│       │       ├── report_codec.dart           # CHANGE: kReportSchemaVersion=2; encode/decode the tree
│       │       └── migrations/
│       │           └── v1_to_v2.dart           # NEW: SchemaMigration(fromVersion:1) flat-bands -> tree (incl. resetGroup name->id)
│       ├── rendering/
│       │   ├── fill/report_filler.dart         # REWRITE: traverse ReportBody/DetailScope/GroupLevel natively
│       │   └── layout/report_layouter.dart     # REWRITE: furniture from PageFurniture; group flags from GroupLevel
│       └── designer/                           # Phase 3: controller, commands/*, selection, panels (Properties/Outline), canvas → author ReportDefinition
└── test/                                       # mirrors above; goldens carried over; TDD per phase

apps/jet_print_playground/
└── lib/invoice_sample.dart, rendered_invoice_example.dart   # CHANGE: build a ReportDefinition (Phase 3)
```

**Structure Decision**: Existing workspace monorepo; no new top-level structure.
The tree types live in the **domain** layer (inward-only deps). `ReportTemplate`
and friends are retained transitionally (Phases 1–2) behind a converter so the
suite stays green, then removed in Phase 3.

## Phasing (one feature, three phases — each ends green)

1. **Domain + serialization.** Add the tree types (+ `validate()`) alongside the
   legacy model; codec v2 + 1→2 migration. Unit + round-trip tests. *Legacy
   model untouched; suite green.*
2. **Native engine.** Rewrite `ReportFiller`/`ReportLayouter` to consume
   `ReportDefinition`. A temporary internal `ReportTemplate → ReportDefinition`
   converter feeds the engine from the still-legacy designer. Goldens stay
   byte-identical. *Suite green.*
3. **Designer migration.** Controller/commands/selection/panels/canvas author
   `ReportDefinition` natively (band lifecycle; first-class group/scope
   inspectors; `validate()` surfaced). Remove the converter, `ReportTemplate`,
   `ReportBand`, `ReportGroup`. Update the playground. *Suite green; public API
   finalized.*

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Breaking public-API change: `ReportTemplate`/`ReportBand`/`ReportGroup` removed, replaced by the `ReportDefinition` tree | The reification's entire value is an explicit model; retaining the flat types as public API would preserve the inferred-role bugs and a dual surface | Keeping both models permanently rejected: two public models confuse hosts and re-admit the fragile flat shape. Acceptable now: library is pre-deployment; MAJOR SemVer bump + CHANGELOG + v1→v2 data migration cover it. |
| Transitional adapter + legacy types retained during Phases 1–2 | Constitution III forbids merging with a red suite; the designer can't migrate until Phase 3, so an internal `ReportTemplate→ReportDefinition` converter keeps render/preview green between phases | Atomic landing (engine + designer in one phase, red mid-branch) rejected: breaks incremental TDD, bisect, and review. The adapter is throwaway, deleted in Phase 3. |
