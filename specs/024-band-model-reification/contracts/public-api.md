# Phase 1 Contracts — Band Model Reification

The library's external interface is its **public Dart API** (`package:jet_print`)
plus the **report JSON format**. Below: the public surface delta and the
behavioral contracts (test groups), grouped by phase. TDD red→green per group.

## Public surface delta

**Added (exported from `jet_print.dart`):**
`ReportDefinition`, `PageFurniture`, `ReportBody`, `DetailScope`, `ScopeNode`
(+ `BandNode`, `NestedScope`), `GroupLevel`, `Band`, and
`validate(ReportDefinition) → List<Diagnostic>`. `BandType` stays exported.

**Removed (Phase 3):** `ReportTemplate`, `ReportBand`, `ReportGroup`.

**Render entry point:** `JetReportEngine.render` accepts a `ReportDefinition`
(was `ReportTemplate`). `RenderOptions` unchanged.

**Internal (not exported):** the `ReportTemplate → ReportDefinition` converter
(Phases 2–3 only), `v1_to_v2` migration, fill/layout.

`public_api_test` records the additions and the removals.

## Behavioral contracts

### Phase 1 — model + serialization

- **C1 (construct + value semantics)**: each tree type builds, is value-equal by
  content, and `copyWith` replaces only named fields. Sealed `ScopeNode`
  pattern-matches exhaustively.
- **C2 (validate)**: `validate()` returns empty for a valid definition; returns
  the right diagnostic for each violated semantic invariant I1–I6
  (duplicate id; duplicate group name in scope; unparseable key; `$F{}` in
  record-blind furniture/title/summary/noData; band `type`↔slot mismatch;
  non-root scope missing `collectionField`). Never throws.
- **C3 (codec round-trip)**: `decode(encode(def)) == def` for representative
  definitions (furniture + title/summary + grouped master/detail + nested
  scopes + reserved furniture slots). `schemaVersion` stamped `2`.
- **C4 (v1→v2 migration, lossless)**: every existing v1 fixture decodes (via the
  1→2 migration) into the expected tree; the per-row band order in
  `root.children` equals the v1 band order; each `resetGroup` name is rewritten
  to the matching group id; ids are deterministic.
- **C5 (codec fail-fast)**: malformed JSON / `schemaVersion` newer than the build
  still throws `ReportFormatException` (unchanged).

### Phase 2 — native engine (byte-identical)

- **C6 (engine parity — goldens)**: rendering each existing fixture through the
  rewritten fill+layout produces `PageFrame`s **byte-identical** to the current
  engine. The full existing golden suite passes unchanged (canvas/preview/PDF/
  PNG). *Headline gate (Principle IV).*
- **C7 (migrated == native)**: a migrated v1 report renders identically to the
  same report authored directly as a `ReportDefinition` (FR-008).
- **C8 (semantics preserved)**: master-level multi-level grouping (cascade
  break, outer→inner reopen), arbitrary-depth master/detail iteration,
  `keepTogether` / `reprintHeaderOnEachPage` / `startNewPage`, `noData`,
  page-furniture page-scoped substitution — all behave exactly as today
  (parametrized against carried-over fixtures).
- **C9 (deferred capabilities are inert)**: a definition that *represents* a
  deferred capability (a non-root scope with `groups`, multiple `BandNode`s in
  one scope) renders today's behavior without error (the extra structure is
  simply not yet given new rendering semantics) and is flagged by `validate()`
  as "not yet rendered" where appropriate.

### Phase 3 — designer authoring

- **C10 (lifecycle)**: add / remove / reorder / retype a band updates the model
  correctly; each is one undoable+redoable commit; ids stay stable across
  reorder.
- **C11 (first-class group/scope)**: selecting a `GroupLevel` exposes its key +
  all three flags in **one** inspector; the same control does not appear on both
  its header and footer bands (the 023 two-bands smell is gone). Creating /
  deleting groups and scopes works and renders.
- **C12 (validation surfaced)**: author-time `validate()` diagnostics show in the
  designer before render (e.g. duplicate group name, `$F{}` dropped on furniture)
  rather than only as fill diagnostics.
- **C13 (public-API + layering)**: `public_api_test` shows the tree exported and
  `ReportTemplate`/`ReportBand`/`ReportGroup` gone; `layer_boundaries_test` shows
  `ReportDefinition` imports no Flutter/rendering; the playground builds a
  `ReportDefinition` through the public API only.
