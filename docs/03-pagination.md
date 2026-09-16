# Pagination

How a filled band stream becomes pages, and why only the ones you look at exist.

Page 02 ended with a `FilledReport`: a flat, ordered list of `FilledBand`s whose
values are already resolved. Layout's whole job is deciding where the breaks
fall, and it answers that completely before drawing anything — the page count is
exact the moment `renderDefinition` returns.

## Two passes over one seam

[`rendering/layout/report_layouter.dart`](../packages/jet_print/lib/src/rendering/layout/report_layouter.dart)
→ `layoutLazyDefinition` is the first pass: it measures every filled band, walks
them with a cursor, decides every break, and records what landed where as a
list-of-lists of `_PlacedBand` — a measured band plus a page-absolute `x` and `y`
— while emitting **no** paint primitives through the renderers' `emit`. What it
returns, `LazyLayout`, knows `pageCount` and can produce any page on demand.

The second pass is `LazyLayout.buildPage`, which replays one page's recorded
placements through the element renderers' `emit` and appends that page's chrome.
Caching sits above it, in `rendering/engine/rendered_report.dart` →
`RenderedReport.pageAt`: a `Map<int, RenderedPage>` filled by `putIfAbsent`, so a
page is built at most once and re-access returns the *identical* instance.

That replay is also the host's one hook into what gets drawn. When
`RenderOptions.onElementPrint` is non-null, the layouter's `_place` calls it once
per element immediately before `emit`, passing an `ElementPrintContext` carrying
the page number and count, the band's type and name, and the row's fields and
variables — on preview, export and print alike, since all three go through
`buildPage`. Returning `null` suppresses the element; returning one of the same
runtime type replaces it, and its `bounds` supply the x, y and width `emit` is
handed. Its height does not: that comes from the measured box, because the
boundary pass already committed to it. A different type, or a throw, is a warning
and a fall back to the original.

"Lazy" oversells it, though. The boundary pass measures **all** bands —
`rendering/layout/band_measurer.dart` → `BandMeasurer.measure` runs once per
filled band and `LazyLayout` retains a `MeasuredBand` for each — so what is
deferred is *primitive construction*, not the work per band.
`test/rendering/engine/performance_test.dart` asserts that property: `emit` calls
for page 0 number the same for 100 records as for 1000.

Measuring once and placing later is sound only because measurement is
position-independent: `BandMeasurer` grows each element to its content height at
the element's authored width and takes the band height as the maximum element
bottom, floored at the designed height — no input from where the band lands.
`rendering/elements/renderers/text_element_renderer.dart` → `TextElementRenderer`
keeps that honest by wrapping at `el.bounds.width` in both `measure` and `emit`.

## What decides a break

The body occupies `bodyTop` (top margin plus page-header height) to `bodyBottom`
(bottom margin less page-footer height). A cursor starts at `bodyTop` and a band
is placed **whole** — bands never split across pages:

```dart
bool broke = false;
if (keepExtent.containsKey(i)) {
  // ... the keepTogether fit test, which may break the page early
}
if (!broke && cursorY + mb.height > bodyBottom && cursorY > bodyTop) {
  breakPage();
}
if (bodyCapacity > 0 && mb.height > bodyCapacity) {
  diagnostics.warning('band height ${mb.height} exceeds body capacity '
      '$bodyCapacity; content overflows');
}
linearPlans.last.add((band: mb, x: left, y: cursorY));
cursorY += mb.height;
```

`cursorY > bodyTop` stops a break that would accomplish nothing but an empty
page: at the top of a fresh page there is nowhere better to go, so an over-tall
band is placed anyway, overflows, and is diagnosed. The three `GroupLevel`
pagination flags reach into this same loop. `startNewPage` breaks before every
group instance *after the first*. Every group header is pushed onto an open-group
stack as it is placed; `reprintHeaderOnEachPage` rides along on that entry and
decides only whether `breakPage` re-emits it at the next page's top.
`keepTogether` needs a group's total extent before reaching its end, so a pre-pass
walks the stream with a cumulative-height table and a span stack, recording each
such group's extent against the index of its opening header; the fit test
compares it against capacity *less* the outer headers that would reprint, and a
group too tall even for a fresh page is not moved, only split. One shape skips
the loop entirely: when `domain/report_definition.dart` → `soleDetailBand`
carries a `ColumnLayout`, the layouter lays a uniform label grid at a fixed pitch.

## Furniture, and what page one does differently

`buildPage` emits the body placements first, then the page header at the top
margin, then the page footer anchored at `bodyBottom` — not below the last band.
That order is the z-order: body primitives precede chrome in the frame's list.
The watermark is the exception at the other end — `rendering/watermark_primitive.dart`
→ `buildWatermarkPrimitive` is computed once in the boundary pass (its result is
page-independent) and added *first* on every page, behind everything. Those three
are the furniture that repeats; the `columnHeader`, `columnFooter` and
`background` slots are representable in the model but are not laid out, and each
one present draws an info diagnostic.

