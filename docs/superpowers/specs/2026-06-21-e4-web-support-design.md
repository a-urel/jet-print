# Epic E4 — Web Support — Design

**Status:** approved (2026-06-21)
**Parent roadmap:** [2026-06-20-production-readiness-roadmap-design.md](./2026-06-20-production-readiness-roadmap-design.md)
**Predecessors:** E1 (release hygiene), E2 (resilience/stress), E3 (desktop
matrix Phase A) — all DONE and merged to `main`.

## 1. Purpose & the local-verifiability advantage

E4 makes the "supports Flutter web" claim honest: the library compiles to web,
renders correctly under CanvasKit, exports PDF/PNG, and prints via the browser.
The roadmap rates this **L / High risk** with the `printing` plugin's web
behavior as the chief unknown.

The decisive enabler: **Chrome is installed and `flutter` lists a web device**,
so every E4 check runs locally on the dev Mac — `flutter build web`,
`flutter test --platform chrome`, and `flutter run -d chrome` for manual smoke.
**E4 has no dependency on GitHub Actions** (which is currently billing-locked,
see [[spec-e3-desktop-matrix-status]]). This is single-phase work, fully
verifiable here.

This is **verify + harden**, not a port. The library's headless-rendering-engine
+ conditional-FFI + swappable-print-seam architecture already anticipated web.

## 2. Scope (settled by four decisions)

1. **Depth = verify + harden + smoke.** Confirm the library builds for web,
   make the playground web-buildable, verify runtime in Chrome (designer canvas
   renders; PNG + PDF export work; fonts load; print works), and harden whatever
   breaks. *(Not: compile-only — too weak; full web-functional playground —
   heavier, deferred.)*
2. **Print on web = use the browser print dialog.** Wire the existing seam to
   `printing`'s web impl (`Printing.layoutPdf` → browser print via pdf.js).
   Verify and document the web semantics; no seam redesign.
