# CanvasKit Font-Registration Leak — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the web playground's demo-switch from slowing down without bound by fixing the CanvasKit font-registration leak (and the playground remount that triggers it), so switches stay fast and in-progress edits survive.

**Architecture:** Three localized fixes. **LIB-A:** make `CanvasPainter` register each engine font variant once per process via a shared, injectable guard (engine font registration is process-global, so the guard must be too). **LIB-B:** dispose the painter's decoded `ui.Image` textures after the frame is recorded (the recorded `Picture` keeps its own refs). **APP-C:** host the playground's demo designers in a structurally-stable `IndexedStack` (ShadTabs as selector only) so a tab switch never remounts the designer.

**Tech Stack:** Dart / Flutter, `flutter_test`. Library package `packages/jet_print`; consumer app `apps/jet_print_playground`. Renderer touches `dart:ui` only in `canvas_painter.dart`.

**Spec:** [docs/superpowers/specs/2026-06-21-designer-canvaskit-font-leak-design.md](../specs/2026-06-21-designer-canvaskit-font-leak-design.md)

## Global Constraints

- **Goldens byte-identical** — no task may change rendered output. Golden suite must stay green (Constitution IV).
- **No public API change** — `CanvasPainter`, `DesignTimeFrameBuilder` are under `src/`; the package's exported surface (53 symbols) is unchanged (Constitution I).
- **Layering** — `canvas_painter.dart` stays the only rendering file importing `dart:ui`/Flutter (Constitution II). No new `dart:ui` import elsewhere.
- **Run commands from `packages/jet_print`** for the library; from `apps/jet_print_playground` for the app. **Run `git` from repo root** `/Users/ahmeturel/Projects/oss/jet-print` (`flutter` leaves cwd inside the package).
- **Branch:** `039-canvaskit-font-leak` (create off local `main`; specs run through `038`).
- **TDD (NON-NEGOTIABLE)** — every task Red→Green. `flutter analyze` clean; dartdoc on new public-in-package members.
- **Three temporary diagnostic probes already exist in the working tree** (uncommitted): the `addTimingsCallback` JANK printer in `main.dart`, the `_recordCount` printer in `design_canvas.dart`, and the `debugFontLoadCount` printer in `canvas_painter.dart`. They are removed in Task 4 — leave them until then (they verify the fix).

---

## Task 0: Create the feature branch

- [ ] **Step 1: Branch off local main (carrying the uncommitted probes).**

Run (from repo root):
```bash
git checkout -b 039-canvaskit-font-leak
git status --short
```
Expected: on `039-canvaskit-font-leak`; the three probe files show as ` M` (modified, uncommitted) and carry over.

---

