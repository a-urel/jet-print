# Epic E3 — Desktop Matrix — Design

**Status:** approved (2026-06-20)
**Parent roadmap:** [2026-06-20-production-readiness-roadmap-design.md](./2026-06-20-production-readiness-roadmap-design.md)
**Predecessors:** E1 (release hygiene) and E2 (resilience/stress) — DONE, merged to `main`, pushed to `origin` at `396af82`.

## 1. Purpose & the embed-breadth gate

E3 makes the "supports Windows / Linux" claim *honest*. Today the engineering
core is platform-agnostic but only ever **built, tested, and rendered on
macOS** — the single dev platform and the only CI runner. E3 proves
`jet_print` compiles, tests green, and links its native plugins on all three
desktop OSes, so the program can truthfully say "desktop: macOS / Windows /
Linux" for the embed target and for the eventual pub.dev `1.0` (E6).

This is **infrastructure + platform hardening**, not a feature. No engine,
domain, or rendering behavior changes. The public API surface is untouched.

## 2. Scope (settled by four decisions)

1. **Depth = test + build the app** on all three OSes. Running the full test
   suite proves the Dart/widget layer; **building the playground app**
   (`flutter build {linux,windows,macos}`) proves the native plugin
   toolchain (`printing` / `pdf` / `file_selector` CMake) actually links
   per-platform. This is the honest "supports X" bar. *(Not chosen: test-only
   — too weak; test+build+integration-smoke-run — heaviest, deferred.)*
2. **Golden strategy = gate to macOS canonical.** Cross-OS font rasterization
   (CoreText vs FreeType vs DirectWrite) exceeds the existing 0.5% tolerance,
   so the committed goldens run **only on macOS** (their baseline host); build
   and all non-golden tests run on all three. **Zero re-baselining.**
3. **Validation = GitHub Actions matrix.** The dev host is macOS-only, so the
   Windows/Linux proof can only come from Actions. `main` is already on
   `origin`, so a pushed branch / PR yields real per-OS results.
4. **Fix posture = absorb inline (option a).** E3 is "matrix + whatever fixes
   make it green." A matrix that is not green proves nothing; genuine
   cross-platform fixes surfaced by the first runs are part of E3, not logged
   follow-ups.

### Out of scope (explicitly)

- **Web / mobile** — E4 / E5 (the playground guard keeps failing clearly there).
- **Packaging / signing / distribution / installers** — E7.
- **Per-platform golden baselines** (3× PNG sets) — rejected for maintenance cost.
- **Integration-driver smoke run** (launch-and-render on each OS) — deferred;
  `flutter build` already proves native linkage.
- **pub.dev publish, CHANGELOG `1.0`, dartdoc** — E6 capstone.

## 3. Grounding — what exists today

- **CI:** [.github/workflows/ci.yml](../../../.github/workflows/ci.yml) — a single
  `macos-latest` job: checkout → Flutter `3.44.0` → `flutter pub get` →
  `dart format --set-exit-if-changed` → `flutter analyze` →
  `flutter test packages/jet_print apps/jet_print_playground`.
- **Goldens:** 69 committed PNGs under three `goldens/` dirs +
  one byte-pinned `test/goldens/invoice.pdf`. A tolerant comparator
  ([flutter_test_config.dart](../../../packages/jet_print/test/flutter_test_config.dart),
  0.5%) absorbs macOS-dev → macOS-CI sub-pixel AA noise — **not** cross-OS deltas.
