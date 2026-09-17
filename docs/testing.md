# Testing

Roughly 420 test files: ~390 in the library, ~30 in the playground. The counts here are approximate on purpose — see AGENTS.md; an exact figure is wrong as soon as the next file lands and nothing fails when it does. They are the reason
the rules in [`../AGENTS.md`](../AGENTS.md) are enforceable rather than
aspirational.

## Running them

```bash
flutter test packages/jet_print apps/jet_print_playground     # everything
flutter test packages/jet_print/test/rendering                # one seam
flutter test packages/jet_print/test/goldens/rendered_invoice_test.dart
flutter test --exclude-tags golden packages/jet_print         # what non-macOS CI runs
```

Name the member packages. `flutter test` at a workspace root only looks at the
root package, so the bare command passes while testing nothing.

## The taxonomy

| Directory | Files | What it proves |
|---|---:|---|
| `test/architecture/` | 4 | Whole-repo invariants: layer boundaries, third-party isolation, built-in element registration parity, and single-site painter construction. Mostly by scanning import directives; the registration guard compares registries at runtime. |
| `test/domain/` | ~55 | The model, `validate()`, and serialization round-trips including lossless unknown types. |
| `test/expression/` | ~30 | Lexer, parser, evaluator, functions, aggregates, formatting. |
| `test/data/` | ~15 | Data sources, schemas, cursors, nested collections. |
| `test/rendering/` | ~100 | Fill, layout, pagination, frames, painters, export, text metrics, crosstab. |
| `test/designer/` | ~175 | Controller commands, undo/redo, canvas interaction, panels, inspectors, and designer goldens. |
| `test/print/` | 2 | The printer seam. |
| `test/goldens/` | 4 | The cross-cutting visual and byte-pinned goldens. |
| `test/web/` | 2 | Behavior that differs under CanvasKit. |
| `test/` (root) | 2 | `encapsulation_test.dart` and `public_api_test.dart`. |

### The two architecture tests

`layer_boundaries_test.dart` reads every file under `domain/`, `data/` and
`expression/`, extracts its `import`/`export` URIs, and fails if any reaches the
rendering or designer seams or a Flutter UI library. It also asserts each
directory *has* files, so an empty scan cannot produce a false green.

`barcode_dependency_isolation_test.dart` does the same for `package:barcode`,
allowing exactly one adapter file.

Both match directives rather than raw substrings, which is why they can safely
contain the very strings they forbid.

### The two consumer tests

`public_api_test.dart` acts as an external consumer — it imports only the public
entry point and builds, mutates, validates, serializes and renders a report
through it. That is the proof the public surface is *sufficient*.

`encapsulation_test.dart` guards the other direction: no library file imports the
playground, and no file outside the allowlist reaches into
`package:jet_print/src/...`.

The allowlist matters, because it is not a short one. White-box seam tests
legitimately exercise unexported types in isolation, so these are permitted
wholesale — `test/domain`, `test/data`, `test/expression`, `test/rendering`,
`test/print`, `test/web`, `test/designer/template` — plus a long list of
individually named designer tests, each with a comment explaining why that
particular helper is unexported and unit-tested directly. Everything else is
default-deny, and **the playground app is never exempt**.

So the rule is not "tests are black-box". It is: the inner seams are tested
white-box by design; the designer's *widget* tests use the public API unless a
named exception says otherwise. Adding an exception means adding an entry and a
reason — an unexplained entry erodes the only record of what is deliberate.

## Goldens

Goldens are visual PNG comparisons plus one byte-pinned `invoice.pdf`. They are
tagged `golden` in `dart_test.yaml` and run **only on macOS**, because host font
rasterization and PDF font subsetting differ per OS. Other CI legs pass
`--exclude-tags golden`.

**A passing golden is not a byte-identical one.** `test/support/golden_config_io.dart`
installs a tolerant comparator: it accepts any image whose `diffPercent` is at
most `0.005`, i.e. half a percent of pixels may differ. That is deliberate — host
rasterization wobbles — but it means "goldens green" says *no visible change*,
not *no change*, and a claim of byte-identical output needs a different check.
The one genuinely byte-pinned artifact is `invoice.pdf`, compared as bytes in
`test/rendering/export/pdf_determinism_test.dart`.

That tolerance has a consequence worth knowing before you trust a `failures/`
directory: **a fully passing run can still write a complete set of failure
images.** Reproduced by deleting every `failures/` directory, then running
`test/rendering/export/png_export_test.dart` alone: "All tests passed!", and four
`invoice_page1_2x_*` images appear. The comparison detects a real difference, the
tolerance lets it pass, and the artifacts are written regardless — which call
writes them is not established. So images in `failures/` do not mean a golden
moved. Check the run's exit status, not the directory.

Discipline, in order:

1. A golden moved — confirmed by a failing run, not by files in `failures/`.
   **Look at the failure image first** — `test/**/failures/` holds the diff,
   master and test images (git-ignored).
2. Name what changed and why. "The toolbar gained a button, so the top bar's
   measured width shifted" is an explanation. "Rendering changed slightly" is not.
3. Only then regenerate, on macOS, and say in the change description which
   goldens moved.

A golden that shifts for a reason you cannot articulate is an undiscovered bug,
not noise. Regenerating to get green is how a WYSIWYG tool starts lying.

Two recurring causes worth recognizing: adding or removing chrome widgets drifts
the Skia glyph cache and can move canvas goldens that have nothing to do with
your change; and non-English locales are wider — German binds toolbar width, so
a locale test needs its own isolate per locale.

## Support helpers

`test/support/` — use these rather than hand-rolling:

- `report_builders.dart` — builds report fixtures.
- `workspace.dart` — `findWorkspaceRoot()`, for tests that scan the tree.
- `test_fonts.dart`, `fixture_font_data.dart` — deterministic fonts, so text
  metrics don't depend on the host.
- `golden_config_io.dart` / `golden_config_web.dart` — per-platform golden setup.

Fixtures live in `test/fixtures/`.

Two habits that have caught real bugs: build fixtures that *force divergence*
rather than ones where the right and wrong answers coincide (const
canonicalization and associative aggregates both hide errors this way), and when
a test involves image decoding, remember it needs `runAsync`.

## CI

`.github/workflows/ci.yml`, five legs:

| Leg | Runs |
|---|---|
| macOS (**canonical**) | format check, analyze, build, **full suite including goldens** |
| Ubuntu | analyze, build, suite minus goldens |
| Windows | analyze, build, suite minus goldens |
| web (chrome) | build, suite minus goldens — **per package**, because the repo-root multi-package `--platform chrome` command fails on DDC workspace path resolution |
| android / ios | build only |

Every leg builds the playground app, which is what proves the native plugin
toolchain still links on that OS.