## Task 1: LIB-A — register each engine font variant once per process

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/paint/canvas_painter.dart` (constructor + `_ensureFont`; add a shared registry + a test-reset hook)
- Test (modify): `packages/jet_print/test/rendering/paint/canvas_painter_variant_test.dart` (isolate its existing load-count test from the new shared default)
- Test (create): `packages/jet_print/test/rendering/paint/canvas_painter_font_dedupe_test.dart`

**Interfaces:**
- Produces: `CanvasPainter(Canvas, FontRegistry, {FontLoader? fontLoader, Set<String>? registeredFamilies})` — `registeredFamilies` defaults to a library-global shared set; pass a fresh `<String>{}` to isolate. `static void CanvasPainter.debugResetEngineFonts()` clears the shared default.
- Consumes (Task 2 relies on): unchanged `_decoded`/`prepare` behavior.

> Context — the leak: a fresh `CanvasPainter` is built on every `recordFrame`, and its `_loadedFamilies` (per-instance) starts empty, so `_ensureFont` re-calls `ui.loadFontFromList` for every variant. CanvasKit appends each registration without dedupe → unbounded font-collection bloat → ever-growing text raster. Fix: move the "already registered in the engine" guard to process scope.

- [ ] **Step 1: Write the failing test** (new file `canvas_painter_font_dedupe_test.dart`):

```dart
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(CanvasPainter.debugResetEngineFonts);

  // Builds a one-text-run frame for the default family.
  PageFrame textFrame(FontRegistry reg) {
    final MeasuredText m =
        MetricsTextMeasurer(reg).measure('Hi', const JetTextStyle(fontSize: 10));
    return (FrameBuilder(const PageFormat(
            width: 100, height: 20, margins: JetEdgeInsets.all(0)))
          ..add(TextRunPrimitive(
              bounds: const JetRect(x: 0, y: 0, width: 100, height: 14),
              lines: m.lines,
              style: const JetTextStyle(fontSize: 10),
              fontFamily: FontRegistry.defaultFamily)))
        .build();
  }

  test('a font variant is registered into the engine only once per process',
      () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    int loads = 0;
    Future<void> counting(Uint8List bytes, {String? fontFamily}) async => loads++;

    // Two painters sharing the default (process-global) registry — like two
    // successive recordFrame() calls.
    for (var i = 0; i < 2; i++) {
      final ui.PictureRecorder rec = ui.PictureRecorder();
      final CanvasPainter painter =
          CanvasPainter(ui.Canvas(rec), reg, fontLoader: counting);
      await painter.prepare(textFrame(reg));
      rec.endRecording();
    }

    expect(loads, 1, reason: 'second painter must reuse the engine registration');
  });

  test('an injected fresh registry registers again (proves the guard is the set)',
      () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    int loads = 0;
    Future<void> counting(Uint8List bytes, {String? fontFamily}) async => loads++;

    for (var i = 0; i < 2; i++) {
      final ui.PictureRecorder rec = ui.PictureRecorder();
      final CanvasPainter painter = CanvasPainter(ui.Canvas(rec), reg,
          fontLoader: counting, registeredFamilies: <String>{});
      await painter.prepare(textFrame(reg));
      rec.endRecording();
    }

    expect(loads, 2, reason: 'isolated registries do not share state');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/jet_print && flutter test test/rendering/paint/canvas_painter_font_dedupe_test.dart`
Expected: FAIL — first test gets `loads == 2` (no dedupe yet); `debugResetEngineFonts`/`registeredFamilies` are undefined (compile error).

- [ ] **Step 3: Implement the guard** in `canvas_painter.dart`. Replace the constructor (currently lines 30-31) and the `_loadedFamilies` field (line 37) and `_ensureFont` (lines 51-59):

```dart
  /// Creates a painter drawing to [_canvas], resolving fonts via [_registry].
  /// [fontLoader] overrides the engine font loader (tests). [registeredFamilies]
  /// overrides the process-global registry of already-registered engine font
  /// families (tests pass a fresh set for isolation).
  CanvasPainter(
    this._canvas,
    this._registry, {
    FontLoader? fontLoader,
    Set<String>? registeredFamilies,
  })  : _loadFont = fontLoader ?? ui.loadFontFromList,
        _registered = registeredFamilies ?? _engineRegisteredFamilies;

  final ui.Canvas _canvas;
  final FontRegistry _registry;
  final FontLoader _loadFont;
  final Map<ImagePrimitive, ui.Image> _decoded = <ImagePrimitive, ui.Image>{};

  /// Engine font registration is process-global: a typeface loaded under a
  /// `uiFamily` name stays registered for the isolate's lifetime. Re-registering
  /// it (CanvasKit appends without dedupe) bloats the font collection and slows
  /// every later text raster, so the "already registered" guard is shared across
  /// all painters, not per-instance.
  static final Set<String> _engineRegisteredFamilies = <String>{};

  /// Test seam: clears the shared registry so the next painter re-registers.
  @visibleForTesting
  static void debugResetEngineFonts() => _engineRegisteredFamilies.clear();

  final Set<String> _registered;
```

Then `_ensureFont`:
```dart
  Future<void> _ensureFont(
      String family, JetFontWeight weight, bool italic) async {
    final String uiFamily = uiFontFamily(family, weight, italic);
    if (_registered.contains(uiFamily)) return;
    final Uint8List bytes =
        _registry.bytesFor(family, weight: weight, italic: italic);
    await _loadFont(bytes, fontFamily: uiFamily);
    _registered.add(uiFamily);
  }
```

Add the `@visibleForTesting` import at the top of the file:
```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
```
(The TEMP-PROBE `debugPrint` import added during diagnosis already pulls `package:flutter/foundation.dart`; merge the shows: `show debugPrint, visibleForTesting` — Task 4 strips the `debugPrint` half.)

- [ ] **Step 4: Run the new test to verify it passes**

Run: `cd packages/jet_print && flutter test test/rendering/paint/canvas_painter_font_dedupe_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Fix the pre-existing variant test** — it asserts `loads` happen and now shares the global default, so isolate it. In `canvas_painter_variant_test.dart`, change the painter built at line 52-53 to inject a fresh registry:

```dart
    final CanvasPainter painter = CanvasPainter(ui.Canvas(recorder), reg,
        fontLoader: recordingLoader, registeredFamilies: <String>{});
```

- [ ] **Step 6: Run the variant test + the golden suite to verify no regression**

Run:
```bash
cd packages/jet_print
flutter test test/rendering/paint/canvas_painter_variant_test.dart
flutter test test/goldens/ test/rendering/paint/canvas_painter_golden_test.dart
```
Expected: PASS; goldens unchanged (the font is still registered once; rendering identical).

- [ ] **Step 7: Analyze + commit**

Run:
```bash
cd packages/jet_print && flutter analyze lib/src/rendering/paint/canvas_painter.dart test/rendering/paint/
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/paint/canvas_painter.dart \
        packages/jet_print/test/rendering/paint/canvas_painter_font_dedupe_test.dart \
        packages/jet_print/test/rendering/paint/canvas_painter_variant_test.dart
git commit -m "fix(render): register each engine font variant once per process

CanvasPainter rebuilt _loadedFamilies per instance, so every recordFrame
re-called ui.loadFontFromList; CanvasKit appends without dedupe, bloating
its font collection and slowing text raster unboundedly. Move the guard to
a shared, injectable process-global set (debugResetEngineFonts for tests)."
```

---

## Task 2: LIB-B — dispose decoded image textures after recording

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/paint/canvas_painter.dart` (add `dispose()` + a `@visibleForTesting` accessor)
- Modify: `packages/jet_print/lib/src/designer/canvas/design_time_frame.dart:93-98` (`recordFrame` disposes the painter after `endRecording`)
- Test (create): `packages/jet_print/test/rendering/paint/canvas_painter_image_dispose_test.dart`

**Interfaces:**
- Produces: `void CanvasPainter.dispose()` disposes every decoded `ui.Image` and clears `_decoded`; `@visibleForTesting Iterable<ui.Image> CanvasPainter.debugDecodedImages`.
- Consumes: Task 1's `CanvasPainter` constructor.

> Context — `CanvasPainter._decoded` holds `ui.Image`s from `instantiateImageCodec` that are never disposed. On CanvasKit those are GPU textures; each record with an image leaks one. The recorded `Picture` keeps its own reference, so disposing the handles **after** `endRecording` is safe.

- [ ] **Step 1: Write the failing test** (`canvas_painter_image_dispose_test.dart`):

```dart
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/elements/image_source.dart'; // JetBoxFit
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A tiny real PNG so instantiateImageCodec has something to decode.
  Future<Uint8List> pngBytes() async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(
        const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint()..color = const ui.Color(0xFF112233));
    final ui.Image img = await rec.endRecording().toImage(2, 2);
    final Uint8List bytes =
        (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    img.dispose();
    return bytes;
  }

  test('dispose() releases every decoded image texture', () async {
    final Uint8List png = await pngBytes();
    final FontRegistry reg = FontRegistry()..registerDefault();
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final CanvasPainter painter = CanvasPainter(ui.Canvas(rec), reg);

    final frame = (FrameBuilder(const PageFormat(
            width: 10, height: 10, margins: JetEdgeInsets.all(0)))
          ..add(ImagePrimitive(
              bounds: const JetRect(x: 0, y: 0, width: 10, height: 10),
              bytes: png,
              fit: JetBoxFit.contain)))
        .build();
    await paintFrame(frame, painter);
    rec.endRecording();

    final List<ui.Image> decoded = painter.debugDecodedImages.toList();
    expect(decoded, isNotEmpty);
    expect(decoded.every((ui.Image i) => i.debugDisposed), isFalse);

    painter.dispose();

    expect(decoded.every((ui.Image i) => i.debugDisposed), isTrue);
  });
}
```

(`JetBoxFit` is defined in `domain/elements/image_source.dart` — confirmed; `ImagePrimitive.fit` is a `JetBoxFit`.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/jet_print && flutter test test/rendering/paint/canvas_painter_image_dispose_test.dart`
Expected: FAIL — `dispose`/`debugDecodedImages` undefined.

