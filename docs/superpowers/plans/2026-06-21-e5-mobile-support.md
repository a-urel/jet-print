# Epic E5 — Mobile / Touch Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make jet_print usable on iOS + Android (phone + tablet) — rendering/printing reports and authoring in the designer — via targeted touch affordances on the already-responsive designer plus an E4-style harden of the output path.

**Architecture:** One adaptive `JetReportDesigner` keyed on the **active pointer kind** (touch vs mouse/stylus), not `Platform.isX`. The output path (paint → PDF → print) is verified/hardened like E4 did for web. Three phases: (1) output harden + playground mobile-readiness, (2) touch affordances (pointer-kind signal, 44px touch hit areas, long-press context menu), (3) phone-width layout tuning. Pinch-zoom and any `onPan*`→`onScale*` migration are explicitly OUT — zoom stays on the existing +/−/fit buttons, leaving the element-move/marquee/pan drag code untouched.

**Tech Stack:** Flutter 3.44.0 (pinned); Dart; `shadcn_ui` 0.54.0 (`ShadContextMenuRegion`); plugins `pdf ^3.12`, `printing ^5.14.3`, `image ^4.3`, `file_selector ^1.1`. Tests via `flutter_test` (`WidgetTester.longPress`, `tester.startGesture(..., kind: PointerDeviceKind.touch)`, `debugDefaultTargetPlatformOverride`). Local verification on the iOS Simulator + an Android emulator.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-06-21-e5-mobile-support-design.md`. Branch `e5-mobile-support` (spec already committed at `2db5313`).
- **Goldens byte-identical.** All touch adaptations are *gated on touch input*; golden tests never simulate a touch pointer, so the touch branches never execute under goldens. Run the golden suite as the gate on every Phase-2/3 task.
- **macOS full suite stays green** via the documented command, run from the repo root: `flutter test packages/jet_print apps/jet_print_playground`.
- **Run `flutter`/`dart` from `packages/jet_print`** for library work (from `apps/jet_print_playground` for app-specific work); **run `git` from the repo root** (`/Users/ahmeturel/Projects/oss/jet-print`). `flutter` leaves the CWD inside the package — always `cd` back to the repo root before `git`.
- **No engine/domain change.** Library edits are confined to `lib/src/designer/**`, `lib/src/print/jet_report_printer.dart` (doc only), and tests. The expression layer must not depend on the fill layer; arch tests use `findWorkspaceRoot()`.
- **Additive public API only** — do not break the 53 exports. The pointer-kind signal and touch sizing are package-internal (no new public export).
- **Adaptation keyed on the active pointer kind, never `Platform.isX`.**
- **Pinch-zoom is OUT.** Do not touch the canvas `onPanStart/onPanUpdate/onPanEnd` recognizer wiring or add a scale recognizer.
- **Commits end with:** `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Do not push** (GitHub Actions is billing-locked; validate locally on sim/emulator).

### Two grounding corrections (the spec's §3 was built on an inventory that was wrong on these — trust this plan)

1. **The top bar already has Undo/Redo, Cut/Copy/Paste, and zoom buttons** ([designer_top_bar.dart:118-177](../../../packages/jet_print/lib/src/designer/layout/designer_top_bar.dart#L118-L177)), and already collapses to icon-only below 1300px and scrolls below 1040px. So FR-E5-008's "add Undo/Redo buttons" is **already satisfied** — no toolbar code is added. Touch reaches Delete/Duplicate via the long-press menu (Task 7); the rest are already on the bar.
2. **The playground save already uses `XFile.saveTo` / `getSaveLocation`, not raw `dart:io File`** ([main.dart:445-462](../../../apps/jet_print_playground/lib/main.dart#L445-L462)) — E4 made it cross-platform. Mobile only needs a *branch* (Task 4), not a conditional-import rewrite.

---

## File Structure

**Library (`packages/jet_print/lib/src/designer/`)**
- `canvas/design_tunables.dart` — add `kHandleHitSizeTouch` (44pt). Pure data.
- `canvas/selection_overlay.dart` — `DesignerSelectionOverlay` gains a `touchTargets` flag; handles + band divider pick the touch hit size. Visual geometry unchanged.
- `canvas/design_canvas.dart` — track the active pointer kind from the existing `Listener.onPointerDown`; pass `touchTargets` to the overlay; widen the scrollbars under touch; set `longPressEnabled: true` on the context-menu region.
- `print/jet_report_printer.dart` — doc-comment only: mobile (native share/print sheet) semantics.

**Playground (`apps/jet_print_playground/`)**
- `ios/`, `android/` — generated runner dirs (Task 1).
- `lib/main.dart` — relax the platform guard; add a mobile branch to `_saveBytes`.
- `pubspec.yaml` — add `printing` (for the mobile share sheet).

**Tests (`packages/jet_print/test/`, `apps/jet_print_playground/test/`)**
- `test/rendering/export/mobile_render_export_test.dart` — render + PDF + PNG under a mobile platform override (Task 2).
- `test/designer/canvas/touch_targets_test.dart` — touch enlarges the handle hit area; mouse keeps 16 (Task 6).
- `test/designer/canvas/long_press_menu_test.dart` — long-press opens the context menu on the pressed element (Task 7).
- `test/designer/phone_width_layout_test.dart` — the shell authors at phone width without the 600px horizontal scroll (Task 8).

**CI / docs**
- `.github/workflows/ci.yml` — mobile build jobs (Task 9).
- `docs/superpowers/specs/2026-06-21-e5-findings.md` — harden + smoke record (Task 10).

---

## Phase 1 — Output harden (the E4 twin)

### Task 1: De-risk build gate — playground builds for iOS + Android

**Files:**
- Create: `apps/jet_print_playground/ios/**`, `apps/jet_print_playground/android/**` (generated)
- Modify: `apps/jet_print_playground/lib/main.dart:36-44`

**Interfaces:**
- Produces: a playground that compiles and builds for iOS + Android. Later tasks assume the runner dirs exist.

- [ ] **Step 1: Generate the iOS + Android runner dirs**

Run (from the repo root):
```bash
cd apps/jet_print_playground && flutter create --platforms=ios,android --org dev.jetprint . && cd /Users/ahmeturel/Projects/oss/jet-print
```
Expected: new `ios/` and `android/` directories; existing Dart/`web`/desktop files untouched.

- [ ] **Step 2: Relax the desktop/web guard to allow mobile**

In [main.dart:36-44](../../../apps/jet_print_playground/lib/main.dart#L36-L44), replace the `supported` check:

```dart
  final bool supported = kIsWeb ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  if (!supported) {
    throw UnsupportedError(
      'jet_print_playground targets desktop (macOS, Windows, Linux), web, '
      'and mobile (iOS, Android).',
    );
  }
```

- [ ] **Step 3: Build for Android (the de-risk gate)**

Run (from the repo root):
```bash
cd apps/jet_print_playground && flutter build apk --debug && cd /Users/ahmeturel/Projects/oss/jet-print
```
Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`. If a transitive plugin fails to compile for Android, STOP and report — that is the hidden blocker this gate exists to surface.

- [ ] **Step 4: Build for iOS (no codesign)**

Run (from the repo root):
```bash
cd apps/jet_print_playground && flutter build ios --debug --no-codesign && cd /Users/ahmeturel/Projects/oss/jet-print
```
Expected: `Built build/ios/iphoneos/Runner.app` (or the simulator equivalent). A CocoaPods install runs on first build.

- [ ] **Step 5: Confirm the macOS suite still builds/analyzes**

Run (from the repo root):
```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/ios apps/jet_print_playground/android apps/jet_print_playground/lib/main.dart
git commit -m "feat(e5): playground builds for iOS + Android (de-risk gate)

Generate ios/ + android/ runner dirs; relax the platform guard to allow
mobile. flutter build apk/ios both succeed.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Mobile output regression test (render + PDF + PNG under a mobile platform override)

**Files:**
- Create: `packages/jet_print/test/rendering/export/mobile_render_export_test.dart`
- (Harden only if red:) `packages/jet_print/lib/src/**`

**Interfaces:**
- Consumes: `const JetReportEngine().renderDefinition(ReportDefinition, JetDataSource)` → `RenderedReport`; `const JetReportExporter().toPdf(RenderedReport)` → `Future<Uint8List>` (`%PDF-` header); `const JetReportExporter().pageToPng(RenderedReport, int)` → `Future<Uint8List>` (8-byte PNG signature). All are existing public API (mirrors `test/web/web_render_export_test.dart`).

This is the automated regression net for *platform-conditional Dart code* (the class of bug E4's `_d()` fixed). It runs in the VM with `defaultTargetPlatform` overridden to a mobile target; it does **not** exercise the real Impeller renderer — that is the manual smoke's job (Task 10). State that honestly in the file header.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/rendering/export/mobile_render_export_test.dart`:

```dart
// Mobile render + export smoke. Runs in the VM with defaultTargetPlatform
// pinned to a mobile target, so it guards platform-CONDITIONAL Dart code on
// the export path (the class of bug E4's `_d()` number helper fixed). It does
// NOT exercise the real iOS/Android Impeller renderer — that is the manual
// sim/emulator smoke (E5 SC-002). No dart:io.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _definition() => const ReportDefinition(
      name: 'Mobile smoke',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: Band(
          id: 'body/title',
          type: BandType.title,
          height: 48,
          elements: <ReportElement>[
            TextElement(
              id: 'h',
              bounds: JetRect(x: 0, y: 0, width: 300, height: 24),
              text: 'MOBILE RENDER 5.0',
              style: JetTextStyle(fontSize: 18, weight: JetFontWeight.bold),
            ),
          ],
        ),
        root: DetailScope(id: 'root', children: <ScopeNode>[]),
      ),
    );

RenderedReport _render() => const JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    group('$platform', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      test('PDF export produces valid bytes', () async {
        final Uint8List pdf = await const JetReportExporter().toPdf(_render());
        expect(pdf.length, greaterThan(100));
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      });

      test('PNG export (page rasterizer) produces a valid image', () async {
        final Uint8List png =
            await const JetReportExporter().pageToPng(_render(), 0);
        expect(png.length, greaterThan(100));
        expect(png.sublist(0, 8),
            <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      });
    });
  }
}
```

- [ ] **Step 2: Run it**

Run (from `packages/jet_print`):
```bash
flutter test test/rendering/export/mobile_render_export_test.dart
```
Expected: **PASS** (the export path is already platform-agnostic; this test is the standing net). If it FAILS, the failure is a real mobile-conditional bug — harden it with a localized conditional/fallback (no engine/golden change), exactly as E4 did, then re-run. Record any fix in the Task-10 findings doc.

- [ ] **Step 3: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test/rendering/export/mobile_render_export_test.dart
git commit -m "test(e5): render + PDF/PNG export under iOS/Android platform override

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Print seam — document the mobile (native share/print sheet) semantics

**Files:**
- Modify: `packages/jet_print/lib/src/print/jet_report_printer.dart` (doc comment near the `Printing.info()` / `Printing.layoutPdf` call, ~line 72-98)

**Interfaces:**
- Consumes: the existing `JetReportPrinter` seam (`Printing.info()` + `Printing.layoutPdf`). No behavior change.

The seam already routes to `printing`, which on iOS/Android opens the **native print/share sheet**. No code path changes; this task records the mobile semantics next to the seam so the contract is documented (mirroring how E4 documented browser-print), and verifies nothing throws under a mobile override.

- [ ] **Step 1: Document the mobile semantics**

In `jet_report_printer.dart`, extend the doc comment on the printing method (the one calling `Printing.layoutPdf`) to add a mobile paragraph. Insert after the existing platform notes:

```dart
  /// On **iOS/Android**, `Printing.layoutPdf` presents the native print/share
  /// sheet for the deterministic [JetReportExporter.toPdf] bytes; there is no
  /// desktop print dialog, and a user dismissal may report as success (the
  /// `true`/`false` "handed off / cancelled" contract is best-effort on
  /// mobile, as on web). `PrintUnavailableException` still covers genuinely
  /// unsupported environments.
```

- [ ] **Step 2: Verify the existing printer suite stays green**

Run (from `packages/jet_print`):
```bash
flutter test test/print/jet_report_printer_test.dart
```
Expected: PASS (doc-only change).

- [ ] **Step 3: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/print/jet_report_printer.dart
git commit -m "docs(e5): document the print seam's mobile share-sheet semantics

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Playground mobile save branch (share sheet)

**Files:**
- Modify: `apps/jet_print_playground/lib/main.dart:445-462` (`_saveBytes`), imports
- Modify: `apps/jet_print_playground/pubspec.yaml` (add `printing`)

**Interfaces:**
- Consumes: `Printing.sharePdf({required Uint8List bytes, required String filename})` from `package:printing` — opens the OS share/save sheet for arbitrary bytes on iOS/Android (web-safe; no `dart:io`).

`getSaveLocation` (file_selector) is unsupported on iOS/Android, so the desktop branch would throw there. Add a mobile branch that shares the bytes. Per the spec this is the *minimal* mobile save; full file UX is E7.

- [ ] **Step 1: Add the `printing` dependency**

In `apps/jet_print_playground/pubspec.yaml`, under `dependencies:` (beside `file_selector`):
```yaml
  printing: ^5.14.3
```
Run (from `apps/jet_print_playground`):
```bash
flutter pub get
```
Expected: resolves (the library already locks `printing ^5.14.3`).

- [ ] **Step 2: Add the import**

In `main.dart`, add beside the other plugin imports:
```dart
import 'package:printing/printing.dart' show Printing;
```

- [ ] **Step 3: Add the mobile branch to `_saveBytes`**

In `_saveBytes` ([main.dart:445-462](../../../apps/jet_print_playground/lib/main.dart#L445-L462)), insert the mobile branch immediately after the `if (kIsWeb)` block and before `getSaveLocation`:

```dart
    if (kIsWeb) {
      await XFile.fromData(bytes, name: suggestedName, mimeType: mimeType)
          .saveTo(suggestedName);
      return;
    }
    // Mobile: file_selector's getSaveLocation is desktop/web-only, so present
    // the OS share sheet for the bytes instead (minimal save — full mobile
    // file UX is deferred to E7).
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      await Printing.sharePdf(bytes: bytes, filename: suggestedName);
      return;
    }
    final FileSaveLocation? location = await getSaveLocation(
```

- [ ] **Step 4: Verify it analyzes and the playground suite is green**

Run (from the repo root):
```bash
flutter analyze && flutter test apps/jet_print_playground
```
Expected: `No issues found!` and the playground tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/main.dart apps/jet_print_playground/pubspec.yaml pubspec.lock
git commit -m "feat(e5): playground saves via the OS share sheet on mobile

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase 2 — Touch affordances

### Task 5: Active-pointer-kind signal on the canvas

**Files:**
- Modify: `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` (State field + `Listener.onPointerDown` at ~line 801; a `_isTouch` getter)
- Test: `packages/jet_print/test/designer/canvas/touch_targets_test.dart` (created in Task 6 — this task ships the signal; Task 6 asserts its effect)

**Interfaces:**
- Produces: a private `bool _isTouch` on the canvas `State`, true when the last pointer-down came from `PointerDeviceKind.touch`. Consumed by Task 6 (overlay sizing + scrollbar width) and available for any later touch branch.

- [ ] **Step 1: Add the pointer-kind field + getter**

In the canvas `State` (near `_hoverPage`, ~line 186 in `design_canvas.dart`), add:

```dart
  /// The kind of the most recent pointer-down over the canvas. Drives the
  /// touch-sized grab affordances (larger resize handles + scrollbars) without
  /// a `Platform` check — a mouse on a touchscreen laptop keeps pixel
  /// precision, a finger on the same device gets fat targets.
  PointerDeviceKind _pointerKind = PointerDeviceKind.mouse;

  bool get _isTouch => _pointerKind == PointerDeviceKind.touch;

  void _updatePointerKind(PointerDeviceKind kind) {
    if (kind == _pointerKind) return;
    setState(() => _pointerKind = kind);
  }
```

- [ ] **Step 2: Track the kind from the existing Listener**

In the `Listener.onPointerDown` ([design_canvas.dart:801](../../../packages/jet_print/lib/src/designer/canvas/design_canvas.dart#L801)), add the tracking call as the first line:

```dart
              onPointerDown: (PointerDownEvent e) {
                _updatePointerKind(e.kind);
                if (e.buttons == kSecondaryButton) {
                  _handleSecondaryTapDown(
                      e.localPosition, controller, transform, layout);
                } else if (_contextMenu.isOpen) {
                  _contextMenu.hide();
                }
              },
```

- [ ] **Step 3: Verify it analyzes (no behavior change yet)**

Run (from `packages/jet_print`):
```bash
flutter analyze
```
Expected: `No issues found!` (`_isTouch` is unused until Task 6 — if analyze flags the unused getter, proceed to Task 6 in the same branch; the two tasks ship together. To keep this task self-contained, you may temporarily mark it with `// ignore: unused_element` and remove the ignore in Task 6.)

- [ ] **Step 4: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/canvas/design_canvas.dart
git commit -m "feat(e5): track the active pointer kind on the canvas

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Touch-sized hit areas (handles, band divider, scrollbars)

**Files:**
- Modify: `packages/jet_print/lib/src/designer/canvas/design_tunables.dart` (add `kHandleHitSizeTouch`)
- Modify: `packages/jet_print/lib/src/designer/canvas/selection_overlay.dart` (`touchTargets` flag; hit-size selection)
- Modify: `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` (pass `touchTargets`; widen scrollbars under touch)
- Test: `packages/jet_print/test/designer/canvas/touch_targets_test.dart`

**Interfaces:**
- Consumes: `_isTouch` from Task 5.
- Produces: `DesignerSelectionOverlay({required layout, required scale, bool touchTargets = false})`; `const double kHandleHitSizeTouch = 44`.

The **visual** geometry is unchanged: `_handle`/`_bandHandle` keep their `kHandleVisualSize` (8pt) drawn square centered on the same point; only the transparent `Positioned` hit box grows. Goldens never simulate touch, so `touchTargets` is false under every golden → bytes identical.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/canvas/touch_targets_test.dart`:

```dart
// Touch enlarges the resize-handle hit area to a finger-friendly target while
// the drawn handle (and thus goldens) stays put; a mouse keeps the 16px hit.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/canvas/design_tunables.dart';
import 'package:jet_print/src/designer/canvas/selection_overlay.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/designer/canvas/design_time_layout.dart';

void main() {
  test('kHandleHitSizeTouch is a finger-friendly target larger than the mouse hit',
      () {
    expect(kHandleHitSizeTouch, greaterThanOrEqualTo(44));
    expect(kHandleHitSizeTouch, greaterThan(kHandleHitSize));
    // The visual size is unchanged — only the hit area grows.
    expect(kHandleVisualSize, 8);
  });

  testWidgets('the overlay sizes its handle hit box from touchTargets',
      (WidgetTester tester) async {
    // A handle Positioned is `hit` square; assert touch swaps 16 -> 44 while the
    // drawn handle box stays kHandleVisualSize. We read the Positioned that owns
    // a handle key by pumping the overlay twice (mouse, then touch).
    Future<double> hitSizeFor({required bool touch}) async {
      await tester.pumpWidget(_HostOverlay(touchTargets: touch));
      final Finder handle = find.byKey(handleKey(ResizeHandle.topLeft));
      final Size size = tester.getSize(handle);
      return size.width;
    }

    // Requires a selected single element; _HostOverlay wires a controller with
    // one element selected (see the helper below).
    expect(await hitSizeFor(touch: false), kHandleHitSize);
    expect(await hitSizeFor(touch: true), kHandleHitSizeTouch);
  });
}
```

> **Implementer note:** `_HostOverlay` must mount `DesignerSelectionOverlay` inside a `DesignerScope` whose controller has exactly one element selected, at `scale: 1`, with a `DesignTimeLayout` that returns a non-null rect for that element — follow the existing pattern in `test/designer/canvas/` selection/handle tests (e.g. `selection_overlay`/`band_bounded_chrome` tests) for the scaffolding. If a touch-target widget test proves too heavy to scaffold, keep the constant assertion (first test) and assert the hit-size selection by unit-testing the `hit` expression via a small extracted helper instead; do not weaken the contract (touch → `kHandleHitSizeTouch`, mouse → `kHandleHitSize`).

- [ ] **Step 2: Run it to verify it fails**

Run (from `packages/jet_print`):
```bash
flutter test test/designer/canvas/touch_targets_test.dart
```
Expected: FAIL — `kHandleHitSizeTouch` undefined / `touchTargets` not a parameter.

- [ ] **Step 3: Add the tunable**

In `design_tunables.dart`, after `kHandleHitSize` (line 89):

```dart
/// Side length, in screen pixels, of a resize handle's *hit* area under TOUCH
/// input — a finger-friendly target (~Apple HIG / Material 44pt). Selected by
/// the selection overlay when the active pointer is touch; the drawn handle
/// stays [kHandleVisualSize], so goldens (which never simulate touch) are
/// unchanged.
const double kHandleHitSizeTouch = 44;
```

- [ ] **Step 4: Thread `touchTargets` through the overlay**

In `selection_overlay.dart`:

Add the field + constructor param on `DesignerSelectionOverlay`:
```dart
  const DesignerSelectionOverlay(
      {required this.layout,
      required this.scale,
      this.touchTargets = false,
      super.key});

  /// The active zoom factor.
  final double scale;

  /// When true, resize handles + the band divider present a finger-sized hit
  /// area ([kHandleHitSizeTouch]); the drawn handle is unchanged.
  final bool touchTargets;
```

In `_handle` (line ~314) replace `const double hit = kHandleHitSize;` with:
```dart
    final double hit =
        widget.touchTargets ? kHandleHitSizeTouch : kHandleHitSize;
```

In `_bandHandle` (line ~199) replace `const double hit = kHandleHitSize;` with:
```dart
    final double hit =
        widget.touchTargets ? kHandleHitSizeTouch : kHandleHitSize;
```

- [ ] **Step 5: Pass the flag from the canvas + widen scrollbars under touch**

In `design_canvas.dart`, at the overlay construction ([design_canvas.dart:1148](../../../packages/jet_print/lib/src/designer/canvas/design_canvas.dart#L1148)):
```dart
                  Positioned.fill(
                    child: DesignerSelectionOverlay(
                        layout: displayLayout,
                        scale: scale,
                        touchTargets: _isTouch),
                  ),
```

Widen the scrollbars under touch. Introduce a local at the top of the scrollbar build (just before `final Widget viewportStack`):
```dart
            final double barThickness = _isTouch ? 20 : 8;
```
Then in the vertical scrollbar `Positioned` (line ~882-895) use `bottom: hScrollable ? barThickness : 0`, `width: barThickness`; in the horizontal one (line ~896-909) use `right: vScrollable ? barThickness : 0`, `bottom: 0`, `height: barThickness`. Leave the `_CanvasScrollbar` color/keys unchanged. (Remove the temporary `// ignore: unused_element` from Task 5 if you added one.)

- [ ] **Step 6: Run the test to verify it passes**

Run (from `packages/jet_print`):
```bash
flutter test test/designer/canvas/touch_targets_test.dart
```
Expected: PASS.

- [ ] **Step 7: Gate — goldens byte-identical + analyze**

Run (from the repo root):
```bash
flutter analyze && flutter test packages/jet_print
```
Expected: `No issues found!` and the full library suite green **including every golden** (touch branches never run under goldens, so the PNGs/PDF are unchanged). If any golden differs, STOP — a touch branch is leaking into a non-touch path; fix the gating, do not re-baseline.

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/canvas/design_tunables.dart \
        packages/jet_print/lib/src/designer/canvas/selection_overlay.dart \
        packages/jet_print/lib/src/designer/canvas/design_canvas.dart \
        packages/jet_print/test/designer/canvas/touch_targets_test.dart
git commit -m "feat(e5): finger-sized resize handles + scrollbars under touch

Touch input selects a 44pt hit area for handles/band divider and a 20px
scrollbar; the drawn handle is unchanged so goldens stay byte-identical.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Long-press opens the context menu (the right-click equivalent)

**Files:**
- Modify: `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` (the `ShadContextMenuRegion` at ~line 819)
- Test: `packages/jet_print/test/designer/canvas/long_press_menu_test.dart`

**Interfaces:**
- Consumes: the existing `ShadContextMenuRegion` (`longPressEnabled` param, shadcn_ui 0.54.0) and `_contextMenuItems`. `onTapDown` already selects the element under a touch contact, so the menu acts on the pressed element with no extra pre-select wiring.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/canvas/long_press_menu_test.dart`:

```dart
// Long-press is the touch right-click: it opens the canvas context menu on the
// pressed element (onTapDown already selects it on contact).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// Reuse the canvas test harness used by the other design_canvas tests in this
// directory (pumps a JetReportDesigner / DesignCanvas with one element).
import 'support/canvas_harness.dart';

void main() {
  testWidgets('long-press on an element opens the context menu', (tester) async {
    await pumpDesignCanvas(tester); // harness: one text element on the canvas
    final Finder element = find.byKey(elementHitKey('e1'));
    expect(element, findsOneWidget);

    await tester.longPress(element);
    await tester.pumpAndSettle();

    // The menu surfaces the existing Cut/Copy/Paste/Duplicate/Delete items.
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });
}
```

> **Implementer note:** Use the existing canvas test scaffolding in `packages/jet_print/test/designer/canvas/` (the helpers the paste/selection/band tests already use to pump a canvas with a known element and to address its hit region). Replace `support/canvas_harness.dart`, `pumpDesignCanvas`, `elementHitKey('e1')`, and the menu label strings with the harness + the real `_contextMenuItems` labels (from `JetPrintLocalizations`) those tests use. The assertion that must hold: after `tester.longPress` on an element, the context-menu items are visible.

- [ ] **Step 2: Run it to verify it fails**

Run (from `packages/jet_print`):
```bash
flutter test test/designer/canvas/long_press_menu_test.dart
```
Expected: FAIL — the menu does not open on long-press (default off, or it opens but the test confirms RED first).

- [ ] **Step 3: Enable long-press on the region**

In `design_canvas.dart`, on the `ShadContextMenuRegion` ([design_canvas.dart:819](../../../packages/jet_print/lib/src/designer/canvas/design_canvas.dart#L819)), add `longPressEnabled: true`:

```dart
              child: ShadContextMenuRegion(
                key: const ValueKey<String>(
                    'jet_print.designer.canvas.contextMenu'),
                controller: _contextMenu,
                longPressEnabled: true,
                items: _contextMenuItems(controller, l10n),
```

- [ ] **Step 4: Run the test to verify it passes**

Run (from `packages/jet_print`):
```bash
flutter test test/designer/canvas/long_press_menu_test.dart
```
Expected: PASS.

- [ ] **Step 5: Regression — the desktop canvas suite stays green**

Run (from `packages/jet_print`):
```bash
flutter test test/designer/canvas
```
Expected: PASS — long-press is additive; secondary-click/right-click, tap-select, marquee, and drag-move are unaffected (the region's long-press recognizer does not contend with the canvas tap/pan recognizers, which have no long-press).

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/canvas/design_canvas.dart \
        packages/jet_print/test/designer/canvas/long_press_menu_test.dart
git commit -m "feat(e5): long-press opens the context menu (touch right-click)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase 3 — Phone-width tuning

### Task 8: Author at phone width without the horizontal-scroll fallback

**Files:**
- Modify: `packages/jet_print/lib/src/designer/jet_report_designer.dart:198` (`_minShellWidth`)
- Test: `packages/jet_print/test/designer/phone_width_layout_test.dart`

**Interfaces:**
- Consumes: the existing responsive shell (`_breakpoint = 1024` narrow layout: toolbox + surface + collapsed right rail/overlay; `_minShellWidth` below which the whole shell horizontally scrolls).

At a ~390pt phone width the shell currently lays out at `_minShellWidth = 600` and scrolls horizontally — the page is half off-screen. The narrow layout (toolbox 48 + surface + rail 48 + separators) fits comfortably under ~390pt, so lowering the floor lets a phone author in the real (non-scrolling) narrow layout. Residual cramping beyond this is documented (Task 10), not expanded.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/phone_width_layout_test.dart`:

```dart
// At a phone width the designer lays out in the narrow (rail) layout WITHOUT
// falling back to the 600px horizontal-scroll shell.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
// Reuse the shell test scaffolding used by the existing jet_report_designer
// responsive-layout tests in test/designer/.
import 'support/designer_harness.dart';

void main() {
  testWidgets('a 390pt-wide designer does not horizontally scroll the shell',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDesigner(tester); // harness: a JetReportDesigner with a sample def
    await tester.pumpAndSettle();

    // The horizontal-scroll fallback only mounts below _minShellWidth; at 390pt
    // it must NOT be present (the narrow rail layout absorbs the width instead).
    expect(find.byKey(const ValueKey<String>('jet_print.designer.shellHScroll')),
        findsNothing);
    // The collapsed right-panel rail IS present (narrow layout).
    expect(find.byKey(const ValueKey<String>('jet_print.designer.rightPanel.rail')),
        findsOneWidget);
  });
}
```

> **Implementer note:** Reuse the existing `jet_report_designer` responsive-layout test scaffolding (the tests that exercise the wide/narrow breakpoint). The fallback `SingleChildScrollView` at [jet_report_designer.dart:249](../../../packages/jet_print/lib/src/designer/jet_report_designer.dart#L249) needs a stable key (`'jet_print.designer.shellHScroll'`) — add it in Step 3 so the test can assert its absence. Use the rail key already on `_CollapsedRail` (`_rightPanelRailKey`) for the second assertion; if its string differs, use the real one.

- [ ] **Step 2: Run it to verify it fails**

Run (from `packages/jet_print`):
```bash
flutter test test/designer/phone_width_layout_test.dart
```
Expected: FAIL — at 390pt the `_minShellWidth = 600` fallback scroll mounts.

- [ ] **Step 3: Lower the shell-width floor + key the fallback**

In `jet_report_designer.dart`:

Lower the floor (line 198):
```dart
  /// The shell's minimum usable width. Below it the whole shell is laid out at
  /// this width and scrolls horizontally instead of squeezing its fixed chrome.
  /// Set to a phone-class width so a ~390pt phone authors in the real narrow
  /// (rail) layout rather than a horizontally-scrolling shell (E5 Phase 3).
  static const double _minShellWidth = 360;
```

Key the fallback scroll (line ~249) so it is assertable:
```dart
              return SingleChildScrollView(
                key: const ValueKey<String>('jet_print.designer.shellHScroll'),
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _minShellWidth,
                  height: constraints.maxHeight,
                  child: shell,
                ),
              );
```

- [ ] **Step 4: Run the test to verify it passes**

Run (from `packages/jet_print`):
```bash
flutter test test/designer/phone_width_layout_test.dart
```
Expected: PASS.

- [ ] **Step 5: Gate — full library suite + analyze (goldens unaffected)**

Run (from the repo root):
```bash
flutter analyze && flutter test packages/jet_print
```
Expected: `No issues found!` and green. The wide/narrow layout tests still pass (the breakpoint at 1024 is unchanged; only the sub-360 fallback floor moved).

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/jet_report_designer.dart \
        packages/jet_print/test/designer/phone_width_layout_test.dart
git commit -m "feat(e5): author at phone width in the narrow layout (no h-scroll floor)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Cross-cutting

### Task 9: CI — mobile build jobs

**Files:**
- Modify: `.github/workflows/ci.yml` (add an `ios` job and an `android` job)

**Interfaces:**
- Mirrors the existing `web` job (lines 71-99). Runs once the Actions billing lock clears; E5 acceptance is local.

- [ ] **Step 1: Add the mobile jobs**

Append to `.github/workflows/ci.yml` after the `web:` job:

```yaml
  android:
    name: android (apk)
    runs-on: ubuntu-latest
    steps:
      - name: Check out the repository
        uses: actions/checkout@v4
      - name: Set up Java
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.0
          channel: stable
          cache: true
      - name: Resolve workspace dependencies
        run: flutter pub get
      - name: Build the playground APK
        working-directory: apps/jet_print_playground
        run: flutter build apk --debug

  ios:
    name: ios (no codesign)
    runs-on: macos-latest
    steps:
      - name: Check out the repository
        uses: actions/checkout@v4
      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.0
          channel: stable
          cache: true
      - name: Resolve workspace dependencies
        run: flutter pub get
      - name: Build the playground for iOS
        working-directory: apps/jet_print_playground
        run: flutter build ios --debug --no-codesign
```

- [ ] **Step 2: Validate the workflow is well-formed**

Run (from the repo root):
```bash
actionlint .github/workflows/ci.yml || echo "actionlint not installed — skip (validated on push)"
```
Expected: no errors (or the skip note; the file is YAML-valid by inspection).

- [ ] **Step 3: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add .github/workflows/ci.yml
git commit -m "ci(e5): add iOS + Android playground build jobs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: E5 findings doc + manual smoke record

**Files:**
- Create: `docs/superpowers/specs/2026-06-21-e5-findings.md`

**Interfaces:**
- Mirrors `docs/superpowers/specs/2026-06-21-e4-findings.md`. Captures the Phase-1 harden outcome and the manual sim/emulator smoke (SC-E5-002) — to be filled with the user's confirmation.

- [ ] **Step 1: Write the findings doc**

Create `docs/superpowers/specs/2026-06-21-e5-findings.md` with sections:
- **Build gate** — `flutter build apk --debug` and `flutter build ios --debug --no-codesign` results (Task 1); any transitive blocker found.
- **Output harden** — whether the mobile render/export test (Task 2) was green on the first run or required a localized fix (and what).
- **Print seam** — the documented mobile semantics; whether any iOS `Info.plist` / Android manifest entry was needed.
- **Manual smoke (SC-E5-002)** — a checklist to run on the iOS Simulator + an Android emulator: every playground sample renders; PDF + PNG export (share sheet) work; print opens the native sheet; authoring (select → long-press menu → resize via the enlarged handle → move → zoom buttons) works; the phone-width layout authors without horizontal scroll. Leave the result line marked *pending user confirmation*.
- **Known limitations** — any residual phone-width cramping accepted per the lean Phase-3 decision (tablet is the primary authoring target).

- [ ] **Step 2: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add docs/superpowers/specs/2026-06-21-e5-findings.md
git commit -m "docs(e5): mobile findings + manual smoke record

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] **Full documented suite green** — run from the repo root:
```bash
flutter test packages/jet_print apps/jet_print_playground
```
Expected: all green (the macOS canonical leg, goldens included).

- [ ] **Analyze + format** — run from the repo root:
```bash
flutter analyze && dart format --output=none --set-exit-if-changed .
```
Expected: `No issues found!` and no format diffs on E5's own files.

- [ ] **Goldens byte-identical** — confirm `git status` shows no modified `*.png` / `*.pdf` golden files.

- [ ] **Manual smoke (SC-E5-002)** — run the playground on the iOS Simulator and an Android emulator per the Task-10 checklist; record the result in the findings doc and get user confirmation.

- [ ] **Whole-branch review** — dispatch the final code review (superpowers:requesting-code-review) before finishing the branch.
