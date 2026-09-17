# The canvas

What the user sees and touches: the picture a printer gets, under chrome that never enters it.

Page 07 left the loop at `notifyListeners`; this page is what happens next, and what turns a
pointer back into a call on the controller. The canvas is not a second renderer: it builds a
`PageFrame` through the engine's own element renderers, records it through the seam page 05
owns, and layers interaction on a picture it never edits — everything design-only, from the
grid to the selection handles, being a widget above that picture.

## The design-time frame is the render path

Element appearance on the canvas is produced by `ElementRenderer.emit`, unchanged.
[`designer/canvas/design_time_frame.dart`](../packages/jet_print/lib/src/designer/canvas/design_time_frame.dart)
→ `DesignTimeFrameBuilder.build`, less its doc comment and the page/`FrameBuilder` setup above:

```dart
// ... final PageFormat page = …; final FrameBuilder out = FrameBuilder(page);
for (final PlacedBand placed in layout.bands) {
  for (final element in placed.band.elements) {
    final rect = layout.elementRect(element.id);
    if (rect == null) continue;
    final ReportElement display = _designTimeDisplay(element);
    _renderers.rendererFor(display).emit(display, _ctx, rect, out);
  }
}
return out.build();
```

The registry is the one `registerBuiltInElementTypes` fills; the measurer is
`MetricsTextMeasurer` over the `FontRegistry` hoisted into `designer/designer_font_scope.dart`,
so a glyph is measured here from the bytes the exporter will embed.

**The first design-specific part is where bands sit.** `designer/canvas/design_time_layout.dart`
→ `DesignTimeLayout.of` flattens the tree into one visual document order and stacks it on
one sheet instead of paginating: flow items downward from the top margin, page and column
footers upward from the bottom, the sheet growing if the content outgrows the paper. An
element's page rect is `(bandLeft + bounds.x, bandTop + bounds.y)` — the band-relative
mapping page 03's layouter also uses. That layout doubles as the canvas's index:
`elementRect`, `bandRect`, `bandOfElement`, `toBandLocal`, keyed by the stable ids page 01
describes. (Its dartdoc calls this the *only* design-specific part; there is a second, below.
What is genuinely absent is a designer-specific painter.)

`recordFrame` hands the frame to page 05's `recordPageFrame`, and
`designer/canvas/frame_custom_painter.dart` → `FrameCustomPainter` blits the resulting
`ui.Picture` scaled by the zoom. Recording runs off the build path, keyed on the controller's
`frameVersion` — which ticks on live drag previews too — and coalesces: one record at a time,
re-checked on completion, so a fast drag drops frames rather than queuing a record per pointer
move. Zoom and pan only re-blit; the first frame, before any recording lands, paints nothing.

## What a bound element shows

The second design-specific part is the whole of `design_time_frame.dart` → `_designTimeDisplay`,
called by the loop above on each element: a `TextElement` with a non-null `expression` becomes
`element.copyWith(text: fieldTokenLabel(element.expression!))` and everything else is returned
as it is. So a data-bound text element is shown as an ordinary text element whose `text` is the
binding's **token**, drawn by the same text renderer as literal text.
`designer/canvas/binding_token.dart` → `fieldTokenLabel` is `reverseCompile(expression).text`
from `designer/template/value_template_compiler.dart` — the same projection the Properties value
field shows, so canvas and panel cannot disagree: `$F{name}` reads `[name]`, a template reads as
`{ … }`, anything outside the grammar verbatim in braces. No value is resolved; the designer has
no rows. Nothing else is remapped — a field-bound image needs no case, the shared renderer
already emitting the placeholder glyph for a source-less image.

## What a pointer resolves to

`designer/canvas/hit_testing.dart` → `hitTestElement` is the authority, and it is geometry
over the layout rather than Flutter hit-testing — the per-element widgets the canvas builds
carry semantics and test keys and deliberately do not capture pointers. It walks
`layout.bands.reversed`, each band's elements in reverse: paint order is band order then
element order, so the last drawn is on top and the first reverse hit wins. Containment is a
rect test widened by `slop`, passed at every call site as `kHandleHitSize / 2 / transform.scale`
— a constant eight screen pixels at any zoom, so a thin or tiny element stays grabbable.

A miss is not resolved on the spot: the page point is parked and classified on tap-up, because a
press that becomes a drag — a marquee, a band-divider resize — fires `onTapCancel` and must
leave the selection alone. `designer/canvas/design_canvas/gestures.dart` → `_selectEmptyTarget`
then tries a crosstab block, then `bandIdAt` (a band's *full-width* strip, so the margin gutter
beside a band selects it), then the report when on paper, else clears. Hit-testing reads the
committed layout; everything that draws reads the *display* layout — the committed model plus
any in-progress move or resize.

## Chrome over the picture, never into it

`designer/canvas/selection_overlay.dart` → `DesignerSelectionOverlay` is `Positioned` widgets
at `page-point × scale`, above the `CustomPaint`, so clicking something changes a widget
layer and never the recording. What it draws follows what `Selection` holds (page 07): an
outline per selected element, plus — on a *single* element — the eight handles of
`designer/canvas/resize_handle.dart` → `ResizeHandle`, added edges first and corners last so
an overlapping edge hit box never masks a corner; for a band, an outline and one divider on
the growth-facing edge, bottom for a flow band, top for a bottom-anchored footer, which grows
upward; for the report or a crosstab, an outline alone, neither resizable by hand.