- [ ] **Step 3: Implement on `CanvasPainter`** (append after `drawPath`, before the closing brace):

```dart
  /// The images decoded in [prepare]; exposed for tests to assert disposal.
  @visibleForTesting
  Iterable<ui.Image> get debugDecodedImages => _decoded.values;

  /// Releases every decoded image's GPU texture. Call **after** the frame is
  /// recorded — the recorded `Picture` keeps its own reference, so the handles
  /// are then redundant. On CanvasKit, skipping this leaks a texture per record.
  void dispose() {
    for (final ui.Image image in _decoded.values) {
      image.dispose();
    }
    _decoded.clear();
  }
```

- [ ] **Step 4: Wire it into `recordFrame`** in `design_time_frame.dart` (replace lines 93-98):

```dart
  Future<ui.Picture> recordFrame(PageFrame frame) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final CanvasPainter painter = CanvasPainter(ui.Canvas(recorder), fonts);
    await paintFrame(frame, painter);
    final ui.Picture picture = recorder.endRecording();
    painter.dispose(); // free decoded image textures; the picture keeps its refs
    return picture;
  }
```

Note the local type changes from `ReportPainter` to `CanvasPainter` (needed for `.dispose()`); the variable was already a `CanvasPainter` instance, only the declared type was the interface.

