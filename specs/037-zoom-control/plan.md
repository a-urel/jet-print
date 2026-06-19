# Designer Zoom Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static `[ – ] [87%] [ + ]` zoom group in the designer top bar with an editable percentage field plus a dropdown menu offering sticky fit modes (Fit width, Fit page), 100%, and preset percentages.

**Architecture:** A new `JetViewFitMode { none, width, page }` enum and a `_viewFitMode` field on the controller hold the sticky fit mode. User-intent methods (`setZoomPercent`, `zoomBy`, `zoomIn`, `zoomOut`, `setViewFitMode`) own the mode; the low-level `setView`/`setViewScale` stay mode-agnostic so the canvas can *apply* a computed fit without clearing it. Fit arithmetic moves to a pure `zoom_math.dart` (`fitWidthScale`, `fitPageScale`); the canvas re-fits when the viewport changes while a fit mode is active. A new `ZoomControl` widget (editable `ShadInput` + `ShadContextMenu`) drives the controller.

**Tech Stack:** Flutter, shadcn_ui (`ShadInput`, `ShadContextMenu`, `ShadContextMenuItem`, `ShadPopoverController`), `flutter gen-l10n` (ARB → `JetPrintLocalizations`), `lucide_icons_flutter`.

## Global Constraints

- Designer / transient-view-state only. No engine, model, serialization, `validate()`, or render/export change. View state (`_viewScale`, `_viewPan`, `_fitRequest`, `_viewFitMode`) is NOT part of the model or undo/redo history.
- Existing goldens MUST stay byte-identical; no `schemaVersion` change.
- Zoom is clamped to `kMinZoom = 0.25` .. `kMaxZoom = 4.0` (25%–400%) — defined in `packages/jet_print/lib/src/designer/canvas/design_tunables.dart`.
- The percentage field MUST keep `ValueKey('jet_print.designer.action.zoomLevel')`.
- Preset set: `50, 75, 100, 150, 200` (percent). 100% doubles as "actual size".
- Default fit mode on load: `JetViewFitMode.width` (sticky — re-fits on resize).
- All user-facing strings localized across `en` / `de` / `tr` ARB files; `flutter analyze` clean; full `jet_print` suite green.
- Run all `flutter` commands from `packages/jet_print` (the package root). Run `git` from the repo root `/Users/ahmeturel/Projects/oss/jet-print`.

---

### Task 1: View fit-mode enum + controller state and methods

Introduces the sticky fit-mode model and the user-intent zoom methods, keeping the low-level setters mode-agnostic.

**Files:**
- Create: `packages/jet_print/lib/src/designer/controller/view_fit_mode.dart`
- Modify: `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (view section, ~lines 1267–1311)
- Modify: `packages/jet_print/lib/jet_print.dart:40-41` (export the enum)
- Test: `packages/jet_print/test/designer/controller/view_fit_mode_test.dart`

**Interfaces:**
- Produces:
  - `enum JetViewFitMode { none, width, page }`
  - `JetViewFitMode get viewFitMode` (default `JetViewFitMode.width`)
  - `void setViewFitMode(JetViewFitMode mode)` — sets mode, increments `fitRequest`, notifies
  - `void setZoomPercent(double percent)` — sets scale to `percent/100` (clamped), mode → `none`
  - `void zoomBy(double factor)` — multiplies scale, mode → `none`
  - `void zoomIn()` / `void zoomOut()` — unchanged steps (×1.25 / ÷1.25), now also mode → `none`
  - `void fitToView()` — retained as an alias for `setViewFitMode(JetViewFitMode.width)`
  - `void setView(double, JetOffset)` / `setViewScale(double)` / `setViewPan(JetOffset)` — UNCHANGED, mode-agnostic

- [ ] **Step 1: Create the enum file**

Create `packages/jet_print/lib/src/designer/controller/view_fit_mode.dart`:

```dart
/// How the designer canvas fits the page into the viewport.
///
/// A fit mode is *sticky*: while it is [width] or [page], the canvas re-fits on
/// every viewport resize. Any manual zoom (the +/- buttons, a typed percentage,
/// a mouse-wheel zoom, or a preset pick) drops back to [none] — a plain
/// percentage. This is transient designer view state; it is not part of the
/// report model or the undo/redo history.
enum JetViewFitMode {
  /// Manual zoom: the scale is whatever the user last set.
  none,

  /// The page width fills the viewport (re-fit on resize).
  width,

