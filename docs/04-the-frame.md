# The frame

The one structure the whole library converges on, and why nothing draws without it.

Everything upstream of the frame exists to produce it; everything downstream only
draws it. The filler binds data, the layouter paginates, the element renderers
measure and emit — and the entire product of all that work is one small immutable
value, a `PageFrame`. The design canvas, the preview, the thumbnail rail, the PNG
rasterizer and the PDF writer do not know a report model exists. They know a
frame.

## What a frame is

[`rendering/frame/page_frame.dart`](../packages/jet_print/lib/src/rendering/frame/page_frame.dart)
→ `PageFrame`, in full but for its `toString` and its doc comments:

```dart
class PageFrame with ValueEquality {
  PageFrame({required this.page, required List<FramePrimitive> primitives})
      : primitives = List<FramePrimitive>.unmodifiable(primitives);

  final PageFormat page;
  final List<FramePrimitive> primitives;

  @override
  List<Object?> get props => <Object?>[page, primitives];
}
```

A page geometry and a flat list of positioned primitives in paint order. That is
the whole type. Three properties carry the weight:

**Flat.** No tree, no nesting, no parent transforms to compose; a painter walks
the list once, in order. Bands, group nesting and crosstab plans are gone by
this point — they were layout's problem, and layout is over. Every position is an
absolute page-point coordinate, already resolved; no primitive says "below the
previous one".

**Immutable.** The constructor copies its argument into an unmodifiable list, so
a frame handed to several surfaces cannot be mutated by any of them. The write
side is a separate type,
[`rendering/frame/frame_builder.dart`](../packages/jet_print/lib/src/rendering/frame/frame_builder.dart)
→ `FrameBuilder`: renderers `add` primitives, then `build` snapshots them.
Append-only while being built, frozen once built.

**A value.** `PageFrame` mixes in `ValueEquality` over its page and its
primitives, and so does every primitive, so two frames built from the same inputs
compare equal. That is what makes a frame assertable without pixels — which
matters more than it sounds; see *Run it*.

## The five primitives

`FramePrimitive` in
[`rendering/frame/primitive.dart`](../packages/jet_print/lib/src/rendering/frame/primitive.dart)
is a sealed base carrying the three fields every drawn thing has: `bounds` in
page points, an optional `elementId` naming the element that produced it, and a
`rotation` the paint layer applies about the bounds' center.

Five subclasses extend it, and there are no others:

| Primitive | Draws |
|---|---|
| `TextRunPrimitive` | pre-broken lines from the measurer — the painter never re-wraps |
| `ImagePrimitive` | encoded bytes, a fit mode, an opacity |
| `LinePrimitive` | one stroked segment |
| `RectPrimitive` | an optional fill and an optional stroke |
| `PathPrimitive` | move/line/close commands, optional fill and stroke |

That is the entire alphabet a page is written in. Everything this library can
print is spelled with those five:

- A **chart** is paths for the series, lines for axes and gridlines, rectangles
  for bars and text runs for labels, all assembled from pure geometry by
  `rendering/elements/renderers/chart_element_renderer.dart` → `ChartElementRenderer`.
- A **barcode** is a run of rectangles, plus one text run when the
  human-readable line is shown.
- A **watermark** is a rotated text run — or a rotated image, when it carries one
  instead — faded by its opacity: `rendering/watermark_primitive.dart` →
  `buildWatermarkPrimitive`.
- A **shape**, block arrows and rounded rectangles included, is a path from
  `rendering/elements/shape_path.dart` → `shapePath`.

The consequence is the whole point: **adding a chart type, a barcode symbology or
a shape never touches a painter.** A new element type lands entirely on the emit
side, as a new arrangement of the same five primitives. The painters keep working
because none of them was ever told what a chart is.

## Who paints it

Named individually, because the list is the argument:

- the **design canvas** — `designer/canvas/design_time_frame.dart` →
  `DesignTimeFrameBuilder`, over a design-time layout with *unchanged* renderers;
- the **preview** — `designer/preview/jet_report_preview.dart` — and the
  **thumbnail rail** — `designer/preview/page_thumbnail_rail.dart` — both
  painting `pageAt(index).frame`, at different sizes;
- the **PNG rasterizer** — `rendering/paint/page_rasterizer.dart` →
  `PageRasterizer`, that same recording at a chosen scale;
