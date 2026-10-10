# jet-print

[![pub package](https://img.shields.io/pub/v/jet_print.svg)](https://pub.dev/packages/jet_print)
[![CI](https://github.com/a-urel/jet-print/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/a-urel/jet-print/actions/workflows/ci.yml)

**`jet_print`** is a Flutter library for building WYSIWYG report designers: a
report model, a paginating render engine, PDF/PNG export, printing, and an
embeddable, shadcn-themed visual designer. It is published on
[pub.dev](https://pub.dev/packages/jet_print):

```sh
flutter pub add jet_print
```

To use it, start with the package README,
[`packages/jet_print/README.md`](packages/jet_print/README.md): the quickstart,
hosting the designer, saving designs, binding data, and what a host can extend.

This repository is the library's monorepo. It also holds
**`jet_print_playground`**, a desktop, web and mobile app that consumes the
library exactly as an external consumer would. The rest of this page is for
working on the repository itself.

## Layout

```text
jet-print/
├── pubspec.yaml                 # Dart pub workspace root → one pubspec.lock
├── analysis_options.yaml        # shared strict lints (zero-warning gate)
├── LICENSE                      # Apache-2.0
├── packages/jet_print/          # the library (the product)
│   ├── lib/jet_print.dart       # the single PUBLIC entry point (exports only)
│   └── lib/src/                  # PRIVATE internals (domain · expression · data
│                                 #   · rendering · designer · print)
└── apps/jet_print_playground/   # playground app (consumer; desktop · web · mobile)
    └── lib/*_sample.dart        # twelve worked samples: invoice, labels,
                                  #   barcodes, charts, pivot, ledger, payroll, …
```

## Prerequisites

- Flutter **3.44.0+** / Dart **3.6.0+** (pub workspaces require Dart `^3.6.0`).
- Enable the desktop target you build for (e.g. `flutter config
  --enable-macos-desktop`); web and mobile need no extra flag.
- Verify your toolchain with `flutter doctor`.

## Set up the workspace

```bash
flutter pub get        # run from the repository root (single root lockfile)
```

## Run the playground app

> The playground runs on macOS, Windows, Linux, web, and iOS/Android. CI builds
> every target on each push; macOS, Windows, Linux and Chrome also run the test
> suite, while Android and iOS are build-only (see [testing](docs/testing.md)).
> macOS is the canonical platform: it alone runs the golden/WYSIWYG surface,
> since host rasterization differs per OS.

```bash
cd apps/jet_print_playground && flutter run -d macos    # or: -d chrome, windows, linux, …
```

The app shows the report designer with twelve worked samples (invoice, labels,
barcodes, charts, a pivot table, a ledger, payroll, a menu, nested lists, a
packing slip, …) you can edit, preview, export, and print.

## Test & quality gate

Run from the repository root. These three commands mirror CI exactly:

```bash
dart format --output=none --set-exit-if-changed .                 # formatting is clean
flutter analyze                                                    # zero analyzer warnings
flutter test packages/jet_print apps/jet_print_playground          # all tests pass
```

> **Why the explicit paths?** `flutter analyze` fans out across all workspace
> members automatically, but `flutter test` at the workspace root only looks at
> the root package — so the member packages are listed explicitly.

A clean checkout MUST show: formatting clean, analyzer zero warnings, all tests
green.

## Working on this repo

[`AGENTS.md`](AGENTS.md) is the guide for contributors and AI coding agents: the
rules that hold the design together, which test enforces each one, a map of the
layers, and the traps worth knowing before your first edit. It links deeper
notes in [`docs/`](docs/) — [the wiki](docs/README.md),
[testing](docs/testing.md), [workflow](docs/workflow.md).

## Consuming the library

Add it with `flutter pub add jet_print` and import one library:

```dart
import 'package:jet_print/jet_print.dart';
```

The [package README](packages/jet_print/README.md) has the quickstart; its code
is copied from `packages/jet_print/example/`, which CI compiles and runs.
Only the symbols exported from `package:jet_print/jet_print.dart` are public;
everything under `lib/src/` is private implementation detail (enforced by
`encapsulation_test.dart`).

## License

Apache-2.0 — see [LICENSE](LICENSE).
