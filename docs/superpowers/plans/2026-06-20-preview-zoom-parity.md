# Preview Zoom Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the report preview's toolbar use the *same* zoom section as the designer — the shared `ZoomControl` (editable % field + Fit Width / Fit Page / preset dropdown) flanked by zoom-out / zoom-in buttons — with matching absolute-scale semantics.

**Architecture:** The fit math (`fitWidthScale`/`fitPageScale`), the `ZoomControl` widget, and the `JetViewFitMode` enum are already package-internal and shared. We (1) add an optional `keyPrefix` to `ZoomControl` so the preview keeps `jet_print.preview.*` keys, and (2) give `_JetReportPreviewState` an absolute `viewScale` + sticky `JetViewFitMode` view-model, replicating the canvas's post-frame "compute-fit-and-write-back" handshake inside the preview's own `LayoutBuilder`. No controller refactor.

**Tech Stack:** Dart / Flutter, `shadcn_ui`, the `jet_print` package's existing designer widgets and `flutter_test` widget tests.

## Global Constraints

- Reuse the existing shared pieces verbatim: `ZoomControl` (`designer/layout/zoom_control.dart`), `fitWidthScale` / `fitPageScale` (`designer/canvas/zoom_math.dart`), `JetViewFitMode` (`designer/controller/view_fit_mode.dart`), `kMinZoom` / `kMaxZoom` (`designer/canvas/design_tunables.dart`). No new zoom abstraction.
- Zoom bounds are `kMinZoom = 0.25` .. `kMaxZoom = 4.0`; the manual step is `×1.25`.
- "100%" means **actual size** (1.0). The preview opens **fit-to-width** (`JetViewFitMode.width`).
- The preview's stable `ValueKey`s stay under the `jet_print.preview.*` namespace.
- Zoom-out / zoom-in buttons **never disable**; they clamp silently (designer parity).
- The preview test stays black-box: it imports only `package:jet_print/jet_print.dart` (+ `shadcn_ui`, `flutter_test`) and targets widgets by `ValueKey`. Do NOT add a `zoom_control.dart` import there.
- Run all commands from the package dir: `cd packages/jet_print`. Run repo-root arch tests too (see Task 3).

---

### Task 1: `ZoomControl` gains an optional `keyPrefix`