3. **Goldens on web = gate them off** (CanvasKit rasterizes differently from
   desktop; the macOS goldens won't match). The web leg runs
   `flutter test --platform chrome --exclude-tags golden` + `flutter build web`.
   **Zero re-baselining.**
4. **VM-only test audit = option (a), maximal.** Tag exactly the `dart:io`-bound
   tests that genuinely cannot run in a browser with `@TestOn('vm')`, and get
   everything else passing in Chrome — maximizing the real web regression net.

### Out of scope (explicitly)

- **Full web file UX** — a polished browser save/open (download/upload) flow in
  the playground. E4 does the *minimum* to compile + smoke; full web file UX is
  deferred (would be the option-(c) depth we did not choose).
- **Web golden baselines** (a separate CanvasKit golden set) — rejected for
  maintenance cost.
- **Mobile web / responsive touch layout** — that is E5 territory.
- **WASM (`skwasm`) build** — CanvasKit/JS is the E4 target; WASM is a later
  optimization.
- **pub.dev "supports web" platform declaration / 1.0** — E6 capstone.

## 3. Grounding — what exists today

- **Library is web-compile-clean (static evidence).** The only `dart:io` /
  `dart:ffi` in `lib/` is
  [native_resize_cursor_io.dart](../../../packages/jet_print/lib/src/designer/canvas/native_resize_cursor_io.dart),
  already loaded behind a `if (dart.library.io)` conditional import with a web
  stub
  ([native_resize_cursor_stub.dart](../../../packages/jet_print/lib/src/designer/canvas/native_resize_cursor_stub.dart)).
  `platform_shortcut.dart` uses `TargetPlatform` (web-safe), not `dart:io`.
- **Plugins declare web support:** `pdf ^3.12.0` (pure Dart), `printing ^5.14.3`
  (web impl via pdf.js), `image ^4.3.0` (pure Dart).
- **Render/export/print paths to verify under CanvasKit:**
  - PNG export — `Picture.toImage → image.toByteData(format: png)` in
    [page_rasterizer.dart](../../../packages/jet_print/lib/src/rendering/paint/page_rasterizer.dart#L44).
  - Font loading — `ui.loadFontFromList` in
    [canvas_painter.dart](../../../packages/jet_print/lib/src/rendering/paint/canvas_painter.dart#L31),
    plus `jet_print_google_fonts` asset bytes (HTTP on web).
  - Image decode — `ui.instantiateImageCodec` for `ImageElement` bitmaps.
  - Print seam — `Printing.info()` + `Printing.layoutPdf(...)` in
    [jet_report_printer.dart](../../../packages/jet_print/lib/src/print/jet_report_printer.dart#L98).
- **Playground is NOT web-ready:**
  [main.dart](../../../apps/jet_print_playground/lib/main.dart) imports
  `dart:io` (`Platform` for the desktop guard; `File` for the save flow at
  ~line 442), and there is no `web/` runner dir.
- **Web renderer:** Flutter 3.44 dropped the HTML renderer; the default web
  renderer is **CanvasKit** (supports `toByteData(png)` and `loadFontFromList`).

## 4. The de-risk gate (first concrete step)

The whole design rests on "the library compiles to web." Before any hardening,
**empirically `flutter build web` a minimal web consumer** of `jet_print`. If a
hidden transitive web-blocker exists (in a dep's Dart side), surface it here and
adapt the design — exactly the discipline that turned E3's format-gate surprise
into its Task 1. Static evidence says it will compile; this gate proves it.

## 5. Library hardening — the three CanvasKit runtime soft spots

Verify each in Chrome (`flutter run -d chrome` smoke + a `--platform chrome`
test where feasible) and harden only if it breaks:

- **PNG export** — confirm `Picture.toImage → toByteData(png)` produces a valid
  PNG under CanvasKit (the top risk; CanvasKit supports it).
- **Font loading** — confirm `loadFontFromList` registers the bundled + Google
  fonts and the canvas renders text in them.
- **Image decode** — confirm `instantiateImageCodec` decodes `ImageElement`
  bitmaps.

The render path (`canvas_painter` / `report_painter`) uses `dart:ui` `Canvas`
primitives that CanvasKit implements; verify the designer canvas renders. Any
fix is expected to be a small conditional/fallback, not an engine change; no
golden bytes change (goldens stay macOS-canonical).

## 6. The print seam on web (browser print)

The seam already abstracts printing behind `PrintDialogPresenter`. On web,
`Printing.info().canPrint` is true and `Printing.layoutPdf(...)` opens the
**browser print dialog** (pdf.js). Verify both in Chrome. **Document the web
semantics:** there is no OS dialog, and user-cancel may not be reported — so the
seam's `true`/`false` "handed to OS / cancelled" contract is best-effort on web.
No seam redesign; `PrintUnavailableException` stays the path for genuinely
unsupported environments.

## 7. Playground web-readiness (minimal)

To `flutter build web` and smoke the library, the playground must compile for
web:

- **Conditional-import split** of the `dart:io File` save path: an `_io` impl
  (writes via `File`) and a `_web` impl (browser download via `file_selector`
  web / an `XFile`-based save), behind a `if (dart.library.io)` facade — so the
  app compiles on web and the save action does not crash.
- **Relax the desktop guard** in `main()` to permit web (it currently throws off
  macOS/Windows/Linux). Keep a clear failure only for genuinely unsupported
  targets.
- **Generate the `web/` runner dir** (`flutter create --platforms=web .`).

Per the depth decision, the save/open *UX* stays minimal — enough to build and
smoke, not a polished web file experience (deferred, §2 out-of-scope).

## 8. Goldens + the Chrome test leg (+ the VM-only audit)

Two orthogonal gates make the Chrome leg meaningful:

- **Goldens** — already tagged `golden` (E3). The web leg runs
  `flutter test --platform chrome --exclude-tags golden`, so no golden (PNG or
  the pinned PDF) executes in-browser. No re-baselining.
- **VM-only tests** — `flutter test --platform chrome` runs tests *in the
  browser*, so any test importing `dart:io` cannot run there: the architecture
  tests (filesystem scans via `findWorkspaceRoot`), the `pdf_determinism` file
  pins, the 50k stress test (`ProcessInfo`), and similar. Per decision (a),
  **audit and tag exactly those with `@TestOn('vm')`** so the Chrome leg skips
  them, and get everything else passing in Chrome. The audit is one-time;
  `@TestOn('vm')` is the standard, analyze-clean annotation (declared like the
  `golden` tag, recognized by the test runner).

The macOS canonical leg still runs the full suite (goldens + VM tests) exactly
as today — `@TestOn('vm')` and `--exclude-tags golden` only affect the Chrome
leg.

## 9. CI — a web job

Add a **web job** to `.github/workflows/ci.yml` (ubuntu-latest, cheap 1×):
`flutter build web` + `flutter test --platform chrome --exclude-tags golden`.
It runs once the Actions billing lock is cleared; until then, **E4's acceptance
is the local Chrome verification** and the web job is the durable regression
guard. Chrome is preinstalled on `ubuntu-latest` runners.

## 10. Execution model — single-phase, local

Unlike E3 (whose Windows leg is stranded on Actions), E4 is fully verifiable on
the dev Mac: build web → smoke in Chrome → harden the soft spots → make the
playground web-buildable → audit/tag VM-only tests → add the CI web job. Every
acceptance check has a local command.

## 11. Functional requirements

- **FR-E4-001** — a minimal web consumer of `jet_print` compiles:
  `flutter build web` succeeds (the de-risk gate).
- **FR-E4-002** — the designer canvas renders under CanvasKit in Chrome
  (`flutter run -d chrome` smoke); text renders in the bundled/Google fonts.
- **FR-E4-003** — PNG export (`toByteData(png)`) produces a valid image in
  Chrome; PDF export (`toPdf`) produces valid bytes.
- **FR-E4-004** — printing on web uses `Printing.layoutPdf` (browser print);
  `Printing.info().canPrint` is honored; web semantics documented at the seam.
- **FR-E4-005** — the playground compiles and builds for web
  (`flutter build web`), with `dart:io` usage split behind a conditional import
  and the desktop guard relaxed to allow web; a generated `web/` runner dir.
- **FR-E4-006** — VM-only tests (those importing `dart:io`) are tagged
  `@TestOn('vm')`; `flutter test --platform chrome --exclude-tags golden` runs
  green over the remaining browser-capable suite.
- **FR-E4-007** — the full macOS suite (`flutter test packages/jet_print
  apps/jet_print_playground`) stays green and goldens stay byte-identical (no
  regression from the web work).
- **FR-E4-008** — `ci.yml` gains a web job (`flutter build web` +
  `flutter test --platform chrome --exclude-tags golden`).

## 12. Success criteria

- **SC-E4-001** — `flutter build web` of the playground succeeds locally.
- **SC-E4-002** — manual Chrome smoke (`flutter run -d chrome`): the designer
  renders, a report previews, PNG + PDF export work, print opens the browser
  dialog. *(Recorded in an E4 findings note.)*
- **SC-E4-003** — `flutter test --platform chrome --exclude-tags golden` is
  green; the VM-only tests it skips are exactly those that import `dart:io`.
- **SC-E4-004** — the macOS full suite stays green; goldens byte-identical;
  `flutter analyze` clean; no public-API change beyond any additive web seam.
- **SC-E4-005** — no engine/domain change forced by web; any hardening is a
  localized conditional/fallback, documented.

## 13. Risks & mitigations

- **CanvasKit `toByteData(png)` differences** — verified in Chrome smoke; if it
  fails, a CanvasKit-specific encode fallback (localized). Top risk.
- **A hidden transitive web-blocker** in a dependency's Dart side — the §4
  de-risk gate surfaces it before any other work.
- **`flutter test --platform chrome` flakiness / browser startup** — keep the
  Chrome leg to genuinely browser-capable tests (the audit); VM tests stay VM.
- **Web print semantics** (cancel-as-success) — documented at the seam, not
  hidden; the contract is best-effort on web.
- **Font loading over HTTP on web** (asset latency) — fonts are preloaded before
  render as today; verify in smoke.
- **CI web job can't run yet** (billing lock) — acceptance is local; the job is
  the durable guard for when Actions returns.
