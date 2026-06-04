# Implementation Plan: Flutter Library + Tester App Scaffold

**Branch**: `001-flutter-library-scaffold` | **Date**: 2026-06-05 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-flutter-library-scaffold/spec.md`

## Summary

Stand up the foundational monorepo for jet-print: a publishable Flutter widget library
(`jet_print`) and a separate tester app (`jet_print_tester`) that consumes it exactly as an
external consumer would, via **Dart pub workspaces** (one root lockfile). The library
exposes a deliberately minimal public API through a single entry point
(`lib/jet_print.dart`), hides all internals under `lib/src/`, and establishes three
independently testable layer seams (`domain`, `rendering`, `designer`) with an enforced
inward-dependency rule. Both projects integrate the community **`shadcn_ui`** package; the
tester app renders a theme-aware placeholder component inside a `ShadApp`/`ShadTheme` shell
with a working light/dark switch. A green, layered test suite plus strict static analysis
make the architecture "maintainable from day one." Placeholder content is acceptable this
iteration; rendering fidelity and serialization are deferred but their harnesses are seeded.

## Technical Context

**Language/Version**: Dart 3.12.0 / Flutter 3.44.0 (stable), sound null-safety
**Primary Dependencies**: Flutter SDK; `shadcn_ui` (nank1ro community package) for theming/components
**Storage**: N/A (no persistence/serialization this iteration; deferred per Constitution V)
**Testing**: `flutter test` (unit + widget); architecture test for layer boundaries; one golden test to seed the WYSIWYG harness
**Target Platform**: macOS desktop (tester app); library is platform-agnostic
**Project Type**: Dart pub workspace monorepo — reusable library + sample/tester desktop app
**Performance Goals**: N/A for scaffold (no rendering pipeline yet); clone-to-running ≤ 10 min (SC-002)
**Constraints**: Single public entry point; internals unreachable; inward-only layer deps verifiable by automated checks; zero analyzer errors; minimal/justified dependencies
**Scale/Scope**: 2 packages, 3 layer seams, 1 placeholder component, ~4 categories of tests; first iteration of a larger report-designer library

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | Library is a standalone workspace package with a single public entry point; internals under `src/`; tester app consumes only the public API (FR-001/002/003/011). |
| II | Layered & Extensible Architecture | ✅ PASS | Three seams as `src/` directories; inward dependency direction; cross-layer contact via the public surface; placeholders leave extension points open (FR-006/007). |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Tasks phase will write public-API, per-seam, widget, and architecture tests **before** implementation; clean checkout must be green (FR-008, US3). |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | 🟡 DEFERRED (not violated) | No real rendering exists yet. A single **golden test** on the placeholder is seeded so the WYSIWYG harness exists day one; full fidelity coverage arrives with real rendering. |
| V | Versioned & Backward-Compatible Serialization | 🟡 DEFERRED (not violated) | No serialized report model yet. A library **version baseline** and explicit dependency constraints are declared now (FR-012) so future SemVer/schema work has a starting line. |
| VI | Documentation & Developer Experience | ✅ PASS | Every public symbol gets dartdoc; runnable tester app + quickstart/README; `dart format` + strict `analysis_options` enforced (FR-009/010). |

**Initial gate**: PASS. No unjustified complexity — the two deferrals are scope decisions
the spec explicitly permits (placeholders acceptable), not principle violations, so the
Complexity Tracking table stays empty.

**Post-Design re-check**: PASS. The Phase 1 design (single entry point, `src/`-private
seams, architecture test, workspace resolution, golden-test seed, version constant)
introduces no new dependencies beyond `shadcn_ui` and no structural complexity beyond what
the constitution's layering mandates. No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/001-flutter-library-scaffold/
├── plan.md              # This file
├── research.md          # Phase 0 output (4 clarified decisions + enforcement choice)
├── data-model.md        # Phase 1 output (structural entities + layer seams)
├── quickstart.md        # Phase 1 output (clone → run → test)
├── contracts/
│   └── public-api.md     # Phase 1 output (the library's exported surface)
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
jet-print/                          # workspace root
├── pubspec.yaml                    # workspace: [packages/jet_print, apps/jet_print_tester]; sdk ^3.6.0
├── pubspec.lock                    # single shared lockfile (proves consumer-identical resolution)
├── analysis_options.yaml           # shared strict lints (zero-error gate)
├── README.md                       # contributor entry doc (Principle VI / FR-010)
├── packages/
│   └── jet_print/                  # THE LIBRARY (the product)
│       ├── pubspec.yaml            # resolution: workspace; version baseline; shadcn_ui constraint
│       ├── CHANGELOG.md            # seeded for future releases
│       ├── lib/
│       │   ├── jet_print.dart      # PUBLIC entry point — exports only
│       │   └── src/                # PRIVATE internals (never exported wholesale)
│       │       ├── domain/         # seam 1: report model (no UI/rendering imports)
│       │       ├── rendering/      # seam 2: layout/rendering (depends on domain only)
│       │       └── designer/       # seam 3: designer/UI (placeholder component lives here)
│       └── test/
│           ├── public_api_test.dart            # US1 / SC-001 / SC-007
│           ├── jet_print_placeholder_test.dart # widget render + golden (FR-004 / IV seed)
│           ├── architecture/
│           │   └── layer_boundaries_test.dart  # FR-007 / SC-005
│           ├── domain/                          # per-seam test (SC-004)
│           ├── rendering/                       # per-seam test (SC-004)
│           └── designer/                        # per-seam test (SC-004)
└── apps/
    └── jet_print_tester/           # TESTER APP (consumer; macOS desktop)
        ├── pubspec.yaml            # resolution: workspace; depends on jet_print + shadcn_ui
        ├── lib/
        │   └── main.dart           # ShadApp + light/dark toggle rendering the placeholder
        ├── macos/                  # macOS runner (target platform this iteration)
        └── test/
            └── app_consumes_library_test.dart  # US2 / FR-002
```

**Structure Decision**: Dart pub workspace monorepo. `packages/jet_print` is the publishable
library and the single source of truth for the product; `apps/jet_print_tester` is a
sibling consumer package. Both declare `resolution: workspace`; the root `pubspec.yaml`
enumerates them under `workspace:` and produces one `pubspec.lock`, so the tester resolves
the library identically to an external consumer (FR-006a). Layer seams are directories under
`packages/jet_print/lib/src/`, with the inward-dependency rule enforced by
`test/architecture/layer_boundaries_test.dart`.

## Complexity Tracking

> No entries — the Constitution Check passed with no unjustified violations. The two
> deferrals (WYSIWYG fidelity, serialization) are spec-sanctioned scope boundaries, not
> complexity introduced by this design.
