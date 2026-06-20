# Epic 1 — Release Hygiene & Truth

- **Date:** 2026-06-20
- **Status:** Approved — ready for `writing-plans`
- **Parent:** [Production Readiness Roadmap](./2026-06-20-production-readiness-roadmap-design.md) (Epic E1, Tier 0)
- **Risk:** Low — only code change is deleting a dead widget + adding tests; the rest is docs/metadata.

## Goal

Remove the false signals and packaging gaps that make `jet_print` look less
finished than it is, and clean the public surface *before* a 1.0 freeze locks it.
Everything here is reversible-cheap now and expensive after E6.

## Decisions (locked)

- **License:** Apache-2.0. Copyright line: `Copyright 2026 Ahmet Urel`.
- **`JetPrintPlaceholder`:** remove it (dead surface; only its own self-tests reference it).
- **Pending acceptances (T037, T052):** automate the automatable steps; record a
  written acceptance note for the human-only OS-dialog steps; check the tasks off.
- **Spec 033 (multi-level inline aggregates):** pulled into the pre-1.0 scope as a
  **separate sibling spec** (it already has `spec.md` + `plan-designer.md` +
  `plan-engine.md`). It is NOT part of E1; it goes to plan-execution right after E1.

## Work items

### 1. License — Apache-2.0
- Add `/LICENSE` (repo root) — full Apache-2.0 text, `Copyright 2026 Ahmet Urel`.
- Add `/packages/jet_print/LICENSE` — pub.dev requires a `LICENSE` **inside the
  published package directory**; a root-only license is not enough.
- No `pubspec` license field is required — pub derives it from the `LICENSE` file.
- (Optional, deferred) a `NOTICE` file — not required for a from-scratch Apache-2.0
  project with no third-party source vendored in; skip unless we later vendor code.

### 2. Documentation truth — two READMEs
- **Rewrite `/README.md`** (the repo landing page). Drop all "foundational
  scaffold / placeholder" framing. New sections: what jet_print is (a mature
  WYSIWYG report-designer + render/export library); the feature surface; install;
  a **real** quickstart (build a `ReportDefinition` → fill with a `JetDataSource`
  via `JetReportEngine` → preview → export PDF via `JetReportExporter` → print via
  `JetReportPrinter`); the data-source model; an **honest platform-status line**
  (macOS verified today; Windows/Linux/web/mobile tracked in the roadmap); links
  to the 7 playground samples. **Keep** the existing test/quality-gate section — it
  is accurate and strong.
- **Add `/packages/jet_print/README.md`** (currently missing — pub.dev would show a
  blank package page). This is the publishable, consumer-facing README: the
  quickstart + public-API overview, no monorepo/CI internals.

### 3. Remove `JetPrintPlaceholder`
- Delete `packages/jet_print/lib/src/designer/jet_print_placeholder.dart`.
- Remove its `export` line from `packages/jet_print/lib/jet_print.dart`
  (public surface drops 54 → 53 exports).
- Delete `packages/jet_print/test/jet_print_placeholder_test.dart` and its golden
  `packages/jet_print/test/goldens/jet_print_placeholder.png`.
  (Do **not** touch `test/rendering/elements/placeholder_test.dart` or
  `image_placeholder_test.dart` — those cover the unrelated ImageElement glyph.)
- Update `test/public_api_test.dart` and `test/designer/designer_test.dart`:
  replace the placeholder assertions with a real public entry point
  (`JetReportDesigner` is const-constructible / builds inside a `ShadApp` shell).
- Update both READMEs' consuming example to use a real widget, not the placeholder.

### 4. pub.dev metadata
- Add to `packages/jet_print/pubspec.yaml`:
  - `repository: https://github.com/a-urel/jet-print`
  - `homepage: https://github.com/a-urel/jet-print`
  - `issue_tracker: https://github.com/a-urel/jet-print/issues`
  - `topics: [report, pdf, wysiwyg, designer, printing]` (pub rules: lowercase,
    no spaces, ≤5 topics, each ≤32 chars — these comply)
- **Do not** bump `version` to `1.0.0` and **do not** cut a CHANGELOG release entry
  — those belong to E6.

### 5. Close pending acceptances (automate + waive)
- **T037 (spec 012, export):** add widget/integration tests for the automatable
  half — tapping the preview export action invokes `JetReportExporter` (or fires
  the `ReportPreviewRequested`/save callback); the print action drives the
  injectable `PrintDialogPresenter` seam (already swappable, so testable without a
  real OS dialog). Write `specs/012-export-support/acceptance-T037.md` recording
  the human-verified OS save/print steps + the new automated coverage; check off
  T037 in `specs/012-export-support/tasks.md`.
- **T052 (spec 021, format properties):** add tests that style/shape/barcode-tint
  edits round-trip through save→reload with parity and that undo is ≤3 interactions
  (SC-001/SC-006). Write `specs/021-format-properties/acceptance-T052.md` for the
  visual GUI steps; check off T052 in `specs/021-format-properties/tasks.md`.

## Out of scope (→ Epic 6 unless noted)
Version `1.0.0` bump; CHANGELOG release cut; `example/` directory; dartdoc/docs
site; CONTRIBUTING / CODE_OF_CONDUCT; multi-platform CI matrix. **Spec 033 feature
work** → its own spec/plan-execution, immediately after E1.

## Testing strategy
- Public-API test asserts `JetPrintPlaceholder` is gone and a real entry point is
  exported (surface is 53).
- New automated acceptance tests (item 5) cover the export action + format
  round-trip.
- Full `flutter test` stays green; `flutter analyze` clean; `dart format` clean.
- **Goldens unchanged** except the intentional deletion of
  `jet_print_placeholder.png`. If any *other* golden changes, stop and inspect.

## Success criteria
- **SC-E1-1:** Apache-2.0 `LICENSE` present at repo root **and** in
  `packages/jet_print/`.
- **SC-E1-2:** Root README and a new `packages/jet_print/README.md` accurately
  describe the product with a working quickstart; no "scaffold/placeholder"
  language remains.
- **SC-E1-3:** `JetPrintPlaceholder` no longer exported (53 exports); suite green;
  no remaining golden/test references the placeholder.
- **SC-E1-4:** `pubspec.yaml` carries repository/homepage/issue_tracker/topics;
  `dart pub publish --dry-run` reports no missing-metadata/license errors
  (a 0.x version warning is acceptable — the 1.0 bump is E6).
- **SC-E1-5:** T037 and T052 are checked off with an acceptance record; the
  automatable steps have new automated coverage.
- **SC-E1-6:** `flutter analyze` clean, `dart format` clean, full suite green,
  goldens unchanged (except the deleted placeholder golden).

## Risks / watch-outs
- The placeholder golden image must be deleted alongside the widget, or the suite
  fails on a missing reference.
- `dart pub publish --dry-run` may surface *other* latent publish warnings (e.g.
  missing `example/`) — note them as E6 follow-ups, don't try to fix in E1.
- The package README is **new**, not a move — make sure it stands alone (a pub.dev
  reader has no monorepo context).
