# Epic E2 — Resilience & Stress

- **Date:** 2026-06-20
- **Status:** Approved (ready for `writing-plans`)
- **Type:** Implementable epic spec (one plan → implement cycle)
- **Parent roadmap:** [2026-06-20-production-readiness-roadmap-design.md](./2026-06-20-production-readiness-roadmap-design.md)
- **Predecessor:** E1 — Release Hygiene (done, merged to local main)

## Purpose

E2 is the **embed go/no-go gate** of the production-readiness program: prove the
report engine is *embed-safe at real volume with dirty data* before the program
invests in platform breadth (E3–E5). It answers one question — "when an embedder
feeds this engine a large, malformed dataset, does it stay standing, stay
correct, and tell the host what went wrong?" — and locks the answer as a
regression contract.

## Scope decision (deliberate narrowing of roadmap-E2)

The parent roadmap's E2 bundled three concerns: performance benchmarks, memory
profiling, and bad-data hardening. This spec **deliberately narrows** E2 to the
resilience core, by three approved decisions (2026-06-20):

1. **Resilience-only.** No wall-clock performance budgets, no optimization, no
   re-architecture. The deliverable is bad-data hardening plus a test suite that
   *locks* the engine's existing "render-don't-crash" guarantees.
2. **Stress-to-failure at 50k+ rows.** Prove the resilience guarantees hold at
   brutal scale and *locate the breaking point*, rather than asserting a
   fixed-volume time/memory SLA.
3. **Bounded per-row diagnostic visibility.** One real engine change: make
   per-row data faults visible *and* bounded, so a 50k-row dirty dataset yields a
   useful, capped set of located diagnostics instead of one deduped warning (or
   silence).

**The narrowed-out work is recorded, not dropped.** Performance budgets,
streaming fill, and streaming PDF export remain roadmap items. If E2's stress
exercise surfaces real memory or time pressure (the eager-fill `List<FilledBand>`
is the prime suspect — see Grounding), that becomes a **documented finding that
spins a future spec (E2b — streaming fill)**, not work performed inside E2. This
keeps E2 small and low-risk: a go/no-go gate measures, it does not rebuild.

## Grounding: what the engine does today (verified in code)

Audited 2026-06-20 against `packages/jet_print/lib/src`:

- **Data sources are lazy cursors.** `JetDataSource.open()` returns a forward-only
  `DataSet` (`moveNext()`/`current`); the three built-ins delegate to
  `RowCursorDataSet`, pulling one row at a time. In-memory and JSON sources
  *materialize their input* into a `List` at construction, but iteration holds
  only the current row.
- **Fill is eager.** `ReportFiller.fillDefinition` (`report_filler.dart`) walks the
  cursor once and accumulates *every* band for *every* row into a single
  `List<FilledBand>` (`report_filler.dart:229`) before returning. At 50k master
  rows this list is the dominant memory cost and is inherent to group-break and
  aggregate semantics (a `SUM` footer cannot be streamed). **This is the prime
  suspect for any memory finding — and the trigger for a possible E2b.**
- **Layout is lazy out.** The layouter computes page *boundaries* eagerly but
  builds each `PageFrame` on demand; PDF export, by contrast, assembles the whole
  `PdfDocument` in memory before `save()`. (Out of scope for E2 — noted for E2b.)
