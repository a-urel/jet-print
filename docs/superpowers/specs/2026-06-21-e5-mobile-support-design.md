# Epic E5 — Mobile / Touch Support — Design

**Status:** approved (2026-06-21)
**Parent roadmap:** [2026-06-20-production-readiness-roadmap-design.md](./2026-06-20-production-readiness-roadmap-design.md)
**Predecessors:** E1 (release hygiene), E2 (resilience/stress), E3 (desktop
matrix Phase A), E4 (web support), E8 (spec 033) — all DONE and merged.

## 1. Purpose & the "it's leaner than it looks" thesis

E5 makes jet_print usable on **iOS + Android**, phone and tablet — both
*viewing/printing* rendered reports and *authoring* in the designer. The roadmap
rates this **XL / Highest risk** and calls it "closer to an interaction redesign
than a port," noting its cost "may decide whether mobile is in the 1.0."

Exploration changed that estimate. Two facts deflate the "redesign" framing:

1. The designer shell is **already responsive** — a wide/narrow breakpoint
   system collapses the side panels to a 48px rail + overlay on narrow widths
   ([jet_report_designer.dart](../../../packages/jet_print/lib/src/designer/jet_report_designer.dart)).
2. The canvas gesture layer **already accepts touch** — `touch` is in its
   accepted pointer-device set, so tap / drag / marquee already fire under a
   finger.

So E5 splits along a line the codebase already draws: the **rendered-output
path** (paint → PDF → print) is identical to what E4 just verified on web — on
mobile it is *verify-and-harden*; the **designer** is already responsive — it
needs targeted *affordances*, not architecture. This is **verify + harden +
targeted touch affordances**, not a rebuild.

**The decisive enabler (as in E4): full local verifiability.** The dev Mac runs
the iOS Simulator and an Android emulator, so every check — build, automated
gesture tests, and manual smoke — runs here. **E5 has no dependency on GitHub
Actions** (billing-locked; see [[spec-e3-desktop-matrix-status]]).

## 2. Scope (settled by the brainstorm)

The target is **full mobile in one combined spec** (the user rejected splitting
into sub-epics): iOS + Android, phone + tablet, viewing *and* authoring. The
work is organized as **three internal phases of a single spec**, so the plan
stages cleanly while the vision stays cohesive.

Settled decisions:

1. **Target = full mobile, one spec.** iOS + Android; phone + tablet; output
   *and* authoring. Verified on the iOS Simulator + an Android emulator plus a
   human smoke pass.
2. **Architecture = one adaptive single designer.** No separate mobile surface.
   The existing `JetReportDesigner` adapts in place. Adaptation is keyed on the
   **active pointer kind** (touch vs mouse/stylus), *not* `Platform.isX` — so a
   touchscreen laptop and a keyboard-tablet both stay correct, and the mouse
   stays pixel-precise on the same device.
3. **Action surface = long-press + reuse.** Long-press an element opens the
   **existing** context menu (Cut/Copy/Paste/Duplicate/Delete) as a touch
   popover — the right-click equivalent. The toolbar gets a compact density;
   Undo/Redo become always-visible top-bar buttons (today they are
   keyboard-only). Fine positioning uses the **existing Properties X/Y fields**
   (already tap-reachable) — *no* on-screen nudge buttons, *no* persistent
   bottom command bar.
4. **Touch-sized hit areas (essential).** Resize handles, the band divider, and
   the scrollbar grow to a ~44px **hit area when the active pointer is touch**.
   The **visual** size is unchanged, so **goldens stay byte-identical** and the
   mouse keeps its 16px precision.
5. **Pinch-zoom = OUT.** Zoom on touch uses the existing on-screen +/−/fit
   buttons. We do **not** migrate the canvas's pan recognizer to a unified scale
   recognizer — that was the one high-regression-risk refactor, and skipping it
   leaves the existing element-move / marquee / pan drag code **untouched**.

### Out of scope (explicitly)

- **Pinch-to-zoom** and any `onPan*` → `onScale*` gesture migration (decision 5).
- **On-screen nudge arrows / persistent command bar** — fine positioning is the
  Properties X/Y fields (decision 3).
- **Apple Pencil / stylus pressure, multi-touch marquee refinements** — niceties
  beyond a usable touch baseline.
