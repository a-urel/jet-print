# Layout engine — Spec 008a Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the core Layout engine — a pure `(ReportTemplate, FilledReport) → List<PageFrame>` pass that measures body bands, grows them to fit, stacks and paginates them, repeats page header/footer chrome on every page, and emits one `PageFrame` per page.

**Architecture:** A small pure `BandMeasurer` computes each body band's grown height (grow-only, height-only; no intra-band reflow) and per-element grown boxes via the 007a `ElementRenderer.measure` seam. `ReportLayouter` holds one `FrameBuilder` per page, places body bands during a pagination loop, then emits chrome in a **post-pagination pass** (the seam 008c will reuse for page-number substitution), building `PageFrame`s last. No expression engine, no image byte-resolution — 008a is pure geometry over the existing 006/007a seams.

**Tech Stack:** Dart (pub workspace monorepo), Flutter test harness. Pure-Dart `rendering/layout/` seam (domain + sibling rendering subdirs; no `dart:ui`, no Flutter UI, no `expression/`). Value-type output IR (`PageFrame`/`FramePrimitive`) with deep equality; TDD with `flutter test`.

**Spec:** `docs/superpowers/specs/2026-06-08-layout-engine-design.md`.

**Conventions for every task:**
- Run all commands from `packages/jet_print/`. Test form: `flutter test test/<path> -r expanded`.
- After each task `flutter analyze` must print `No issues found!` (root `analysis_options.yaml` promotes `unused_import`/`unused_local_variable`/`unused_element`/`unused_field`/`dead_code` to **errors**, and specifies types — keep explicit types as the surrounding code does).
- `lib/` files use **relative** imports, ordered `dart:` → `package:` → relative, each group alphabetized by import string.
- Test files use white-box `package:jet_print/src/...` imports (`/test/rendering/` is allowlisted).
- New `src/` types are **not** exported from `jet_print.dart` (the public surface is the 011 facade).
- **No domain/serialization change** in 008a (uniform grow-only; spec §10 #1) — schema is untouched.
- Commit messages end with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` (omitted below for brevity).
- Branch is already `008a-layout-engine`.

---

## File Structure

**Create (lib):**
- `lib/src/rendering/layout/band_measurer.dart` — `MeasuredBand` + `BandMeasurer` (pure grow-only band measurement).
- `lib/src/rendering/layout/report_layouter.dart` — `LayoutResult` + `ReportLayouter` (geometry, body pagination loop, chrome post-pass, emission).

**Create (test):**
- `test/rendering/layout/band_measurer_test.dart` — growth-rule heights (uses a deterministic fake measurer).
- `test/rendering/layout/report_layouter_test.dart` — pagination / coordinate / chrome / diagnostics / determinism goldens (uses `ShapeElement`s + the default measurer).

**Modify (test):**
- `test/architecture/layer_boundaries_test.dart` — add a `layout/` seam check (headless + free of the `expression/` engine).

**Modify (docs):**
- `CHANGELOG.md`.

**Key types this plan introduces (referenced across tasks — keep these signatures stable):**
- `class MeasuredBand { const MeasuredBand(this.height, this.elements); final double height; final List<({ReportElement element, JetRect bounds})> elements; }`
- `class BandMeasurer { BandMeasurer(this._registry, this._ctx); MeasuredBand measure(FilledBand band); }`
- `class LayoutResult { const LayoutResult({required this.pages, required this.diagnostics}); final List<PageFrame> pages; final ReportDiagnostics diagnostics; }`
- `class ReportLayouter { ReportLayouter({ElementRendererRegistry? renderers, TextMeasurer? measurer}); LayoutResult layout(ReportTemplate template, FilledReport filled); }`

---

## Task 1: `BandMeasurer` + `MeasuredBand`

**Files:**
- Create: `lib/src/rendering/layout/band_measurer.dart`
- Test: `test/rendering/layout/band_measurer_test.dart`

Context: A pure unit that measures a single `FilledBand` to its grown height plus each element's grown, band-local box. Grow-only and height-only: an element's box height becomes `max(authored height, measured height)` (never shrinks; width stays authored — the text renderer wraps at the element's own width and grows vertically only), and the band height is `max(designed height, tallest element bottom)`. A growing element does **not** move its siblings (banded + absolute-in-band; no reflow). The box is carried alongside the element so the layouter places each element from its already-measured box without measuring it again for geometry (the renderer's own `emit` re-derives its line content via the measurer — the existing 007a seam, which 008a leaves unchanged). The test injects a deterministic fake `TextMeasurer` so growth is asserted exactly without depending on bundled-font pixel metrics.

- [ ] **Step 1: Write the failing test**

Create `test/rendering/layout/band_measurer_test.dart`:

```dart
// BandMeasurer: grow-only, height-only band measurement (spec 008a §5).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/elements/built_in_element_renderers.dart';
import 'package:jet_print/src/rendering/elements/element_type_registry.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/layout/band_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

/// Deterministic measurer: block height = 10 * (number of '\n'-separated lines),
/// so layout growth is exact and font-independent. Width is `maxWidth ?? 0`.
class _FixedMeasurer implements TextMeasurer {
  const _FixedMeasurer();
  @override
  MeasuredText measure(String text, JetTextStyle style, {double? maxWidth}) {
    final List<String> segs = text.split('\n');
    final List<TextLine> lines = <TextLine>[
      for (int i = 0; i < segs.length; i++)
        TextLine(
            text: segs[i],
            width: 0,
            top: i * 10.0,
            baseline: i * 10.0,
            height: 10),
    ];
    return MeasuredText(
      lines: lines,
      size: JetSize(maxWidth ?? 0, segs.length * 10.0),
      firstAscent: 10,
      fontFamily: 'Fake',
    );
  }
}

BandMeasurer _measurer() {
  final ElementTypeRegistry reg = ElementTypeRegistry();
  registerBuiltInElementTypes(reg);
  return BandMeasurer(
      reg.renderers, const RenderContext(measurer: _FixedMeasurer()));
}

FilledBand _band(double height, List<ReportElement> elements) => FilledBand(
      type: BandType.detail,
      height: height,
      elements: elements,
      variables: const <String, JetValue>{},
    );

TextElement _text(String id, JetRect bounds, String text) =>
    TextElement(id: id, bounds: bounds, text: text);

void main() {
  test('a band with no elements measures to its designed height', () {
    final MeasuredBand mb =
        _measurer().measure(_band(40, const <ReportElement>[]));
    expect(mb.height, 40);
    expect(mb.elements, isEmpty);
  });

  test('an element shorter than its box does not shrink it (grow-only)', () {
    // 1 line -> measured 10; bounds height 20 -> box stays 20; designed 50 wins.
    final MeasuredBand mb = _measurer().measure(_band(50, <ReportElement>[
      _text('t', const JetRect(x: 0, y: 0, width: 100, height: 20), 'one'),
    ]));
    expect(mb.elements.single.bounds.height, 20);
    expect(mb.height, 50);
  });

  test('a tall element grows its box and the band to the element bottom', () {
    // 3 lines -> measured 30; bounds height 10 -> box grows to 30; band -> 30.
    final MeasuredBand mb = _measurer().measure(_band(10, <ReportElement>[
      _text('t', const JetRect(x: 0, y: 0, width: 100, height: 10), 'a\nb\nc'),
    ]));
    expect(mb.elements.single.bounds.height, 30);
    expect(mb.elements.single.bounds.width, 100); // width unchanged
    expect(mb.height, 30);
  });

  test('band height is the maximum element bottom', () {
    final MeasuredBand mb = _measurer().measure(_band(10, <ReportElement>[
      _text('a', const JetRect(x: 0, y: 0, width: 100, height: 10), 'x'),
      _text('b', const JetRect(x: 0, y: 50, width: 100, height: 10), 'p\nq'),
    ]));
    // 'b' at y=50, 2 lines -> 20 tall -> bottom 70.
    expect(mb.height, 70);
  });

  test('a growing element does not move its siblings (no reflow)', () {
    final MeasuredBand mb = _measurer().measure(_band(10, <ReportElement>[
      _text('top', const JetRect(x: 0, y: 0, width: 100, height: 10), 'a\nb\nc'),
      _text('below', const JetRect(x: 0, y: 5, width: 100, height: 10), 'z'),
    ]));
    final JetRect below = mb.elements
        .firstWhere((({ReportElement element, JetRect bounds}) e) =>
            e.element.id == 'below')
        .bounds;
    expect(below.y, 5); // keeps its authored y even though 'top' grew to 30
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/layout/band_measurer_test.dart -r expanded`
Expected: FAIL — `band_measurer.dart` does not exist (`BandMeasurer`/`MeasuredBand` undefined).

- [ ] **Step 3: Implement**

Create `lib/src/rendering/layout/band_measurer.dart`:

```dart
/// Measures a body band to its grown height with each element's grown, band-local
/// box (spec 008a §5). Pure and position-independent, so the layouter measures
/// each element only once and reuses the result for both the page-break decision
/// and placement (the renderer's `emit` re-derives its own line content — the
/// 007a seam — which this pass does not change).
///
/// **Grow-only, height-only:** an element keeps its authored width (the renderer
/// wraps at the element's own width and grows vertically) and never shrinks below
/// its authored height — it only stretches when its measured content needs more
/// room. A growing element does NOT push its siblings down (banded +
/// absolute-in-band; no reflow): the band height is the maximum element bottom,
/// floored at the designed height.
library;

import '../../domain/geometry.dart';
import '../../domain/report_element.dart';
import '../elements/element_renderer_registry.dart';
import '../elements/render_context.dart';
import '../fill/filled_report.dart';

/// A band measured to its grown [height], with each element paired with its
/// grown band-local [bounds] (reused for placement, so the layouter measures an
/// element's geometry only once — the renderer's `emit` re-derives its own line
/// content separately, the unchanged 007a seam).
class MeasuredBand {
  /// Creates a measured band.
  const MeasuredBand(this.height, this.elements);

  /// The grown band height (>= the band's designed height), in points.
  final double height;

  /// Each element with its grown, band-local box (reused for placement, so the
  /// layouter does not re-measure an element's geometry at emit time).
  final List<({ReportElement element, JetRect bounds})> elements;
}

/// Measures [FilledBand]s for layout, delegating per-element sizing to the
/// registered [ElementRenderer]s.
class BandMeasurer {
  /// Creates a measurer over the renderer [_registry] and render [_ctx].
  BandMeasurer(this._registry, this._ctx);

  final ElementRendererRegistry _registry;
  final RenderContext _ctx;

  /// Measures [band] into its grown height and per-element grown boxes.
  MeasuredBand measure(FilledBand band) {
    final List<({ReportElement element, JetRect bounds})> boxes =
        <({ReportElement element, JetRect bounds})>[];
    double maxBottom = band.height;
    for (final ReportElement el in band.elements) {
      final JetSize natural = _registry.rendererFor(el).measure(
            el,
            _ctx,
            JetConstraints(maxWidth: el.bounds.width),
          );
      final double grownHeight = natural.height > el.bounds.height
          ? natural.height
          : el.bounds.height;
      boxes.add((
        element: el,
        bounds: JetRect(
          x: el.bounds.x,
          y: el.bounds.y,
          width: el.bounds.width,
          height: grownHeight,
        ),
      ));
      final double bottom = el.bounds.y + grownHeight;
      if (bottom > maxBottom) maxBottom = bottom;
    }
    return MeasuredBand(maxBottom, boxes);
  }
}
```

- [ ] **Step 4: Run the test + analyzer**

Run: `flutter test test/rendering/layout/band_measurer_test.dart -r expanded && flutter analyze`
Expected: PASS (5 tests); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/rendering/layout/band_measurer.dart test/rendering/layout/band_measurer_test.dart
git commit -m "feat(layout): BandMeasurer grow-only band measurement (008a)"
```

---

## Task 2: `ReportLayouter` + `LayoutResult`

**Files:**
- Create: `lib/src/rendering/layout/report_layouter.dart`
- Test: `test/rendering/layout/report_layouter_test.dart`

Context: The full layout engine. It takes `template.page` as authoritative (warns on a `filled.page` mismatch), computes the per-page body region from the page margins minus fixed chrome heights, pre-measures each body band, then runs the **held-builders** pagination loop (one `FrameBuilder` per page, guaranteeing ≥1 page) followed by the **chrome post-pass** that repeats `pageHeader`/`pageFooter` on every page. It scans chrome once for unresolved bindings (info diagnostics), guards against chrome overcommit, and ignores `columnHeader`/`columnFooter`/`background` with an info. Pure geometry — no expression engine. Tests use `ShapeElement`s (which measure to their bounds) on a small 200×100 page so all coordinates and breaks are exact.

- [ ] **Step 1: Write the failing tests**

Create `test/rendering/layout/report_layouter_test.dart`:

```dart
// ReportLayouter: pagination, page chrome, coordinates, diagnostics (008a).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

// A small page: 200x100, 10pt margins -> content 180x80; top=10 bottom=90
// left=10 right=190.
const PageFormat _smallPage =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

ShapeElement _rect(String id, JetRect bounds) =>
    ShapeElement(id: id, bounds: bounds, kind: ShapeKind.rectangle);

// A body band whose single rectangle fills the band (so its measured height
// equals the designed height — no growth, exact geometry).
FilledBand _body(double height, {String id = 'r'}) => FilledBand(
      type: BandType.detail,
      height: height,
      elements: <ReportElement>[
        _rect(id, JetRect(x: 0, y: 0, width: 180, height: height)),
      ],
      variables: const <String, JetValue>{},
    );

ReportTemplate _tpl({List<ReportBand> bands = const <ReportBand>[]}) =>
    ReportTemplate(name: 'demo', page: _smallPage, bands: bands);

FilledReport _filled(List<FilledBand> bands) =>
    FilledReport(page: _smallPage, bands: bands);

void main() {
  test('a single page holds all bands that fit', () {
    final LayoutResult r = ReportLayouter()
        .layout(_tpl(), _filled(<FilledBand>[_body(30), _body(30)]));
    expect(r.pages.length, 1);
  });

  test('bands overflow to a second page; the body restarts at bodyTop', () {
    final LayoutResult r = ReportLayouter()
        .layout(_tpl(), _filled(<FilledBand>[_body(30), _body(30), _body(30)]));
    expect(r.pages.length, 2);
    final RectPrimitive rect =
        r.pages[1].primitives.whereType<RectPrimitive>().first;
    expect(rect.bounds, const JetRect(x: 10, y: 10, width: 180, height: 30));
  });

  test('a body band taller than the body capacity overflows with a warning', () {
    // No chrome -> capacity 80; a 100pt band cannot fit even an empty page, so
    // it is placed at bodyTop and overflows (atomic band; no flow solver).
    final LayoutResult r =
        ReportLayouter().layout(_tpl(), _filled(<FilledBand>[_body(100)]));
    expect(r.pages.length, 1);
    final List<Diagnostic> warnings = r.diagnostics.entries
        .where((Diagnostic d) => d.severity == DiagnosticSeverity.warning)
        .toList();
    expect(warnings.single.message, contains('exceeds body capacity'));
  });

  test('element page coords translate the band-local box by (left, cursorY)',
      () {
    final LayoutResult r = ReportLayouter().layout(
        _tpl(), _filled(<FilledBand>[_body(30, id: 'a'), _body(30, id: 'b')]));
    final List<RectPrimitive> rects =
        r.pages.single.primitives.whereType<RectPrimitive>().toList();
    expect(rects[0].bounds, const JetRect(x: 10, y: 10, width: 180, height: 30));
    expect(rects[1].bounds, const JetRect(x: 10, y: 40, width: 180, height: 30));
  });

  test('page header and footer repeat on every page; footer anchored to bottom',
      () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      ReportBand(type: BandType.pageHeader, height: 20, elements: <ReportElement>[
        _rect('hdr', const JetRect(x: 0, y: 0, width: 180, height: 20)),
      ]),
      ReportBand(type: BandType.pageFooter, height: 20, elements: <ReportElement>[
        _rect('ftr', const JetRect(x: 0, y: 0, width: 180, height: 20)),
      ]),
    ]);
    // header 20 + footer 20 -> bodyTop=30, bodyBottom=70, capacity=40.
    // body 30: band1 at 30 (60<=70); band2: 60+30=90>70 -> page 2.
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(30), _body(30)]));
    expect(r.pages.length, 2);
    for (final PageFrame pf in r.pages) {
      final List<RectPrimitive> rects =
          pf.primitives.whereType<RectPrimitive>().toList();
      expect(
          rects.any((RectPrimitive p) =>
              p.elementId == 'hdr' &&
              p.bounds == const JetRect(x: 10, y: 10, width: 180, height: 20)),
          isTrue);
      expect(
          rects.any((RectPrimitive p) =>
              p.elementId == 'ftr' &&
              p.bounds == const JetRect(x: 10, y: 70, width: 180, height: 20)),
          isTrue);
    }
  });

  test('multiple page header bands stack in document order', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      ReportBand(type: BandType.pageHeader, height: 15, elements: <ReportElement>[
        _rect('h1', const JetRect(x: 0, y: 0, width: 180, height: 15)),
      ]),
      ReportBand(type: BandType.pageHeader, height: 15, elements: <ReportElement>[
        _rect('h2', const JetRect(x: 0, y: 0, width: 180, height: 15)),
      ]),
    ]);
    // headerHeight 30 -> bodyTop 40; h1 at top=10, h2 stacked below at 25.
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    final List<RectPrimitive> rects =
        r.pages.single.primitives.whereType<RectPrimitive>().toList();
    expect(rects.firstWhere((RectPrimitive p) => p.elementId == 'h1').bounds,
        const JetRect(x: 10, y: 10, width: 180, height: 15));
    expect(rects.firstWhere((RectPrimitive p) => p.elementId == 'h2').bounds,
        const JetRect(x: 10, y: 25, width: 180, height: 15));
  });

  test('non-detail body bands (title/group/summary) lay out in stream order',
      () {
    FilledBand band(BandType type, String id) => FilledBand(
          type: type,
          height: 15,
          elements: <ReportElement>[
            _rect(id, const JetRect(x: 0, y: 0, width: 180, height: 15)),
          ],
          variables: const <String, JetValue>{},
        );
    // The layouter is type-agnostic for body bands: Fill already ordered the
    // stream (title first, summary last), so layout just stacks them in order.
    final FilledReport filled = _filled(<FilledBand>[
      band(BandType.title, 't'),
      band(BandType.groupHeader, 'gh'),
      band(BandType.detail, 'd'),
      band(BandType.groupFooter, 'gf'),
      band(BandType.summary, 's'),
    ]);
    // 5 * 15 = 75 <= capacity 80 -> one page, stacked in stream order.
    final LayoutResult r = ReportLayouter().layout(_tpl(), filled);
    final List<String?> ids = r.pages.single.primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toList();
    expect(ids, <String>['t', 'gh', 'd', 'gf', 's']);
  });

  test('a chrome text expression renders its literal + an info diagnostic', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      const ReportBand(type: BandType.pageHeader, height: 20, elements: <ReportElement>[
        TextElement(
            id: 'pn',
            bounds: JetRect(x: 0, y: 0, width: 180, height: 20),
            text: 'Page',
            expression: r'$V{PAGE_NUMBER}'),
      ]),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    final TextRunPrimitive run = r.pages.single.primitives
        .whereType<TextRunPrimitive>()
        .firstWhere((TextRunPrimitive p) => p.elementId == 'pn');
    expect(run.lines.map((TextLine l) => l.text).join(), 'Page');
    expect(
        r.diagnostics.entries.any((Diagnostic d) =>
            d.severity == DiagnosticSeverity.info && d.elementId == 'pn'),
        isTrue);
  });

  test('an unresolved chrome image renders a placeholder + an info diagnostic',
      () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      const ReportBand(type: BandType.pageHeader, height: 20, elements: <ReportElement>[
        ImageElement(
            id: 'logo',
            bounds: JetRect(x: 0, y: 0, width: 40, height: 20),
            source: FieldImageSource('logo')),
      ]),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    expect(
        r.pages.single.primitives
            .whereType<RectPrimitive>()
            .any((RectPrimitive p) => p.elementId == 'logo'),
        isTrue); // placeholder outline rect
    expect(
        r.diagnostics.entries.any((Diagnostic d) =>
            d.severity == DiagnosticSeverity.info && d.elementId == 'logo'),
        isTrue);
  });

  test('chrome taller than the printable height warns once and still paginates',
      () {
    // header 50 + footer 50 = 100 > content 80 -> capacity = -20.
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      ReportBand(type: BandType.pageHeader, height: 50, elements: <ReportElement>[
        _rect('h', const JetRect(x: 0, y: 0, width: 180, height: 50)),
      ]),
      ReportBand(type: BandType.pageFooter, height: 50, elements: <ReportElement>[
        _rect('f', const JetRect(x: 0, y: 0, width: 180, height: 50)),
      ]),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(30)]));
    final List<Diagnostic> warnings = r.diagnostics.entries
        .where((Diagnostic d) => d.severity == DiagnosticSeverity.warning)
        .toList();
    expect(warnings.length, 1); // root-cause only; no per-band capacity spam
    expect(warnings.single.message, contains('leaves no room for body'));
    expect(r.pages, isNotEmpty);
  });

  test('an empty band stream still produces one chrome-only page', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      ReportBand(type: BandType.pageHeader, height: 20, elements: <ReportElement>[
        _rect('hdr', const JetRect(x: 0, y: 0, width: 180, height: 20)),
      ]),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(const <FilledBand>[]));
    expect(r.pages.length, 1);
    expect(
        r.pages.single.primitives
            .whereType<RectPrimitive>()
            .any((RectPrimitive p) => p.elementId == 'hdr'),
        isTrue);
  });

  test('a noData band lays out as the sole body band', () {
    final FilledReport filled = _filled(<FilledBand>[
      FilledBand(
          type: BandType.noData,
          height: 30,
          elements: <ReportElement>[
            _rect('nd', const JetRect(x: 0, y: 0, width: 180, height: 30)),
          ],
          variables: const <String, JetValue>{}),
    ]);
    final LayoutResult r = ReportLayouter().layout(_tpl(), filled);
    expect(r.pages.length, 1);
    expect(
        r.pages.single.primitives.whereType<RectPrimitive>().single.elementId,
        'nd');
  });

  test('column/background bands are ignored with an info each', () {
    final ReportTemplate tpl = _tpl(bands: const <ReportBand>[
      ReportBand(type: BandType.background, height: 10),
      ReportBand(type: BandType.columnHeader, height: 10),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.info)
            .length,
        2);
  });

  test('filled.page differing from template.page warns and uses template.page',
      () {
    final FilledReport filled = FilledReport(
        page: const PageFormat(
            width: 999, height: 999, margins: JetEdgeInsets.all(10)),
        bands: <FilledBand>[_body(20)]);
    final LayoutResult r = ReportLayouter().layout(_tpl(), filled);
    expect(r.pages.single.page, _smallPage); // template.page wins
    expect(
        r.diagnostics.entries.any((Diagnostic d) =>
            d.severity == DiagnosticSeverity.warning &&
            d.message.contains('using template.page')),
        isTrue);
  });

  test('determinism — two layouts of identical inputs are equal', () {
    ReportTemplate tpl() => _tpl(bands: <ReportBand>[
          ReportBand(
              type: BandType.pageHeader,
              height: 20,
              elements: <ReportElement>[
                _rect('hdr', const JetRect(x: 0, y: 0, width: 180, height: 20)),
              ]),
        ]);
    FilledReport filled() => _filled(<FilledBand>[_body(30), _body(30)]);
    final LayoutResult a = ReportLayouter().layout(tpl(), filled());
    final LayoutResult b = ReportLayouter().layout(tpl(), filled());
    expect(a.pages, b.pages); // PageFrame has value equality
    List<(DiagnosticSeverity, String, String?)> proj(LayoutResult r) => r
        .diagnostics.entries
        .map((Diagnostic d) => (d.severity, d.message, d.elementId))
        .toList();
    expect(proj(a), proj(b)); // diagnostics by normalized projection
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/rendering/layout/report_layouter_test.dart -r expanded`
Expected: FAIL — `report_layouter.dart` does not exist (`ReportLayouter`/`LayoutResult` undefined).

- [ ] **Step 3: Implement**

Create `lib/src/rendering/layout/report_layouter.dart`:

```dart
/// The Layout engine (spec 008a): places a resolved [FilledReport] band stream
/// onto pages with repeating page chrome, producing one [PageFrame] per page.
/// Pure geometry — no expression engine, no image byte-resolution. INTERNAL; the
/// public surface is the 011 JetReportEngine.
library;

import '../../domain/elements/image_element.dart';
import '../../domain/elements/image_source.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/geometry.dart';
import '../../domain/page_format.dart';
import '../../domain/report_band.dart';
import '../../domain/report_element.dart';
import '../../domain/report_template.dart';
import '../elements/built_in_element_renderers.dart';
import '../elements/element_renderer_registry.dart';
import '../elements/element_type_registry.dart';
import '../elements/render_context.dart';
import '../fill/filled_report.dart';
import '../fill/report_diagnostics.dart';
import '../frame/frame_builder.dart';
import '../frame/page_frame.dart';
import '../text/font_registry.dart';
import '../text/metrics_text_measurer.dart';
import '../text/text_measurer.dart';
import 'band_measurer.dart';

/// The result of a layout: the paginated [pages] and collected [diagnostics].
class LayoutResult {
  /// Creates a layout result.
  const LayoutResult({required this.pages, required this.diagnostics});

  /// One frame per page, in order.
  final List<PageFrame> pages;

  /// The non-fatal issues collected during the pass.
  final ReportDiagnostics diagnostics;
}

/// Lays a [FilledReport] out onto pages (spec 008a).
class ReportLayouter {
  /// Creates a layouter; [renderers] and [measurer] default to the built-ins.
  ReportLayouter({ElementRendererRegistry? renderers, TextMeasurer? measurer})
      : _renderers = renderers ?? _defaultRenderers(),
        _measurer =
            measurer ?? MetricsTextMeasurer(FontRegistry()..registerDefault());

  final ElementRendererRegistry _renderers;
  final TextMeasurer _measurer;

  // Built-ins flow through the canonical PAIRED registration path; the layouter's
  // dependency stays renderer-only (like ReportFiller's JetFunctionRegistry).
  static ElementRendererRegistry _defaultRenderers() {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    return reg.renderers;
  }

  /// Lays [filled] out, sourcing page chrome + page format from [template].
  LayoutResult layout(ReportTemplate template, FilledReport filled) {
    final ReportDiagnostics diagnostics = ReportDiagnostics();
    final RenderContext ctx = RenderContext(measurer: _measurer);
    final BandMeasurer bandMeasurer = BandMeasurer(_renderers, ctx);

    // template.page is authoritative for the page format (spec §2/§10 #5).
    final PageFormat page = template.page;
    if (filled.page != page) {
      diagnostics.warning(
          'filled.page differs from template.page; using template.page');
    }

    final double left = page.margins.left;
    final double top = page.margins.top;
    final double bottom = page.height - page.margins.bottom;
    final double contentHeight = bottom - top;

    final List<ReportBand> headers = <ReportBand>[
      for (final ReportBand b in template.bands)
        if (b.type == BandType.pageHeader) b,
    ];
    final List<ReportBand> footers = <ReportBand>[
      for (final ReportBand b in template.bands)
        if (b.type == BandType.pageFooter) b,
    ];
    double sumHeight(List<ReportBand> bands) {
      double h = 0;
      for (final ReportBand b in bands) {
        h += b.height;
      }
      return h;
    }

    final double headerHeight = sumHeight(headers);
    final double footerHeight = sumHeight(footers);
    final double bodyTop = top + headerHeight;
    final double bodyBottom = bottom - footerHeight;
    final double bodyCapacity = bodyBottom - bodyTop;

    if (bodyCapacity <= 0) {
      diagnostics.warning(
          'page chrome (header $headerHeight + footer $footerHeight) leaves no '
          'room for body on a $contentHeight-pt printable height; chrome '
          'overlaps and body bands overflow');
    }

    // Band types 008a does not lay out yet (008b) — flag once each.
    for (final BandType ignored in const <BandType>[
      BandType.columnHeader,
      BandType.columnFooter,
      BandType.background,
    ]) {
      if (template.bands.any((ReportBand b) => b.type == ignored)) {
        diagnostics
            .info('${ignored.name} bands are not laid out in 008a; ignored');
      }
    }

    // Scan chrome ONCE for unresolved bindings (spec §7) — info only; no later
    // owner is named (page-scoped text -> 008c; images -> Fill/paint-prep).
    for (final ReportBand band in <ReportBand>[...headers, ...footers]) {
      for (final ReportElement el in band.elements) {
        if (el is TextElement && el.expression != null) {
          diagnostics.info(
              'chrome text expression on "${el.id}" was not evaluated in the '
              'static layout pass',
              elementId: el.id);
        } else if (el is ImageElement && el.source is! BytesImageSource) {
          diagnostics.info(
              'chrome image on "${el.id}" is not embedded; renders a placeholder',
              elementId: el.id);
        }
      }
    }

    // Translate band-local boxes to the page and emit each element's primitives.
    void place(List<({ReportElement element, JetRect bounds})> boxes,
        double topY, FrameBuilder fb) {
      for (final ({ReportElement element, JetRect bounds}) e in boxes) {
        _renderers.rendererFor(e.element).emit(
              e.element,
              ctx,
              JetRect(
                x: left + e.bounds.x,
                y: topY + e.bounds.y,
                width: e.bounds.width,
                height: e.bounds.height,
              ),
              fb,
            );
      }
    }

    // 1. Body pagination (held builders; always >= 1 page).
    final List<FrameBuilder> pages = <FrameBuilder>[FrameBuilder(page)];
    double cursorY = bodyTop;
    for (final FilledBand band in filled.bands) {
      final MeasuredBand mb = bandMeasurer.measure(band);
      if (cursorY + mb.height > bodyBottom && cursorY > bodyTop) {
        pages.add(FrameBuilder(page));
        cursorY = bodyTop;
      }
      if (bodyCapacity > 0 && mb.height > bodyCapacity) {
        diagnostics.warning('band height ${mb.height} exceeds body capacity '
            '$bodyCapacity; content overflows');
      }
      place(mb.elements, cursorY, pages.last);
      cursorY += mb.height;
    }

    // 2. Chrome post-pass (page count now known; chrome is fixed-height, emitted
    // at authored bounds). This is the seam 008c reuses for page-number
    // substitution.
    for (final FrameBuilder fb in pages) {
      double y = top;
      for (final ReportBand h in headers) {
        place(_authoredBoxes(h), y, fb);
        y += h.height;
      }
      y = bodyBottom;
      for (final ReportBand f in footers) {
        place(_authoredBoxes(f), y, fb);
        y += f.height;
      }
    }

    return LayoutResult(
      pages: <PageFrame>[for (final FrameBuilder fb in pages) fb.build()],
      diagnostics: diagnostics,
    );
  }

  // Chrome elements emit at their authored band-local box (no growth).
  List<({ReportElement element, JetRect bounds})> _authoredBoxes(
          ReportBand band) =>
      <({ReportElement element, JetRect bounds})>[
        for (final ReportElement el in band.elements)
          (element: el, bounds: el.bounds),
      ];
}
```

- [ ] **Step 4: Run the tests + analyzer**

Run: `flutter test test/rendering/layout/report_layouter_test.dart -r expanded && flutter analyze`
Expected: PASS (15 tests); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/rendering/layout/report_layouter.dart test/rendering/layout/report_layouter_test.dart
git commit -m "feat(layout): ReportLayouter pagination + page chrome (008a)"
```

---

## Task 3: Layer-boundary test — the `layout/` seam stays headless

**Files:**
- Modify: `test/architecture/layer_boundaries_test.dart`

Context: The general rendering-seam tests already cover `layout/` recursively (no `designer` import; only `canvas_painter.dart` imports `dart:ui`). The new, 008a-specific invariant is that `rendering/layout/` is **free of the expression engine** (spec §10 #2: pure geometry over the renderer + measurer seams). Add a dedicated sub-test mirroring the existing `elements/`/`fill/` seam tests, so a future accidental `expression/` import fails the suite.

- [ ] **Step 1: Add the failing test**

In `test/architecture/layer_boundaries_test.dart`, inside the `group('layer boundaries — rendering seam', ...)` block, add this test immediately after the existing `'the fill/ seam exists, ...'` test (before the group's closing `});`):

```dart
    test('the layout/ seam exists, stays Flutter-free, and imports no '
        'expression engine', () {
      final Directory layoutDir = Directory(
          '${root.path}/packages/jet_print/lib/src/rendering/layout');
      expect(layoutDir.existsSync(), isTrue,
          reason: 'Missing ${layoutDir.path}');
      final List<File> layoutFiles = layoutDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((FileSystemEntity f) => f.path.endsWith('.dart'))
          .toList();
      expect(layoutFiles, isNotEmpty);
      final List<String> violations = <String>[];
      for (final File file in layoutFiles) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          // 008a is pure geometry: layout composes domain + sibling rendering
          // subdirs (frame/elements/text/fill) but must NOT reach the expression
          // engine. A relative '../../expression/' or absolute '/expression/' is
          // the violation shape.
          final bool expressionSeam =
              uri.contains('../../expression/') || uri.contains('/expression/');
          if (_isFlutterUi(uri) || expressionSeam) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'rendering/layout must stay headless and free of the '
              'expression engine (008a is pure geometry):\n'
              '${violations.join('\n')}');
    });
```

- [ ] **Step 2: Run the test**

Run: `flutter test test/architecture/layer_boundaries_test.dart -r expanded`
Expected: PASS — `layout/` exists (Tasks 1–2 created it) and neither file imports `dart:ui`/Flutter UI or `expression/`. (If it fails because no `.dart` files are found, Tasks 1–2 are incomplete.)

- [ ] **Step 3: Commit**

```bash
git add test/architecture/layer_boundaries_test.dart
git commit -m "test(layout): pin layout/ seam headless + expression-free (008a)"
```

---

## Task 4: CHANGELOG + final verification

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update the CHANGELOG**

In `CHANGELOG.md`, under the current unreleased `### Added` section (after the 007c entry), add:

```markdown
- **Layout engine (spec 008a).** `ReportLayouter` lays a `FilledReport` band stream onto pages:
  it measures body bands (grow-only, via the element renderers), stacks and paginates them in the
  per-page body region, and repeats `pageHeader`/`pageFooter` chrome on every page, emitting one
  `PageFrame` per page plus diagnostics. A pure `BandMeasurer` computes grown band heights. Chrome is
  emitted as authored (no expression evaluation yet — page-scoped substitution arrives in 008c);
  unresolved chrome bindings, chrome that overcommits the page, and not-yet-supported
  column/background bands are reported as diagnostics.
```

- [ ] **Step 2: Run the full suite + analyzer**

Run: `flutter test -r expanded && flutter analyze`
Expected: every test PASSES (008a adds 5 + 15 + 1 tests; 007a/b/c, domain, expression, data all unchanged); `No issues found!`.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(layout): changelog for the layout engine (008a)"
```

---

## Done

All of spec 008a (layout engine) is implemented: the pure `BandMeasurer` (grow-only band heights + per-element grown boxes), and `ReportLayouter` (held-builders pagination, repeating page header/footer chrome via the post-pagination pass that 008c will reuse for page-number substitution, unresolved-chrome diagnostics, chrome-overcommit guard, `template.page` authority, and column/background ignoral). The output is `List<PageFrame>` + `ReportDiagnostics`; no domain/serialization change. The `layout/` seam is pinned headless and expression-free. After Task 4, dispatch a final holistic code review over the whole 008a change set, then use `superpowers:finishing-a-development-branch` to merge `008a-layout-engine` into `main`.