Make the widget's `ValueKey`s derive from a `keyPrefix` parameter that defaults to `'jet_print.designer'`, so existing designer usage/tests are byte-for-byte unchanged while the preview can pass `'jet_print.preview'`.

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/zoom_control.dart`
- Test: `packages/jet_print/test/designer/layout/zoom_control_test.dart`

**Interfaces:**
- Produces: `ZoomControl({required double viewScale, required JetViewFitMode fitMode, required ValueChanged<double> onPercent, required ValueChanged<JetViewFitMode> onFit, String keyPrefix = 'jet_print.designer'})`. Keys rendered: `'$keyPrefix.action.zoomLevel'` (the `ShadInput` field), `'$keyPrefix.zoom.menuToggle'` (caret), `'$keyPrefix.zoom.fitWidth'`, `'$keyPrefix.zoom.fitPage'`, `'$keyPrefix.zoom.preset.$p'`.

- [ ] **Step 1: Write the failing test**

Add to the bottom of `zoom_control_test.dart` (inside `main()`), and extend the `_pump` helper to accept `keyPrefix`. First change the helper signature:

```dart
Future<void> _pump(
  WidgetTester tester, {
  required double viewScale,
  required JetViewFitMode fitMode,
  required ValueChanged<double> onPercent,
  required ValueChanged<JetViewFitMode> onFit,
  String keyPrefix = 'jet_print.designer',
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
          keyPrefix: keyPrefix,
        ),
      ),
    ),
  );
}
```

Then add the test:

```dart
  testWidgets('keyPrefix namespaces every key (default stays designer)',
      (WidgetTester tester) async {
    // Default prefix: the designer keys resolve.
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (_) {});
    expect(find.byKey(_field), findsOneWidget); // jet_print.designer.action.zoomLevel
    expect(find.byKey(_caret), findsOneWidget); // jet_print.designer.zoom.menuToggle

    // Override prefix: the preview-namespaced keys resolve, the designer ones do not.
    await _pump(tester,
        viewScale: 1.0,
        fitMode: JetViewFitMode.none,
        onPercent: (_) {},
        onFit: (_) {},
        keyPrefix: 'jet_print.preview');
    expect(find.byKey(_field), findsNothing);
    expect(
        find.byKey(const ValueKey<String>('jet_print.preview.action.zoomLevel')),
        findsOneWidget);
    await tester.tap(
        find.byKey(const ValueKey<String>('jet_print.preview.zoom.menuToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('jet_print.preview.zoom.fitWidth')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('jet_print.preview.zoom.preset.200')),
        findsOneWidget);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/layout/zoom_control_test.dart`
Expected: the new test FAILS (the `ZoomControl` constructor has no `keyPrefix` parameter → compile error / arg error). Existing tests still listed.

- [ ] **Step 3: Implement `keyPrefix`**

In `zoom_control.dart`, add the field + constructor param:

```dart
  const ZoomControl({
    super.key,
    required this.viewScale,
    required this.fitMode,
    required this.onPercent,
    required this.onFit,
    this.keyPrefix = 'jet_print.designer',
  });

  final double viewScale;
  final JetViewFitMode fitMode;
  final ValueChanged<double> onPercent;
  final ValueChanged<JetViewFitMode> onFit;

  /// Namespace for the control's stable `ValueKey`s, so the same widget can be
  /// dropped into the designer (`jet_print.designer.*`, the default) and the
  /// preview (`jet_print.preview.*`) without key collisions.
  final String keyPrefix;
```

In `build`, replace each hard-coded key with a `keyPrefix`-derived one (drop `const` where interpolating):

```dart
          ShadContextMenuItem(
            key: ValueKey<String>('${widget.keyPrefix}.zoom.fitWidth'),
            leading: check(widget.fitMode == JetViewFitMode.width),
            onPressed: () => _pickFit(JetViewFitMode.width),
            child: Text(l10n.menuZoomFitWidth),
          ),
          ShadContextMenuItem(
            key: ValueKey<String>('${widget.keyPrefix}.zoom.fitPage'),
            leading: check(widget.fitMode == JetViewFitMode.page),
            onPressed: () => _pickFit(JetViewFitMode.page),
            child: Text(l10n.menuZoomFitPage),
          ),
          // ... divider unchanged ...
          for (final int p in _kZoomPresets)
            ShadContextMenuItem(
              key: ValueKey<String>('${widget.keyPrefix}.zoom.preset.$p'),
              leading:
                  check(widget.fitMode == JetViewFitMode.none && current == p),
              onPressed: () => _pickPreset(p),
              child: Text('$p%'),
            ),
        ],
        child: SizedBox(
          width: 92,
          child: ShadInput(
            key: ValueKey<String>('${widget.keyPrefix}.action.zoomLevel'),
            controller: _text,
            focusNode: _focus,
            onSubmitted: (_) => _commit(),
            trailing: GestureDetector(
              key: ValueKey<String>('${widget.keyPrefix}.zoom.menuToggle'),
              behavior: HitTestBehavior.opaque,
              onTap: _menu.toggle,
              child: const Icon(LucideIcons.chevronDown, size: 14),
            ),
          ),
        ),
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/layout/zoom_control_test.dart`
Expected: PASS (all existing tests + the new `keyPrefix` test).

- [ ] **Step 5: Sanity-check the designer is unaffected**

Run: `cd packages/jet_print && flutter test test/designer/top_bar_test.dart test/designer/unified_toolbar_test.dart test/designer/l10n_zoom_keys_test.dart`
Expected: PASS (the designer still uses the default prefix, so its keys are unchanged).

- [ ] **Step 6: Commit**

```bash
git add packages/jet_print/lib/src/designer/layout/zoom_control.dart \
        packages/jet_print/test/designer/layout/zoom_control_test.dart
git commit -m "feat(designer): add keyPrefix to ZoomControl for reuse in preview"
```

---

### Task 2: Preview adopts the shared zoom model + `ZoomControl`

Replace the preview's `_zoom` fit-multiplier with an absolute `_viewScale` + sticky `_fitMode`, replicate the canvas's fit handshake in the preview's `LayoutBuilder`, and swap the tappable `%` for the `ZoomControl` trio. The existing preview zoom tests are rewritten to the new semantics first (TDD red), then made green.

**Files:**
- Modify: `packages/jet_print/lib/src/designer/preview/jet_report_preview.dart`
- Test: `packages/jet_print/test/designer/preview/jet_report_preview_test.dart`

**Interfaces:**
- Consumes (from Task 1): `ZoomControl(..., keyPrefix: 'jet_print.preview')`.
- Consumes (existing): `fitWidthScale(JetSize, Size, double)`, `fitPageScale(JetSize, Size, double)`, `kMinZoom`, `kMaxZoom`, `JetViewFitMode`, `JetSize`.
- Produces: preview keys `jet_print.preview.action.zoomLevel` (field), `jet_print.preview.zoom.menuToggle` (caret), `jet_print.preview.zoom.fitWidth`, `jet_print.preview.zoom.fitPage`, `jet_print.preview.zoom.preset.$p`; `jet_print.preview.zoomIn` / `jet_print.preview.zoomOut` buttons stay (always enabled); the `jet_print.preview.page` key is unchanged.

- [ ] **Step 1: Rewrite the preview zoom tests to the new semantics**

In `jet_report_preview_test.dart`, replace the zoom key constant and helper. Change line 71 from the old `Text` key to the new field key, and add the menu keys near it:

```dart
const Key _zoomLevelKey =
    ValueKey<String>('jet_print.preview.action.zoomLevel');
const Key _zoomCaretKey = ValueKey<String>('jet_print.preview.zoom.menuToggle');
const Key _fitWidthKey = ValueKey<String>('jet_print.preview.zoom.fitWidth');
const Key _fitPageKey = ValueKey<String>('jet_print.preview.zoom.fitPage');
```

Replace the entire `group('zoom (fit-to-width multiplier)', ...)` block with:

```dart
  group('zoom (shared ZoomControl, absolute scale)', () {
    // The zoom field is now the designer's ShadInput, read via its controller.
    String level(WidgetTester tester) =>
        tester.widget<ShadInput>(find.byKey(_zoomLevelKey)).controller!.text;

    testWidgets('opens fit-to-width; the field shows the computed scale (not a '
        'literal 100%)', (WidgetTester tester) async {
      await _pumpPreview(tester, size: const Size(800, 600));
      final double pageW = tester.getSize(find.byKey(_pageKey)).width;
      // Fit-to-width: the page fills the viewport minus the 16px padding/side.
      expect(pageW, moreOrLessEquals(768, epsilon: 1));
      // The shared field shows that fit as an absolute percentage; with a 200pt
      // page in a 768px-usable viewport that is ~384%, NOT a literal "100%".
      expect(level(tester), '${(pageW / _page.width * 100).round()}%');
    });

    testWidgets('zoom in enlarges the page (manual ×1.25)',
        (WidgetTester tester) async {
      // A mid-range fit (2.34×) leaves head-room below the 4.0 clamp.
      await _pumpPreview(tester, size: const Size(500, 600));
      final double before = tester.getSize(find.byKey(_pageKey)).width;
      await tester.tap(find.byKey(_zoomInKey));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_pageKey)).width, greaterThan(before));
    });

    testWidgets('zoom out shrinks the page below fit (manual ÷1.25)',
        (WidgetTester tester) async {
      await _pumpPreview(tester, size: const Size(500, 600));
      final double fit = tester.getSize(find.byKey(_pageKey)).width;
      await tester.tap(find.byKey(_zoomOutKey));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_pageKey)).width, lessThan(fit));
    });

    testWidgets('picking Fit Width from the dropdown re-fits the page',
        (WidgetTester tester) async {
      await _pumpPreview(tester, size: const Size(500, 600));
      final double fit = tester.getSize(find.byKey(_pageKey)).width;
      await tester.tap(find.byKey(_zoomOutKey)); // manual zoom clears the fit
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_pageKey)).width, lessThan(fit));
      await tester.tap(find.byKey(_zoomCaretKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_fitWidthKey));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_pageKey)).width,
          moreOrLessEquals(fit, epsilon: 1));
    });

    testWidgets('picking Fit Page fits the whole page (height-limited)',
        (WidgetTester tester) async {
      // A short, wide viewport: fit-width would overflow the height, so fit-page
      // (height-limited) yields a smaller page than fit-width.
      await _pumpPreview(tester, size: const Size(800, 300));
      final double fitWidthW = tester.getSize(find.byKey(_pageKey)).width;
      await tester.tap(find.byKey(_zoomCaretKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_fitPageKey));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_pageKey)).width, lessThan(fitWidthW));
    });

    testWidgets('typing a percentage sets the absolute scale',
        (WidgetTester tester) async {
      await _pumpPreview(tester, size: const Size(800, 600));
      await tester.enterText(find.byKey(_zoomLevelKey), '150');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(level(tester), '150%');
      // 150% of a 200pt page = 300px.
      expect(tester.getSize(find.byKey(_pageKey)).width,
          moreOrLessEquals(300, epsilon: 1));
    });

    testWidgets('zoom clamps at the floor; the button stays enabled (designer '
        'parity)', (WidgetTester tester) async {
      await _pumpPreview(tester, size: const Size(500, 600));
      for (int i = 0; i < 20; i++) {
        await tester.tap(find.byKey(_zoomOutKey));
        await tester.pumpAndSettle();
      }
      // Never disables (unlike the old preview): it clamps silently.
      expect(tester.widget<ShadIconButton>(find.byKey(_zoomOutKey)).onPressed,
          isNotNull);
      // kMinZoom (0.25) × 200pt = 50px; another tap does not shrink further.
      final double floorW = tester.getSize(find.byKey(_pageKey)).width;
      expect(floorW, moreOrLessEquals(50, epsilon: 0.5));
      await tester.tap(find.byKey(_zoomOutKey));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_pageKey)).width,
          moreOrLessEquals(floorW, epsilon: 0.5));
    });
  });