Page one alone reorders two things: the first `BandType.title` band in its plan
is drawn at the top margin rather than at its boundary-pass `y`, and the
page-header chrome shifts down by that band's height — JasperReports' default
ordering. Pagination is untouched, because the title already consumed its height
at `bodyTop` during the boundary pass; the two simply exchange positions, and the
shift is zero on every other page.

## Page numbers

Substitution happens in `LazyLayout` and reaches **only chrome**: a `TextElement`
in the page header or footer whose `expression` is non-null, parsed once during
the boundary pass into `chromeExprs` with parse failures and statically
unresolvable references recorded alongside. `buildPage` evaluates that compiled
expression against `rendering/layout/page_eval_context.dart` → `PageEvalContext`,
whose `resolveField` is always `JetNull`, whose params come from
`FilledReport.params`, and whose two reserved names are the point:

```dart
if (name == 'PAGE_NUMBER') return JetString('$_pageNumber');
if (name == 'PAGE_COUNT') return JetString('$_pageCount');
```

Strings, deliberately. The expression engine holds every number as a `double`, so
a `JetNumber` here would render `1.0` — the hazard page 02's *Trap* describes for
`jetStringify`, sidestepped by never making these numbers. The cost is that a
first-page condition is written as string equality, `$V{PAGE_NUMBER} == "1"`.

A body band cannot reach either name — the hand-off page 02 set up from its side.
`rendering/fill/fill_eval_context.dart` → `FillEvalContext.resolveVariable`
returns `JetNull` for anything in `kPageScopedVariables` and records the name;
`rendering/fill/visibility.dart` turns that record into a rejection.

## Why it is like this, and the alternative rejected

The alternative is to materialize every page up front and hand back a list —
precisely what `LayoutResult` is. It is simpler, and it makes diagnostics final.
It loses on both axes that matter. **Memory becomes unbounded in the report**,
every page's primitives live at once for a dataset whose size the library does
not control. And **time to first page scales with the last page**: the preview
paints exactly one page — `designer/preview/jet_report_preview.dart` reads
`pageAt(_index)` — and the thumbnail rail only what it shows, so opening a
900-page report to read page 1 would cost 900 pages of emit.

So the eager path was not deleted, it was inverted. `ReportLayouter.layoutDefinition`
is now `layoutLazyDefinition` plus a `for` loop calling `buildPage(i)`, and
`JetReportEngine.renderDefinition` always takes the lazy seam — as of writing the
wrapper's only callers are tests — which nothing asserts, so check it by grep
rather than trusting this sentence. Being the same code makes the two equal by
construction, and lets the pre-lazy corpus in `test/rendering/layout/` keep
proving the break rules through the wrapper.

The costs are real. Laziness begins at the frame and nowhere earlier: fill is
eager over rows (page 02) and the boundary pass eager over bands, so an exact
`pageCount` is bought by doing all that work first — a `JetPagedDataSource`
streams into a pipeline that has already decided to hold everything. And
`RenderedReport`'s cache never evicts, so a PDF export walks `pageAt(i)` across
the whole report and leaves every frame resident.

## Run it

```bash
flutter test packages/jet_print/test/rendering/engine/lazy_pagination_test.dart
flutter test packages/jet_print/test/rendering/layout/
```

The first is the seam's own proof, structural rather than timed. A spy registry
counts every `emit`: the boundary pass over three bands reports zero, and
`buildPage(0)` over the same input reports two — one per element on page 0, the
third band's frame unbuilt. A second case lays the same report both ways and
asserts `lazy.buildPage(i) == eager.pages[i]` for every page, chrome included.
The second command is the break rules themselves: group reprints, `keepTogether`
against repeated outer headers, chrome anchoring, and the title ordering on page
one.

## Trap

**Diagnostics are not final when `renderDefinition` returns.** `LazyLayout` hands
`RenderedReport` the boundary pass's diagnostics object and keeps appending to it
as pages build — chrome expressions that fail at evaluation, `onElementPrint`
callbacks that throw or return the wrong type. `RenderedReport.diagnostics`
merges its sources live, so asserting on it without touching `pageAt` shows only
what the passes *before* page-building found. The corollary bites harder: the
build path is re-entered per page, so anything recorded there multiplies by the
page count unless it joins a dedupe set. Chrome
errors join two — `chromeFlagged`, so a reference already diagnosed statically is
not re-reported at runtime, and `_runtimeDiagnosed`, keyed by element id and
message so the count cannot depend on which pages were built. Several cases in
`test/rendering/layout/report_layouter_test.dart` assert a diagnostic appears
exactly **once** across a multi-page report; a new one added inside `buildPage`
without that protection turns one authoring mistake into one warning per page.

## Next

Page 04, [the frame](04-the-frame.md), opens the parcel `buildPage` returns.
Everything above is geometry and substitution decided in terms of the report
model; what comes out the other side has forgotten all of it — a `PageFrame`
holding a page format and a flat list of positioned primitives, the only thing
any painter in this library has ever been shown.
