<!--
SYNC IMPACT REPORT
==================
Version change: (template / unversioned) → 1.0.0
Bump rationale: Initial ratification of the project constitution. Baseline 1.0.0
  established because this is the first concrete, governing version replacing the
  placeholder template.

Principles defined (6):
  I.   Library-First & Clean Public API
  II.  Layered & Extensible Architecture
  III. Test-First (NON-NEGOTIABLE)
  IV.  Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE)
  V.   Versioned & Backward-Compatible Serialization
  VI.  Documentation & Developer Experience

Renamed principles: none (initial creation; template placeholders replaced).
Added sections:
  - Technology & Quality Standards (was [SECTION_2_NAME])
  - Development Workflow & Quality Gates (was [SECTION_3_NAME])
  - Governance

Removed sections: none.

Templates / artifacts reviewed:
  ✅ .specify/templates/plan-template.md — "Constitution Check" gate is generic and
       resolves against this file dynamically; no edit required. Aligns with all principles.
  ✅ .specify/templates/spec-template.md — scope/requirements structure compatible; no edit required.
  ⚠ .specify/templates/tasks-template.md — sample text states "Tests are OPTIONAL".
       This conflicts with Principle III (Test-First, NON-NEGOTIABLE). See follow-up below.
  ✅ .specify/templates/commands/ — directory not present; nothing to reconcile.
  ✅ README.md / docs/quickstart.md — not present yet; will be authored to comply with
       Principle VI when created.

Follow-up TODOs:
  - When per-feature specs are written, tasks.md MUST always include test tasks
    (Principle III overrides the generic "tests optional" sample guidance in
    tasks-template.md).
  - RATIFICATION_DATE set to today (new project, no prior adoption date on record).
-->

# jet-print Constitution

## Core Principles

### I. Library-First & Clean Public API

jet-print is, first and foremost, a reusable Flutter package published to pub.dev. Every
capability MUST be consumable as a library by embedding applications without modification.

- The package MUST be self-contained and MUST NOT depend on any host-application code,
  global singletons, or app-specific assumptions.
- The public API surface MUST be deliberately minimal. Internal types MUST live under
  `src/` and MUST NOT be exported; only intentionally public symbols are re-exported from
  the package's top-level library files.
- The sample/playground app and the (future) VS Code extension are CONSUMERS of the library.
  They MUST exercise the package only through its public API — never through private
  internals — proving the API is sufficient for real use.
- Breaking changes to the public API MUST follow Semantic Versioning (see Principle V).

**Rationale**: A reporting tool earns adoption by being embeddable and stable. Treating the
library as the product (and every app as a consumer) keeps the API honest and prevents
hidden coupling that would break downstream users.

### II. Layered & Extensible Architecture

The system MUST maintain strict separation between distinct concerns, each independently
testable:

- **Domain / Report Model**: the serializable report definition (pages, bands, elements,
  data bindings) with NO dependency on Flutter widgets, rendering, or designer UI.
- **Rendering / Layout**: turns a report model + data into laid-out, printable output.
- **Designer UI**: the design canvas, property editors, and tooling (design-time and
  runtime) that manipulate the report model.
- **Data Binding**: connects external data sources to report elements.

Rules:

- Dependencies MUST point inward toward the domain model; the domain model MUST NOT import
  rendering or UI layers.
- New report element types (text, image, table, barcode, etc.) MUST be addable via defined
  extension points WITHOUT modifying the rendering engine's core or the designer's core.
- Cross-layer communication MUST occur through explicit interfaces/abstractions, not
  concrete implementations.

**Rationale**: A report designer accretes element types and features indefinitely. Clean
layering plus extension points is what keeps it maintainable and lets contributors add
elements without destabilizing the core.

### III. Test-First (NON-NEGOTIABLE)

Test-Driven Development is mandatory for all production code.

- Tests MUST be written before implementation: write test → confirm it fails (Red) →
  implement until it passes (Green) → refactor.
- Every public API, every report-model operation, and every serialization path MUST have
  unit tests. Layer boundaries (Principle II) MUST have contract/integration tests.
- Bug fixes MUST begin with a failing regression test that reproduces the bug.
- A change MUST NOT be merged with failing or skipped tests.

**Rationale**: A library that other apps depend on cannot regress silently. Test-first is
the only reliable guard for a reusable, long-lived codebase, and it forces the clean,
testable API that Principles I and II require.

### IV. Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE)

The design canvas, the print preview, and the final printed/exported output MUST be
visually consistent for the same report model and data.