- [ ] **Step 5: Run the test + a render-with-image golden to verify pass + no output change**

Run:
```bash
cd packages/jet_print
flutter test test/rendering/paint/canvas_painter_image_dispose_test.dart
flutter test test/goldens/ test/rendering/paint/canvas_painter_golden_test.dart
```
Expected: PASS; goldens unchanged (the picture still draws the image; only the redundant handle is freed).

- [ ] **Step 6: Analyze + commit**

Run:
```bash
cd packages/jet_print && flutter analyze lib/src/rendering/paint/canvas_painter.dart lib/src/designer/canvas/design_time_frame.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/paint/canvas_painter.dart \
        packages/jet_print/lib/src/designer/canvas/design_time_frame.dart \
        packages/jet_print/test/rendering/paint/canvas_painter_image_dispose_test.dart
git commit -m "fix(render): dispose decoded image textures after recording the frame

CanvasPainter._decoded ui.Images were never disposed; on CanvasKit each
record leaked a GPU texture. Dispose them after endRecording (the picture
retains its own refs). Bites every consumer rendering an ImageElement,
including on each drag-preview record."
```

---

## Task 3: APP-C — host demos in a stable IndexedStack (no remount; edits survive)

**Files:**
- Modify: `apps/jet_print_playground/lib/main.dart` (`_PlaygroundHomeState`: ShadTabs becomes a selector; an `IndexedStack` hosts the bodies; delete `_FillTabHeight`)
- Test (modify): `apps/jet_print_playground/test/app_consumes_library_test.dart` (assertions that assumed one mounted designer)

**Interfaces:**
- Consumes: nothing from Tasks 1–2 at the API level (the leak fixes are internal). This task is independent and lands last.
- Produces: no exported symbols; playground-internal.

> Context — the remount: ShadTabs wraps **only the selected** tab's content in `Expanded` (shadcn `tabs.dart` `expandContent`). Flipping `Expanded` on/off at the Column slot changes the widget type there, so Flutter remounts the subtree on every switch (`recordFrame run #1` fired every switch in profiling) — re-recording and discarding edits. Hosting the bodies in a structurally-constant `IndexedStack` (only `index` changes) removes the flip.

- [ ] **Step 1: Write the failing test** — append to `app_consumes_library_test.dart`:

```dart
  testWidgets(
    'every demo designer stays mounted across a switch (no remount keep-alive)',
    (WidgetTester tester) async {
      await tester.pumpWidget(const JetPrintPlaygroundApp());
      await tester.pumpAndSettle();

      // All demo designers are mounted at once (IndexedStack keep-alive), not
      // just the selected one — unlike Offstage tabs, IndexedStack children are
      // not skipped by the finder.
      final int mounted =
          tester.widgetList(find.byType(JetReportDesigner)).length;
      expect(mounted, greaterThan(1),
          reason: 'IndexedStack keeps all demo designers mounted');

      // Switching the selector keeps them all mounted (the count is stable).
      await tester.tap(find.widgetWithText(ShadTab<String>, 'Empty'));
      await tester.pumpAndSettle();
      expect(tester.widgetList(find.byType(JetReportDesigner)).length, mounted,
          reason: 'a switch must not add or drop a designer (no remount)');
    },
  );
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/jet_print_playground && flutter test test/app_consumes_library_test.dart -n "stays mounted"`
Expected: FAIL — today only the selected (non-offstage) designer is found, so `mounted == 1` and `greaterThan(1)` fails.

- [ ] **Step 3: Refactor `_PlaygroundHomeState`** in `main.dart`. Replace the body — read the current `build` (lines 180-402) and `_FillTabHeight` (lines 405-432) first, then apply:

(a) Add selection state to the State class (near `_demoTabsKey`, line 177):
```dart
  /// The selected demo's value; drives the body IndexedStack and the strip.
  String _selectedDemo = 'fatura';
```

(b) Introduce one list describing the demos so the strip and the bodies stay in
lockstep (place above `build`, inside the State):
```dart
  /// One entry per demo: the strip tab (value/icon/label) and its live body.
  /// The strip selects; the IndexedStack hosts. Keeping both off one list keeps
  /// their order and indices in sync.
  List<({String value, IconData icon, String label, Widget body})> _demos(
      AppLocalizations l10n) {
    Widget tab(ReportDefinition seed, JetDataSchema schema,
            RenderedReport Function(ReportDefinition) render) =>
        _DesignerTab(
            fonts: widget.fonts,
            seed: seed,
            dataSchema: schema,
            renderReport: render);
    return <({String value, IconData icon, String label, Widget body})>[
      (
        value: 'fatura',
        icon: LucideIcons.fileText,
        label: l10n.tabInvoice,
        body: tab(invoiceSampleDefinition(), invoiceSchema,
            (d) => renderInvoiceDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'etiket',
        icon: LucideIcons.tag,
        label: l10n.tabLabel,
        body: tab(labelSampleDefinition(), labelSchema,
            (d) => renderLabelDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'barkod',
        icon: LucideIcons.barcode,
        label: l10n.tabBarcode,
        body: tab(barcodeSampleDefinition(), barcodeSchema,
            (d) => renderBarcodeDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'makbuz',
        icon: LucideIcons.package,
        label: l10n.tabPackingSlip,
        body: tab(packingSlipDefinition(), shipmentSchema,
            (d) => renderPackingSlipDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'bordro',
        icon: LucideIcons.banknote,
        label: l10n.tabPayroll,
        body: tab(payrollDefinition(), payrollSchema,
            (d) => renderPayrollDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'nested-lists',
        icon: LucideIcons.listTree,
        label: l10n.tabList,
        body: tab(nestedListsDefinition(), customersSchema,
            (d) => renderNestedListsDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'menu',
        icon: LucideIcons.image,
        label: l10n.tabMenu,
        body: tab(menuSampleDefinition(), menuSchema,
            (d) => renderMenuDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'bos',
        icon: LucideIcons.squareDashed,
        label: l10n.tabEmpty,
        body: tab(emptyDesignDefinition(), invoiceSchema,
            (d) => renderInvoiceDefinition(definition: d, fonts: widget.fonts)),
      ),
    ];
  }
```