- **Polished mobile file open/save UX** — the playground does the *minimum*
  (app-documents dir + share sheet) to build and smoke; real file UX is E7.
- **pub.dev "supports iOS/Android" platform declaration / 1.0** — E6 capstone.
- **Any engine, domain, or golden-byte change** — E5 is designer + playground +
  platform glue only.

## 3. Grounding — what exists today

- **Library is mobile-compile-clean.** Mobile *has* `dart:io` (unlike web), so
  the only conditional path —
  [native_resize_cursor_io.dart](../../../packages/jet_print/lib/src/designer/canvas/native_resize_cursor_io.dart) —
  compiles and returns `false` off `Platform.isMacOS`. `platform_shortcut.dart`
  already uses `TargetPlatform` (maps iOS → `⌘`/`⇧`).
- **Plugins declare mobile support:** `pdf ^3.12.0` (pure Dart), `printing
  ^5.14.3` (iOS/Android native print), `image ^4.3.0` (pure Dart).
- **Render/export/print paths to verify on Impeller/Skia mobile** (the same soft
  spots E4 checked under CanvasKit):
  - Font loading — `ui.loadFontFromList` in
    [canvas_painter.dart](../../../packages/jet_print/lib/src/rendering/paint/canvas_painter.dart#L31).
  - Image decode — `ui.instantiateImageCodec` for `ImageElement` bitmaps.
  - PNG export — `Picture.toImage → toByteData(png)` in
    [page_rasterizer.dart](../../../packages/jet_print/lib/src/rendering/paint/page_rasterizer.dart#L44).
  - Number formatting — E4's `_d()` helper already normalizes `double.toString`
    cross-platform (VM no-op); verify no new divergence on mobile.
  - PDF determinism — the byte-pinned `invoice.pdf`; PDF generation is pure Dart,
    so it *should* match the macOS pin — verify.
  - Print seam — `Printing.info()` + `Printing.layoutPdf(...)` in
    [jet_report_printer.dart](../../../packages/jet_print/lib/src/print/jet_report_printer.dart#L98)
    routes to the native iOS/Android print/share sheet.
- **Designer interaction surface (the affordance gaps):**
  - Handle hit area `kHandleHitSize = 16` and visual `kHandleVisualSize = 8`
    ([design_tunables.dart](../../../packages/jet_print/lib/src/designer/canvas/design_tunables.dart));
    band divider 28×16; scrollbar thumb ~8px wide — all below the ~44px touch
    minimum.
  - The Cut/Copy/Paste/Duplicate/Delete menu is reached only via secondary-tap
    ([design_canvas.dart](../../../packages/jet_print/lib/src/designer/canvas/design_canvas.dart#L801)).
  - Undo/Redo, Select-All, Delete-solo, Escape-clear, and arrow-nudge are
    keyboard-only
    ([canvas_shortcuts.dart](../../../packages/jet_print/lib/src/designer/interaction/canvas_shortcuts.dart)).
- **Playground is NOT mobile-ready:**
  [main.dart](../../../apps/jet_print_playground/lib/main.dart) guards to desktop
  (+ web from E4) and writes the save flow via `dart:io File`; there are no
  `ios/` or `android/` runner dirs.

## 4. The de-risk gate (first concrete step)

The design rests on "the library + playground build for mobile." Before any
hardening, **empirically `flutter build apk --debug` and `flutter build ios
--debug --no-codesign`** of the playground (after generating the runner dirs and
a minimal entrypoint). Static evidence says they compile; this gate proves it
and surfaces any hidden transitive blocker early — the same discipline that made
E4 Task 1 the de-risk gate.

## 5. Phase 1 — Output harden (the E4 twin)

Verify each render/export/print path on the iOS Simulator + Android emulator
(`flutter run` smoke + automated tests under `debugDefaultTargetPlatformOverride`
where feasible) and harden only what breaks:

- **Canvas render** — fonts load (`loadFontFromList`); text renders; `ImageElement`
  bitmaps decode (`instantiateImageCodec`); every playground sample paints.
- **Export** — `toByteData(png)` produces a valid PNG; `toPdf` produces valid
  bytes; the pinned `invoice.pdf` matches (or the divergence is understood and
  documented).
- **Print** — `Printing.info().canPrint` is honored; `Printing.layoutPdf` opens
  the **native iOS/Android print/share sheet**. Document the mobile semantics
  (no OS desktop dialog; cancel-as-success best-effort), as E4 documented
  browser-print. `PrintUnavailableException` stays for genuinely unsupported
  environments. Verify any required iOS `Info.plist` / Android manifest entries.

Any fix is expected to be a localized conditional/fallback, **not** an engine
change; **no golden bytes change**.

## 6. Phase 2 — Touch affordances (the lean designer changes)

- **Pointer-kind signal.** The canvas tracks the **active pointer kind** from
  pointer-down events and exposes a touch flag. This single signal drives every
  touch adaptation below; it is *not* a `Platform` check.
- **Touch-sized hit areas.** When the active pointer is touch, the selection
  handles, band divider, and scrollbar select a ~44px hit area (a touch variant
  of `kHandleHitSize`). **Visual size unchanged → goldens byte-identical.** Mouse
  input keeps the existing 16px precision.
- **Long-press = right-click.** Add `onLongPressStart` to the canvas; reuse the
  existing secondary-tap pre-select logic, then open the **same**
  `ShadContextMenuRegion` menu as a popover anchored at the press point. No new
  menu — the existing Cut/Copy/Paste/Duplicate/Delete items.
- **Compact toolbar + Undo/Redo buttons.** Tighten `designer_top_bar.dart`
  density at narrow/touch widths; add the always-visible **Undo/Redo** buttons
  the top bar currently lacks (wired to `controller.undo/redo`). Zoom stays on
  the existing +/−/fit buttons (decision 5).

Hover-only affordances (native cursors, ruler hover tracking) remain no-ops on
touch and **degrade harmlessly** — no work needed.

## 7. Phase 3 — Phone-width tuning

The narrow breakpoint already collapses the panels to a 48px rail + ~300px
overlay; at a ~390pt phone width that overlay is near-full-width, which is an
acceptable modal-panel pattern. Phase 3 **verifies and tunes** rather than
rebuilds:

- Confirm the Outline and Properties panels are usable as overlays at phone
  widths; tune breakpoint values where the canvas is starved.
- Promote a panel to a full-width bottom sheet **only** where it is genuinely
  cramped.
- **Lean acceptance:** if authoring at ~390pt proves cramped beyond what tuning
  fixes, that is **documented as a known limitation** (the findings doc), not a
  scope expansion. Tablet authoring is the primary authoring target; phone
  authoring is "usable," not "optimal."

## 8. Playground mobile-readiness (minimal)

- **Generate `ios/` + `android/` runner dirs** (`flutter create
  --platforms=ios,android .`).
- **Relax the desktop/web guard** in `main()` to permit iOS/Android.
- **Keep the save path minimal:** on mobile, write to the app-documents
  directory and offer a **share sheet** (via the existing `printing`/share
  capability or a minimal `dart:io` write under `path_provider`). Full mobile
  file UX is deferred to E7 (§2 out-of-scope).

## 9. Testing — simulated touch in the VM suite

E5's test story is **simpler than E4's**: touch needs no separate platform leg.
`WidgetTester` simulates it natively.

- **Automated (existing `flutter test` VM run):**
  - `tester.longPress(...)` opens the context-menu popover.
  - A touch-kind pointer enlarges the handle hit area; a mouse-kind pointer keeps
    16px (assert the pointer-kind signal + handle sizing).
  - The Undo/Redo top-bar buttons drive `controller.undo/redo`.
  - Render + PDF/PNG export under `debugDefaultTargetPlatformOverride =
    TargetPlatform.android`/`iOS` produce valid bytes.
- **Manual smoke (you):** boot the playground on the iOS Simulator + an Android
  emulator — render every sample, export PDF/PNG, print (share sheet), author
  (select → long-press menu → resize via the enlarged handle → move → zoom
  buttons), and check the phone-width panel overlays. Recorded in an `e5-findings`
  doc.

No new test *leg* and no per-package split — the touch tests join the normal VM
suite. The existing `@TestOn('vm')` / `golden` tags from E3/E4 are unchanged.

## 10. CI — mobile build jobs

Add **mobile build jobs** to `.github/workflows/ci.yml`: a macOS runner
(`flutter build ios --debug --no-codesign`) and an ubuntu runner (`flutter build
apk --debug`), mirroring E4's web job. They run once the Actions billing lock
clears; until then, **E5's acceptance is the local sim/emulator verification**
and the jobs are the durable regression guard.

## 11. Functional requirements

- **FR-E5-001** — the playground builds for Android (`flutter build apk --debug`)
  and iOS (`flutter build ios --debug --no-codesign`) after runner-dir
  generation (the de-risk gate).
- **FR-E5-002** — every playground sample renders on the iOS Simulator + Android
  emulator; fonts load and `ImageElement` bitmaps decode.
- **FR-E5-003** — PNG export (`toByteData(png)`) and PDF export (`toPdf`) produce
  valid bytes on mobile; the pinned `invoice.pdf` matches or the divergence is
  documented.
- **FR-E5-004** — printing on mobile uses `Printing.layoutPdf` (native print/share
  sheet); `Printing.info().canPrint` is honored; mobile semantics documented at
  the seam; required platform manifest entries added.
- **FR-E5-005** — the designer exposes an **active-pointer-kind** signal (touch
  vs mouse/stylus); it is keyed on pointer kind, not `Platform.isX`.
- **FR-E5-006** — under touch, the resize handles, band divider, and scrollbar
  present a ~44px hit area; visual sizes and goldens are unchanged; mouse input
  keeps 16px precision.
- **FR-E5-007** — long-press on an element opens the existing context menu as a
  touch popover (the right-click equivalent), reusing the existing menu items.
- **FR-E5-008** — the top bar gains always-visible Undo/Redo buttons and a
  compact density at narrow/touch widths; zoom remains on the +/−/fit buttons.
- **FR-E5-009** — the playground compiles and builds for iOS + Android with the
  desktop guard relaxed, generated `ios/`+`android/` runner dirs, and a minimal
  save path (app-documents dir + share sheet).
- **FR-E5-010** — the phone-width layout is verified and tuned via the existing
  narrow breakpoint; any residual cramping is documented as a known limitation.
- **FR-E5-011** — the full macOS suite (`flutter test packages/jet_print
  apps/jet_print_playground`) stays green and goldens stay byte-identical.
- **FR-E5-012** — `ci.yml` gains mobile build jobs (iOS on macOS runner, APK on
  ubuntu runner).

## 12. Success criteria

- **SC-E5-001** — `flutter build apk --debug` and `flutter build ios --debug
  --no-codesign` of the playground succeed locally.
- **SC-E5-002** — manual smoke on the iOS Simulator + Android emulator: the
  designer renders, a report previews, PNG + PDF export work, print opens the
  native share/print sheet, and authoring (select / long-press menu / resize via
  the enlarged handle / move / zoom buttons) works on both. *(Recorded in an E5
  findings note; user-confirmed.)*
- **SC-E5-003** — new gesture/widget tests are green: long-press menu, touch
  hit-target sizing (touch enlarges, mouse stays 16px), Undo/Redo buttons,
  mobile-platform render/export.
- **SC-E5-004** — the macOS full suite stays green; goldens byte-identical;
  `flutter analyze` clean; no public-API change beyond additive designer
  signals; the 53 exports are unbroken.
- **SC-E5-005** — no engine/domain change forced by mobile; any hardening is a
  localized conditional/fallback, documented; the expression layer stays
  independent of the fill layer; arch tests green.

## 13. Risks & mitigations

- **A mobile output bug** (text measurement / font / raster divergence, like
  E4's `double.toString`) — budget 1–2 small localized fixes; the §4 gate +
  Phase 1 smoke surface them.
- **`printing` mobile setup** (iOS `Info.plist` / Android manifest) — verified in
  Phase 1; documented.
- **Phone authoring genuinely cramped at ~390pt** — Phase 3 tunes; residual
  cramping is a documented known limitation, not a scope expansion (decision:
  tablet is the primary authoring target).
- **Touch/mouse coexistence on hybrid devices** — mitigated by keying
  adaptation on the *active pointer kind*, not the platform.
- **CI mobile jobs can't run yet** (billing lock) — acceptance is local; the jobs
  are the durable guard for when Actions returns.
- **A hidden transitive mobile blocker** in a dependency's native side — the §4
  build gate surfaces it before any other work.