```

`TextInputAction` comes from `package:flutter/services.dart`, already imported by the test (`import 'package:flutter/services.dart';`).

- [ ] **Step 2: Run the rewritten tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/designer/preview/jet_report_preview_test.dart`
Expected: the new `group('zoom (shared ZoomControl, absolute scale)')` tests FAIL — the old preview renders a tappable `Text`, not the `ShadInput` field, so `find.byKey(_zoomLevelKey)` finds nothing. Other groups still pass.

- [ ] **Step 3: Update the preview imports + class doc**

In `jet_report_preview.dart`, add these imports alongside the existing ones (keep them sorted with the others):

```dart
import '../../domain/geometry.dart';
import '../canvas/design_tunables.dart';
import '../canvas/zoom_math.dart';
import '../controller/view_fit_mode.dart';
import '../layout/zoom_control.dart';
```

Replace the `* **Zoom**` bullet in the class doc comment with:

```dart
/// * **Zoom** — the *same* zoom section as the designer: zoom out/in buttons
///   flank an editable percentage field whose dropdown offers Fit Width, Fit
///   Page and presets (the shared `ZoomControl`). Opens fit-to-width; "100%"
///   is actual size. The page re-fits on viewport resize while a sticky fit
///   mode is active, and scrolls when zoomed past the viewport.
```

