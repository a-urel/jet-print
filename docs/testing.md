# Testing

406 test files: 377 in the library, 29 in the playground. They are the reason
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
| `test/architecture/` | 2 | Layer boundaries and third-party isolation, by scanning import directives. |
| `test/domain/` | 55 | The model, `validate()`, and serialization round-trips including lossless unknown types. |
| `test/expression/` | 30 | Lexer, parser, evaluator, functions, aggregates, formatting. |
| `test/data/` | 14 | Data sources, schemas, cursors, nested collections. |
| `test/rendering/` | 97 | Fill, layout, pagination, frames, painters, export, text metrics, crosstab. |
| `test/designer/` | 169 | Controller commands, undo/redo, canvas interaction, panels, inspectors, and designer goldens. |
| `test/print/` | 2 | The printer seam. |
| `test/goldens/` | 4 | The cross-cutting visual and byte-pinned goldens. |
| `test/web/` | 2 | Behavior that differs under CanvasKit. |
| `test/` (root) | 2 | `encapsulation_test.dart` and `public_api_test.dart`. |

### The two architecture tests

`layer_boundaries_test.dart` reads every file under `domain/`, `data/` and
`expression/`, extracts its `import`/`export` URIs, and fails if any reaches the
rendering or designer seams or a Flutter UI library. It also asserts each
directory *has* files, so an empty scan cannot produce a false green. It has since
grown past those three: it also pins the `rendering/` seam (no designer imports,
and `dart:ui` only in `paint/canvas_painter.dart`, `paint/page_rasterizer.dart`
and `engine/render_options.dart`), confines `package:printing` to `lib/src/print/`,
and checks what the public entry point exports.

It matches `import`/`export` directives by regex rather than raw substrings, so a
file may name a forbidden URI in a comment without failing.

`barcode_dependency_isolation_test.dart` guards `package:barcode` and does **not**
work that way. Its first assertion reads every `.dart` file under
`packages/jet_print/lib`, skips the one whose path ends
`package_barcode_encoder.dart`, and fails on any whose *text* contains
`package:barcode/` — a comment mentioning the package is a CI failure, not just an
import. Its second assertion scans `lib/src/domain` the same way, for
`package:barcode/` or the substring `rendering/elements/barcode`, which catches a
relative import of the adapter's directory as well as the vendor package.

Whether that strictness is deliberate or accidental has not been decided; the
behaviour above is what the test does today, and changing it is a change to a
passing CI gate.

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

Discipline, in order:

1. A golden moved. **Look at the failure image first** —
   `test/**/failures/` holds the diff, master and test images (git-ignored).
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