Handles are drawn at `kHandleVisualSize` and hit at `kHandleHitSize`, both in *screen* pixels,
so they neither shrink nor grow with the zoom; their geometry comes from the display layout,
already run through the controller's `clampToBand`, so the chrome tracks the clamped element and
cannot leave its band. Live snap guides join them in the same overlay, in a layer that is always
present so that a guide appearing mid-drag never unmounts the keyed, gesture-owning handles
beside it.

## Grid and rulers are arithmetic

`designer/canvas/grid_geometry.dart` → `gridLineOffsets` and `designer/canvas/ruler_scale.dart`
→ `RulerScale` import no Flutter, no domain and no tunables: every step, ladder and pixel floor
arrives as an argument from `designer/canvas/design_tunables.dart`, so the density math is
unit-testable without a widget.

Grid lines are exact multiples of the snap step — `kGridStep`, the point value of the 5 mm
`kGridStepMm` — and `designer/controller/snapping.dart` reads that same constant, so every
drawn line *is* a snap candidate. Density adapts: the step coarsens by
`f = ⌈minGapPx / (step·scale)⌉`, and past `kGridMaxCoarsenFactor` the function returns
nothing, hiding the grid rather than smearing the page into a fill. `RulerScale` likewise
picks the smallest entry on a nice-number millimetre ladder whose spacing clears the label
gap, and computes each major from its integer millimetre value rather than accumulating, which
keeps alignment float-exact. Millimetres are display-only — `designer/canvas/ruler_metrics.dart`
→ `kPointsPerMm` converts for tick labels and for `selectionExtent`, the span the rulers
highlight — and the model stays in points.

## Interaction adapts to the pointer, not the platform

The canvas tracks the device kind of the most recent pointer-down over it rather than
checking the host platform, so a mouse on a touchscreen laptop keeps pixel precision while a
finger on the same machine gets fat targets. Touch changes three things: handle hit boxes
become `kHandleHitSizeTouch` while the *drawn* square stays `kHandleVisualSize` (goldens
never simulate touch, so none of them move); the scrollbars thicken; and a drag beginning on
empty canvas pans the viewport instead of starting a marquee, there being no wheel to scroll
with and no grabbing a thin bar with a finger (`touch_targets_test.dart` pins the first).

Long-press is the touch right-click. `ShadContextMenuRegion` is configured
`longPressEnabled: true`, so the gesture exists on desktop too, and `tapEnabled: false`,
because its mobile default opens the menu on a plain touch-down and that stole finger-downs
from the resize handles. Since the menu owns a long-press, the handles and the band divider
accept a long-press-drag as well as a pan-drag and route both into the same resize, so a hold
on a handle wins the arena instead of opening a menu.

## Why it is like this, and the alternative rejected

The alternative is a designer-specific element painter: a canvas that walks bands and draws
text, rectangles and images with the widget toolkit it already has. Page 04 gives the general
argument; on the canvas it is sharper, because this is where the user forms the expectation the
export has to meet. A second painter does not fail loudly. It fails by wrapping a heading one
word later than the PDF will, in a document nobody re-checks.

The costs are specific. `DesignTimeLayout` is a second layout implementation, agreeing with
the layouter by arithmetic rather than by shared code; a crosstab has no elements to emit, so
its block is a stand-in of approximate height, excluded from hit-testing; and a bound element
is measured as its *token*, so a field whose printed text is far longer than `[name]` can wrap
at render time where the design showed one line.

## Run it

```bash
flutter test packages/jet_print/test/designer/canvas/
```

`grid_geometry_test.dart` and `ruler_scale_test.dart` assert enumeration, coarsening and tick
alignment with no widget in sight. `band_page_select_test.dart` states the click
classification end to end, margin gutter included, and `resize_cursor_test.dart` pins that
handle order by driving a mouse over each handle at 0.25 zoom, where the boxes overlap.
`bound_token_render_test.dart` is the golden for the token and the image placeholder; being
`golden`-tagged it is macOS-only, for the reason `AGENTS.md` gives under *Traps*.

## Trap

**`designer/canvas/design_time_layout.dart`'s `bandIdAt` and `bandIdNear` must not be
swapped.** Both map a page point to a band id; only `bandIdNear` falls back to the nearest
band when the point is in none. `designer/canvas/design_canvas/drop_menu.dart` needs that
fallback — a dropped element must land *somewhere*, so a drop into the empty flow gap
resolves to the nearest band. Click selection must not have it: `bandIdAt` returning null is
what lets an empty spot on the paper select the report. Swapped, neither failure looks like a
bug — clicks in the margin start selecting whichever band is nearest, or a drop into the gap
silently does nothing. `band_page_select_test.dart` pins the click side. The confusion is
already live in the tree: the comment above the `bandIdAt` call in
`designer/canvas/design_canvas/gestures.dart` → `_selectEmptyTarget` says `bandIdAt` snaps to
the nearest band, which its own body does not do.

## Next

Page 09, [the panels](09-the-panels.md), stays in the designer and turns to the surfaces
beside the canvas — the outline tree, the properties panel and its inspectors — which edit the
same definition through the same controller, without a pointer on a page.