- the **PDF painter** — `rendering/export/pdf_painter.dart` → `PdfPainter`, a
  pure-Dart backend over `package:pdf`.

They all meet at `rendering/paint/report_painter.dart` → `paintFrame` — the first
four through `rendering/paint/record_page_frame.dart` → `recordPageFrame`, which
owns that sequence for them, the exporter calling `paintFrame` itself once per page:

```dart
for (final FramePrimitive primitive in frame.primitives) {
  switch (primitive) {
    case TextRunPrimitive():
      painter.drawTextRun(primitive);
    // ... one case per primitive, no default
  }
}
```

It is a switch *statement* over a sealed base with no `default`, so Dart requires
it to be exhaustive: a sixth primitive fails to compile here, in `paintFrame`
itself. The backends fail second — a new primitive also brings a new `drawX`
member on the abstract `ReportPainter`, which every implementor must then supply.
The compiler, not a reviewer, is what stops a surface from silently skipping
something it does not recognize.

So WYSIWYG does not hold because several painters are kept in agreement. It holds
because there is exactly one thing to paint, and the surfaces differ only in how
they turn `drawRect` into ink.

## Why it is like this, and the alternative rejected

The obvious alternative is the one most report tools reach for: hand every
surface the report model and let it draw. The canvas walks bands and paints
elements; the PDF writer walks the same bands and emits PDF operators; the
preview does its own version again. It is less machinery, and each surface uses
exactly the drawing API it likes. It fails in three ways.

**Divergence, silently.** Every drawing path re-derives position, wrap points and
font fallback. They agree right up until one of them is fixed for a bug the
others also have. A designer that wraps a header after *quarterly* while the PDF
wraps it after *results* is not a bug anyone finds; it is one a user reports
months later, about a document already sent.

**Nothing to test parity against.** With several drawing paths, parity is an
N-way pixel comparison, per platform, per font — and pixels differ innocently
across hosts. With one frame, everything above it is proven once, and only the
small backend below it needs pixels at all. The interesting assertions move off
images: layout tests in `test/rendering/layout/report_layouter_test.dart` find a
primitive by its `elementId` and assert its `bounds` — fast, exact,
platform-independent, and not expressible if "where the header landed" exists
only as pixels.

**Extension becomes N-way.** A new element type would have to teach every surface
how to draw it, forever. Against the frame it teaches one emitter and reaches
all of them at once.

The frame's own costs are real and worth naming: one page's primitives are
materialized before anything draws, and a primitive cannot ask a painter a
question — it cannot measure text, so the measurer runs above the frame and its
results travel inside `TextRunPrimitive`. Both were accepted deliberately, and
pagination stays lazy per page, so what is materialized is one page, not a report.

## Run it

```bash
flutter test packages/jet_print/test/rendering/frame/
```

`frame_builder_test.dart` is the shortest complete statement of the contract:

```dart
// ... rect is a const RectPrimitive
final FrameBuilder b = FrameBuilder(PageFormat.a4Portrait)..add(rect);
final PageFrame frame = b.build();
expect(frame.primitives, <Object>[rect]);
expect(() => frame.primitives.add(rect), throwsUnsupportedError);
```

Passing proves the three properties the rest of the pipeline leans on: the
builder accumulates in paint order, `build` freezes the result so mutation
throws, and two frames built the same way are equal. `primitive_test.dart` proves
the same value semantics for each of the five primitives, including that
`rotation` participates in equality — a rotated watermark is not equal to an
unrotated one.

## Trap

**A new field on a primitive is invisible until it is added to that primitive's
`props`.** Each subclass spreads `baseProps` then lists its own fields, and the
equality mixin compares exactly what `props` returns — nothing more. Omit a field
and the code still compiles and still paints correctly, but two primitives that
genuinely differ compare equal, and every equality-based assertion above them
goes blind. That is how a change ends up proven by a test that could not have
failed. `test/rendering/frame/primitive_test.dart` asserts that each new field
*breaks* equality, not merely that it defaults; add that assertion with the field.

## Next

Page 05, [painting](05-painting.md), picks the frame up from here: how
`CanvasPainter` turns primitives into `dart:ui` calls, how `PdfPainter` writes
the same primitives as PDF operators with embedded fonts and selectable text, and
why the rendering seam's `dart:ui` imports are a short allowlist, held and named by
`test/architecture/layer_boundaries_test.dart`.