(c) Replace `build` (lines 180-402). The strip is now a selector (`onChanged`, no
`content`); a single `IndexedStack` hosts the bodies under an `Expanded`, so its
structure never changes — only its `index`:
```dart
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<({String value, IconData icon, String label, Widget body})> demos =
        _demos(l10n);
    final int index =
        demos.indexWhere((d) => d.value == _selectedDemo).clamp(0, demos.length - 1);

    // Selector only: tapping a tab changes _selectedDemo; the heavy bodies live
    // in the IndexedStack below, so the strip never hosts (or remounts) them.
    final Widget demoStrip = ShadTabs<String>(
      key: _demoTabsKey,
      value: _selectedDemo,
      onChanged: (String v) => setState(() => _selectedDemo = v),
      scrollable: true,
      tabs: <ShadTab<String>>[
        for (final d in demos)
          ShadTab<String>(
            value: d.value,
            leading: Icon(d.icon, size: 16),
            child: Text(d.label),
          ),
      ],
    );

    // The hero: one structurally-stable IndexedStack keeps every designer
    // mounted (edits survive) and swaps which is shown by index alone — no
    // Expanded-flip, so no remount on switch.
    final Widget bodies = IndexedStack(
      index: index,
      sizing: StackFit.expand,
      children: <Widget>[for (final d in demos) d.body],
    );

    final Widget toggleCluster = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: widget.onToggleTheme,
          child: Text(widget.isDark ? 'Light' : 'Dark'),
        ),
        const SizedBox(width: 4),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: widget.onCycleLanguage,
          child: Text(widget.localeCode.toUpperCase()),
        ),
      ],
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The selector header: width-gated like before — a compact row above
            // on a phone, an overlaid cluster on the right at desktop width.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                if (constraints.maxWidth < _narrowWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 4),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: toggleCluster,
                        ),
                      ),
                      demoStrip,
                    ],
                  );
                }
                return Stack(
                  children: <Widget>[
                    demoStrip,
                    Positioned(top: 0, right: 8, child: toggleCluster),
                  ],
                );
              },
            ),
            Expanded(child: bodies),
          ],
        ),
      ),
    );
  }
```

(d) Delete the `_FillTabHeight` class (lines 405-432) — `IndexedStack` with
`StackFit.expand` bounds every child, so the offstage-unbounded-height hack is
obsolete. Also delete its now-unused doc references.

- [ ] **Step 4: Update the existing assertions** that assumed a single mounted designer. In `app_consumes_library_test.dart`:
  - Line 23: `expect(find.byType(JetReportWorkspace), findsOneWidget);` → `findsWidgets` (all demos are now mounted).
  - Line 25 and line 55: `expect(find.byType(JetReportDesigner), findsOneWidget);` → `findsWidgets`.
  - Lines 82-83 (`tester.widget<JetReportDesigner>(find.byType(JetReportDesigner))`) → target the displayed one: `tester.widget<JetReportDesigner>(find.byType(JetReportDesigner).first)`.
  - Lines 142-143 (`find.byType(JetReportWorkspace)`) → `.first`.
  - Update the line-30 test name/comment "seven live designer tabs" → "eight demo tabs" if it asserts a count; otherwise leave prose.

- [ ] **Step 5: Run the playground test file to verify pass**

Run: `cd apps/jet_print_playground && flutter test test/app_consumes_library_test.dart`
Expected: PASS (new keep-alive test + the updated existing tests).

- [ ] **Step 6: Run the whole playground suite (catch any other structural assumption)**

Run: `cd apps/jet_print_playground && flutter test`
Expected: PASS. If another test taps a tab and reads the lone designer, apply the same `.first` / `findsWidgets` adjustment.

- [ ] **Step 7: Analyze + commit**

Run:
```bash
cd apps/jet_print_playground && flutter analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/main.dart apps/jet_print_playground/test/app_consumes_library_test.dart
git commit -m "fix(playground): host demos in a stable IndexedStack (no remount)

ShadTabs wraps only the selected tab in Expanded; flipping it on/off
remounted the designer every switch (re-record + silent edit-loss). Use
ShadTabs as a selector and host the bodies in a structurally-constant
IndexedStack so a switch changes only the shown index. Edits now survive a
switch; drops the _FillTabHeight unbounded-height workaround."
```

---

## Task 4: Remove probes, verify end-to-end, close out

**Files:**
- Modify: `apps/jet_print_playground/lib/main.dart`, `packages/jet_print/lib/src/designer/canvas/design_canvas.dart`, `packages/jet_print/lib/src/rendering/paint/canvas_painter.dart` (strip the three temp probes)

