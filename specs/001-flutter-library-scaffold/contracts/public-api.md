# Public API Contract: `jet_print` library

**Feature**: `001-flutter-library-scaffold`
**Date**: 2026-06-05

For a Flutter/Dart library the "interface contract" is the set of symbols re-exported from
its single public entry point. This document is the authoritative description of that
surface for the scaffold iteration. The playground app and any future consumer MUST rely only
on what is listed here.

## Entry point

```dart
import 'package:jet_print/jet_print.dart';
```

There is exactly **one** public entry point. Importing any `package:jet_print/src/...` path
is a contract violation and is what the consumption tests guard against.

## Exported symbols (this iteration)

| Symbol | Kind | Purpose | Stability |
|--------|------|---------|-----------|
| `JetPrintPlaceholder` | `Widget` | The placeholder component a consumer renders to prove end-to-end consumption and theming. Reads `ShadTheme` so it reflects the active shadcn theme. | Experimental (0.x) |
| `jetPrintVersion` | `const String` | The library's declared version string, exposed for diagnostics; establishes the SemVer baseline. | Experimental (0.x) |

> The exact symbol names are the contract intent; implementation may refine names during
> Phase 2, but the *shape* (one renderable, theme-aware placeholder widget + a version
> constant, nothing reaching into `src/`) is fixed.

### `JetPrintPlaceholder` contract

- MUST be a `const`-constructible `StatelessWidget` (or equivalent) that builds without any
  ancestor beyond a standard `ShadApp`/`MaterialApp` shell.
- MUST NOT require host-application state, global singletons, or playground-app code.
- MUST visibly change appearance when the surrounding `ShadTheme` changes (e.g. light/dark),
  satisfying SC-006.
- MUST carry dartdoc describing purpose and usage (Principle VI).

## Non-goals (explicitly NOT in the public surface)

- No domain/report-model types are exported yet (`lib/src/domain` stays private).
- No rendering or designer types are exported yet.
- No serialization API yet (deferred; Constitution Principle V).

## Contract tests (Phase 1 → enforced in Phase 2)

These tests assert the contract above and MUST be written test-first (Principle III):

1. **Public-API import test**: a test that imports *only*
   `package:jet_print/jet_print.dart` and references `JetPrintPlaceholder` +
   `jetPrintVersion`, proving the surface is sufficient (US1 / SC-001).
2. **Encapsulation test**: a test/grep assertion that no consumer file (playground app +
   library tests acting as consumer) imports a `package:jet_print/src/` path (SC-007).
3. **Placeholder widget test**: pumps `JetPrintPlaceholder` standalone and asserts it
   renders (FR-004 / US3).
4. **Architecture (layer-boundary) test**: scans `lib/src/domain/**` and asserts no inward
   violations — domain importing rendering/designer or Flutter UI (FR-007 / SC-005).