- **Resilience is already strong (render-don't-crash).** Nothing found aborts a
  report on one bad row. Parse errors → `!ERR` + error diagnostic
  (`element_resolver.dart:118`); a field missing from the schema → fallback token
  + warning (`element_resolver.dart:133`); a field absent from a row → blank +
  warning; null/wrong-type/non-row collections → empty + warning
  (`report_filler.dart` `childRowsOf`); wrong-type aggregate inputs → **silently
  skipped** (`variable_accumulator.dart:50`, an `if (input is JetNumber)` with no
  `else`). The expression evaluator is total: failures are `JetError` *values*
  (rendered `!ERR`), never thrown.

Two scale-hostile diagnostic behaviors fall out of that audit, and are the gap
E2 closes:

- **Deduped-to-one.** `warnedFields` / `warnedCollections` are `Set<String>`
  caches keyed by name (`element_resolver.dart:49-50`), so a fault in row 1 warns
  *once* for the whole report — the host cannot tell where, or how widespread.
- **Silent.** Wrong-type aggregate inputs vanish with no diagnostic — a `SUM`
  quietly under-counts. This is the worst case: **silent data corruption**.

`ReportDiagnostics` (`report_diagnostics.dart`) is a flat growable `List<Diagnostic>`
with `info`/`warning`/`error(message, {elementId})` helpers — no row concept, no
cap.

## Pillars

### Pillar 1 — Bad-data resilience matrix (tests only; no behavior change)

A new contract suite that locks today's render-don't-crash guarantees so they
cannot silently regress. One case per fault class; each asserts **(a)** the fill
does not throw, **(b)** the documented fallback renders, and **(c)** the expected
diagnostic (severity + identifying message/element) is recorded.

Fault classes (all already handled today — the suite makes the handling a
contract):

| # | Fault | Expected render | Expected diagnostic |
|---|-------|-----------------|---------------------|
| R1 | Expression references a field absent from the schema | fallback token (`#ERROR` default) | warning, names the field |
| R2 | Ragged row: field declared by schema, absent in one row | blank | warning (bounded, row-tagged — see Pillar 2) |
| R3 | Wrong-type value feeding `SUM`/`AVG` | aggregate skips the value | warning (bounded, row-tagged — Pillar 2) |
| R4 | Wrong-type value feeding `MIN`/`MAX` | aggregate skips the value | warning (bounded, row-tagged — Pillar 2) |
| R5 | Null collection field on a nested scope | scope emits no rows | none (legitimate empty) |
| R6 | Wrong-type collection field (not a list) | scope emits no rows | warning, names the collection |
| R7 | Non-row entry inside a collection list | entry skipped | warning (bounded, row-tagged — Pillar 2) |
| R8 | Malformed/un-parseable expression | `!ERR` | error, names the parse failure |
| R9 | Division by zero | `!ERR` | error |
| R10 | Unknown function call | `!ERR` | error |
| R11 | Empty data source (0 rows) | `noData` band renders | info |

For R2/R3/R4/R7, the *bounded, row-tagged* form is a Pillar 2 deliverable; before
Pillar 2 lands these emit today's deduped/silent form, so the matrix tests are
authored against the **post-Pillar-2** behavior (the plan orders Pillar 2 before
the matrix cases that depend on it, or marks those cases pending until Pillar 2).

### Pillar 2 — Bounded, row-aware diagnostics (the one engine change)

Introduce a **`DiagnosticBudget`** in the fill layer (`lib/src/rendering/fill/`)
that makes per-row *data* faults both visible and bounded.

**Behavior:**

- Carries the **current row position** — a 1-based master-row index for v1 — set
  by `ReportFiller` as it advances the cursor.
- **Caps** the number of per-row *data* diagnostics at **N = 100** (a named
  internal constant). Once N have been emitted, further per-row data diagnostics
  are counted but not recorded; at **fill completion**, if any were suppressed, a
  single trailing `info` is recorded reflecting the final suppressed total `M`:
  `"… and <M> more row-level data issues were suppressed (showing first <N>)"`.
- Each per-row data diagnostic message includes the row position, e.g.
  `"Row 1234: value for "amount" is not a number; skipped from SUM"`.

**Applied to the per-row fault sites** that are currently deduped-once or silent:

- **R2 ragged row** (field declared by schema, absent in this row): row-tagged,
  bounded. (Today: deduped warning via `warnedFields`.)
- **R3/R4 wrong-type aggregate input**: *surfaced* (today: silent). The
  accumulator stays pure — `VariableAccumulator` exposes a new pure
  `int skippedNonNumeric` counter (incremented where `fold` currently skips a
  non-`JetNumber` input for `sum`/`average`, and a non-comparable input for
  `min`/`max`); the **filler** reads the delta after folding each row's
  contribution and routes a bounded, row-tagged diagnostic through the budget. No
  diagnostics dependency is added to the expression layer (layering preserved).
- **R7 non-row collection entry**: row-tagged, bounded. (Today: deduped via
  `"$name#entry"`.)

**Unchanged (correct as-is):**

- *Structural* diagnostics stay deduped-once — they are identical for every row:
  field/collection not in schema (R1, R6), expression parse error (R8), URL-only
  image. One entry is the right answer.
- *Present-but-null* values stay silent — a legitimately blank cell is not a
  fault.

**Sub-decision (settled):** the cap `N` is an **internal constant**, not a new
`RenderOptions` field. E6 freezes the public surface; exposing a tunable is a
clean E6-era addition if embedders ask. v1 of the row position is the
**master-row index only**; a richer nested-scope path (e.g.
`"row 1234 ▸ lines[3]"`) is explicitly deferred.

**Why the cap is load-bearing:** unbounded per-row diagnostics would *themselves*
be the memory blow-up the epic exists to prevent — a dirty 50k-row dataset would
grow a 50k-entry diagnostics list. Bounded-with-location is the only design that
is both useful to a host and safe under stress; decisions (2) and (3) reconcile
*only because* of the cap.

### Pillar 3 — 50k-row stress-to-failure

Two tiers, to deliver "find the breaking point" without committing a CI-hostile
test:

- **Committed test** — one stress test at a single CI-stable large N (**target
  50,000** master rows, dialed down only if it cannot stay within a few seconds
  of wall time on the dev/CI machine), feeding a dataset with **scattered bad
  data** (a mix of the Pillar 1 fault classes sprinkled across the rows). It
  asserts **resilience invariants only**:
  - the fill/render does not throw;
  - a paintable `RenderedReport` is produced with a sane `pageCount`;
  - diagnostics are **bounded** (count ≤ N + the suppression summary);
  - spot-checked **correctness** on known-clean rows (their values render
    correctly despite neighbouring dirty rows — proving per-row isolation at
    scale).

  It records **no time or memory assertion** (honoring "resilience-only / skip
  performance benchmarking"). Peak RSS and wall time are *logged as advisory
  observations* (via `ProcessInfo.currentRss` from `dart:io`), not gated.

- **Implementation-time exploration** — during implementation, run the stress
  scenario at escalating N (10k / 50k / 100k+) to locate the cliff (where wall
  time or memory becomes unacceptable, or it OOMs). **Findings are written to the
  E2 findings/acceptance record** (`specs/`-adjacent or a doc under
  `docs/superpowers/`), not committed as an always-run test. This is the
  stress-to-failure deliverable, and it is the input to the deferred E2b decision.

## Functional requirements

- **FR-E2-001** A new resilience matrix suite asserts no-throw + documented
  fallback + expected diagnostic for fault classes R1–R11.
- **FR-E2-002** A `DiagnosticBudget` in the fill layer tracks the current
  (1-based master-row) position and caps per-row data diagnostics at the internal
  constant `N = 100`, emitting exactly one suppression-summary `info` at fill
  completion if any were suppressed.
- **FR-E2-003** Per-row data diagnostics (R2, R3, R4, R7) include the row position
  in their message and are routed through the budget.
- **FR-E2-004** `VariableAccumulator` exposes a pure `skippedNonNumeric` count
  (no diagnostics/fill dependency); the filler turns its per-row delta into a
  bounded, row-tagged diagnostic. Wrong-type aggregate inputs are no longer
  silent.
- **FR-E2-005** Structural diagnostics (R1, R6, R8, URL-only image) remain
  deduped-once; present-but-null values remain silent. No regression to existing
  diagnostic behavior outside the four per-row sites.
- **FR-E2-006** A committed stress test at N = 50,000 (CI-stable; dialed down only
  if necessary) with scattered bad data asserts the resilience invariants in
  Pillar 3 and logs RSS/wall-time as advisory only.
- **FR-E2-007** An E2 findings record documents the implementation-time
  escalating-N exploration (observed behavior, located breaking point, OOM if
  any) and states whether a follow-up E2b (streaming fill) is warranted.

## Success criteria

- **SC-E2-001** The full suite stays green via the documented CI command
  (`flutter test packages/jet_print apps/jet_print_playground` from repo root).
- **SC-E2-002** `flutter analyze` is clean; `dart format` leaves E2's own files
  unchanged.
- **SC-E2-003** Goldens are byte-unchanged (E2 touches diagnostics + tests, not
  render output).
- **SC-E2-004** The resilience matrix (R1–R11) passes, each case asserting all
  three of: no-throw, fallback render, expected diagnostic.
- **SC-E2-005** A 50k-row scattered-dirty-data render completes without throwing,
  produces a paintable report, emits ≤ N + 1 per-row diagnostics, and renders the
  known-clean rows correctly.
- **SC-E2-006** The E2 findings record exists and states the breaking-point
  observation and the E2b recommendation.

## File structure

- **Create** `lib/src/rendering/fill/diagnostic_budget.dart` — the bounded,
  row-aware sink (current position, cap `N`, suppression summary).
- **Modify** `lib/src/rendering/fill/report_filler.dart` — set the row position
  as the cursor advances; own a `DiagnosticBudget`; read per-row
  `skippedNonNumeric` deltas and route them through the budget; route R2/R7
  through the budget.
- **Modify** `lib/src/rendering/fill/element_resolver.dart` — route the per-row
  ragged-field fault (R2) through the budget while leaving the structural
  schema-absence warning (R1) deduped-once.
- **Modify** `lib/src/expression/aggregate/variable_accumulator.dart` — add the
  pure `skippedNonNumeric` counter; no new dependencies.
- **Create** `test/rendering/resilience/bad_data_matrix_test.dart` — Pillar 1
  (R1–R11).
- **Create** `test/rendering/resilience/stress_dirty_dataset_test.dart` —
  Pillar 3 committed stress test.
- **Create** `test/rendering/fill/diagnostic_budget_test.dart` — unit tests for
  the cap, suppression summary, and row-tagging.
- **Modify/Create** `test/expression/aggregate/variable_accumulator_test.dart` —
  cover `skippedNonNumeric`.
- **Create** the E2 findings record (e.g.
  `docs/superpowers/specs/2026-06-20-e2-findings.md`) capturing the
  escalating-N stress observations and the E2b recommendation.

## Global constraints

Copied verbatim from the program's conventions; every task inherits these:

- The full suite must stay green via the **documented CI command**
  `flutter test packages/jet_print apps/jet_print_playground`, run from the repo
  root `/Users/ahmeturel/Projects/oss/jet-print`.
- Run `flutter` / `dart` from `packages/jet_print`; run `git` from the repo root
  (flutter leaves the cwd inside the package).
- **Goldens must not change.** E2 alters diagnostics and adds tests; it must not
  alter any render output.
- Architecture tests that scan source files must use `findWorkspaceRoot()` from
  `test/support/workspace.dart` — never a bare relative `Directory('lib')`.
- The expression layer must not depend on the fill/render layer (the inward-only
  rule enforced by `architecture/layer_boundaries_test.dart`). FR-E2-004's
  pure-counter design exists to honor this.
- Commit messages end with
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Do not push; branch before committing (E1 landed on local `main`).

## Out of scope (explicit)

- Performance budgets / wall-clock SLAs / time assertions.
- Streaming fill, chunked fill, or any change to the eager `List<FilledBand>`
  materialization (→ deferred E2b, gated on FR-E2-007's finding).
- Streaming or on-disk PDF export (→ E2b).
- Nested-scope-path row positions (v1 is master-row index only).
- Exposing the diagnostic cap `N` via `RenderOptions` (→ possible E6 addition).
- Desktop / web / mobile platform concerns (E3–E5).

## Next step

Ready for `writing-plans`. The plan must order Pillar 2 (the engine change)
before the Pillar 1 matrix cases that assert its post-change behavior (R2/R3/R4/
R7), and keep Pillar 1's behavior-free cases (R1, R5, R6, R8–R11) independent.