  /// The whole page (width and height) fits the viewport (re-fit on resize).
  page,
}
```

- [ ] **Step 2: Write the failing controller tests**

Create `packages/jet_print/test/designer/controller/view_fit_mode_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  late JetReportDesignerController c;

  setUp(() => c = JetReportDesignerController());
  tearDown(() => c.dispose());

  test('the default fit mode is width', () {
    expect(c.viewFitMode, JetViewFitMode.width);
  });

  test('setViewFitMode sets the mode, bumps fitRequest, and notifies', () {
    int notifications = 0;
    c.addListener(() => notifications++);
    final int before = c.fitRequest;

    c.setViewFitMode(JetViewFitMode.page);

    expect(c.viewFitMode, JetViewFitMode.page);
    expect(c.fitRequest, before + 1);
    expect(notifications, greaterThan(0));
  });

  test('setZoomPercent sets the scale (clamped) and clears the fit mode', () {
    c.setViewFitMode(JetViewFitMode.page);

    c.setZoomPercent(130);
    expect(c.viewScale, closeTo(1.30, 1e-9));
    expect(c.viewFitMode, JetViewFitMode.none);

    c.setZoomPercent(1000); // clamps to 400%
    expect(c.viewScale, 4.0);
    c.setZoomPercent(1); // clamps to 25%
    expect(c.viewScale, 0.25);
  });

  test('zoomIn, zoomOut, and zoomBy clear the fit mode', () {
    c.setViewFitMode(JetViewFitMode.width);
    c.zoomIn();
    expect(c.viewFitMode, JetViewFitMode.none);

    c.setViewFitMode(JetViewFitMode.page);
    c.zoomOut();
    expect(c.viewFitMode, JetViewFitMode.none);

    c.setViewFitMode(JetViewFitMode.width);
    c.zoomBy(1.1);
    expect(c.viewFitMode, JetViewFitMode.none);
  });

  test('zoomBy multiplies the current scale', () {
    c.setZoomPercent(100); // 1.0
    c.zoomBy(2.0);
    expect(c.viewScale, 2.0);
  });

  test('the low-level setViewScale leaves the fit mode untouched', () {
    c.setViewFitMode(JetViewFitMode.width);
    c.setViewScale(2.0); // the canvas applies a computed fit this way
    expect(c.viewFitMode, JetViewFitMode.width);
    expect(c.viewScale, 2.0);
  });

  test('clearing the mode notifies even when the scale does not change', () {
    c.setZoomPercent(100); // scale 1.0, mode none
    c.setViewFitMode(JetViewFitMode.width); // mode width (scale unchanged at 1.0)
    int notifications = 0;
    c.addListener(() => notifications++);

    c.setZoomPercent(100); // same scale (1.0) but must clear width -> none

    expect(c.viewFitMode, JetViewFitMode.none);
    expect(notifications, greaterThan(0));
  });

  test('fitToView is an alias for fit-width', () {
    final int before = c.fitRequest;
    c.setZoomPercent(50); // mode none
    c.fitToView();
    expect(c.viewFitMode, JetViewFitMode.width);
    expect(c.fitRequest, before + 1);
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/designer/controller/view_fit_mode_test.dart`
Expected: FAIL — `viewFitMode`, `setViewFitMode`, `setZoomPercent`, `zoomBy`, and `JetViewFitMode` are undefined.

- [ ] **Step 4: Export the enum from the public barrel**

In `packages/jet_print/lib/jet_print.dart`, immediately after the existing controller export (lines 40–41):

```dart
export 'src/designer/controller/jet_report_designer_controller.dart'
    show JetReportDesignerController;
export 'src/designer/controller/view_fit_mode.dart' show JetViewFitMode;
```

- [ ] **Step 5: Wire the fit mode into the controller**

In `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`:

First add the import next to the other controller imports near the top of the file:

```dart
import 'view_fit_mode.dart';
```

Then replace the view section (currently lines ~1271–1311) with:

```dart
  double _viewScale = 1.0;
  JetOffset _viewPan = const JetOffset(0, 0);
  int _fitRequest = 0;
  JetViewFitMode _viewFitMode = JetViewFitMode.width;

  /// The current zoom factor (1.0 == 100%), clamped to [kMinZoom]..[kMaxZoom].
  double get viewScale => _viewScale;

  /// The current pan offset, in screen pixels.
  JetOffset get viewPan => _viewPan;

  /// Increments whenever a fit is requested; the canvas recomputes the fit (it
  /// owns the viewport) and calls [setViewScale].
  int get fitRequest => _fitRequest;

  /// The active sticky fit mode. While [JetViewFitMode.width]/[JetViewFitMode.page]
  /// the canvas re-fits on viewport resize; manual zoom clears it to
  /// [JetViewFitMode.none].
  JetViewFitMode get viewFitMode => _viewFitMode;

  /// Sets the zoom [scale] (clamped) and [pan] together. Mode-agnostic on
  /// purpose: the canvas applies a computed fit through here without clearing
  /// the active fit mode.
  void setView(double scale, JetOffset pan) {
    final double clamped =
        scale < kMinZoom ? kMinZoom : (scale > kMaxZoom ? kMaxZoom : scale);
    if (clamped == _viewScale && pan == _viewPan) return;
    _viewScale = clamped;
    _viewPan = pan;
    notifyListeners();
  }

  /// Sets just the zoom factor (keeping the current pan). Mode-agnostic.
  void setViewScale(double scale) => setView(scale, _viewPan);

  /// Sets just the pan offset (keeping the current zoom).
  void setViewPan(JetOffset pan) => setView(_viewScale, pan);

  /// Runs a manual-zoom [apply], clearing the fit mode. If [apply] does not
  /// change the scale (e.g. already at the clamp, or the same value re-entered),
  /// still notifies so a cleared fit mode reaches listeners.
  void _manualZoom(void Function() apply) {
    final bool modeChanged = _viewFitMode != JetViewFitMode.none;
    _viewFitMode = JetViewFitMode.none;
    final double before = _viewScale;
    apply();
    if (modeChanged && _viewScale == before) notifyListeners();
  }

  /// Zooms in one step (×1.25); manual zoom, so the fit mode is cleared.
  void zoomIn() => _manualZoom(() => setViewScale(_viewScale * 1.25));

  /// Zooms out one step (÷1.25); manual zoom, so the fit mode is cleared.
  void zoomOut() => _manualZoom(() => setViewScale(_viewScale / 1.25));

  /// Sets the zoom to [percent] % (e.g. 130 → 1.30), clamped; clears the fit
  /// mode. Used by the editable zoom field and the preset menu rows.
  void setZoomPercent(double percent) =>
      _manualZoom(() => setViewScale(percent / 100));

  /// Multiplies the zoom by [factor] (mouse-wheel zoom); clears the fit mode.
  void zoomBy(double factor) =>
      _manualZoom(() => setViewScale(_viewScale * factor));

  /// Selects a sticky fit [mode] and requests a re-fit (fulfilled by the
  /// canvas, which owns the viewport).
  void setViewFitMode(JetViewFitMode mode) {
    _viewFitMode = mode;
    _fitRequest++;
    notifyListeners();
  }

  /// Back-compat alias: fit the page to the viewport width.
  void fitToView() => setViewFitMode(JetViewFitMode.width);
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/designer/controller/view_fit_mode_test.dart`
Expected: PASS (all tests green).

- [ ] **Step 7: Confirm no regression in the existing zoom/pan tests**

Run: `cd packages/jet_print && flutter test test/designer/canvas/zoom_pan_test.dart`
Expected: PASS — `setViewScale` clamping, scale rendering, and `fitToView` recentering all still work.

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/controller/view_fit_mode.dart \
        packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart \
        packages/jet_print/lib/jet_print.dart \
        packages/jet_print/test/designer/controller/view_fit_mode_test.dart
git commit -m "feat(designer): sticky view fit mode + percent/zoomBy controller methods"
```

---

### Task 2: Pure fit-math helpers (`zoom_math.dart`)

Extracts fit-to-width arithmetic from the canvas and adds fit-to-page, both pure and unit-testable.

**Files:**
- Create: `packages/jet_print/lib/src/designer/canvas/zoom_math.dart`
- Test: `packages/jet_print/test/designer/canvas/zoom_math_test.dart`

**Interfaces:**
- Consumes: `JetSize` (`../../domain/geometry.dart`), `kMinZoom`/`kMaxZoom` (`design_tunables.dart`), `Size` (`package:flutter/widgets.dart`).
- Produces:
  - `double fitWidthScale(JetSize content, Size viewport, double padding)`
  - `double fitPageScale(JetSize content, Size viewport, double padding)`

- [ ] **Step 1: Write the failing tests**

Create `packages/jet_print/test/designer/canvas/zoom_math_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/canvas/zoom_math.dart';
import 'package:jet_print/src/domain/geometry.dart';

void main() {
  const double padding = 32;

  group('fitWidthScale', () {
    test('scales the page width into the usable viewport width', () {
      // usable = 200 - 2*0 ... use padding 0 for an exact ratio
      final double s = fitWidthScale(
          const JetSize(100, 999), const Size(232, 500), padding);
      // usable width = 232 - 64 = 168; 168 / 100 = 1.68
      expect(s, closeTo(1.68, 1e-9));
    });

    test('clamps up to kMinZoom for an enormous page', () {
      final double s = fitWidthScale(
          const JetSize(100000, 100), const Size(500, 500), padding);
      expect(s, 0.25);
    });

    test('clamps down to kMaxZoom for a tiny page', () {
      final double s =
          fitWidthScale(const JetSize(1, 1), const Size(500, 500), padding);
      expect(s, 4.0);
    });

    test('returns 1.0 when the usable width is non-positive', () {
      expect(fitWidthScale(const JetSize(100, 100), const Size(10, 500), padding),
          1.0);
    });
  });

  group('fitPageScale', () {
    test('uses the smaller of the width and height ratios (height-bound)', () {
      // usable W = 264-64 = 200 -> 200/100 = 2.0; usable H = 164-64 = 100 ->
      // 100/100 = 1.0; min = 1.0
      final double s = fitPageScale(
          const JetSize(100, 100), const Size(264, 164), padding);
      expect(s, closeTo(1.0, 1e-9));
    });

    test('uses the smaller of the width and height ratios (width-bound)', () {
      // usable W = 164-64 = 100 -> 1.0; usable H = 264-64 = 200 -> 2.0; min 1.0
      final double s = fitPageScale(
          const JetSize(100, 100), const Size(164, 264), padding);
      expect(s, closeTo(1.0, 1e-9));
    });

    test('returns 1.0 when a usable dimension is non-positive', () {
      expect(
          fitPageScale(const JetSize(100, 100), const Size(10, 500), padding),
          1.0);
      expect(
          fitPageScale(const JetSize(100, 100), const Size(500, 10), padding),
          1.0);
    });

    test('clamps to the allowed zoom range', () {
      expect(
          fitPageScale(const JetSize(1, 1), const Size(500, 500), padding), 4.0);
      expect(
          fitPageScale(
              const JetSize(100000, 100000), const Size(500, 500), padding),
          0.25);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/designer/canvas/zoom_math_test.dart`
Expected: FAIL — `zoom_math.dart` does not exist.

- [ ] **Step 3: Implement the helpers**

Create `packages/jet_print/lib/src/designer/canvas/zoom_math.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../domain/geometry.dart';
import 'design_tunables.dart';

/// The zoom that fits the page width into [viewport] (less [padding] on each
/// side), clamped to [kMinZoom]..[kMaxZoom]. Centering and vertical reach are
/// handled by the scroll viewport, so only the scale is returned.
///
/// Returns `1.0` when the usable width (or the content width) is non-positive,
/// so the caller never applies `0`, `NaN`, or `Infinity`.
double fitWidthScale(JetSize content, Size viewport, double padding) {
  final double usable = viewport.width - 2 * padding;
  if (usable <= 0 || content.width <= 0) return 1.0;
  return (usable / content.width).clamp(kMinZoom, kMaxZoom);
}

/// The zoom that fits the whole page (width *and* height) into [viewport] (less
/// [padding] on each side), clamped to [kMinZoom]..[kMaxZoom]. The limiting
/// dimension wins (the smaller of the two ratios).
///
/// Returns `1.0` when any usable dimension (or content dimension) is
/// non-positive.
double fitPageScale(JetSize content, Size viewport, double padding) {
  final double usableW = viewport.width - 2 * padding;
  final double usableH = viewport.height - 2 * padding;
  if (usableW <= 0 ||
      usableH <= 0 ||
      content.width <= 0 ||
      content.height <= 0) {
    return 1.0;
  }
  final double raw =
      math.min(usableW / content.width, usableH / content.height);
  return raw.clamp(kMinZoom, kMaxZoom);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/designer/canvas/zoom_math_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/canvas/zoom_math.dart \
        packages/jet_print/test/designer/canvas/zoom_math_test.dart
git commit -m "feat(designer): pure fitWidthScale/fitPageScale helpers"
```

---

### Task 3: Canvas — use the helpers, sticky re-fit on resize, wheel via zoomBy

Wires the controller's fit mode into the canvas: the canvas picks the fit formula by mode, re-fits when the viewport changes while a fit mode is active, and routes Ctrl/⌘+wheel zoom through `zoomBy` (so it clears the mode).

**Files:**
- Modify: `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` (imports; `_fitScale` at ~281–288; pointer-signal at ~442–456; fit-apply block at ~722–734; add `_lastFitViewport` field near ~118–119)
- Test: `packages/jet_print/test/designer/canvas/sticky_fit_test.dart`

**Interfaces:**
- Consumes: `fitWidthScale`/`fitPageScale` (Task 2), `controller.viewFitMode`/`fitRequest`/`setViewScale`/`zoomBy` (Task 1).
- Produces: no new public API (internal canvas behavior).

- [ ] **Step 1: Write the failing widget tests**

Create `packages/jet_print/test/designer/canvas/sticky_fit_test.dart`:

```dart
// Sticky fit: while a fit mode is active the canvas re-fits when the viewport
// resizes; with no fit mode, a manual zoom survives a resize.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

void main() {
  testWidgets('fit-width re-fits when the viewport narrows (sticky)',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    // Default mode is fit-width; the canvas fits on load.
    expect(controller.viewFitMode, JetViewFitMode.width);
    await tester.pumpAndSettle();
    final double wide = controller.viewScale;

    // Narrow the window: fit-width must shrink the scale to keep fitting.
    tester.view.physicalSize = const Size(700, 900);
    await tester.pumpAndSettle();
    final double narrow = controller.viewScale;

    expect(narrow, lessThan(wide),
        reason: 'a narrower viewport must re-fit to a smaller width scale');
  });

  testWidgets('a manual zoom survives a resize (no fit mode)',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    await tester.pumpAndSettle();

    controller.setZoomPercent(150); // manual -> mode none
    await tester.pumpAndSettle();
    expect(controller.viewFitMode, JetViewFitMode.none);
    expect(controller.viewScale, 1.5);

    tester.view.physicalSize = const Size(700, 900);
    await tester.pumpAndSettle();

    expect(controller.viewScale, 1.5,
        reason: 'with no fit mode, a resize must not change the manual zoom');
  });
}
```

If `pumpDesignerWith` constrains the designer to a fixed-size box (so `tester.view.physicalSize` does not drive the canvas viewport), the resize will not change the fit. In that case, drive the resize the way the harness allows (e.g. wrap the returned widget in a resizable `SizedBox` you re-pump, or use the harness's own sizing hook) — the assertion (`narrow < wide` for fit-width; unchanged scale for `none`) stays the same. Check `packages/jet_print/test/designer/support/designer_harness.dart` first.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/designer/canvas/sticky_fit_test.dart`
Expected: FAIL — today the canvas does not re-fit on resize, so `narrow` equals `wide`.

- [ ] **Step 3: Add the zoom_math import**

In `packages/jet_print/lib/src/designer/canvas/design_canvas.dart`, add to the import group (alongside `import 'design_tunables.dart';` at line 39):

```dart
import 'zoom_math.dart';
```

- [ ] **Step 4: Add the last-fitted-viewport field**

Near the other view-state fields (after `int _appliedFitRequest = 0;` at line 119), add:

```dart
  /// The viewport size at the last applied fit; lets a steady viewport avoid
  /// re-fitting every frame while a sticky fit mode is active.
  Size? _lastFitViewport;
```

- [ ] **Step 5: Remove the private `_fitScale` method**

Delete the `_fitScale` method (lines ~281–288):

```dart
  /// The zoom that fits the page width into [viewport] (with padding), clamped to
  /// the allowed zoom range. Centering + vertical reach are handled by the scroll
  /// viewport, so this only needs the scale.
  double _fitScale(JetSize content, Size viewport) {
    final double usable = viewport.width - 2 * _viewportPadding;
    final double raw = usable <= 0 ? 1.0 : usable / content.width;
    return raw.clamp(kMinZoom, kMaxZoom);
  }
```

(The logic now lives in `fitWidthScale`.)

- [ ] **Step 6: Replace the fit-apply block**

Replace the current block (lines ~722–734):

```dart
            // Apply the initial fit-to-width once, and again whenever a fit is
            // requested — off the build path (it mutates the controller + scroll).
            if (!_viewInitialized ||
                controller.fitRequest != _appliedFitRequest) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _viewInitialized = true;
                _appliedFitRequest = controller.fitRequest;
                controller.setViewScale(_fitScale(layout.size, viewport));
                if (_vScroll.hasClients) _vScroll.jumpTo(0);
                if (_hScroll.hasClients) _hScroll.jumpTo(0);
              });
            }
```

with:

```dart
            // Apply a fit (1) on first load, (2) whenever a fit is explicitly
            // requested, or (3) when the viewport changes while a sticky fit
            // mode is active — all off the build path (it mutates the controller
            // + scroll). The chosen formula follows the controller's fit mode.
            final bool fitModeActive =
                controller.viewFitMode != JetViewFitMode.none;
            final bool viewportChanged = _lastFitViewport != viewport;
            if (!_viewInitialized ||
                controller.fitRequest != _appliedFitRequest ||
                (fitModeActive && viewportChanged)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _viewInitialized = true;
                _appliedFitRequest = controller.fitRequest;
                _lastFitViewport = viewport;
                final double fitted =
                    controller.viewFitMode == JetViewFitMode.page
                        ? fitPageScale(layout.size, viewport, _viewportPadding)
                        : fitWidthScale(layout.size, viewport, _viewportPadding);
                controller.setViewScale(fitted);
                if (_vScroll.hasClients) _vScroll.jumpTo(0);
                if (_hScroll.hasClients) _hScroll.jumpTo(0);
              });
            }
```

Note: `controller.setViewScale` is mode-agnostic (Task 1), so applying the fit does not clear the active fit mode — that is what keeps it sticky.

- [ ] **Step 7: Route the mouse-wheel zoom through `zoomBy`**

In `_handlePointerSignal` (line ~450), replace:

```dart
      if (zoom) {
        controller.setViewScale(
            controller.viewScale * (event.scrollDelta.dy > 0 ? 0.9 : 1.1));
      } else {
```

with:

```dart
      if (zoom) {
        controller.zoomBy(event.scrollDelta.dy > 0 ? 0.9 : 1.1);
      } else {
```

- [ ] **Step 8: Run the new tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/designer/canvas/sticky_fit_test.dart`
Expected: PASS — narrowing the viewport re-fits while in fit-width; a manual zoom survives a resize.

- [ ] **Step 9: Run the full canvas test directory for regressions**

Run: `cd packages/jet_print && flutter test test/designer/canvas/`
Expected: PASS — existing fit/zoom/ruler/grid/scroll tests still green (no `_fitScale` references remain; `fitToView` still recenters).

- [ ] **Step 10: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/canvas/design_canvas.dart \
        packages/jet_print/test/designer/canvas/sticky_fit_test.dart
git commit -m "feat(designer): canvas sticky re-fit by mode; wheel zoom via zoomBy"
```

---

### Task 4: Localization strings

Adds the new chrome strings and removes the now-unused fit tooltip, then regenerates `JetPrintLocalizations`.

**Files:**
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb` (lines ~61–63: the `actionZoomFitTooltip` block)
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_de.arb` (line ~19)
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_tr.arb` (line ~19)
- Regenerate: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations*.dart` (via `flutter gen-l10n`)
- Test: `packages/jet_print/test/designer/l10n_zoom_keys_test.dart`

**Interfaces:**
- Produces (generated getters on `JetPrintLocalizations`): `actionZoomFieldTooltip`, `menuZoomFitWidth`, `menuZoomFitPage`. Removes `actionZoomFitTooltip`.

- [ ] **Step 1: Write the failing key-resolution test**

Create `packages/jet_print/test/designer/l10n_zoom_keys_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/l10n/jet_print_localizations.dart';

void main() {
  for (final Locale locale in <Locale>[
    const Locale('en'),
    const Locale('de'),
    const Locale('tr'),
  ]) {
    testWidgets('zoom chrome strings resolve for $locale',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        Localizations(
          locale: locale,
          delegates: JetPrintLocalizations.localizationsDelegates,
          child: Builder(
            builder: (BuildContext context) {
              final JetPrintLocalizations l10n =
                  JetPrintLocalizations.of(context);
              expect(l10n.actionZoomFieldTooltip, isNotEmpty);
              expect(l10n.menuZoomFitWidth, isNotEmpty);
              expect(l10n.menuZoomFitPage, isNotEmpty);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/l10n_zoom_keys_test.dart`
Expected: FAIL — the new getters do not exist on `JetPrintLocalizations`.

- [ ] **Step 3: Edit the English ARB (template)**

In `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, replace the `actionZoomFitTooltip` entry (lines ~61–63 plus its `@` block):

```json
  "actionZoomFitTooltip": "Fit to width",
  "@actionZoomFitTooltip": {
    "description": "Tooltip for the zoom-level label, which fits the page to the viewport width when tapped."
  },
```

with:

```json
  "actionZoomFieldTooltip": "Zoom level — type a percentage, or pick a preset or fit mode",
  "@actionZoomFieldTooltip": {
    "description": "Tooltip for the editable zoom-level field and its dropdown caret in the top-bar zoom group."
  },
  "menuZoomFitWidth": "Fit width",
  "@menuZoomFitWidth": {
    "description": "Zoom dropdown row: scale so the page width fills the viewport (sticky)."
  },
  "menuZoomFitPage": "Fit page",
  "@menuZoomFitPage": {
    "description": "Zoom dropdown row: scale so the whole page fits the viewport (sticky)."
  },
```

- [ ] **Step 4: Edit the German ARB**

In `packages/jet_print/lib/src/designer/l10n/jet_print_de.arb`, replace the line:

```json
  "actionZoomFitTooltip": "An Breite anpassen",
```

with:

```json
  "actionZoomFieldTooltip": "Zoomstufe – Prozentwert eingeben oder Voreinstellung bzw. Anpassung wählen",
  "menuZoomFitWidth": "An Breite anpassen",
  "menuZoomFitPage": "An Seite anpassen",
```

- [ ] **Step 5: Edit the Turkish ARB**

In `packages/jet_print/lib/src/designer/l10n/jet_print_tr.arb`, replace the line:

```json
  "actionZoomFitTooltip": "Genişliğe sığdır",
```

with:

```json
  "actionZoomFieldTooltip": "Yakınlaştırma düzeyi — yüzde girin ya da hazır değer veya sığdırma seçin",
  "menuZoomFitWidth": "Genişliğe sığdır",
  "menuZoomFitPage": "Sayfaya sığdır",
```

- [ ] **Step 6: Regenerate the localizations**

Run: `cd packages/jet_print && flutter gen-l10n`
Expected: regenerates `lib/src/designer/l10n/jet_print_localizations.dart` (and `_en`/`_de`/`_tr`) with the three new getters and without `actionZoomFitTooltip`. No errors.

- [ ] **Step 7: Run the key-resolution test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/l10n_zoom_keys_test.dart`
Expected: PASS for en/de/tr.

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/l10n/
git add packages/jet_print/test/designer/l10n_zoom_keys_test.dart
git commit -m "feat(designer): l10n for zoom field tooltip + fit-mode menu rows"
```

---

### Task 5: The `ZoomControl` widget

The editable percentage field plus the dropdown menu (fit modes + presets), driven by callbacks so it is testable in isolation.

**Files:**
- Create: `packages/jet_print/lib/src/designer/layout/zoom_control.dart`
- Test: `packages/jet_print/test/designer/layout/zoom_control_test.dart`

**Interfaces:**
- Consumes: `JetViewFitMode` (Task 1), `kMinZoom`/`kMaxZoom` (`../canvas/design_tunables.dart`), `JetPrintLocalizations` (Task 4), shadcn_ui, lucide icons.
- Produces:
  - `class ZoomControl extends StatefulWidget` with named params:
    - `double viewScale`
    - `JetViewFitMode fitMode`
    - `ValueChanged<double> onPercent` (receives a percent, e.g. `130`)
    - `ValueChanged<JetViewFitMode> onFit`
  - Stable keys: field `ValueKey('jet_print.designer.action.zoomLevel')`, caret `ValueKey('jet_print.designer.zoom.menuToggle')`, rows `...zoom.fitWidth`, `...zoom.fitPage`, `...zoom.preset.<n>`.

- [ ] **Step 1: Write the failing widget tests**

Create `packages/jet_print/test/designer/layout/zoom_control_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/l10n/jet_print_localizations.dart';
import 'package:jet_print/src/designer/layout/zoom_control.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const Key _field = ValueKey<String>('jet_print.designer.action.zoomLevel');
const Key _caret = ValueKey<String>('jet_print.designer.zoom.menuToggle');
const Key _fitPage = ValueKey<String>('jet_print.designer.zoom.fitPage');
const Key _preset200 = ValueKey<String>('jet_print.designer.zoom.preset.200');

Future<void> _pump(
  WidgetTester tester, {
  required double viewScale,
  required JetViewFitMode fitMode,
  required ValueChanged<double> onPercent,
  required ValueChanged<JetViewFitMode> onFit,
}) {
  return tester.pumpWidget(
    ShadApp(
      localizationsDelegates: JetPrintLocalizations.localizationsDelegates,
      supportedLocales: JetPrintLocalizations.supportedLocales,
      home: Center(
        child: ZoomControl(
          viewScale: viewScale,
          fitMode: fitMode,
          onPercent: onPercent,
          onFit: onFit,
        ),
      ),
    ),
  );
}

String _fieldText(WidgetTester tester) =>
    tester.widget<ShadInput>(find.byKey(_field)).controller!.text;

void main() {
  testWidgets('shows the current scale as a rounded percentage',
      (WidgetTester tester) async {
    await _pump(tester,
        viewScale: 0.87,
        fitMode: JetViewFitMode.width,
        onPercent: (_) {},
        onFit: (_) {});
    expect(_fieldText(tester), '87%');
  });

  testWidgets('typing a value and submitting reports the percent',
      (WidgetTester tester) async {
    double? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (double p) => got = p,
        onFit: (_) {});

    await tester.enterText(find.byKey(_field), '130');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(got, 130);
  });

  testWidgets('an invalid entry reverts without reporting',
      (WidgetTester tester) async {
    double? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (double p) => got = p,
        onFit: (_) {});

    await tester.enterText(find.byKey(_field), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(got, isNull);
    expect(_fieldText(tester), '100%'); // reverted to the current value
  });

  testWidgets('opening the menu and picking Fit page reports the fit mode',
      (WidgetTester tester) async {
    JetViewFitMode? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (JetViewFitMode m) => got = m);

    await tester.tap(find.byKey(_caret));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_fitPage));
    await tester.pumpAndSettle();

    expect(got, JetViewFitMode.page);
  });

  testWidgets('picking a preset reports the percent',
      (WidgetTester tester) async {
    double? got;
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (double p) => got = p,
        onFit: (_) {});

    await tester.tap(find.byKey(_caret));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_preset200));
    await tester.pumpAndSettle();

    expect(got, 200);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/designer/layout/zoom_control_test.dart`
Expected: FAIL — `zoom_control.dart` does not exist.

- [ ] **Step 3: Implement the widget**

Create `packages/jet_print/lib/src/designer/layout/zoom_control.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../canvas/design_tunables.dart';
import '../controller/view_fit_mode.dart';
import '../l10n/jet_print_localizations.dart';