- [ ] **Step 4: Swap the preview's zoom state + intent methods**

In `_JetReportPreviewState`, delete the three zoom constants and the `_zoom` field (lines ~113-132 region) and replace with the absolute-scale model:

```dart
  /// Absolute zoom: `1.0` == 100% == actual size, bounded by the shared
  /// [kMinZoom]/[kMaxZoom] so the preview and designer agree. Manual zoom is a
  /// straight multiplier on this; fit modes compute it from the viewport.
  double _viewScale = 1.0;

  /// The active sticky fit mode. Defaults to fit-to-width (matching the designer
  /// and preserving the preview's prior "opens fit-to-width" behaviour). While
  /// [JetViewFitMode.width]/[JetViewFitMode.page] the page re-fits on viewport
  /// resize; any manual zoom clears it to [JetViewFitMode.none].
  JetViewFitMode _fitMode = JetViewFitMode.width;

  /// The manual zoom step (×/÷ per zoom-in/out press), matching the designer.
  static const double _zoomStep = 1.25;

  /// Fit bookkeeping (mirrors the canvas): [_fitRequest] is bumped on every
  /// explicit fit pick so re-picking the active mode still re-fits;
  /// [_appliedFitRequest]/[_lastFitViewport] guard against redundant fits, and
  /// [_viewInitialized] gates the first-load fit.
  int _fitRequest = 0;
  int _appliedFitRequest = -1;
  Size? _lastFitViewport;
  bool _viewInitialized = false;
```

