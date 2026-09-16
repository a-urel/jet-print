# Painting

How one frame becomes screen pixels, a PNG and a PDF, with nothing kept in sync by
hand.

Page 04 left a `PageFrame`: a flat list of positioned, already-measured
primitives. Everything below it is translation. A backend takes them in paint
order, turns each into the ink its medium understands — `dart:ui` calls, or PDF
operators — and is consulted about nothing else: not where text goes, how wide a
line is, where it wraps, or which font to use. That is why WYSIWYG is not
maintenance work here: the surfaces are never asked the question they could
disagree on.

## What a backend is

[`rendering/paint/report_painter.dart`](../packages/jet_print/lib/src/rendering/paint/report_painter.dart)
→ `ReportPainter` is ten members: `prepare`, `beginPage`, `endPage`,
`pushTransform`/`popTransform`, and one `drawX` per primitive; page 04 showed the
dispatch. `prepare` is the only asynchronous member — fonts load and images decode
there, once per frame, which leaves every `drawX` synchronous and the walk over
the list ordinary straight-line code. And `beginPage`/`endPage` bracket one frame,
leaving each backend to decide what a *document* is.

## The canvas path, and the PNG that reuses it

[`rendering/paint/canvas_painter.dart`](../packages/jet_print/lib/src/rendering/paint/canvas_painter.dart)
→ `CanvasPainter` is one of the two paint files on the `dart:ui` allowlist page 04
pointed at, pinned by `test/architecture/layer_boundaries_test.dart` (the third
entry is a `Locale`). Its `prepare` registers each run's exact variant bytes under
a variant-unique engine name from `rendering/text/ui_font_family.dart` →
`uiFontFamily`; because that registration is process-global and CanvasKit appends
without deduplicating, the "already registered" guard is a `static` set shared by
every painter.

The other paint file,
[`rendering/paint/page_rasterizer.dart`](../packages/jet_print/lib/src/rendering/paint/page_rasterizer.dart)
→ `PageRasterizer`, has no drawing code — it is the path the preview and its
thumbnail rail already run, both recording `pageAt(i).frame` through this same
painter:

```dart
final ui.PictureRecorder recorder = ui.PictureRecorder();
final ui.Canvas canvas = ui.Canvas(recorder)..scale(scale, scale);
await paintFrame(frame, CanvasPainter(canvas, fonts));
// ... recorder.endRecording().toImage at the rounded pixel size, the PNG
// encode, and the ui.Image disposal in a finally
```

The difference is where the scale goes: the preview and design canvas record at
1:1 and blit under a view transform (`designer/canvas/frame_custom_painter.dart` →
`FrameCustomPainter`), so zooming re-blits rather than re-records, while the
rasterizer scales *before* recording and `toImage` gets exactly
`round(page.width × scale)` device pixels.

## Where a line of text lands

A `TextRunPrimitive` carries lines the measurer already broke, each `TextLine`
carrying both its `top` and its `baseline` within the block. The backends take
different halves of that:

```dart
// rendering/paint/canvas_painter.dart → drawTextRun
_canvas.drawParagraph(para, ui.Offset(dx, p.bounds.y + line.top));
// rendering/export/pdf_painter.dart → drawTextRun
g.drawString(font, p.style.fontSize, line.text, dx,
    _mapY(p.bounds.y + line.baseline));
```

The canvas hands the engine a one-line paragraph laid out at infinite width —
never re-wrapped — positioned by the line box's *top*, and lets the engine drop
the baseline an ascent below it. The PDF places the baseline itself, that being
the only origin a PDF text object has. Both numbers come from one measurement of
one font program: `rendering/text/metrics_text_measurer.dart` →
`MetricsTextMeasurer` computes `baseline` as `top` plus the ascent read from the
face's `hhea` table, and those bytes are what the canvas registers and the PDF
embeds. The residual is that the engine derives its own ascent for the face; the
goldens are where a disagreement would show.

Horizontal placement is the honest exception. `dx` — distribute the unused width,
left, centre or right — is written out twice, once per backend, the PDF copy
commented as the canvas's math. What holds the two copies together is a test.

## PDF: what is shared, and what is rebuilt

[`rendering/export/pdf_painter.dart`](../packages/jet_print/lib/src/rendering/export/pdf_painter.dart)
→ `PdfPainter` imports no Flutter and no `dart:ui`; it is pure Dart over
`package:pdf`'s low-level `PdfDocument`/`PdfPage`/`PdfGraphics`, accumulating
pages so that `rendering/export/jet_report_exporter.dart` →
`JetReportExporter.toPdf` writes a whole report through one painter and one
`save`. It records no picture and shares no drawing code with the canvas backend
— what it shares are the inputs and the geometry: the primitives, the measured
lines, `FontRegistry` byte-for-byte, `rendering/paint/image_fit.dart` →
`computeImageFit`, and `rendering/text/underline_metrics.dart` → `underlineFor`.

What it produces is a real document, not a picture of one. Each measured line
becomes its own PDF text object drawn against the embedded TTF, so the exported
text is selectable and searchable at exactly the baselines the preview drew — and
it is that one-text-object-per-line structure the parity test counts.