/// The preset zoom percentages offered in the dropdown. 100% doubles as the
/// "actual size" anchor.
const List<int> _kZoomPresets = <int>[50, 75, 100, 150, 200];

/// The editable zoom field + dropdown menu in the designer top bar.
///
/// The field always shows the live computed percentage and stays editable; the
/// active sticky fit mode (if any) is shown only by a checkmark in the menu.
/// Pure and callback-driven so it can be tested in isolation: the parent passes
/// the current [viewScale]/[fitMode] and receives intent via [onPercent] (a
/// percent value, e.g. 130) and [onFit].
class ZoomControl extends StatefulWidget {
  const ZoomControl({
    super.key,
    required this.viewScale,
    required this.fitMode,
    required this.onPercent,
    required this.onFit,
  });

  final double viewScale;
  final JetViewFitMode fitMode;
  final ValueChanged<double> onPercent;
  final ValueChanged<JetViewFitMode> onFit;

  @override
  State<ZoomControl> createState() => _ZoomControlState();
}

class _ZoomControlState extends State<ZoomControl> {
  late final TextEditingController _text =
      TextEditingController(text: _format(widget.viewScale));
  final FocusNode _focus = FocusNode();
  final ShadPopoverController _menu = ShadPopoverController();

  static String _format(double scale) => '${(scale * 100).round()}%';

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(ZoomControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reflect controller-driven scale changes, but never clobber active typing.
    if (!_focus.hasFocus && widget.viewScale != oldWidget.viewScale) {
      _text.text = _format(widget.viewScale);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _text.dispose();
    _menu.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final String raw = _text.text.replaceAll('%', '').trim();
    final double? parsed = double.tryParse(raw);
    if (parsed == null) {
      _text.text = _format(widget.viewScale); // reject: revert to current
      return;
    }
    // Show the value the controller will land on (it clamps identically), so a
    // later blur re-commit does not drift.
    final double clamped = (parsed / 100).clamp(kMinZoom, kMaxZoom);
    _text.text = _format(clamped);
    widget.onPercent(parsed);
  }

  void _pickFit(JetViewFitMode mode) {
    _menu.hide();
    widget.onFit(mode);
  }

  void _pickPreset(int percent) {
    _menu.hide();
    widget.onPercent(percent.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    final int current = (widget.viewScale * 100).round();

    // The checkmark uses the established visible-when-selected pattern (the
    // glyph is always present but coloured as the background when unselected).
    Widget check(bool on) => Icon(
          LucideIcons.check,
          size: 16,
          color: on ? colors.foreground : colors.background,
        );

    return ShadTooltip(
      builder: (BuildContext context) => Text(l10n.actionZoomFieldTooltip),
      child: ShadContextMenu(
        controller: _menu,
        items: <Widget>[
          ShadContextMenuItem(
            key: const ValueKey<String>('jet_print.designer.zoom.fitWidth'),
            leading: check(widget.fitMode == JetViewFitMode.width),
            onPressed: () => _pickFit(JetViewFitMode.width),
            child: Text(l10n.menuZoomFitWidth),
          ),
          ShadContextMenuItem(
            key: const ValueKey<String>('jet_print.designer.zoom.fitPage'),
            leading: check(widget.fitMode == JetViewFitMode.page),
            onPressed: () => _pickFit(JetViewFitMode.page),
            child: Text(l10n.menuZoomFitPage),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: colors.border,
          ),
          for (final int p in _kZoomPresets)
            ShadContextMenuItem(
              key: ValueKey<String>('jet_print.designer.zoom.preset.$p'),
              leading: check(
                  widget.fitMode == JetViewFitMode.none && current == p),
              onPressed: () => _pickPreset(p),
              child: Text('$p%'),
            ),
        ],
        child: SizedBox(
          width: 92,
          child: ShadInput(
            key: const ValueKey<String>('jet_print.designer.action.zoomLevel'),
            controller: _text,
            focusNode: _focus,
            onSubmitted: (_) => _commit(),
            trailing: GestureDetector(
              key: const ValueKey<String>('jet_print.designer.zoom.menuToggle'),
              behavior: HitTestBehavior.opaque,
              onTap: _menu.toggle,
              child: const Icon(LucideIcons.chevronDown, size: 14),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/designer/layout/zoom_control_test.dart`
Expected: PASS. If `ShadInput` does not expose `controller` as a public field in the pinned shadcn_ui version, adjust `_fieldText` in the test to read the value via `find.descendant(of: find.byKey(_field), matching: find.byType(EditableText))` and `.controller.text`; do not change the widget.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/zoom_control.dart \
        packages/jet_print/test/designer/layout/zoom_control_test.dart
git commit -m "feat(designer): ZoomControl widget (editable % + fit/preset menu)"
```

---

### Task 6: Wire `ZoomControl` into the top bar + fix the top-bar test

Replaces the static percentage label with `ZoomControl` and updates the existing top-bar test that read the zoom level as a `Text`.

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart` (imports; zoom group at lines ~168–184)
- Modify: `packages/jet_print/test/designer/top_bar_test.dart` (lines ~128–131: the `pct()` helper)

**Interfaces:**
- Consumes: `ZoomControl` (Task 5), `JetViewFitMode` (Task 1), `controller.viewScale`/`viewFitMode`/`setZoomPercent`/`setViewFitMode` (Task 1).

- [ ] **Step 1: Update the top-bar test's reader to match the new widget (failing)**

In `packages/jet_print/test/designer/top_bar_test.dart`, add the shadcn import near the top (with the other imports):

```dart
import 'package:shadcn_ui/shadcn_ui.dart';
```

Then replace the `pct()` helper (lines ~130–131):

```dart
      int pct() =>
          int.parse(tester.widget<Text>(zoomLevel).data!.replaceAll('%', ''));
```

with:

```dart
      int pct() => int.parse(tester
          .widget<ShadInput>(zoomLevel)
          .controller!
          .text
          .replaceAll('%', ''));
```

- [ ] **Step 2: Run the top-bar test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/top_bar_test.dart`
Expected: FAIL — the zoom level is still a `Text` (no `ShadInput` with that key yet), so the cast/finder fails.

- [ ] **Step 3: Import the new widget and enum in the top bar**

In `packages/jet_print/lib/src/designer/layout/designer_top_bar.dart`, add to the imports:

```dart
import '../controller/view_fit_mode.dart';
import 'zoom_control.dart';
```

- [ ] **Step 4: Replace the static percentage label with `ZoomControl`**

Replace the zoom-level block (lines ~168–184):

```dart
      ShadTooltip(
        builder: (BuildContext context) => Text(l10n.actionZoomFitTooltip),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: controller.fitToView,
          child: SizedBox(
            width: 46,
            child: Text(
              '${(controller.viewScale * 100).round()}%',
              key:
                  const ValueKey<String>('jet_print.designer.action.zoomLevel'),
              textAlign: TextAlign.center,
              style: theme.textTheme.small.copyWith(color: colors.foreground),
            ),
          ),
        ),
      ),
```

with:

```dart
      ZoomControl(
        viewScale: controller.viewScale,
        fitMode: controller.viewFitMode,
        onPercent: controller.setZoomPercent,
        onFit: controller.setViewFitMode,
      ),
```

If `theme` or `colors` become unused in this build method after the change, leave them — they are used by the surrounding icon buttons/dividers. If `flutter analyze` (Step 7) flags an unused local, remove only that local.

- [ ] **Step 5: Run the top-bar test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/top_bar_test.dart`
Expected: PASS — the zoom level now resolves as a `ShadInput`; the zoomIn/zoomOut interactive test still reads the percentage and sees it increase/decrease.

- [ ] **Step 6: Verify the cross-panel sync test still passes**

Run: `cd packages/jet_print && flutter test test/designer/panels/cross_panel_sync_test.dart`
Expected: PASS — `controller.fitToView()` still recenters (now via the fit-width alias).

- [ ] **Step 7: Analyze and run the full suite**

Run: `cd packages/jet_print && flutter analyze`
Expected: No issues (no remaining `actionZoomFitTooltip` or `_fitScale` references).

Run: `cd packages/jet_print && flutter test`
Expected: PASS — full suite green; goldens byte-identical (no engine/output change).

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/designer_top_bar.dart \
        packages/jet_print/test/designer/top_bar_test.dart
git commit -m "feat(designer): use ZoomControl in the top bar zoom group"
```

---

## Manual verification (after all tasks)

Run the playground designer and confirm in the GUI:
1. The zoom group shows an editable field with a caret; the field shows a live `%`.
2. Typing `130` + Enter zooms to 130%; typing `1000` clamps to 400%; typing junk reverts.
3. The dropdown lists Fit width, Fit page, and 50/75/100/150/200%, with a checkmark on the active one.
4. Fit page fits the whole page; resizing the window keeps it fit (sticky); the same for Fit width.
5. Clicking `+`/`–`, Ctrl/⌘-scrolling, or picking a preset removes the checkmark (mode → manual).
6. On load the page is fit to width (as before), and now re-fits when panels/window resize.

## Notes for the implementer

- **Why the low-level setters stay mode-agnostic (Task 1):** the canvas applies a *computed* fit via `setViewScale`. If that cleared the fit mode, sticky fit would clear itself on the very first apply. Only the named user-intent methods clear the mode.
- **Why `_manualZoom` may notify without a scale change:** at the clamp boundary (or when re-entering the same %), `setView` no-ops, but the fit mode still changed and listeners (the menu checkmark) must update.
- **shadcn_ui API drift:** `ShadInput.controller`, `ShadContextMenu(controller:, items:, child:)`, `ShadContextMenuItem(leading:, onPressed:, child:)`, and `ShadPopoverController.toggle/hide` follow the existing usages in `outline_panel.dart` and `properties_panel.dart`. If a signature differs in the pinned version, match those files rather than this plan verbatim.
