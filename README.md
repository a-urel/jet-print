# jet-print

A monorepo for **`jet_print`** — a layered, theme-aware Flutter library for
building WYSIWYG report designers — and **`jet_print_playground`**, a macOS
desktop app that consumes the library exactly as an external consumer would.

`jet_print` provides a reified report model, a render/paginate engine, PDF/PNG
export and system printing, and an interactive shadcn-themed designer surface.
See [`packages/jet_print/README.md`](packages/jet_print/README.md) for the
library quickstart and public API.

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
└── apps/jet_print_playground/   # playground app (consumer; macOS desktop only)
    └── lib/*_sample.dart        # invoice, label, barcode, menu, nested-list,
                                  #   packing-slip, payroll samples
```

## Prerequisites

- Flutter **3.44.0+** / Dart **3.6.0+** (pub workspaces require Dart `^3.6.0`).
- macOS with desktop support: `flutter config --enable-macos-desktop`.
- Verify your toolchain with `flutter doctor`.

## Install

```bash
flutter pub get        # run from the repository root (single root lockfile)
```

## Run the playground app (macOS desktop only)

> The playground targets **macOS desktop** this iteration and fails fast with a
> clear message elsewhere. The `jet_print` library itself is platform-agnostic;
> cross-platform verification is tracked on the production-readiness roadmap.

```bash
cd apps/jet_print_playground && flutter run -d macos
```

The app shows the report designer with several worked samples (invoice, labels,
barcodes, menu, nested lists, packing slip, payroll) you can edit, preview,
export, and print.

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

## Consuming the library

```dart
import 'package:jet_print/jet_print.dart';

// The interactive designer, inside a ShadApp / ShadTheme shell:
const JetReportDesigner();

// Diagnostics:
print(jetPrintVersion);
```

Only the symbols exported from `package:jet_print/jet_print.dart` are public;
everything under `lib/src/` is private implementation detail (enforced by
`encapsulation_test.dart`).

## License

Apache-2.0 — see [LICENSE](LICENSE).
