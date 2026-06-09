# jet-print

A monorepo for **`jet_print`** — a layered, theme-aware Flutter widget library for
building WYSIWYG report designers — and **`jet_print_playground`**, a macOS desktop app
that consumes the library exactly as an external consumer would.

This is the foundational scaffold: a minimal but real public API, three internal
layer seams with an enforced inward-dependency rule, shadcn theming, and a green,
layered test suite (including a golden test that seeds the WYSIWYG harness).

## Layout

```text
jet-print/
├── pubspec.yaml                 # Dart pub workspace root → one pubspec.lock
├── analysis_options.yaml        # shared strict lints (zero-warning gate)
├── packages/jet_print/          # the library (the product)
│   ├── lib/jet_print.dart       # the single PUBLIC entry point (exports only)
│   └── lib/src/                  # PRIVATE internals
│       ├── domain/              # report model — pure Dart, no UI
│       ├── rendering/           # layout — depends on domain only
│       └── designer/            # UI — the placeholder component lives here
└── apps/jet_print_playground/       # playground app (consumer; macOS desktop only)
    └── lib/main.dart            # ShadApp + light/dark toggle rendering the placeholder
```

## Prerequisites

- Flutter **3.44.0+** / Dart **3.12.0+** (pub workspaces require Dart `^3.6.0`).
- macOS with desktop support enabled: `flutter config --enable-macos-desktop`.
- Verify your toolchain with `flutter doctor`.

## Install

The whole workspace resolves through a single root lockfile:

```bash
flutter pub get        # run from the repository root
```

## Run the playground app (macOS desktop only)

> **Platform note:** the playground app targets **macOS desktop only** this iteration.
> It fails fast with a clear message on other platforms. The `jet_print` library
> itself is platform-agnostic.

```bash
flutter run -d macos --directory apps/jet_print_playground
# or:  cd apps/jet_print_playground && flutter run -d macos
```

You should see `JetPrintPlaceholder` rendered inside a `ShadApp` shell. Use the
in-app toggle to switch light/dark and watch the placeholder change appearance —
this proves the shadcn theming pipeline is live.

## Test & quality gate

Run from the repository root. These three commands mirror CI exactly:

```bash
dart format --output=none --set-exit-if-changed .                 # formatting is clean
flutter analyze                                                     # zero analyzer warnings
flutter test packages/jet_print apps/jet_print_playground              # all tests pass
```

> **Why the explicit paths?** `flutter analyze` fans out across all workspace
> members automatically, but `flutter test` run at the workspace root only looks
> at the root package — so the member packages are listed explicitly.

A clean checkout MUST show: formatting clean, analyzer zero warnings, all tests
green.

### What the tests prove

| Test | Proves |
|------|--------|
| `public_api_test.dart` | The library is consumable through `package:jet_print/jet_print.dart` alone |
| `encapsulation_test.dart` | No external consumer reaches into `lib/src/`; the library depends on no host/app code |
| `domain/` · `rendering/` · `designer/` | Each layer seam is independently testable |
| `architecture/layer_boundaries_test.dart` | The inward-dependency rule is enforced, not aspirational |
| `jet_print_placeholder_test.dart` | The placeholder renders and matches its golden image |

## Consuming the library

```dart
import 'package:jet_print/jet_print.dart';

// Inside a ShadApp / ShadTheme shell:
const JetPrintPlaceholder();

// Diagnostics:
print(jetPrintVersion); // 0.1.0
```

Only the symbols exported from `package:jet_print/jet_print.dart` are public. The
authoritative contract lives in
[`specs/001-flutter-library-scaffold/contracts/public-api.md`](specs/001-flutter-library-scaffold/contracts/public-api.md).
