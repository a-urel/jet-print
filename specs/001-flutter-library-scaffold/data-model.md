# Phase 1 Data Model: Flutter Library + Tester App Scaffold

**Feature**: `001-flutter-library-scaffold`
**Date**: 2026-06-05

This is a scaffolding feature, so the "entities" are primarily *structural* (packages,
layers, the public surface) rather than serializable data records. They are drawn directly
from the spec's Key Entities and the constitution's layering principle.

## Structural Entities

### Widget Library Package (`jet_print`)

The reusable, publishable unit — the product.

| Attribute | Value / Rule |
|-----------|--------------|
| Location | `packages/jet_print/` |
| Public entry point | `lib/jet_print.dart` (only re-exports intentional symbols) |
| Private internals | `lib/src/**` (never exported wholesale) |
| Version | Declared in `pubspec.yaml` (initial baseline, e.g. `0.1.0`) |
| Dependency constraints | Flutter SDK + `shadcn_ui` declared with explicit ranges (FR-012) |
| Workspace role | Member: `resolution: workspace` |
| Self-containment | MUST NOT import tester-app or host-app code (FR-011) |

**Validation rules**: every symbol reachable from `lib/jet_print.dart` is intentional and
documented (FR-003, SC-007); nothing under `lib/src/` is exported except via the entry point.

### Public API Surface

The set of intentionally exported, documented symbols. Formalized in
[`contracts/public-api.md`](contracts/public-api.md).

| Attribute | Rule |
|-----------|------|
| Source | `lib/jet_print.dart` `export` directives only |
| Minimality | Deliberately minimal; one placeholder component for this iteration |
| Documentation | Every exported symbol carries dartdoc (Principle VI) |
| Stability | Future changes follow SemVer (Principle V) |

### Tester (Sample) Application (`jet_print_tester`)

A consumer of the library; keeps the public API honest.

| Attribute | Value / Rule |
|-----------|--------------|
| Location | `apps/jet_print_tester/` |
| Dependency on library | Via workspace resolution; imports `package:jet_print/jet_print.dart` only |
| Theming | Wraps app in `ShadApp` with `ShadThemeData`; supports a light/dark toggle |
| Target platform | macOS desktop (this iteration) |
| Prohibition | MUST NOT import `package:jet_print/src/...` and MUST NOT duplicate internals (FR-002) |

### Placeholder Component

The minimal example widget proving end-to-end consumption + theming.

| Attribute | Rule |
|-----------|------|
| Exported as | A single public widget from `lib/jet_print.dart` |
| Behavior | Builds and renders standalone (no tester-app dependency, FR-004) |
| Theme awareness | Reads `ShadTheme` so a theme switch visibly changes it (SC-006) |
| Tested by | A widget test asserting it builds/renders in isolation |

### Architecture Layer Seam

A defined, independently testable boundary with constrained inward dependency direction.

| Seam | Directory | First-iteration content | Dependency rule |
|------|-----------|-------------------------|-----------------|
| Domain / Report Model | `lib/src/domain/` | Placeholder type(s) | Depends on nothing inward; no Flutter UI/rendering imports |
| Rendering / Layout | `lib/src/rendering/` | Placeholder type(s) | May depend on Domain only |
| Designer / UI | `lib/src/designer/` | Placeholder component impl | May depend on Domain (and Rendering) |

**Dependency direction (FR-007)**: arrows point inward toward Domain.
`Designer → Rendering → Domain`. Domain imports neither of the other two. Verified by the
architecture test.

## State Transitions

Not applicable in this iteration — no serialized report model or runtime state machine yet.
Serialization (Constitution Principle V) is deferred; only a version baseline is established.

## Relationships (text diagram)

```text
workspace root (pubspec.yaml: workspace: [...], one pubspec.lock)
├── packages/jet_print  ──(public API: lib/jet_print.dart)──┐
│     └── lib/src/{domain ← rendering ← designer}           │ consumed via
└── apps/jet_print_tester ─────────────────────────────────┘ package:jet_print/jet_print.dart
        └── ShadApp / ShadTheme renders the Placeholder Component
```
