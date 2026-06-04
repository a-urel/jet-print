# Phase 0 Research: Flutter Library + Tester App Scaffold

**Feature**: `001-flutter-library-scaffold`
**Date**: 2026-06-05

All four open decisions raised during specification were resolved in the spec's
Clarifications session. This document records the rationale and the alternatives
considered so future contributors understand *why* the scaffold is shaped this way.

## Decision 1: Monorepo strategy — Dart pub workspaces

- **Decision**: Use built-in Dart **pub workspaces** (`resolution: workspace`). The
  repository root declares a `workspace:` list; the library and tester app are separate
  sibling packages that share a single root `pubspec.lock`.
- **Rationale**: Pub workspaces (stable since Dart 3.6; toolchain here is Dart 3.12.0)
  let the tester app depend on the library exactly as an external consumer would — through
  normal dependency resolution — while keeping one lockfile and one `pub get`. No
  third-party orchestration tooling is required, satisfying the constitution's
  "minimal, justified dependencies" standard.
- **Alternatives considered**:
  - **Melos**: mature monorepo tool, but adds a dependency and bootstrapping step the
    built-in workspace feature now makes unnecessary for a two-package repo. Rejected as
    avoidable complexity.
  - **Path dependencies without a workspace**: works, but produces per-package lockfiles
    and lets versions drift between packages; weaker guarantee that the tester consumes the
    same resolution a real consumer gets. Rejected.
  - **Separate repositories**: maximally consumer-honest but destroys the "one clone, run
    everything" developer experience the spec requires (SC-002). Rejected.

## Decision 2: Layer seams realized as internal directories

- **Decision**: Realize the domain, rendering, and designer/UI seams as directories under
  the library's private source area (`lib/src/domain`, `lib/src/rendering`,
  `lib/src/designer`), **not** as separate packages.
- **Rationale**: The constitution (Principle II) mandates layered separation and inward
  dependencies, but does not require physical package boundaries. Directory seams keep the
  scaffold simple while still being independently testable. The inward-dependency rule is
  enforced by an **architecture test** (see Decision 4).
- **Alternatives considered**:
  - **One package per layer**: stronger compile-time isolation, but heavy for a first
    iteration with placeholder contents; can be extracted later without breaking the public
    API since everything lives under `src/`. Rejected for now as premature.

## Decision 3: Tester app target platform — macOS desktop

- **Decision**: Target **macOS desktop** for this iteration; other platforms may be enabled
  later.
- **Rationale**: Fast native iteration on the development machine (Apple Silicon), no
  emulator/simulator overhead, and a single platform to document for the <10-minute
  clone-to-run goal (SC-002). The library itself stays platform-agnostic; only the tester
  app pins a platform.
- **Alternatives considered**:
  - **Web**: fast to run, but desktop better represents a print/report-design host.
  - **iOS/Android**: simulator/emulator setup adds friction to the first-run path. Deferred.

## Decision 4: shadcn UI implementation — `shadcn_ui` (nank1ro)

- **Decision**: Use the community **`shadcn_ui`** Flutter package, wiring the tester app
  through the `ShadApp` / `ShadThemeData` (`ShadTheme`) pipeline.
- **Rationale**: Named explicitly in the spec clarification. It provides themed components
  and a complete theming pipeline (light/dark color schemes) that lets the tester
  demonstrate a live theme switch on the placeholder component (SC-006). The library
  depends on it loosely so consumers can supply a compatible version.
- **Alternatives considered**:
  - **`shadcn_flutter`** (sunarya-thito): an alternative port (New York style). Capable,
    but not the package the stakeholders chose; using it would diverge from the spec.
    Rejected.
  - **Material/Cupertino only**: would not satisfy FR-005 (shadcn design system). Rejected.

## Decision 5: Layer-boundary enforcement mechanism — architecture test

- **Decision**: Enforce the inward-dependency rule (FR-007, SC-005) with a Dart **unit
  test** that scans source files under `lib/src/domain` and asserts none of them import
  `package:jet_print/src/rendering/...` or `package:jet_print/src/designer/...` (and that
  domain imports no Flutter widget/rendering libraries).
- **Rationale**: Zero additional dependencies, runs in the normal `flutter test` pass, and
  fails CI deterministically when a boundary is violated — exactly what SC-005 demands
  ("detected by automated checks rather than passing silently"). The spec allows
  "via tests or analysis".
- **Alternatives considered**:
  - **`custom_lint` / `import_lint` plugin**: gives editor-time feedback but adds a dev
    dependency and analyzer-plugin configuration. Can be layered on later; the test is
    sufficient and cheaper for the scaffold. Rejected for now.

## Toolchain baseline (verified)

- Flutter **3.44.0** (stable), Dart **3.12.0** — satisfies the `^3.6.0` floor required for
  pub workspaces.
- Testing: `flutter test` (widget + unit), with a golden test seeding the WYSIWYG harness
  for Principle IV even though no real rendering exists yet.

## Sources

- [Pub workspaces (monorepo support) — dart.dev](https://dart.dev/tools/pub/workspaces)
- [Announcing Dart 3.6 — The Dart Blog](https://dart.dev/blog/announcing-dart-3-6)
- [shadcn_ui | Flutter package — pub.dev](https://pub.dev/packages/shadcn_ui)
- [Flutter Shadcn UI docs — mariuti.com](https://flutter-shadcn-ui.mariuti.com/)