What it rebuilds is what the medium forces. PDF's origin is bottom-left, so every
draw call maps `y' = pageHeight - y` individually — deliberately not a global
negative-y transform, which would mirror glyph outlines. Colour operators carry no
alpha, so a translucent colour becomes a scoped `ExtGState` rather than being
dropped. A paint operator consumes the current path, so a filled *and* stroked
path is replayed per pass, preserving the canvas's fill-then-stroke order. Images
decode through `package:image`, not the engine's codec, onto the rects
`computeImageFit` returned. And byte-determinism belongs to this file: a fixed
document ID, no `/Info` dictionary, no clock, randomness or locale read.

## Underlines are stroked, never decorated

Both backends draw an underline as an explicit segment at the offset and thickness
`underlineFor` computes from the font size, spanning the measured line width.
Neither uses `dart:ui`'s `TextDecoration` — because there would be no second
implementation to agree with it. PDF has no text-decoration property at the
graphics level (`package:pdf` exposes underline only in its widgets layer, which
draws a line itself), so the exporter must place that line from *some* number, and
the number the engine would use comes from font tables nothing on the PDF path
reads: the in-house parser `rendering/text/ttf/ttf_metrics.dart` reads `head`,
`hhea`, `maxp`, `hmtx` and `cmap`, and no `post` table. One shared helper is what
makes the two segments identical rather than merely similar; real per-face metrics
later would change that function alone.

## Nothing vendor-shaped reaches a painter

A barcode is the one thing the paint path cannot work out for itself, so the
encoding is bought from outside — but what is bought is only geometry. The adapter
turns the vendor's positioned elements into `BarcodeModule` rectangles and
`BarcodeHriText` runs, and its `BarcodeException` into a `BarcodeInvalid` value
carrying a reason, so the vendor's types, exceptions and coordinate conventions
stop at the seam and the renderer downstream only ever fills rectangles it already
understands. Let that vocabulary past the adapter and it spreads to everything
that asks a barcode a question — the renderer, the designer's validity check, the
layout box — and a version bump becomes a change to all of them rather than to one
file's insides. The interface it implements, `BarcodeEncoder`, is what makes the
seam testable: `BarcodeElementRenderer` takes it as a defaulted constructor
argument, so a test can substitute a fake encoder and pin the painting without
encoding anything.

## Why it is like this, and the alternative rejected

The alternative was available and much shorter. `package:pdf` ships a widgets
layer with text, styles, alignment and decoration; let each backend lay text out
with its own library's facilities and most of `PdfPainter` disappears. It fails on
the one thing the product sells. Layout would happen twice, from two metric
sources and two wrap algorithms, agreeing on ordinary Latin text right up until
they did not — a heading wrapping after a different word in the PDF than in the
preview, found in a document already sent. It also cuts pagination loose: page
03's breaks come from measured band heights, so a backend that re-wraps has
silently disagreed about how many pages there are.

The cost is specific. Measurement sums per-codepoint advances from `hmtx` with no
`kern` or `GPOS` parsed, so `line.width` is a kerning-free, shaping-free number
while the canvas draws each line through the engine's real shaper. Widths and
alignment rest on the measurer's arithmetic, glyph positions on the engine's —
which shows, where it shows at all, as alignment drift rather than broken text.

## Run it

```bash
flutter test packages/jet_print/test/rendering/export/pdf_painter_parity_test.dart
flutter test packages/jet_print/test/goldens/
```

The first is where backend parity is proven, and it uses no pixels: it paints
hand-built frames through `PdfPainter`, reads the content stream back and asserts
the operators — one text object per pre-measured line and no more, each at
`pageHeight - (bounds.y + line.baseline)`; the alignment copy against the canvas's
formula; one stroked underline at `underlineFor`'s geometry; fill before stroke;
`computeImageFit`'s rects; no global y-flip. Arithmetic on operators rather than a
comparison of pictures, so it runs on every host, not only macOS.

The second is the visual pin, and it pins the canvas side only — four reports
through `JetReportPreview`. The PDF's own pin is byte-level, against a fixed
`invoice.pdf` in `test/rendering/export/pdf_determinism_test.dart`. Both are
`golden`-tagged; where that makes them run is in `AGENTS.md` under *Traps*, with
the one-paint-path rule they enforce in its *Hard rules*.

## Trap

**Constructing a `CanvasPainter` makes you responsible for disposing it, and
`dispose` is not on the interface.** `prepare` decodes every `ImagePrimitive` into
a `ui.Image`, and `CanvasPainter.dispose` releases those textures; commit
`27c9fb2` added it because on CanvasKit each record leaked a GPU texture, and
disposing after `endRecording` is safe precisely because the recorded picture
holds its own references. But `dispose` is declared on `CanvasPainter`, not on
`ReportPainter`, so a call site that types its variable as the interface — the
more polite-looking choice — cannot call it. Of the four construction sites in the
library, only `designer/canvas/design_time_frame.dart` → `recordFrame` holds the
concrete type and disposes; the preview, the thumbnail rail and `PageRasterizer`
do not. Hold the concrete type when you add a recording site.

## Next

Page 06, [round-tripping](06-round-tripping.md), goes back to the top of the
pipeline and asks the other question about a report: not how it is drawn, but how
it survives being written as JSON by one build and read back by another.