Replace the old `_setZoom` / `_zoomIn` / `_zoomOut` / `_resetZoom` methods (lines ~197-210) with:

```dart
  /// Manual zoom: set the absolute [scale] (clamped) and drop the sticky fit
  /// mode, so the page no longer re-fits on resize. Mirrors the controller's
  /// `_manualZoom`. Zoom only rescales the already-recorded picture
  /// ([FrameCustomPainter] keys its repaint on the scale), so no re-record.
  void _manualZoom(double scale) {
    setState(() {
      _fitMode = JetViewFitMode.none;
      _viewScale = scale.clamp(kMinZoom, kMaxZoom);
    });
  }

  void _zoomIn() => _manualZoom(_viewScale * _zoomStep);

  void _zoomOut() => _manualZoom(_viewScale / _zoomStep);

  /// Sets the zoom to [percent] % (e.g. 130 → 1.30); manual, so the fit clears.
  void _setZoomPercent(double percent) => _manualZoom(percent / 100);

  /// Selects a sticky fit [mode] and requests a re-fit (computed in the
  /// `LayoutBuilder`, which owns the viewport).
  void _setFitMode(JetViewFitMode mode) {
    setState(() {
      _fitMode = mode;
      _fitRequest++;
    });
  }
```

- [ ] **Step 5: Replace the `LayoutBuilder` fit/layout math**

In `build`, replace the body of the `LayoutBuilder` (the `const double pad = 16;` block down through the `final double contentWidth = ...` line) with the absolute-scale handshake. The `SingleChildScrollView` subtree below it is unchanged — it already reads `pageWidth`, `pageHeight`, `contentWidth`, `scale`, `frame`:

```dart
                  builder: (BuildContext context, BoxConstraints constraints) {
                    const double pad = 16;
                    final PageFrame frame = _frame;
                    final Size viewport =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    final JetSize content =
                        JetSize(frame.page.width, frame.page.height);

                    // Re-fit OFF the build path (it mutates state) on first
                    // load, on an explicit fit pick, or when the viewport
                    // changes while a sticky fit mode is active — the designer
                    // canvas's handshake (design_canvas.dart). Manual zoom
                    // clears the mode, so this leaves a user's scale alone.
                    final bool fitActive = _fitMode != JetViewFitMode.none;
                    final bool viewportChanged = _lastFitViewport != viewport;
                    if ((!_viewInitialized && fitActive) ||
                        _fitRequest != _appliedFitRequest ||
                        (fitActive && viewportChanged)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _viewInitialized = true;
                          _appliedFitRequest = _fitRequest;
                          _lastFitViewport = viewport;
                          _viewScale = _fitMode == JetViewFitMode.page
                              ? fitPageScale(content, viewport, pad)
                              : fitWidthScale(content, viewport, pad);
                        });
                      });
                    }

                    final double scale = _viewScale;
                    final double pageWidth = frame.page.width * scale;
                    final double pageHeight = frame.page.height * scale;
                    // The horizontal scroll content is at least as wide as the
                    // viewport, so the page centers when it fits and scrolls
                    // once zoomed past fit.
                    final double contentWidth =
                        math.max(pageWidth + 2 * pad, viewport.width);
                    return SingleChildScrollView(
```

- [ ] **Step 6: Replace the toolbar zoom group**

In `_toolbarActions`, replace the three-widget "Zoom group" (the zoom-out `_ToolbarButton`, the `ShadTooltip`/`GestureDetector` `%` `Text`, and the zoom-in `_ToolbarButton`, lines ~257-285) with:

```dart
      // Zoom group — the SAME section as the designer: out / editable % field +
      // Fit Width / Fit Page / preset menu / in. The buttons clamp silently
      // (no disable), matching the designer.
      _ToolbarButton(
        buttonKey: const ValueKey<String>('jet_print.preview.zoomOut'),
        icon: LucideIcons.zoomOut,
        label: l10n.actionZoomOutTooltip,
        onPressed: _zoomOut,
      ),
      ZoomControl(
        viewScale: _viewScale,
        fitMode: _fitMode,
        onPercent: _setZoomPercent,
        onFit: _setFitMode,
        keyPrefix: 'jet_print.preview',
      ),
      _ToolbarButton(
        buttonKey: const ValueKey<String>('jet_print.preview.zoomIn'),
        icon: LucideIcons.zoomIn,
        label: l10n.actionZoomInTooltip,
        onPressed: _zoomIn,
      ),
```

