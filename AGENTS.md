# Working in jet-print

Guidance for AI coding agents and new contributors. This file is canonical;
`CLAUDE.md` points here and adds Claude Code specifics.

Read this before your first edit. For depth, follow the pointers at the bottom —
don't load them until you need them.

## The repo in three sentences

`jet-print` is a Dart pub workspace holding one product and one consumer.
The product is `packages/jet_print`: a Flutter library for building WYSIWYG
report designers — a reified report model, a fill/paginate/render engine,
PDF/PNG export, system printing, and an interactive shadcn-themed designer.
`apps/jet_print_playground` is a desktop/web/mobile app that consumes the
library **only through its public API**, which is how the API stays honest.

```text
packages/jet_print/           the product
  lib/jet_print.dart          the ONLY public entry point (exports, nothing else)
  lib/src/                    private: domain · expression · data · rendering · designer · print
  test/                       377 test files
packages/jet_print_google_fonts/   optional font catalog add-on
apps/jet_print_playground/    consumer app + worked samples
```

Toolchain: Flutter **3.44.0+**, Dart **^3.6.0** (pub workspaces need 3.6).
One `flutter pub get` at the root resolves everything into one root
`pubspec.lock`.

## The quality gate

Run all three from the repository root. They mirror CI exactly, and a clean
checkout must pass all three:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test packages/jet_print apps/jet_print_playground
```

The member packages are listed explicitly on purpose: `flutter analyze` fans out
across workspace members by itself, but `flutter test` at a workspace root only
looks at the root package and would silently test nothing.

Never report work as done without running these and reading the output.

## Hard rules

Each rule names the test that enforces it. If you think a rule is wrong, the
test is the thing to argue with — change it deliberately and say so.

- **The public API is exactly what `lib/jet_print.dart` exports.** Everything
  under `lib/src/` is private to outside consumers. The playground app is a
  strict consumer: it imports `package:jet_print/jet_print.dart` and never
  `package:jet_print/src/...`. The library itself depends on no host app.
  Enforced by `test/encapsulation_test.dart` and `test/public_api_test.dart`.

  The library's *own* tests are a documented exception. White-box seam tests may
  import `src/` — whole directories (`test/domain`, `data`, `expression`,
  `rendering`, `print`, `web`, `designer/template`) plus individually named
  designer tests. Everything else is default-deny. If you add a test that needs
  an unexported helper, add it to the allowlist in `encapsulation_test.dart`
  **with a comment saying why**; that list is the record of what is deliberately
  white-box, and it only stays meaningful if each entry is justified.

- **Dependencies point inward, toward the domain.** Nothing under `lib/src/domain`
  (nor `data`, nor `expression`) may import the rendering or designer seams, or
  any Flutter UI library — `material`, `widgets`, `rendering`, `cupertino`,
  `painting`, `dart:ui`. `package:flutter/foundation.dart` is fine; it is UI-free.
  Enforced by `test/architecture/layer_boundaries_test.dart`.

- **One paint path.** The design canvas, the preview, page thumbnails, the PDF
  export and the PNG rasterizer all draw from the *same* recorded picture. Never
  achieve visual parity by writing a second painter — that is how a designer
  starts lying about what it will print. Enforced by the golden suites in
  `test/goldens/` and `test/designer/goldens/`.

- **Report JSON is versioned and lossless.** The schema carries an explicit
  version. A report written by a *newer* build must round-trip through an older
  one byte-for-byte — that is what `UnknownElement` and `UnknownScopeNode` are
  for; they preserve raw JSON verbatim, and moving, renaming or hiding such a
  node must not rewrite it. A schema change needs a forward migration
  (`lib/src/domain/serialization/migration.dart`) and a CHANGELOG entry.
  Enforced across `test/domain/serialization/`.

- **Tests come first.** Write the failing test, watch it fail, then implement.
  A bug fix starts with a regression test that reproduces the bug. Nothing
  merges with failing or skipped tests.

- **Golden changes are deliberate, never incidental.** If a golden moves, look at
  the diff image before regenerating and say in the change description what moved
  and why. A golden that shifts for a reason you cannot name is a bug you have
  not found yet.

- **Zero analyzer warnings, `dart format` clean.** Not a preference — CI fails on
  either.

- **Third-party packages stay behind one adapter.** `package:barcode` is reachable
  only from `lib/src/rendering/elements/barcode/package_barcode_encoder.dart`.
  Enforced by `test/architecture/barcode_dependency_isolation_test.dart`.

- **User-visible changes update `packages/jet_print/CHANGELOG.md`** in the same
  change, and public symbols carry dartdoc.

## The layers

| Seam | Files | What it holds |
|---|---:|---|
| `domain/` | 48 | The serializable report tree: `ReportDefinition`, bands, scopes, elements, styles, codecs, migration. Pure Dart. |
| `expression/` | 23 | The `{...}` expression language: lexer, parser, AST, evaluator, function registry, aggregates, formatting. Pure Dart. |
| `data/` | 17 | Data-source seam: `JetDataSource` and its in-memory / JSON / object / paged implementations, `JetDataSchema`, `FieldDef`, `DataSet` cursors. Pure Dart. |
| `rendering/` | 57 | Fill → layout → paint. `report_filler` binds data, `report_layouter` paginates, `paint/` records pictures, `export/` writes PDF/PNG, `crosstab/` plans pivots, `text/` does fonts and metrics. |
| `designer/` | 146 | The interactive surface: `canvas/`, `controller/` (commands + undo/redo), `layout/` (panels, inspectors), `preview/`, `interaction/`, `l10n/`, `template/`. |
| `print/` | 1 | `JetReportPrinter` — the injectable system-printing seam. |

Tests mirror this: `test/domain` (55), `test/expression` (30), `test/data` (14),
`test/rendering` (97), `test/designer` (169), `test/print` (2),
plus `test/architecture` (2), `test/goldens` (4), `test/web` (2), and 29 in the
playground. Shared helpers live in `test/support/` — `report_builders.dart`
builds fixtures, `workspace.dart` locates the repo root, `test_fonts.dart`
loads deterministic fonts.

## Traps

Real ones, each of which has cost time before.

- **`flutter test` at the root tests nothing.** Always name the member packages.
- **Goldens are macOS-only.** They carry the `golden` tag (see `dart_test.yaml`);
  other CI legs run `--exclude-tags golden`. Host font rasterization and PDF font
  subsetting differ per OS, so a golden regenerated elsewhere is wrong. CI's macOS
  leg runs `dart format --set-exit-if-changed` before anything else and stops
  there on failure, so a format regression silently skips the goldens too —
  don't read a green golden suite as confirmation that formatting passed.
- **A new enum variant hits several exhaustive switches.** Adding a `ShapeKind`,
  for instance, means the geometry switch in `rendering/elements/shape_path.dart`
  *and* the designer's thumbnail painter *and* the inspector gallery. Dart will
  fail the build on the ones it can see; grep for the enum name to find the rest.
- **Localization is three ARB files plus regeneration.** Strings live in
  `lib/src/designer/l10n/jet_print_{en,de,tr}.arb`. Editing the generated
  `jet_print_localizations*.dart` directly is a silent break — the next `gen-l10n`
  run discards it. English must stay the first supported locale so a missing key
  falls back to English. Note German strings are the widest; they are what makes
  toolbars overflow.
- **On the web, numbers behave differently — this has caused three bugs here.**
  JavaScript has one number type, so a whole-valued `double` is indistinguishable
  from an `int`: `10.0 is int` is `true`, and `30.0.toString()` is `"30"`, not
  `"30.0"`. Never assert on a stringified double or on int-vs-double typing
  without pinning the representation (`toStringAsFixed`) or choosing a fractional
  value. Two of the three bugs were tests asserting a distinction the platform
  cannot make; the third was real output. The chrome CI leg is what catches
  these, so run `flutter test --platform chrome` from the package directory
  before trusting anything numeric.
- **`copyWith` uses thunks, so it *can* clear nullable fields.** See
  `domain/copy_support.dart`: omit a parameter to keep the current value, pass
  `field: () => null` to clear it, `field: () => v` to set it. Any older comment
  claiming "copyWith cannot clear, build directly" is obsolete.
- **Rebuilders drop fields silently.** Several places reconstruct a scope, band or
  element field-by-field rather than with `copyWith`. When you add a field to one
  of those types, grep for every construction site — a dropped field is data loss
  that no type error catches.
- **Four god-files are split with `part` + `extension`.** `properties_panel.dart`,
  `design_canvas.dart`, `jet_report_designer_controller.dart` and
  `outline_panel.dart` each spread across part files. Two consequences: `setState`
  and `notifyListeners` are `@protected` and unreachable from an extension, hence
  the `_rebuild()` / `_notify()` proxies; and a *public* extension on a public
  class must be named in the barrel's `export ... show` list, or its methods are
  uncallable through `package:jet_print/jet_print.dart`.
- **A long engine file may be long on purpose — apply the test, not a roster.**
  `rendering/fill/report_filler.dart` (bind, walk, accumulate) and
  `rendering/layout/report_layouter.dart` (measure, break, place) are each *one*
  algorithm whose steps share mutable state across the whole pass, which is why
  neither joined the four designer files split above: no seam can be cut without
  threading that state through it by hand. **The test is shape, not size.** A
  long file that is one such pass stays long, and its length wants a comment
  saying so. A long file that is several things sitting together is not
  protected by this rule and probably does have a seam. Either way, find the
  seam before you split.
- **A test that opens a file must not use a bare relative path.** The documented
  command runs from the workspace root, so `Directory.current` is the root, not
  the package — a path like `sample_data/x.json` then resolves to nothing. Locate
  the file relative to the package (the library's tests use
  `findWorkspaceRoot()` from `test/support/workspace.dart`). Golden paths are
  exempt: `matchesGoldenFile` resolves relative to the test file.
- **Per-package lockfiles are not committed** — only the root `pubspec.lock`.
- **Run `git` from the repo root.** `flutter` commands leave the shell inside a
  package directory.

## Going deeper

- [`docs/README.md`](docs/README.md) — the wiki: a six-page walk through the
  engine, with the designer chapters still to come. Start there when you need to
  understand a subsystem rather than look a rule up.
- [`docs/testing.md`](docs/testing.md) — the test taxonomy, golden discipline,
  tags, and the per-platform CI legs.
- [`docs/workflow.md`](docs/workflow.md) — how a change moves from idea to merge.
- [`README.md`](README.md) — user-facing quickstart.
- [`packages/jet_print/README.md`](packages/jet_print/README.md) — library
  quickstart and public API tour.