- Layout and rendering logic MUST be shared across canvas, preview, and print paths —
  fidelity MUST NOT be achieved by maintaining parallel, divergent rendering code.
- Visual output MUST be protected by golden (snapshot) tests covering representative
  reports, including the data-aware invoice scenario.
- Any change that alters rendered output MUST update goldens deliberately and call out the
  visual change in review.

**Rationale**: "What you see is what you print" is the core promise of a report designer.
If preview and print diverge, the tool is untrustworthy regardless of any other quality.

### V. Versioned & Backward-Compatible Serialization

Report definitions are persisted artifacts owned by end users; their format is a contract.

- The report model MUST serialize to and deserialize from a stable, documented,
  human-inspectable format (JSON).
- The serialized schema MUST carry an explicit schema/version field.
- Older serialized reports MUST continue to load in newer library versions; when the schema
  changes, a forward migration MUST be provided.
- Both the package version AND the report-schema version MUST follow Semantic Versioning.
  A breaking schema change is a MAJOR event and MUST be documented in the changelog with a
  migration path.

**Rationale**: Users invest effort designing reports. Silently breaking saved reports is
unacceptable; versioning plus migration makes the format dependable over time.

### VI. Documentation & Developer Experience

As a pub.dev package, jet-print MUST meet the ecosystem's quality expectations.

- All public API symbols MUST carry dartdoc comments explaining purpose and usage.
- The repository MUST maintain a runnable example/sample app and a `CHANGELOG.md` updated
  with every release.
- Public-facing changes MUST update relevant documentation in the same change.
- Code MUST pass the project's configured analyzer/lints with zero warnings; formatting MUST
  follow `dart format`.

**Rationale**: Adoption and contribution both depend on discoverable, accurate docs and a
frictionless first-run experience. Documentation is part of the deliverable, not an
afterthought.

## Technology & Quality Standards

- **Platform**: Flutter / Dart with sound null-safety. The library MUST compile and run on
  the platforms it advertises; platform-specific code MUST be isolated behind abstractions.
- **Printing & preview**: printing/preview capabilities MUST be provided through
  well-scoped, swappable abstractions so the rendering core stays platform-agnostic.
- **MVP scope**: the first milestone MUST enable an end user to build a **data-aware invoice
  designer** — i.e., bind a data source, design an invoice layout on the canvas, preview it,
  and print it. Features outside this MVP path MUST NOT block MVP delivery.
- **Dependencies**: third-party dependencies MUST be justified, minimal, and compatible with
  pub.dev publication (permissive licensing, maintained). Prefer the Flutter/Dart standard
  library and first-party packages.
- **Static analysis**: a strict analysis_options configuration MUST be in place; CI MUST run
  analyze, format-check, and the full test suite.

## Development Workflow & Quality Gates

- **Constitution Check**: every `plan.md` MUST pass the Constitution Check gate before
  Phase 0 and again after Phase 1 design. Violations MUST be recorded and justified in the
  plan's Complexity Tracking table or the design MUST be revised.
- **Code review**: every change MUST be reviewed. Reviewers MUST verify compliance with all
  principles — especially Test-First (III) and Rendering Fidelity (IV).
- **Merge gates**: a change MUST NOT merge unless tests pass, analyzer/lints are clean,
  formatting is applied, goldens are current, and affected docs/changelog are updated.
- **Releases**: versions are cut per Semantic Versioning; `CHANGELOG.md` MUST describe
  user-visible changes, schema migrations, and any breaking changes.

## Governance

This constitution supersedes all other development practices. Where any other document or
habit conflicts with it, this constitution prevails.

- **Amendments**: changes to this constitution MUST be proposed in writing, reviewed and
  approved, and accompanied by a version bump and an update to all dependent templates and
  guidance docs.
- **Versioning policy** (of this constitution): MAJOR for backward-incompatible governance
  or principle removals/redefinitions; MINOR for a new principle/section or materially
  expanded guidance; PATCH for clarifications and non-semantic refinements.
- **Compliance review**: all plans, reviews, and merges MUST verify compliance. Unjustified
  complexity or principle violations MUST be rejected or remediated before merge.
- **Runtime guidance**: agent- and contributor-facing guidance (e.g., `CLAUDE.md`, README,
  quickstart) MUST stay consistent with this constitution and is subordinate to it.

**Version**: 1.0.0 | **Ratified**: 2026-06-04 | **Last Amended**: 2026-06-04