(The `colors`/`theme` locals in `_toolbarActions` are still used by the page-indicator `Text`, so leave them.)

- [ ] **Step 7: Run the preview tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/designer/preview/jet_report_preview_test.dart`
Expected: PASS — all groups, including the rewritten zoom group.

- [ ] **Step 8: Analyze for dead code / unused imports**

Run: `cd packages/jet_print && flutter analyze lib/src/designer/preview/jet_report_preview.dart`
Expected: No issues. (If `math` or any import is flagged unused, it means a usage was missed — fix before committing. `math.max` is still used for `contentWidth`.)

- [ ] **Step 9: Commit**

```bash
git add packages/jet_print/lib/src/designer/preview/jet_report_preview.dart \
        packages/jet_print/test/designer/preview/jet_report_preview_test.dart
git commit -m "feat(designer): preview uses the same zoom section as the designer"
```

---

### Task 3: Full-suite + architecture verification

Confirm nothing else regressed (other widget tests, goldens, l10n key tests) and that the new cross-seam imports respect the architecture tests.

**Files:** none (verification only).

- [ ] **Step 1: Run the full package test suite**

Run: `cd packages/jet_print && flutter test`
Expected: all green, 0 skipped beyond any pre-existing skips. (Goldens are unaffected — no paint pipeline change.)

- [ ] **Step 2: Run the repo-root architecture tests explicitly**

Run: `cd packages/jet_print && flutter test test/architecture/layer_boundaries_test.dart test/encapsulation_test.dart test/public_api_test.dart`
Expected: PASS. (The preview lives in the designer seam and may import `canvas/`, `controller/`, `domain/`; the preview *test* still imports only the public entry point. No public API change.)

- [ ] **Step 3: Analyze the whole package**

Run: `cd packages/jet_print && flutter analyze`
Expected: No issues.

- [ ] **Step 4: Manual GUI smoke (playground)**

Launch the playground, open a report's Preview, and confirm: opens fit-to-width; the editable field shows the computed %; typing a % and Enter rescales; the dropdown's Fit Width / Fit Page / presets behave; zoom-/+ clamp without disabling; resizing the window re-fits while a fit mode is active. (No automated step — record the result in the commit/PR or memory.)

---

## Self-Review

**Spec coverage:**
- "Full parity — reuse `ZoomControl`, absolute scale, fit-width default, fit-page added, re-fit on resize, presets" → Task 2 (state, handshake, toolbar).
- "Add optional `keyPrefix`, preview keeps `jet_print.preview.*`" → Task 1 + Task 2 Step 6.
- "Zoom buttons clamp instead of disabling" → Task 2 Steps 4 (`_manualZoom` clamps) + 6 (`onPressed: _zoomOut/_zoomIn`, never null) + the clamp test in Step 1.
- "Rewrite preview zoom tests to new semantics" → Task 2 Step 1.
- "Units already covered (`ZoomControl`, fit math)" → unchanged; Task 1 only adds a `keyPrefix` test.
- "Out of scope: no controller refactor / shared model / pan-wheel / export-print-nav changes" → honored; only `zoom_control.dart` + `jet_report_preview.dart` (+ their tests) change.

**Placeholder scan:** none — every step has concrete code and exact commands.

**Type consistency:** `_viewScale: double`, `_fitMode: JetViewFitMode`, `_zoomStep: double`, `_fitRequest/_appliedFitRequest: int`, `_lastFitViewport: Size?`, `_viewInitialized: bool`. Methods `_manualZoom(double)`, `_zoomIn()`, `_zoomOut()`, `_setZoomPercent(double)`, `_setFitMode(JetViewFitMode)` match the `ZoomControl` callback types (`ValueChanged<double>` ⇒ `_setZoomPercent`, `ValueChanged<JetViewFitMode>` ⇒ `_setFitMode`). `fitWidthScale`/`fitPageScale(JetSize, Size, double)` are fed `JetSize(frame.page.width, frame.page.height)`, the LayoutBuilder `Size`, and `pad`. Test field key `jet_print.preview.action.zoomLevel` matches the `keyPrefix`-derived field key from Task 1.
