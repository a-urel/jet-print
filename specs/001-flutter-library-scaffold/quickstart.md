# Quickstart: jet-print scaffold

**Feature**: `001-flutter-library-scaffold`
**Goal**: From a fresh clone to a running, shadcn-themed playground app and a green test suite —
in under 10 minutes (SC-002).

## Prerequisites

- Flutter **3.44.0+** / Dart **3.12.0+** (pub workspaces require Dart `^3.6.0`).
- macOS with desktop support enabled (`flutter config --enable-macos-desktop`).
- Verify with: `flutter doctor`.

## 1. Clone and resolve (one lockfile for the whole workspace)

```bash
git clone <repo-url> jet-print
cd jet-print
flutter pub get        # resolves every workspace member into one root pubspec.lock
```

## 2. Run the playground app (macOS desktop)

```bash
cd apps/jet_print_playground
flutter run -d macos
```

You should see the `JetPrintPlaceholder` component rendered inside a `ShadApp` shell.
Use the in-app theme toggle to switch light/dark and watch the placeholder change
appearance — this proves the shadcn theming pipeline is live (SC-006).

## 3. Run the full check suite

From the repo root:

```bash
dart format --output=none --set-exit-if-changed .   # formatting gate
flutter analyze                                       # static analysis, zero errors (FR-009)
flutter test                                          # all tests pass (FR-008)
```

A clean checkout MUST show: formatting clean, analyzer zero errors, all tests green
(SC-003).

## What the tests prove

| Test | Proves |
|------|--------|
| Public-API import test | The library is consumable through `package:jet_print/jet_print.dart` alone (US1/SC-001) |
| Encapsulation test | No consumer reaches into `lib/src/` (SC-007) |
| Placeholder widget test | The placeholder renders standalone (FR-004) |
| Per-seam tests (domain / rendering / designer) | Each layer seam is independently testable (SC-004) |
| Architecture (layer-boundary) test | Inward-dependency rule is enforced, not aspirational (SC-005) |

## Project layout (where things live)

```text
jet-print/
├── pubspec.yaml                 # workspace root: workspace: [packages/jet_print, apps/jet_print_playground]
├── analysis_options.yaml        # shared strict lints
├── packages/jet_print/          # the library (the product)
│   ├── lib/jet_print.dart       # PUBLIC entry point (exports only)
│   ├── lib/src/domain/          # domain seam (no UI/rendering imports)
│   ├── lib/src/rendering/       # rendering seam (depends on domain only)
│   ├── lib/src/designer/        # designer/UI seam (placeholder component lives here)
│   └── test/                    # public-api, per-seam, architecture, widget tests
└── apps/jet_print_playground/       # playground app (consumer; macOS desktop)
    └── lib/main.dart            # ShadApp + theme toggle rendering the placeholder
```

## Troubleshooting

- **`flutter run` can't find a macOS device**: run `flutter config --enable-macos-desktop`
  then `flutter create --platforms=macos .` inside the playground app if the `macos/` runner is
  missing.
- **Version solving failed**: ensure every package's `pubspec.yaml` has `resolution: workspace`
  and an SDK constraint of `^3.6.0` or higher, and that the root lists each member under
  `workspace:`.