- **Playground:** only a `macos/` runner dir exists; `main()` hard-throws
  `UnsupportedError` off macOS
  ([main.dart:34](../../../apps/jet_print_playground/lib/main.dart#L34)).
- **Platform-sensitive library code (no change needed):**
  - FFI diagonal-cursor bridge selected via `if (dart.library.io)`
    (compiles on Win/Linux) but short-circuits on `!Platform.isMacOS`
    *before* any Objective-C lookup → safe no-op off macOS.
  - `printing` is isolated behind a swappable seam; bundled fonts (not system
    fonts) drive rendering, so render output is host-font-independent.

## 4. The matrix design

Evolve `ci.yml` from one job into a **3-OS matrix**
(`ubuntu-latest`, `windows-latest`, `macos-latest`), same pinned Flutter
`3.44.0`, same triggers (`push: [main]`, `pull_request`). Each job runs the
same spine with three small per-OS variations:

| Step | ubuntu | windows | macos (canonical) |
|------|--------|---------|-------------------|
| Native build deps | `apt-get` GTK/clang/cmake/ninja/pkg-config + CUPS | VS preinstalled | Xcode preinstalled |
| `flutter pub get` | ✓ | ✓ | ✓ |
| `flutter analyze` | ✓ | ✓ | ✓ |
| `dart format --set-exit-if-changed` | — | — | ✓ (once) |
| Build playground | `flutter build linux --debug` | `flutter build windows --debug` | `flutter build macos --debug` |
| Test | `flutter test --exclude-tags golden …` | `--exclude-tags golden …` | full suite (incl. goldens) |

**Rationale for the per-OS choices:**
- **Format check once, on macOS.** `dart format` is platform-independent;
  running it once avoids any Windows CRLF-vs-LF false failure and saves CI
  minutes. The `.gitattributes` LF rule (§7) is the belt to that suspenders.
- **`--debug` build.** We need the native toolchain to *compile + link*, not a
  release artifact. Debug is much faster.
- **Analyze on all three.** Cheap, and the conditional-import files
  (`_io` / `_stub`) are worth analyzing under each host's library resolution.

## 5. Golden gating (macOS canonical)

The **golden surface** is broader than the `matchesGoldenFile` matcher: it
includes the byte-pinned `invoice.pdf` comparison in `pdf_determinism_test.dart`
(raw `expect(bytes, golden.readAsBytesSync())`), whose PDF bytes embed
subsetted font glyphs + zlib output and therefore differ across platforms.

Tag the golden surface with the `golden` tag and exclude it off-canonical:

- **`dart_test.yaml`** (new, in `packages/jet_print/`) declares the `golden`
  tag so `--exclude-tags golden` raises no "unknown tag" warning.
- **Pure-golden files → file-level `@Tags(['golden'])`** (every test case in the
  file is a golden): `bound_token_render_test`, `design_surface_grid_test`,
  `shape_forms_test`, `data_aware_invoice_test`,
  `jet_report_designer_light_dark_test`, `design_surface_test`,
  `barcode_symbologies_golden_test`, `canvas_painter_golden_test`,
  `rendered_invoice_test`, `label_sheet_test`, `formatted_value_test`.
- **Mixed files → test/group-level tags on only the golden case(s)**, so the
  platform-independent cases keep running on all three OSes:
  - `page_letter_landscape_test` — 3 cases, 2 goldens (1 non-golden stays).
  - `png_export_test` — 8 cases, 1 `matchesGoldenFile` golden (7
    dimension/exception/byte-self-consistency cases stay).
  - `pdf_determinism_test` — 4 cases; **only** the "matches the pinned golden
    invoice.pdf" case is tagged. The three export-twice-identical
    self-consistency cases are valuable cross-platform determinism checks and
    **must keep running everywhere**.

The exact tag granularity per file is re-verified during planning (audit each
listed file's cases). The tolerant comparator
([flutter_test_config.dart](../../../packages/jet_print/test/flutter_test_config.dart))
is unchanged — it now only ever executes on macOS.

## 6. Playground cross-platform

- **Generate runner dirs:** run `flutter create --platforms=windows,linux .`
  in `apps/jet_print_playground` to scaffold `windows/` + `linux/` CMake
  runners. It does not touch `lib/`, `macos/`, or `pubspec.yaml`. This is
  runnable on the macOS dev host (it only writes scaffolding) and committed.
- **Relax the guard:** [main.dart](../../../apps/jet_print_playground/lib/main.dart#L34)
  changes from "macOS, else throw" to "one of the three desktop OSes, else
  throw" — preserving a clear, intentional failure for the not-yet-supported
  web/mobile targets (E4 / E5).

No other library or app source changes are anticipated; any that the matrix
forces are §8 platform fixes.

## 7. Cross-platform hygiene

A minimal, scoped **`.gitattributes`** (new, repo root):

```
*.dart text eol=lf
*.png  binary
*.pdf  binary
```

Forces LF for Dart sources (so a Windows checkout cannot break the `dart
format` gate) and marks the golden PNG/PDF artifacts binary (so EOL conversion
can never corrupt a baseline). Narrow on purpose — no mass renormalization.

The ubuntu job installs the standard Flutter-Linux-desktop build deps plus the
`printing` plugin's CUPS dependency before building:
`clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libcups2-dev`.

## 8. Execution model — two phases

E3 differs from E1/E2: **the Windows/Linux result cannot be verified on the
macOS dev host.** Execution is therefore explicitly two-phase.

- **Phase A — infrastructure (locally verifiable).** The matrix workflow,
  golden tags + `dart_test.yaml`, generated runner dirs, relaxed guard, and
  `.gitattributes`. Built correct-by-construction and proven on macOS locally:
  the full suite (incl. goldens) stays green and `flutter build macos --debug`
  succeeds. This phase is suitable for subagent-driven development.
- **Phase B — matrix-to-green (CI feedback loop).** Push the branch / open a
  PR → read the real Windows/Linux/macOS results from Actions → fix what they
  surface (path assumptions, font availability, native link flags, plugin
  build deps) → re-push until all three jobs are green. This loop is
  inherently iterative and driven against Actions; it cannot be fully
  pre-planned. Per decision (a), these fixes are absorbed into E3.

## 9. Functional requirements

- **FR-E3-001** — `ci.yml` runs a matrix over
  `{ubuntu-latest, windows-latest, macos-latest}`, Flutter `3.44.0` pinned,
  on `push: [main]` and `pull_request`.
- **FR-E3-002** — every OS job runs, in order: `flutter pub get` →
  `flutter analyze` → build the playground (`flutter build <os> --debug`) →
  `flutter test`.
- **FR-E3-003** — macOS is canonical: it runs the **full** test suite
  (including the golden surface) and the `dart format --set-exit-if-changed`
  gate.
- **FR-E3-004** — ubuntu and windows run `flutter test --exclude-tags golden`
  over `packages/jet_print apps/jet_print_playground`.
- **FR-E3-005** — the entire golden surface is tagged `golden`: all
  `matchesGoldenFile` tests **and** the byte-pinned `invoice.pdf` comparison.
  Pure-golden files tagged file-level; the three mixed files tagged
  test/group-level so their platform-independent cases still run on all OSes.
- **FR-E3-006** — `packages/jet_print/dart_test.yaml` declares the `golden`
  tag (no unknown-tag warnings under `--exclude-tags`).
- **FR-E3-007** — `apps/jet_print_playground` gains committed `windows/` and
  `linux/` runner directories; `lib/`, `macos/`, and `pubspec.yaml` unchanged.
- **FR-E3-008** — the playground `main()` guard permits macOS, Windows, and
  Linux, and throws `UnsupportedError` on any other target.
- **FR-E3-009** — a repo-root `.gitattributes` enforces `eol=lf` for `*.dart`
  and `binary` for `*.png` / `*.pdf`.
- **FR-E3-010** — the ubuntu job installs
  `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libcups2-dev`
  before building.
- **FR-E3-011** — genuine cross-platform failures surfaced by the matrix are
  fixed inline until all three jobs pass (scope decision a).

## 10. Success criteria

- **SC-E3-001** — macOS job green: full suite (incl. goldens) + format gate +
  `flutter build macos`. *(Verified locally before push.)*
- **SC-E3-002** — ubuntu job green: analyze + non-golden suite +
  `flutter build linux`. *(Actions.)*
- **SC-E3-003** — windows job green: analyze + non-golden suite +
  `flutter build windows`. *(Actions.)*
- **SC-E3-004** — no golden (PNG or the pinned PDF) ever runs off-canonical;
  no cross-OS rasterization/byte failure appears in any non-macOS job.
- **SC-E3-005** — zero golden re-baselining; the 69 PNGs and `invoice.pdf` are
  byte-identical to their pre-E3 state.
- **SC-E3-006** — the only `lib/`-or-app source changes are the playground
  guard and generated runner dirs (plus any §8 platform fixes); **no engine,
  domain, or rendering change; no public-API change.**

## 11. Risks & mitigations

- **Linux native link of `printing` (CUPS).** Mitigated by the apt step
  (FR-E3-010). If the plugin needs more, absorbed per (a).
- **Windows/Linux test assumptions** (hardcoded paths, separators, font
  availability). The library uses bundled fonts and no hardcoded paths in
  `lib/`, lowering this; any surfaced failure is fixed inline.
- **Phase B requires push to Actions.** Accepted — it is the only way to prove
  the non-macOS targets; `main` is already on `origin`.
- **CRLF breaking the format gate on Windows.** Mitigated two ways: format
  runs only on macOS, and `.gitattributes` forces LF on `*.dart`.
- **Runner image drift** (`*-latest` moving). Acceptable for a quality gate;
  Flutter is version-pinned, which is the dimension that matters for goldens.
