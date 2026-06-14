# Phase 0 Research — Band Model Reification

All decisions below are resolved (no remaining NEEDS CLARIFICATION). Format:
Decision / Rationale / Alternatives considered.

## 1. Green between phases without a long-term bridge

- **Decision**: Keep `ReportTemplate`/`ReportBand`/`ReportGroup` *transitionally*
  through Phases 1–2 behind a temporary, internal `ReportTemplate →
  ReportDefinition` converter that feeds the rewritten engine. The designer
  keeps producing the legacy model until Phase 3; render/preview go
  legacy → converter → new engine. In Phase 3 the designer authors
  `ReportDefinition` natively and the converter + legacy types are deleted.
- **Rationale**: Constitution III forbids merging with a red/skip suite; the
  designer (controller, ~15 commands, panels, canvas) cannot migrate until
  Phase 3, so an internal converter is the only way each phase ends green. The
  converter is lossless for the shapes the legacy designer can produce.
- **Alternatives**: (a) *Atomic landing* (engine + designer in one phase) —
  rejected: a long red mid-branch breaks incremental TDD, bisect, review.
  (b) *Lowering as the permanent engine strategy* — rejected earlier (design
  D3): the engine must consume the tree natively, so the converter is throwaway,
  not a permanent IR.

## 2. Invariant validation — throw vs flag

- **Decision**: Split by invariant kind.
  - **Structural** invariants are *unrepresentable by construction*: furniture
    slots are single `Band?` fields; a `GroupLevel` owns its header/footer;
    a scope's contents are a typed `List<ScopeNode>`. No runtime check needed.
  - **Semantic** invariants are returned by a **non-throwing**
    `validate(ReportDefinition) → List<Diagnostic>`: unique ids and unique group
    `name`s within a scope, parseable `GroupLevel.key`, record-blind furniture /
    title / summary / noData bands contain no record-dependent (`$F{}`)
    bindings, and each `Band.type` is consistent with its slot (FR-001a).
  - The **codec** still fail-fasts (`ReportFormatException`) on *malformed*
    JSON, as today.
- **Rationale**: Matches existing patterns — fill emits diagnostics
  (render-don't-crash), the designer validates and surfaces at author time, the
  codec fail-fasts on malformed input. Non-throwing semantic validation lets the
  editor hold transient invalid states (e.g. a duplicate name mid-rename)
  without exceptions.
- **Alternatives**: *Eager throw at construction* (like `JetFontFamily` in 022)
  — rejected for the report model: it would make mid-edit transient states
  impossible and crash the designer.

## 3. Native engine traversal (reproducing today's band stream byte-identically)

- **Decision**: The rewritten `ReportFiller` traverses `ReportBody` directly and
  emits the same logical band stream the current filler does:
  `title` once → open `body.root.groups` outermost-first → walk `root.children`
  in order (a `BandNode` is a per-row band; a `NestedScope` recurses over its
  collection) → close groups → `summary`; `noData` when empty. The rewritten
  `ReportLayouter` reads page furniture from `PageFurniture` (record-blind,
  per-page, page-scoped substitution unchanged) and group-pagination flags from
  the relevant `GroupLevel`.
- **Rationale**: The current fill/layout semantics (master-level multi-level
  grouping, arbitrary-depth master/detail, `keepTogether`/`reprint`/
  `startNewPage`) map 1:1 onto the tree, so the emitted `FilledBand` stream and
  `PageFrame`s are identical — provable by the carried-over goldens.
- **Alternatives**: *Lowering to the legacy filler* — rejected (D3, native
  engine). The traversal is the native rewrite, not a lowering shim.

## 4. v1 → v2 migration mapping

- **Decision**: One `SchemaMigration(fromVersion: 1)` performs a pure map→map
  transform (see [data-model.md](data-model.md) for the full table). Highlights:
  `pageHeader/pageFooter/columnHeader/columnFooter/background` → `furniture.*`;
  `title/summary/noData` → `body.*`; template `groups[]` → `body.root.groups[]`;
  `groupHeader/groupFooter` (by name) folded into the matching
  `GroupLevel.header/footer`; master `detail` bands and `collectionField`
  detail bands → ordered `root.children` (`BandNode`/`NestedScope`) preserving
  v1 band order; nested `band.children` recurse; every variable `resetGroup`
  name is rewritten to the new group `id` (Q2 / FR-003a).
- **Rationale**: Every v1 construct has exactly one v2 home, and authored order
  is preserved by emitting `children` in v1 order — this is why `ScopeNode` is an
  ordered heterogeneous list. Lossless ⇒ a migrated report renders identically.
- **Alternatives**: *Drop unsupported v1 bands* (column/background) — rejected:
  they map cleanly to reserved furniture slots (still not laid out, so
  byte-identical holds). *Best-effort on invalid v1* (groupHeader naming an
  undeclared group) — preserved with a diagnostic (render-don't-crash), not a
  hard failure.

## 5. Stable id assignment

- **Decision**: Migration assigns **deterministic** ids derived from
  position/role (e.g. role + path index), so a migrated v1 report is reproducible
  and golden-stable. The designer mints fresh unique ids (reusing the existing
  `ElementIdFactory` pattern) for newly created bands/groups/scopes.
- **Rationale**: Deterministic migration keeps round-trip and render-equality
  tests stable; a factory mirrors how element ids already work in the designer.
- **Alternatives**: Random/UUID ids in migration — rejected: non-reproducible,
  noisy goldens/diffs.

## 6. Naming, furniture, and band `type` (confirmed)

- **Decision**: Keep the names `ReportDefinition` / `PageFurniture` /
  `ReportBody` / `DetailScope` / `ScopeNode` (`BandNode`/`NestedScope`) /
  `GroupLevel` / `Band` (design D4/Q-naming). `columnHeader`/`columnFooter`/
  `background` are **reserved** furniture slots (not laid out; multi-column is a
  future feature). Every `Band` keeps a `type` (`BandType`) for labels/glyphs,
  identity, and faithful migration, with position authoritative for role and
  `type` validated consistent with the slot (Q1 / FR-001a).
- **Rationale**: Locked during brainstorming + /clarify.
- **Alternatives**: positional-only band (no `type`) — rejected by the user
  (Q1=B); group reference by `name` — rejected (Q2=A, by id).

## 7. Dependencies

- **Decision**: No new dependency. Uses existing `flutter`, `pdf`, `shadcn_ui`,
  the existing expression engine, element codecs, `SchemaMigration`
  infrastructure, and golden harness.
- **Rationale**: Principle I (minimal) and the existing infra already covers
  serialization/migration, rendering, and the designer.