- [ ] **Step 1: Remove the `main.dart` JANK probe.** Delete the `SchedulerBinding.instance.addTimingsCallback(...)` block in `main()` and its imports: `import 'dart:ui' show FrameTiming;`, `import 'package:flutter/scheduler.dart' show SchedulerBinding;`, and the `debugPrint` from the foundation import (revert line 5-6 to its original `show kIsWeb, defaultTargetPlatform, TargetPlatform`).

- [ ] **Step 2: Remove the `design_canvas.dart` record probe.** Delete the `_recordCount` field (the `// TEMP PROBE` line near line 117) and the `debugPrint('recordFrame run #...')` block at the top of `_maybeRebuild`.

- [ ] **Step 3: Remove the `canvas_painter.dart` font probe.** Delete `static int debugFontLoadCount`, the `debugPrint('loadFontFromList total=...')` line in `_ensureFont`, and narrow the foundation import back to `show visibleForTesting` only (the probe added `debugPrint`; Task 1 added `visibleForTesting`).

- [ ] **Step 4: Verify no probe residue.**

Run (from repo root):
```bash
grep -rn "TEMP PROBE\|debugFontLoadCount\|recordFrame run\|JANK frame\|addTimingsCallback" packages/jet_print/lib apps/jet_print_playground/lib
```
Expected: no matches.

- [ ] **Step 5: Full library + playground suites + analyze.**

Run:
```bash
cd packages/jet_print && flutter analyze && flutter test
cd ../../apps/jet_print_playground && flutter analyze && flutter test
```
Expected: all green; goldens byte-identical (no golden file shows as modified in `git status`).

- [ ] **Step 6: Manual web re-measurement (the closing acceptance gate).**

This needs the probes, so do it BEFORE committing their removal if you want the numbers — or re-add a throwaway timing probe. Procedure (the §7 spec check):
1. `cd apps/jet_print_playground && flutter run -d chrome --profile`
2. DevTools Console open; bounce Fatura ⇄ Bordro ≥ 30×.
3. Confirm: steady-state switch < 150ms, `raster(GPU)` does **not** climb across switches.
4. Edit on one tab (move an element), switch away and back; confirm the edit/selection persists.

Record the result (pass/fail + a couple sample numbers) in the commit message or a `docs/superpowers/specs/2026-06-21-font-leak-findings.md` note.

- [ ] **Step 7: Commit the probe removal.**

Run:
```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/main.dart \
        packages/jet_print/lib/src/designer/canvas/design_canvas.dart \
        packages/jet_print/lib/src/rendering/paint/canvas_painter.dart
git commit -m "chore: remove temporary font-leak diagnostic probes

Strip the addTimingsCallback JANK printer, the recordFrame counter, and the
loadFontFromList counter added while diagnosing the CanvasKit font leak.
Verified post-fix: demo switch flat (<150ms), no raster growth over 30+
switches, edits survive a switch."
```

- [ ] **Step 8: Finish the branch.** Use superpowers:finishing-a-development-branch to pick merge/PR/cleanup (repo convention: FF-merge to local `main`).

---

## Self-Review (completed)

**Spec coverage:** LIB-A → Task 1; LIB-B → Task 2; APP-C → Task 3; probe removal (§9) + acceptance #1-2 manual gate (§8) → Task 4. Goldens-byte-identical constraint enforced in Tasks 1, 2, 4. Edit-survival (acceptance #4) is closed by Task 3's keep-alive test (structural) + Task 4 Step 6 (manual) — the app's controllers aren't reachable from a widget test, so the automated proof is the no-remount mount-count, with manual confirmation of the edit itself; this is the one spec item whose automated form is weaker than its wording, intentionally.

**Placeholder scan:** none — every code/test step carries full code; one verification aside (the `JetBoxFit` import path in Task 2 Step 1) is an explicit `grep`-to-confirm, not a placeholder.

**Type consistency:** `CanvasPainter(Canvas, FontRegistry, {fontLoader, registeredFamilies})`, `debugResetEngineFonts()`, `dispose()`, `debugDecodedImages` are defined in Tasks 1-2 and used consistently. `_demos(...)` record type is identical where produced (Step 3b) and consumed (Step 3c).
